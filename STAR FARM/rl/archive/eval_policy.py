"""Evaluate the trained IPPO policy against baselines.

Answers the questions the training curve alone can't:
  1. Is the learned policy actually BETTER than acting randomly / by fixed rules?
  2. How much do the actions even move the global profit (the leverage ceiling)?

For each "policy" we run `--episodes` full 10-year episodes and report the mean ±
std of the (unscaled) global return = sum over years of sum(Farmer.yearly_profit).

Policies compared:
  * trained        : the learned network, deterministic (argmax per action dim)
  * random         : uniform random MultiDiscrete([2,3,3]) every year
  * fixed_low      : everyone always [CF, pest=0, fert=0]
  * fixed_mid      : everyone always [CF, pest=1, fert=1]
  * fixed_high     : everyone always [AWD, pest=2, fert=2]

Prerequisite: GAMA-server running on the ip/port in config.yaml.

Usage:
    py eval_policy.py [path/to/config.yaml] [--episodes N]
"""

from __future__ import annotations

import argparse
import os

import numpy as np
import yaml

from starfarm_env import StarfarmParallelEnv
from ppo_agent import PPOAgent


def load_config(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def _global_profit(infos):
    """True global objective for the year, from infos[agent]['global_profit'] (same for
    all agents). Mode-independent, so eval measures total profit no matter how trained."""
    if not infos:
        return 0.0
    info = next(iter(infos.values()))
    try:
        return float(info.get("global_profit", 0.0))
    except AttributeError:
        return 0.0


def run_episode(env, choose_action, sequential=False, rng=None):
    """Run one full episode with a callable choose_action(agent, obs) -> np.array.
    With sequential=True the yearly decisions are taken farmer by farmer in random order
    (each seeing the earlier commitments) — same protocol as sequential training. Fixed
    baselines ignore the observation so the protocol does not change their behaviour.
    Returns the true global return = sum over the episode of sum(Farmer.yearly_profit)."""
    obs, _ = env.reset()
    agents = list(obs.keys())
    total = 0.0
    actions = None
    while True:
        if actions is None or env.needs_new_action:
            if sequential:
                turn = list(agents)
                (rng if rng is not None else np.random).shuffle(turn)
                actions = {}
                for a in turn:
                    o = env.observe_one(a)
                    actions[a] = choose_action(a, o)
                    env.inject_one(a, actions[a])
                env.end_decision_round()
            else:
                actions = {a: choose_action(a, obs[a]) for a in agents}
        obs, rewards, terminated, truncated, infos = env.step(actions)
        total += _global_profit(infos)
        if (truncated and all(truncated.values())) or (terminated and any(terminated.values())):
            break
    return total


def summarize(name, returns):
    arr = np.asarray(returns, dtype=np.float64)
    print(f"  {name:12s}  mean={arr.mean():>12,.0f}  std={arr.std():>9,.0f}  "
          f"min={arr.min():>12,.0f}  max={arr.max():>12,.0f}")
    return arr.mean()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("config", nargs="?",
                        default=os.path.join(os.path.dirname(__file__), "config.yaml"))
    parser.add_argument("--episodes", type=int, default=10,
                        help="episodes per policy (default 10)")
    parser.add_argument("--ckpt", default=None,
                        help="explicit checkpoint path (overrides config dir/filename)")
    parser.add_argument("--best", action="store_true",
                        help="load best_<filename> instead of the last-episode checkpoint")
    args = parser.parse_args()

    # Resolve the config relative to this script if it isn't found in the cwd, so the
    # script works no matter which directory you launch it from.
    cfg_path = args.config
    if not os.path.exists(cfg_path):
        alt = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.path.basename(cfg_path))
        if os.path.exists(alt):
            cfg_path = alt
    cfg = load_config(cfg_path)
    g, t, c = cfg["gama"], cfg["training"], cfg["checkpoint"]

    ckpt_dir = os.path.join(os.path.dirname(os.path.abspath(cfg_path)), c["dir"])
    fname = ("best_" + c["filename"]) if args.best else c["filename"]
    ckpt_path = args.ckpt or os.path.join(ckpt_dir, fname)

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
    env.SUBSTEP_DAYS = int(g.get("substep_days", 0))
    sequential = bool(t.get("sequential_decisions", False))
    print(f"Decision mode: {'SEQUENTIAL' if sequential else 'simultaneous'} | "
          f"substep_days={env.SUBSTEP_DAYS}")

    sample = list(env.possible_agents)[0]
    obs_dim = int(np.prod(env.observation_space(sample).shape))
    act_dim = int(np.prod(env.action_space(sample).shape))

    # Pick the agent class from the config ("ippo" default, or "mappo"). Both expose the
    # same act_greedy(obs) interface, so evaluation is identical either way.
    algo = str(t.get("algo", "ippo")).lower()
    if algo == "mappo":
        from mappo_agent import MAPPOAgent
        agent = MAPPOAgent(
            obs_dim=obs_dim, act_dim=act_dim, n_agents=len(env.possible_agents),
            hidden_dim=t["hidden_dim"], lr=t["lr"], gamma=t["gamma"],
            gae_lambda=t["gae_lambda"], clip_eps=t["clip_eps"], k_epochs=t["k_epochs"],
            minibatch_size=t["minibatch_size"], entropy_coef=t["entropy_coef"],
            value_coef=t["value_coef"], normalize_obs=t["normalize_obs"],
            critic_hidden_dim=t.get("critic_hidden_dim"),
        )
    else:
        agent = PPOAgent(
            obs_dim=obs_dim, act_dim=act_dim,
            hidden_dim=t["hidden_dim"], lr=t["lr"], gamma=t["gamma"],
            gae_lambda=t["gae_lambda"], clip_eps=t["clip_eps"], k_epochs=t["k_epochs"],
            minibatch_size=t["minibatch_size"], entropy_coef=t["entropy_coef"],
            value_coef=t["value_coef"], normalize_obs=t["normalize_obs"],
        )
    print(f"Algo: {algo}")
    have_ckpt = os.path.exists(ckpt_path)
    if have_ckpt:
        agent.load(ckpt_path)
        print(f"Loaded checkpoint: {ckpt_path}")
    else:
        print(f"WARNING: no checkpoint at {ckpt_path} — skipping the 'trained' policy.")

    rng = np.random.default_rng(t.get("seed", 0))

    def trained(_a, obs):
        return agent.act_greedy(obs)

    def random_pol(_a, _obs):
        return rng.random(act_dim).astype(np.float32)

    def fixed(vec):
        v = np.asarray(vec, dtype=np.float32)
        return lambda _a, _obs: v

    # Box action = [irr_selector, irr_qty, pesticide, fertilizer, cultivar, seasons], each in [0,1].
    policies = {}
    if have_ckpt:
        policies["trained"] = trained
    policies.update({
        "random": random_pol,
        # CF / BAU pest / BAU fert / standard cultivar / 3 seasons (conventional intensive)
        "fixed_low": fixed([0.0, 0.5, 0.0, 0.0, 0.0, 1.0]),
        # CF / IPM / sustainable / standard / 3 seasons
        "fixed_mid": fixed([0.0, 0.5, 0.5, 0.5, 0.0, 1.0]),
        # AWD / IPM / sustainable / premium cultivar / 2 seasons
        "fixed_high": fixed([1.0, 0.5, 1.0, 1.0, 1.0, 0.0]),
    })

    n = args.episodes
    print(f"\nEvaluating {len(policies)} policies x {n} episodes each "
          f"(global return = sum over the episode of sum(Farmer.yearly_profit)):\n")

    means = {}
    try:
        eval_rng = np.random.default_rng(t.get("seed", 0))
        for name, fn in policies.items():
            returns = [run_episode(env, fn, sequential=sequential, rng=eval_rng) for _ in range(n)]
            means[name] = summarize(name, returns)
    finally:
        env.close()

    if "trained" in means:
        base = means.get("random")
        print("\nTrained vs baselines (mean global return):")
        for name, m in means.items():
            if name == "trained":
                continue
            diff = means["trained"] - m
            pct = 100.0 * diff / abs(m) if m else float("nan")
            print(f"  trained - {name:10s} = {diff:>+12,.0f}  ({pct:>+5.1f}%)")
    print("\nDone.")


if __name__ == "__main__":
    main()
