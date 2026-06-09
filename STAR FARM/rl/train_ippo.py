"""IPPO training entry point for the Starfarm MARL setup.

Prerequisite: a GAMA-server must be running and reachable at the ip/port set in
config.yaml (the gama-pettingzoo examples start it on port 1001). This script then:

  1. Connects via StarfarmParallelEnv (loads the embedded ReinforcementLearning.gaml,
     experiment "marl" — PetzAgent lives inside the Starfarm world, no co-model).
  2. Runs `num_episodes` episodes. Each step == one simulated year; each episode is
     `rl_max_years` years (truncation is signalled by publish_rl on the last year).
  3. Pools all farmers' transitions (shared-weights policy) and does a PPO update
     per episode.
  4. Checkpoints the policy and logs the per-episode global reward.

Usage:
    python train_ippo.py [path/to/config.yaml]
"""

from __future__ import annotations

import json
import os
import sys

import numpy as np
import yaml

from starfarm_env import StarfarmParallelEnv
from ppo_agent import PPOAgent, RolloutBuffer


def load_config(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def _global_profit(infos):
    """The true global objective for a year, published in infos[agent]['global_profit']
    (same value for every agent). Mode-independent, unlike the per-agent reward."""
    if not infos:
        return 0.0
    info = next(iter(infos.values()))
    try:
        return float(info.get("global_profit", 0.0))
    except AttributeError:
        return 0.0


def _summarize_actions(actions):
    """Human-readable summary of one year's actions across farmers. Box(6) =
    [irr_selector, irr_qty, pesticide, fertilizer, cultivar, seasons], clamped to [0,1]
    then thresholded at 0.5 the same way the GAML side decodes them."""
    A = np.clip(np.asarray(list(actions.values()), dtype=float), 0.0, 1.0)
    n = len(A)
    awd = int((A[:, 0] >= 0.5).sum())
    ipm = int((A[:, 2] >= 0.5).sum())
    sust = int((A[:, 3] >= 0.5).sum())
    prem = int((A[:, 4] >= 0.5).sum()) if A.shape[1] > 4 else 0
    s3 = int((A[:, 5] >= 0.5).sum()) if A.shape[1] > 5 else 0
    return (f"AWD={awd}/{n} IPM={ipm}/{n} SUST={sust}/{n} "
            f"PREM={prem}/{n} 3S={s3}/{n} irrQ={A[:, 1].mean():.2f}")


def run_episode(env, agent, reward_scale, verbose=False, ep=None):
    """Collect one episode into per-agent rollout buffers. Returns (buffers, raw_return)."""
    obs, _ = env.reset()
    agents = list(obs.keys())
    buffers = {a: RolloutBuffer() for a in agents}
    last_obs = dict(obs)
    raw_episode_reward = 0.0
    year = 0

    while True:
        actions, logps, values = {}, {}, {}
        for a in agents:
            act, logp, val = agent.select_action(obs[a])
            actions[a] = act
            logps[a] = logp
            values[a] = val

        next_obs, rewards, terminated, truncated, infos = env.step(actions)
        year += 1

        done_flags = {a: bool(terminated.get(a, False) or truncated.get(a, False)) for a in agents}
        for a in agents:
            r = rewards.get(a, 0.0) * reward_scale
            buffers[a].add(obs[a], actions[a], logps[a], r, values[a], done_flags[a])
            last_obs[a] = next_obs.get(a, obs[a])

        # Track the TRUE global objective (sum of all farmers' profit), read from infos,
        # so the logged metric is the same regardless of the reward mode used for learning.
        gp = _global_profit(infos)
        raw_episode_reward += gp

        if verbose:
            days = getattr(env, "last_days_stepped", 0)
            jump = getattr(env, "last_coarse_jump", 0)
            print(f"    ep{ep} yr{year:2d}: days={days:3d} (jump {jump}+poll {days - jump})  "
                  f"global={gp:>11,.0f}  {_summarize_actions(actions)}", flush=True)

        obs = next_obs
        if (truncated and all(truncated.values())) or (terminated and any(terminated.values())):
            break

    # GAE per agent (bootstrap with the value of the final observation).
    for a, buf in buffers.items():
        last_v = agent.value_of(last_obs[a]) if len(buf) and not buf.dones[-1] else 0.0
        agent.compute_gae(buf, last_v)

    return list(buffers.values()), raw_episode_reward


def main():
    cfg_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "config.yaml")
    cfg = load_config(cfg_path)

    g = cfg["gama"]
    t = cfg["training"]
    c = cfg["checkpoint"]

    np.random.seed(t.get("seed", 0))

    ckpt_dir = os.path.join(os.path.dirname(os.path.abspath(cfg_path)), c["dir"])
    os.makedirs(ckpt_dir, exist_ok=True)
    ckpt_path = os.path.join(ckpt_dir, c["filename"])
    rewards_log_path = os.path.join(ckpt_dir, c["rewards_log"])

    print(f"Connecting to GAMA at {g['ip_address']}:{g['port']} ...")
    env = StarfarmParallelEnv(
        gaml_experiment_path=g["controler_path"],
        gaml_experiment_name=g["experiment_name"],
        gama_ip_address=g["ip_address"],
        gama_port=g["port"],
    )

    env.MIN_DAYS_PER_YEAR = int(g.get("min_days_per_year", env.MIN_DAYS_PER_YEAR))
    env.MAX_DAYS_PER_YEAR = int(g.get("max_days_per_year", env.MAX_DAYS_PER_YEAR))
    env.YEAR_END_MARGIN = int(g.get("year_end_margin", env.YEAR_END_MARGIN))

    reward_mode = t.get("reward_mode", "global")
    env.set_reward_mode(reward_mode == "per_agent")
    print(f"Reward mode: {reward_mode} | macro-step jump: {env.MIN_DAYS_PER_YEAR} days")

    possible = list(env.possible_agents)
    if not possible:
        raise RuntimeError("No agents reported by the GAMA controler (PetzAgent[0].possible_agents was empty).")
    sample_agent = possible[0]
    obs_space = env.observation_space(sample_agent)
    act_space = env.action_space(sample_agent)
    obs_dim = int(np.prod(obs_space.shape))
    act_dim = int(np.prod(act_space.shape))
    print(f"{len(possible)} agents | obs_dim={obs_dim} | action Box(dim={act_dim})")

    agent = PPOAgent(
        obs_dim=obs_dim, act_dim=act_dim,
        hidden_dim=t["hidden_dim"], lr=t["lr"], gamma=t["gamma"],
        gae_lambda=t["gae_lambda"], clip_eps=t["clip_eps"], k_epochs=t["k_epochs"],
        minibatch_size=t["minibatch_size"], entropy_coef=t["entropy_coef"],
        value_coef=t["value_coef"], normalize_obs=t["normalize_obs"],
    )

    episode_rewards = []
    start_episode = 0
    if c.get("resume", False) and os.path.exists(ckpt_path):
        print(f"Resuming from checkpoint {ckpt_path}")
        agent.load(ckpt_path)
        if os.path.exists(rewards_log_path):
            with open(rewards_log_path, "r", encoding="utf-8") as f:
                episode_rewards = json.load(f)
            start_episode = len(episode_rewards)

    reward_scale = float(t["reward_scale"])

    # Keep the BEST model separately: the last-episode policy is often worse than the
    # peak (PPO drifts late in training). best_ckpt_path holds the highest-ma20 model.
    best_ckpt_path = os.path.join(ckpt_dir, "best_" + c["filename"])
    best_ma = -float("inf")
    # Linear learning-rate annealing 3e-4 -> 0 over the run: removes the late-training
    # drift where a fixed LR keeps overshooting after the policy has converged.
    base_lr = float(t["lr"])
    total_eps = int(t["num_episodes"])
    # Per-year detail logging (one line per simulated year inside each episode).
    verbose = bool(t.get("verbose", True))

    try:
        for ep in range(start_episode, t["num_episodes"]):
            lr_now = base_lr * (1.0 - ep / max(1, total_eps))
            for pg in agent.optimizer.param_groups:
                pg["lr"] = lr_now

            if verbose:
                print(f"--- episode {ep} (lr={lr_now:.2e}) ---", flush=True)
            buffers, raw_return = run_episode(env, agent, reward_scale, verbose=verbose, ep=ep)
            stats = agent.update(buffers)
            episode_rewards.append(raw_return)

            ma = np.mean(episode_rewards[-20:])
            print(f"[ep {ep:4d}] global_return={raw_return:,.1f} | ma20={ma:,.1f} | lr={lr_now:.2e} | "
                  f"pi_loss={stats.get('policy_loss', float('nan')):.4f} "
                  f"v_loss={stats.get('value_loss', float('nan')):.4f} "
                  f"H={stats.get('entropy', float('nan')):.3f}", flush=True)

            if ma > best_ma:
                best_ma = ma
                agent.save(best_ckpt_path)

            if (ep + 1) % c["save_every"] == 0 or (ep + 1) == t["num_episodes"]:
                agent.save(ckpt_path)
                with open(rewards_log_path, "w", encoding="utf-8") as f:
                    json.dump(episode_rewards, f)
                print(f"  saved checkpoint -> {ckpt_path}  (best ma20={best_ma:,.0f} -> {os.path.basename(best_ckpt_path)})")
    finally:
        # Always persist progress and close the GAMA connection.
        agent.save(ckpt_path)
        with open(rewards_log_path, "w", encoding="utf-8") as f:
            json.dump(episode_rewards, f)
        env.close()
        print("Done. Connection closed.")


if __name__ == "__main__":
    main()
