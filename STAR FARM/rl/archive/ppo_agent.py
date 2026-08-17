"""From-scratch IPPO with a shared-weights actor-critic and a continuous Box policy.

Design:
  * One policy network shared by all farmers (parameter sharing). Each farmer's
    observation is fed independently; transitions from all farmers are pooled into
    a single buffer and PPO-updated together.
  * Box(act_dim) action: a diagonal Gaussian policy. The actor outputs a mean per
    dimension; a state-independent log-std vector is learned. log-prob and entropy
    are summed over the action dimensions. Actions are unbounded here and clamped to
    the Box range [0,1] on the GAML side (we keep the raw sample so the stored
    log-prob stays consistent under the PPO ratio).
  * Observation normalisation via a running mean/std (RunningMeanStd).
  * GAE(lambda) advantages, clipped surrogate objective, value + entropy losses.
"""

from __future__ import annotations

import numpy as np
import torch
import torch.nn as nn
from torch.distributions import Normal


class RunningMeanStd:
    """Welford running mean/variance for observation normalisation."""

    def __init__(self, shape, epsilon: float = 1e-4):
        self.mean = np.zeros(shape, dtype=np.float64)
        self.var = np.ones(shape, dtype=np.float64)
        self.count = epsilon

    def update(self, x: np.ndarray):
        x = np.asarray(x, dtype=np.float64)
        if x.ndim == 1:
            x = x[None, :]
        batch_mean = x.mean(axis=0)
        batch_var = x.var(axis=0)
        batch_count = x.shape[0]

        delta = batch_mean - self.mean
        tot = self.count + batch_count
        self.mean += delta * batch_count / tot
        m_a = self.var * self.count
        m_b = batch_var * batch_count
        m2 = m_a + m_b + delta ** 2 * self.count * batch_count / tot
        self.var = m2 / tot
        self.count = tot

    def normalize(self, x: np.ndarray) -> np.ndarray:
        return (np.asarray(x, dtype=np.float64) - self.mean) / np.sqrt(self.var + 1e-8)

    def state_dict(self):
        return {"mean": self.mean, "var": self.var, "count": self.count}

    def load_state_dict(self, d):
        self.mean = d["mean"]
        self.var = d["var"]
        self.count = d["count"]


class ActorCritic(nn.Module):
    """Shared-weights actor-critic with a diagonal Gaussian policy (continuous Box action).
    The actor outputs a mean per action dim; a single state-independent log-std vector is
    learned. Actions are unbounded here and clamped to the Box range on the GAML side."""

    def __init__(self, obs_dim: int, act_dim: int, hidden_dim: int = 128):
        super().__init__()
        self.act_dim = int(act_dim)
        self.shared = nn.Sequential(
            nn.Linear(obs_dim, hidden_dim), nn.Tanh(),
            nn.Linear(hidden_dim, hidden_dim), nn.Tanh(),
        )
        self.mean_head = nn.Linear(hidden_dim, self.act_dim)
        # State-independent log-std (a common, stable choice). exp(-1.2) ~ 0.30 std.
        self.log_std = nn.Parameter(torch.full((self.act_dim,), -1.2))
        self.critic_head = nn.Linear(hidden_dim, 1)

    def get_dist_value(self, obs: torch.Tensor):
        h = self.shared(obs)
        mean = self.mean_head(h)
        std = torch.exp(self.log_std).expand_as(mean)
        dist = Normal(mean, std)
        value = self.critic_head(h).squeeze(-1)
        return dist, value


class RolloutBuffer:
    def __init__(self):
        self.obs = []
        self.actions = []
        self.logprobs = []
        self.rewards = []
        self.values = []
        self.dones = []
        # advantages / returns filled by compute_gae
        self.advantages = None
        self.returns = None

    def add(self, obs, action, logprob, reward, value, done):
        self.obs.append(obs)
        self.actions.append(action)
        self.logprobs.append(logprob)
        self.rewards.append(reward)
        self.values.append(value)
        self.dones.append(done)

    def __len__(self):
        return len(self.obs)

    def clear(self):
        self.__init__()


class PPOAgent:
    def __init__(self, obs_dim, act_dim, hidden_dim=128, lr=3e-4, gamma=0.95,
                 gae_lambda=0.95, clip_eps=0.2, k_epochs=4, minibatch_size=64,
                 entropy_coef=0.01, value_coef=0.5, normalize_obs=True, device=None):
        self.device = device or ("cuda" if torch.cuda.is_available() else "cpu")
        self.obs_dim = obs_dim
        self.act_dim = int(act_dim)
        self.gamma = gamma
        self.gae_lambda = gae_lambda
        self.clip_eps = clip_eps
        self.k_epochs = k_epochs
        self.minibatch_size = minibatch_size
        self.entropy_coef = entropy_coef
        self.value_coef = value_coef

        self.policy = ActorCritic(obs_dim, act_dim, hidden_dim).to(self.device)
        self.optimizer = torch.optim.Adam(self.policy.parameters(), lr=lr)

        self.normalize_obs = normalize_obs
        self.obs_rms = RunningMeanStd(obs_dim) if normalize_obs else None

    # ---- acting ----
    def _norm(self, obs: np.ndarray) -> np.ndarray:
        if self.normalize_obs:
            return self.obs_rms.normalize(obs)
        return obs

    @torch.no_grad()
    def select_action(self, obs: np.ndarray):
        """Return (action np.ndarray[float], logprob float, value float). The action is the
        raw Gaussian sample (unclamped); the GAML side clamps it into the Box range, and we
        keep the raw value so the stored log-prob stays consistent under the PPO ratio."""
        if self.normalize_obs:
            self.obs_rms.update(obs)
        t = torch.as_tensor(self._norm(obs), dtype=torch.float32, device=self.device).unsqueeze(0)
        dist, value = self.policy.get_dist_value(t)
        action = dist.sample()
        logprob = dist.log_prob(action).sum(-1)
        return (action.squeeze(0).cpu().numpy().astype(np.float32),
                float(logprob.item()),
                float(value.item()))

    @torch.no_grad()
    def act_greedy(self, obs: np.ndarray) -> np.ndarray:
        """Deterministic action = the Gaussian mean (no exploration noise). For evaluation
        only — does NOT update the obs normaliser (unlike select_action)."""
        t = torch.as_tensor(self._norm(obs), dtype=torch.float32, device=self.device).unsqueeze(0)
        dist, _ = self.policy.get_dist_value(t)
        return dist.mean.squeeze(0).cpu().numpy().astype(np.float32)

    @torch.no_grad()
    def value_of(self, obs: np.ndarray) -> float:
        t = torch.as_tensor(self._norm(obs), dtype=torch.float32, device=self.device).unsqueeze(0)
        _, value = self.policy.get_dist_value(t)
        return float(value.item())

    # ---- advantage estimation ----
    def compute_gae(self, buf: RolloutBuffer, last_value: float):
        n = len(buf)
        adv = np.zeros(n, dtype=np.float32)
        last_gae = 0.0
        values = buf.values + [last_value]
        for t in reversed(range(n)):
            non_terminal = 1.0 - float(buf.dones[t])
            delta = buf.rewards[t] + self.gamma * values[t + 1] * non_terminal - values[t]
            last_gae = delta + self.gamma * self.gae_lambda * non_terminal * last_gae
            adv[t] = last_gae
        ret = adv + np.asarray(buf.values, dtype=np.float32)
        buf.advantages = adv
        buf.returns = ret

    # ---- learning ----
    def update(self, buffers: list[RolloutBuffer]):
        """PPO update over pooled transitions from all agents."""
        obs_list, act_list, logp_list, adv_list, ret_list = [], [], [], [], []
        for buf in buffers:
            if len(buf) == 0 or buf.advantages is None:
                continue
            obs_list.append(np.asarray(buf.obs, dtype=np.float32))
            act_list.append(np.asarray(buf.actions, dtype=np.float32))
            logp_list.append(np.asarray(buf.logprobs, dtype=np.float32))
            adv_list.append(buf.advantages)
            ret_list.append(buf.returns)

        if not obs_list:
            return {}

        obs = np.concatenate(obs_list, axis=0)
        if self.normalize_obs:
            obs = self.obs_rms.normalize(obs).astype(np.float32)
        actions = np.concatenate(act_list, axis=0)
        old_logp = np.concatenate(logp_list, axis=0)
        adv = np.concatenate(adv_list, axis=0)
        ret = np.concatenate(ret_list, axis=0)

        # Normalise advantages.
        adv = (adv - adv.mean()) / (adv.std() + 1e-8)

        obs_t = torch.as_tensor(obs, dtype=torch.float32, device=self.device)
        act_t = torch.as_tensor(actions, dtype=torch.float32, device=self.device)
        old_logp_t = torch.as_tensor(old_logp, dtype=torch.float32, device=self.device)
        adv_t = torch.as_tensor(adv, dtype=torch.float32, device=self.device)
        ret_t = torch.as_tensor(ret, dtype=torch.float32, device=self.device)

        n = obs_t.shape[0]
        idx = np.arange(n)
        last_stats = {}
        for _ in range(self.k_epochs):
            np.random.shuffle(idx)
            for start in range(0, n, self.minibatch_size):
                mb = idx[start:start + self.minibatch_size]
                mb_t = torch.as_tensor(mb, dtype=torch.long, device=self.device)
                dist, value = self.policy.get_dist_value(obs_t[mb_t])
                logp = dist.log_prob(act_t[mb_t]).sum(-1)
                entropy = dist.entropy().sum(-1).mean()

                ratio = torch.exp(logp - old_logp_t[mb_t])
                surr1 = ratio * adv_t[mb_t]
                surr2 = torch.clamp(ratio, 1 - self.clip_eps, 1 + self.clip_eps) * adv_t[mb_t]
                policy_loss = -torch.min(surr1, surr2).mean()
                value_loss = ((value - ret_t[mb_t]) ** 2).mean()
                loss = policy_loss + self.value_coef * value_loss - self.entropy_coef * entropy

                self.optimizer.zero_grad()
                loss.backward()
                nn.utils.clip_grad_norm_(self.policy.parameters(), 0.5)
                self.optimizer.step()

                last_stats = {
                    "policy_loss": float(policy_loss.item()),
                    "value_loss": float(value_loss.item()),
                    "entropy": float(entropy.item()),
                }
        return last_stats

    # ---- checkpointing ----
    def save(self, path: str):
        ckpt = {
            "policy": self.policy.state_dict(),
            "optimizer": self.optimizer.state_dict(),
            "obs_dim": self.obs_dim,
            "act_dim": self.act_dim,
        }
        if self.normalize_obs:
            ckpt["obs_rms"] = self.obs_rms.state_dict()
        torch.save(ckpt, path)

    def load(self, path: str):
        # weights_only=False: our own checkpoint embeds numpy arrays (obs_rms).
        ckpt = torch.load(path, map_location=self.device, weights_only=False)
        self.policy.load_state_dict(ckpt["policy"])
        self.optimizer.load_state_dict(ckpt["optimizer"])
        if self.normalize_obs and "obs_rms" in ckpt:
            self.obs_rms.load_state_dict(ckpt["obs_rms"])
