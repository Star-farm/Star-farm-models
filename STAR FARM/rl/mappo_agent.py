"""MAPPO — centralized-critic PPO (CTDE) for the Starfarm MARL setup.

Why MAPPO over IPPO: the dynamic market couples the farmers (if everyone grows premium
rice, its price collapses). Independent critics (IPPO) see only local observations and
treat the others as a non-stationary environment, which hurts credit assignment and
coordination. MAPPO keeps:

  * a DECENTRALIZED actor (shared weights) — each farmer acts on its own observation;
    execution is identical to IPPO;
  * a CENTRALIZED critic — it sees the GLOBAL state (all farmers' observations
    concatenated) during training, giving far better value estimates under coupling.

Cooperative team reward (the global profit). GAE is computed on the single centralized-
value trajectory; every farmer's transition at time t shares that timestep's advantage.
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
        bmean = x.mean(axis=0)
        bvar = x.var(axis=0)
        bcount = x.shape[0]
        delta = bmean - self.mean
        tot = self.count + bcount
        self.mean += delta * bcount / tot
        m_a = self.var * self.count
        m_b = bvar * bcount
        m2 = m_a + m_b + delta ** 2 * self.count * bcount / tot
        self.var = m2 / tot
        self.count = tot

    def normalize(self, x: np.ndarray) -> np.ndarray:
        return (np.asarray(x, dtype=np.float64) - self.mean) / np.sqrt(self.var + 1e-8)

    def state_dict(self):
        return {"mean": self.mean, "var": self.var, "count": self.count}

    def load_state_dict(self, d):
        self.mean, self.var, self.count = d["mean"], d["var"], d["count"]


class RunningScalarStd:
    """Welford running mean/std for a scalar stream (used to normalise value targets).
    Adaptive replacement for a hand-tuned fixed reward scale: with the scenario
    environment, return magnitudes vary wildly across policies (-300k .. +435k), so a
    fixed scale is always wrong for someone. The critic learns on normalised targets;
    get_value de-normalises so GAE stays in the raw reward scale."""

    def __init__(self, epsilon: float = 1e-4):
        self.mean = 0.0
        self.var = 1.0
        self.count = epsilon

    def update(self, x):
        x = np.asarray(x, dtype=np.float64).ravel()
        if x.size == 0:
            return
        bmean = float(x.mean())
        bvar = float(x.var())
        bcount = x.size
        delta = bmean - self.mean
        tot = self.count + bcount
        self.mean += delta * bcount / tot
        m2 = self.var * self.count + bvar * bcount + delta ** 2 * self.count * bcount / tot
        self.var = m2 / tot
        self.count = tot

    @property
    def std(self) -> float:
        return float(np.sqrt(self.var + 1e-8))

    def state_dict(self):
        return {"mean": self.mean, "var": self.var, "count": self.count}

    def load_state_dict(self, d):
        self.mean, self.var, self.count = d["mean"], d["var"], d["count"]


class Actor(nn.Module):
    """Shared decentralized actor: per-farmer observation -> diagonal Gaussian action."""

    def __init__(self, obs_dim: int, act_dim: int, hidden_dim: int = 128):
        super().__init__()
        self.body = nn.Sequential(
            nn.Linear(obs_dim, hidden_dim), nn.Tanh(),
            nn.Linear(hidden_dim, hidden_dim), nn.Tanh(),
        )
        self.mean = nn.Linear(hidden_dim, act_dim)
        self.log_std = nn.Parameter(torch.full((act_dim,), -1.2))

    def dist(self, obs):
        h = self.body(obs)
        std = torch.exp(self.log_std).expand_as(self.mean(h))
        return Normal(self.mean(h), std)


class Critic(nn.Module):
    """Centralized critic: global state (all farmers' obs concatenated) -> scalar value."""

    def __init__(self, global_dim: int, hidden_dim: int = 128):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(global_dim, hidden_dim), nn.Tanh(),
            nn.Linear(hidden_dim, hidden_dim), nn.Tanh(),
            nn.Linear(hidden_dim, 1),
        )

    def forward(self, g):
        return self.net(g).squeeze(-1)


class MAPPOAgent:
    def __init__(self, obs_dim, act_dim, n_agents, hidden_dim=128, lr=3e-4, gamma=0.97,
                 gae_lambda=0.95, clip_eps=0.2, k_epochs=4, minibatch_size=64,
                 entropy_coef=0.01, value_coef=0.5, normalize_obs=True, device=None,
                 critic_hidden_dim=None, target_kl=0.03):
        self.device = device or ("cuda" if torch.cuda.is_available() else "cpu")
        self.obs_dim = int(obs_dim)
        self.act_dim = int(act_dim)
        self.n_agents = int(n_agents)
        self.global_dim = self.obs_dim * self.n_agents
        self.gamma = gamma
        self.gae_lambda = gae_lambda
        self.clip_eps = clip_eps
        self.k_epochs = k_epochs
        self.minibatch_size = minibatch_size
        self.entropy_coef = entropy_coef
        self.value_coef = value_coef
        # Early-stop actor updates when the policy has moved too far from the rollout
        # policy (approx KL > 1.5 * target_kl) — prevents the destructive updates that
        # show up as sudden dips in the training curve.
        self.target_kl = float(target_kl) if target_kl else None

        # The critic ingests the global state (obs_dim * n_agents, e.g. 150 dims) — give it
        # more capacity than the actor unless told otherwise. None -> same as actor (back-
        # compat with checkpoints trained before this option existed).
        ch = int(critic_hidden_dim) if critic_hidden_dim else int(hidden_dim)
        self.actor = Actor(self.obs_dim, self.act_dim, hidden_dim).to(self.device)
        self.critic = Critic(self.global_dim, ch).to(self.device)
        self.optimizer = torch.optim.Adam(
            list(self.actor.parameters()) + list(self.critic.parameters()), lr=lr)

        self.normalize_obs = normalize_obs
        self.obs_rms = RunningMeanStd(self.obs_dim) if normalize_obs else None
        # Adaptive value-target normalisation (see RunningScalarStd docstring).
        self.ret_rms = RunningScalarStd()

    # ---- normalisation ----
    def _norm(self, obs):
        return self.obs_rms.normalize(obs) if self.normalize_obs else np.asarray(obs, dtype=np.float64)

    def global_state(self, obs_dict, order):
        """Concatenate the (normalised) observations of all agents in a FIXED order."""
        return np.concatenate([self._norm(obs_dict[a]) for a in order]).astype(np.float32)

    # ---- acting (decentralized actor) ----
    @torch.no_grad()
    def select_action(self, obs):
        if self.normalize_obs:
            self.obs_rms.update(obs)
        t = torch.as_tensor(self._norm(obs), dtype=torch.float32, device=self.device).unsqueeze(0)
        dist = self.actor.dist(t)
        a = dist.sample()
        logp = dist.log_prob(a).sum(-1)
        return a.squeeze(0).cpu().numpy().astype(np.float32), float(logp.item())

    @torch.no_grad()
    def act_greedy(self, obs):
        t = torch.as_tensor(self._norm(obs), dtype=torch.float32, device=self.device).unsqueeze(0)
        return self.actor.dist(t).mean.squeeze(0).cpu().numpy().astype(np.float32)

    # ---- centralized value ----
    @torch.no_grad()
    def get_value(self, gstate):
        """Critic outputs a NORMALISED value; de-normalise so GAE runs in raw reward scale."""
        t = torch.as_tensor(gstate, dtype=torch.float32, device=self.device).unsqueeze(0)
        return float(self.critic(t).item()) * self.ret_rms.std + self.ret_rms.mean

    def compute_gae(self, rewards, values, dones, last_value):
        n = len(rewards)
        adv = np.zeros(n, dtype=np.float32)
        last = 0.0
        vals = list(values) + [last_value]
        for t in reversed(range(n)):
            nonterm = 1.0 - float(dones[t])
            delta = rewards[t] + self.gamma * vals[t + 1] * nonterm - vals[t]
            last = delta + self.gamma * self.gae_lambda * nonterm * last
            adv[t] = last
        ret = adv + np.asarray(values, dtype=np.float32)
        return adv, ret

    def compute_gae_var(self, rewards, values, gammas, dones, last_value):
        """GAE with a PER-STEP discount factor. Sub-steps cover varying numbers of simulated
        days, so each step t discounts by gamma_annual ** (days_t / 365) — passed in
        `gammas`. With constant gammas this reduces to compute_gae."""
        n = len(rewards)
        adv = np.zeros(n, dtype=np.float32)
        last = 0.0
        vals = list(values) + [last_value]
        for t in reversed(range(n)):
            nonterm = 1.0 - float(dones[t])
            g = float(gammas[t])
            delta = rewards[t] + g * vals[t + 1] * nonterm - vals[t]
            last = delta + g * self.gae_lambda * nonterm * last
            adv[t] = last
        ret = adv + np.asarray(values, dtype=np.float32)
        return adv, ret

    # ---- learning ----
    def update(self, dec_obs, dec_act, dec_logp, dec_adv, all_obs, all_ret):
        """Dual-batch MAPPO update (semi-MDP with a dense critic):
          * ACTOR trains on the DECISION transitions only — dec_obs (D, n_agents, obs_dim),
            dec_act (D, n_agents, act_dim), dec_logp (D, n_agents), dec_adv (D,). Each
            decision's advantage is the GAE at its first sub-step, which captures the full
            discounted future from the decision point.
          * CRITIC trains on EVERY sub-step — all_obs (J, n_agents, obs_dim) global states
            with all_ret (J,) dense return targets. J >= D, so the critic sees a much denser
            value-learning signal for the same simulation cost.
        In annual mode the trainer passes the same arrays for both -> previous behaviour."""
        D = dec_obs.shape[0]
        na = self.n_agents

        # Per-agent decision transitions for the actor (normalised obs).
        obs_flat = dec_obs.reshape(D * na, self.obs_dim)
        if self.normalize_obs:
            obs_flat = self.obs_rms.normalize(obs_flat).astype(np.float32)
        act_flat = dec_act.reshape(D * na, self.act_dim).astype(np.float32)
        logp_flat = dec_logp.reshape(D * na).astype(np.float32)
        # dec_adv is either (D,) — one team advantage per decision, broadcast to every
        # farmer (global reward) — or (D, n_agents) — a per-farmer advantage (per-agent
        # reward). The (D*na,) flatten order matches obs_flat: index = d*na + a.
        dec_adv = np.asarray(dec_adv, dtype=np.float32)
        adv_flat = (np.repeat(dec_adv, na) if dec_adv.ndim == 1
                    else dec_adv.reshape(D * na)).astype(np.float32)
        adv_flat = (adv_flat - adv_flat.mean()) / (adv_flat.std() + 1e-8)

        # Dense global states for the critic (normalised concat, rebuilt from raw obs).
        T = all_obs.shape[0]
        if self.normalize_obs:
            g = self.obs_rms.normalize(all_obs.reshape(T * na, self.obs_dim))
        else:
            g = all_obs.reshape(T * na, self.obs_dim)
        gstates = g.reshape(T, self.global_dim).astype(np.float32)
        ret_t = all_ret

        # Adaptive value-target normalisation: update the running stats with this batch's
        # returns, then train the critic on NORMALISED targets (get_value de-normalises).
        ret_raw = np.asarray(ret_t, dtype=np.float64)
        self.ret_rms.update(ret_raw)
        ret_norm = ((ret_raw - self.ret_rms.mean) / self.ret_rms.std).astype(np.float32)

        obs_t = torch.as_tensor(obs_flat, dtype=torch.float32, device=self.device)
        act_t = torch.as_tensor(act_flat, dtype=torch.float32, device=self.device)
        oldlp_t = torch.as_tensor(logp_flat, dtype=torch.float32, device=self.device)
        adv_tt = torch.as_tensor(adv_flat, dtype=torch.float32, device=self.device)
        g_t = torch.as_tensor(gstates, dtype=torch.float32, device=self.device)
        ret_tt = torch.as_tensor(ret_norm, device=self.device)

        n_trans = obs_t.shape[0]
        ai = np.arange(n_trans)
        ti = np.arange(T)
        stats = {}
        actor_stopped = False
        for epoch in range(self.k_epochs):
            # --- actor (skipped once the KL budget is spent) ---
            if not actor_stopped:
                np.random.shuffle(ai)
                for s in range(0, n_trans, self.minibatch_size):
                    mb = torch.as_tensor(ai[s:s + self.minibatch_size], device=self.device)
                    dist = self.actor.dist(obs_t[mb])
                    logp = dist.log_prob(act_t[mb]).sum(-1)
                    entropy = dist.entropy().sum(-1).mean()

                    # Early stop when the policy drifts too far from the rollout policy.
                    approx_kl = float((oldlp_t[mb] - logp).mean().item())
                    stats["approx_kl"] = approx_kl
                    if self.target_kl is not None and approx_kl > 1.5 * self.target_kl:
                        actor_stopped = True
                        stats["actor_epochs"] = epoch + 1
                        break

                    ratio = torch.exp(logp - oldlp_t[mb])
                    s1 = ratio * adv_tt[mb]
                    s2 = torch.clamp(ratio, 1 - self.clip_eps, 1 + self.clip_eps) * adv_tt[mb]
                    policy_loss = -torch.min(s1, s2).mean() - self.entropy_coef * entropy
                    self.optimizer.zero_grad()
                    policy_loss.backward()
                    nn.utils.clip_grad_norm_(self.actor.parameters(), 0.5)
                    self.optimizer.step()
                    stats["policy_loss"] = float(policy_loss.item())
                    stats["entropy"] = float(entropy.item())
            # --- centralized critic (always trains the full schedule) ---
            np.random.shuffle(ti)
            for s in range(0, T, self.minibatch_size):
                mb = torch.as_tensor(ti[s:s + self.minibatch_size], device=self.device)
                value = self.critic(g_t[mb])
                value_loss = ((value - ret_tt[mb]) ** 2).mean()
                loss = self.value_coef * value_loss
                self.optimizer.zero_grad()
                loss.backward()
                nn.utils.clip_grad_norm_(self.critic.parameters(), 0.5)
                self.optimizer.step()
                stats["value_loss"] = float(value_loss.item())
        stats.setdefault("actor_epochs", self.k_epochs)
        return stats

    # ---- checkpointing ----
    def save(self, path):
        ckpt = {"actor": self.actor.state_dict(), "critic": self.critic.state_dict(),
                "optimizer": self.optimizer.state_dict(),
                "obs_dim": self.obs_dim, "act_dim": self.act_dim, "n_agents": self.n_agents,
                "ret_rms": self.ret_rms.state_dict()}
        if self.normalize_obs:
            ckpt["obs_rms"] = self.obs_rms.state_dict()
        torch.save(ckpt, path)

    def load(self, path):
        ckpt = torch.load(path, map_location=self.device, weights_only=False)
        self.actor.load_state_dict(ckpt["actor"])
        self.critic.load_state_dict(ckpt["critic"])
        try:
            self.optimizer.load_state_dict(ckpt["optimizer"])
        except Exception:
            pass
        if self.normalize_obs and "obs_rms" in ckpt:
            self.obs_rms.load_state_dict(ckpt["obs_rms"])
        # Older checkpoints (pre value-normalisation) don't carry ret_rms.
        if "ret_rms" in ckpt:
            self.ret_rms.load_state_dict(ckpt["ret_rms"])
