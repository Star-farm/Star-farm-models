"""MAPPO training entry point for Starfarm (centralized critic, decentralized actors).

Same macro-step cadence as the IPPO trainer (1 RL step == 1 simulated year), but the
critic is centralized: at each year we also build the GLOBAL state (all farmers' obs
concatenated) and value it once; GAE runs on that single value trajectory, and every
farmer's transition shares its timestep advantage.

Usage:
    py train_mappo.py [path/to/config.yaml]
"""
from __future__ import annotations

import json
import os
import sys

import numpy as np
import yaml

from starfarm_env import StarfarmParallelEnv
from mappo_agent import MAPPOAgent


def load_config(path):
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def _global_profit(infos):
    if not infos:
        return 0.0
    info = next(iter(infos.values()))
    try:
        return float(info.get("global_profit", 0.0))
    except AttributeError:
        return 0.0


def _summarize_actions(actions):
    A = np.clip(np.asarray(list(actions.values()), dtype=float), 0.0, 1.0)
    n = len(A)
    awd = int((A[:, 0] >= 0.5).sum())
    ipm = int((A[:, 2] >= 0.5).sum())
    sust = int((A[:, 3] >= 0.5).sum())
    prem = int((A[:, 4] >= 0.5).sum()) if A.shape[1] > 4 else 0
    s3 = int((A[:, 5] >= 0.5).sum()) if A.shape[1] > 5 else 0
    return (f"AWD={awd}/{n} IPM={ipm}/{n} SUST={sust}/{n} "
            f"PREM={prem}/{n} 3S={s3}/{n} irrQ={A[:, 1].mean():.2f}")


def run_greedy_episode(env, agent, order, sequential=False, rng=None):
    """One deterministic (greedy, no exploration noise) episode. Returns the raw global
    return. This is the TRUE performance of the current policy — the training-episode
    return is polluted by exploration noise, so checkpoint selection uses this instead."""
    obs, _ = env.reset()
    total = 0.0
    actions = None
    while True:
        if actions is None or env.needs_new_action:
            if sequential:
                turn = list(order)
                (rng if rng is not None else np.random).shuffle(turn)
                actions = {}
                for a in turn:
                    o = env.observe_one(a)
                    actions[a] = agent.act_greedy(o)
                    env.inject_one(a, actions[a])
                env.end_decision_round()
            else:
                actions = {a: agent.act_greedy(obs[a]) for a in order}
        obs, _rew, terminated, truncated, infos = env.step(actions)
        total += _global_profit(infos)
        if (truncated and all(truncated.values())) or (terminated and any(terminated.values())):
            break
    return total


def run_episode(env, agent, reward_scale, order, verbose=False, ep=None,
                sequential=False, rng=None, per_agent=False):
    """Collect one episode (works in both annual and sub-step mode).

    Decisions stay ANNUAL: a fresh action is sampled only when env.needs_new_action
    (always True in annual mode; True at year boundaries in sub-step mode), and repeated
    in between. With `sequential=True`, the yearly decision round is taken farmer by
    farmer in a RANDOM order: each farmer observes the commitments already made by the
    earlier deciders (dynamic premium share + decided fraction), which lets the shared
    deterministic policy diversify. The critic sees the DENSE sub-step chain; each
    decision's advantage is the GAE at its first sub-step.

    Returns (dec_obs, dec_act, dec_logp, dec_adv, all_obs, all_ret, raw_return)."""
    obs, _ = env.reset()
    # Dense chain (every step). rew_seq holds the per-FARMER reward each step (in global
    # mode every farmer gets the same team delta -> identical columns).
    all_obs_seq, rew_seq, values, gammas, dones = [], [], [], [], []
    # Decision entries (annual).
    dec_idx, dec_obs_seq, dec_act_seq, dec_logp_seq = [], [], [], []
    current_actions = None
    raw_return = 0.0
    step_i = 0

    while True:
        if current_actions is None or env.needs_new_action:
            if sequential:
                # Random turn order; inject each action immediately so the next farmer
                # in the round observes its effect on the market signals.
                turn = list(order)
                (rng if rng is not None else np.random).shuffle(turn)
                per = {}
                for a in turn:
                    o = env.observe_one(a)
                    act, logp = agent.select_action(o)
                    env.inject_one(a, act)
                    per[a] = (o, act, logp)
                env.end_decision_round()
                obs_row = [per[a][0] for a in order]
                act_row = [per[a][1] for a in order]
                logp_row = [per[a][2] for a in order]
                current_actions = {a: per[a][1] for a in order}
            else:
                actions, obs_row, act_row, logp_row = {}, [], [], []
                for a in order:
                    act, logp = agent.select_action(obs[a])
                    actions[a] = act
                    obs_row.append(np.asarray(obs[a], dtype=np.float32))
                    act_row.append(act)
                    logp_row.append(logp)
                current_actions = actions
            dec_idx.append(step_i)
            dec_obs_seq.append(obs_row)
            dec_act_seq.append(act_row)
            dec_logp_seq.append(logp_row)

        value = agent.get_value(agent.global_state(obs, order))

        next_obs, step_rewards, terminated, truncated, infos = env.step(current_actions)
        gp = _global_profit(infos)
        done = (truncated and all(truncated.values())) or (terminated and any(terminated.values()))

        # Per-step discount proportional to the simulated days this step covered.
        days = getattr(env, "last_substep_days", 0) or getattr(env, "last_days_stepped", 365)
        all_obs_seq.append([np.asarray(obs[a], dtype=np.float32) for a in order])
        # Per-farmer reward this step (global mode -> all equal to the team delta).
        rew_seq.append([float(step_rewards.get(a, gp)) * reward_scale for a in order])
        values.append(value)
        gammas.append(agent.gamma ** (days / 365.0))
        dones.append(done)
        raw_return += gp
        step_i += 1

        if verbose:
            print(f"    ep{ep} step{step_i:3d} (yr{len(dec_idx):2d}, {days:3d}j): "
                  f"global={gp:>11,.0f}  {_summarize_actions(current_actions)}", flush=True)

        obs = next_obs
        if done:
            break

    # Bootstrap the value of the final (truncated) global state.
    last_value = 0.0 if dones[-1] and not (truncated and all(truncated.values())) \
        else agent.get_value(agent.global_state(obs, order))

    rew_arr = np.asarray(rew_seq, dtype=np.float32)        # (J, n_agents)
    dec_i = np.asarray(dec_idx, dtype=int)
    if per_agent:
        # Centralized critic shared by all farmers: it predicts the MEAN per-farmer return,
        # so each farmer's advantage = its own return relative to that shared baseline.
        _, ret_all = agent.compute_gae_var(rew_arr.mean(axis=1), values, gammas, dones, last_value)
        adv_cols = [agent.compute_gae_var(rew_arr[:, i], values, gammas, dones, last_value)[0]
                    for i in range(rew_arr.shape[1])]
        adv_all = np.stack(adv_cols, axis=1)              # (J, n_agents)
        dec_adv = adv_all[dec_i]                          # (D, n_agents)
    else:
        # Team (global) reward: identical for every farmer -> one shared advantage per step.
        adv_all, ret_all = agent.compute_gae_var(rew_arr[:, 0], values, gammas, dones, last_value)
        dec_adv = adv_all[dec_i]                          # (D,)

    dec_obs = np.asarray(dec_obs_seq, dtype=np.float32)    # (D, n_agents, obs_dim)
    dec_act = np.asarray(dec_act_seq, dtype=np.float32)    # (D, n_agents, act_dim)
    dec_logp = np.asarray(dec_logp_seq, dtype=np.float32)  # (D, n_agents)
    all_obs = np.asarray(all_obs_seq, dtype=np.float32)    # (J, n_agents, obs_dim)
    return dec_obs, dec_act, dec_logp, dec_adv, all_obs, ret_all, raw_return


def main():
    cfg_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "config.yaml")
    if not os.path.exists(cfg_path):
        alt = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.path.basename(cfg_path))
        if os.path.exists(alt):
            cfg_path = alt
    cfg = load_config(cfg_path)
    g, t, c = cfg["gama"], cfg["training"], cfg["checkpoint"]
    np.random.seed(t.get("seed", 0))

    ckpt_dir = os.path.join(os.path.dirname(os.path.abspath(cfg_path)), c["dir"])
    os.makedirs(ckpt_dir, exist_ok=True)
    ckpt_path = os.path.join(ckpt_dir, c["filename"])
    best_ckpt_path = os.path.join(ckpt_dir, "best_" + c["filename"])
    rewards_log_path = os.path.join(ckpt_dir, c["rewards_log"])

    print(f"Connecting to GAMA at {g['ip_address']}:{g['port']} ...")
    env = StarfarmParallelEnv(
        gaml_experiment_path=g["controler_path"], gaml_experiment_name=g["experiment_name"],
        gama_ip_address=g["ip_address"], gama_port=g["port"])
    env.MIN_DAYS_PER_YEAR = int(g.get("min_days_per_year", env.MIN_DAYS_PER_YEAR))
    env.MAX_DAYS_PER_YEAR = int(g.get("max_days_per_year", env.MAX_DAYS_PER_YEAR))
    env.YEAR_END_MARGIN = int(g.get("year_end_margin", env.YEAR_END_MARGIN))
    # Sub-step (seasonal reward) mode: 0/absent = annual steps as before.
    env.SUBSTEP_DAYS = int(g.get("substep_days", 0))
    # Sequential decision round (random order, dynamic market signals between deciders).
    sequential = bool(t.get("sequential_decisions", False))
    dec_rng = np.random.default_rng(t.get("seed", 0))
    # Reward objective: "global" (team profit) | "per_agent" (own profit) |
    # "pollution" (minimise own pollution) | "balanced" (own profit - lambda*pollution).
    reward_mode = str(t.get("reward_mode", "global")).lower()
    balance_weight = float(t.get("balance_weight", 1.0))
    env.set_reward_mode(reward_mode, balance_weight)
    # Everything except the team objective trains on per-farm advantages (shared critic).
    per_agent = reward_mode != "global"
    print(f"Reward mode: {reward_mode.upper()}"
          + (f" (lambda={balance_weight:g})" if reward_mode == "balanced" else "")
          + f" | Decision mode: {'SEQUENTIAL (random order)' if sequential else 'simultaneous'} | "
          f"substep_days={env.SUBSTEP_DAYS}")

    possible = sorted(env.possible_agents)
    if not possible:
        raise RuntimeError("No agents reported by the GAMA experiment.")
    obs_dim = int(np.prod(env.observation_space(possible[0]).shape))
    act_dim = int(np.prod(env.action_space(possible[0]).shape))
    n_agents = len(possible)
    print(f"MAPPO | {n_agents} agents | obs_dim={obs_dim} | act_dim={act_dim} | "
          f"global_state_dim={obs_dim * n_agents}")

    agent = MAPPOAgent(
        obs_dim=obs_dim, act_dim=act_dim, n_agents=n_agents,
        hidden_dim=t["hidden_dim"], lr=t["lr"], gamma=t["gamma"], gae_lambda=t["gae_lambda"],
        clip_eps=t["clip_eps"], k_epochs=t["k_epochs"], minibatch_size=t["minibatch_size"],
        entropy_coef=t["entropy_coef"], value_coef=t["value_coef"], normalize_obs=t["normalize_obs"],
        critic_hidden_dim=t.get("critic_hidden_dim"), target_kl=t.get("target_kl", 0.03))

    # Safety net: a fresh (resume:false) launch must never silently clobber an existing
    # checkpoint — back it up first so a mis-set flag can't wipe a trained model.
    if not c.get("resume", False) and os.path.exists(ckpt_path):
        import shutil, time
        stamp = time.strftime("%Y%m%d-%H%M%S")
        shutil.copy2(ckpt_path, f"{ckpt_path}.bak-{stamp}")
        if os.path.exists(rewards_log_path):
            shutil.copy2(rewards_log_path, f"{rewards_log_path}.bak-{stamp}")
        print(f"[safety] resume=false but a checkpoint exists -> backed up with suffix .bak-{stamp}")

    episode_rewards = []
    start_episode = 0
    if c.get("resume", False) and os.path.exists(ckpt_path):
        print(f"Resuming from {ckpt_path}")
        agent.load(ckpt_path)
        if os.path.exists(rewards_log_path):
            episode_rewards = json.load(open(rewards_log_path, encoding="utf-8"))
            start_episode = len(episode_rewards)

    reward_scale = float(t["reward_scale"])
    base_lr = float(t["lr"])
    total_eps = int(t["num_episodes"])
    best_ma = -float("inf")
    verbose = bool(t.get("verbose", True))
    # Entropy decay: explore early, commit late (a constant coef kept IPPO drifting).
    ent0 = float(t["entropy_coef"])
    ent1 = float(t.get("entropy_coef_final", ent0))
    # Periodic deterministic evaluation (true policy performance, used for best-checkpoint).
    eval_every = int(t.get("eval_every", 0))
    eval_log_path = os.path.join(ckpt_dir, "eval_returns.json")
    eval_returns = []
    if os.path.exists(eval_log_path):
        eval_returns = json.load(open(eval_log_path, encoding="utf-8"))
    best_eval = max((e["return"] for e in eval_returns), default=-float("inf"))

    try:
        for ep in range(start_episode, total_eps):
            frac = ep / max(1, total_eps)
            lr_now = base_lr * (1.0 - frac)
            for pg in agent.optimizer.param_groups:
                pg["lr"] = lr_now
            agent.entropy_coef = ent0 + (ent1 - ent0) * frac
            if verbose:
                print(f"--- episode {ep} (lr={lr_now:.2e}, ent={agent.entropy_coef:.4f}) ---", flush=True)

            dec_obs, dec_act, dec_logp, dec_adv, all_obs, ret_all, raw_return = run_episode(
                env, agent, reward_scale, possible, verbose=verbose, ep=ep,
                sequential=sequential, rng=dec_rng, per_agent=per_agent)
            stats = agent.update(dec_obs, dec_act, dec_logp, dec_adv, all_obs, ret_all)
            episode_rewards.append(raw_return)
            ma = np.mean(episode_rewards[-20:])
            print(f"[ep {ep:4d}] global_return={raw_return:,.1f} | ma20={ma:,.1f} | lr={lr_now:.2e} | "
                  f"pi_loss={stats.get('policy_loss', float('nan')):.4f} "
                  f"v_loss={stats.get('value_loss', float('nan')):.4f} "
                  f"H={stats.get('entropy', float('nan')):.3f} "
                  f"kl={stats.get('approx_kl', float('nan')):.4f} "
                  f"aep={stats.get('actor_epochs', '?')}", flush=True)

            # Best checkpoint: by periodic GREEDY eval when enabled (true performance),
            # else by the stochastic ma20 as before.
            if eval_every > 0 and (ep + 1) % eval_every == 0:
                greedy_return = run_greedy_episode(env, agent, possible,
                                                   sequential=sequential, rng=dec_rng)
                eval_returns.append({"episode": ep, "return": greedy_return})
                json.dump(eval_returns, open(eval_log_path, "w", encoding="utf-8"))
                marker = ""
                if greedy_return > best_eval:
                    best_eval = greedy_return
                    agent.save(best_ckpt_path)
                    marker = "  ** new best -> saved"
                print(f"  [eval ep {ep}] greedy_return={greedy_return:,.1f}{marker}", flush=True)
            elif eval_every <= 0 and ma > best_ma:
                best_ma = ma
                agent.save(best_ckpt_path)

            if (ep + 1) % c["save_every"] == 0 or (ep + 1) == total_eps:
                agent.save(ckpt_path)
                json.dump(episode_rewards, open(rewards_log_path, "w", encoding="utf-8"))
                best_str = f"{best_eval:,.0f}" if eval_every > 0 else f"{best_ma:,.0f}"
                print(f"  saved -> {ckpt_path}  (best={best_str})", flush=True)
    finally:
        agent.save(ckpt_path)
        json.dump(episode_rewards, open(rewards_log_path, "w", encoding="utf-8"))
        env.close()
        print("Done. Connection closed.")


if __name__ == "__main__":
    main()
