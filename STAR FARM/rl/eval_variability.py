"""Reproducibility test: run N greedy episodes of the per-agent policy and measure how much
the behaviour varies under the environment's (slight) stochasticity + the random decision
order. Answers "is the behaviour redundant or not?".

Reuses run_eval() from eval_per_farmer.py (no duplication). For each episode it records the
global profit, every farmer's 25-year profit, and the per-year count of farms in premium.
Writes an Excel (resume / reward_par_episode / premium_par_an_episodes) and a 2x2 figure.

Usage (GAMA server must be running):
    py eval_variability.py [config.yaml] [--episodes 5] [--best] [--last]
"""
from __future__ import annotations

import argparse
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

from starfarm_env import StarfarmParallelEnv
from mappo_agent import MAPPOAgent
from eval_per_farmer import run_eval, load_config


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("config", nargs="?",
                    default=os.path.join(os.path.dirname(__file__), "config_mappo3_peragent.yaml"))
    ap.add_argument("--episodes", type=int, default=5)
    ap.add_argument("--best", action="store_true")
    ap.add_argument("--last", action="store_true")
    ap.add_argument("--ckpt", default=None)
    args = ap.parse_args()

    cfg_path = args.config
    if not os.path.exists(cfg_path):
        alt = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.path.basename(cfg_path))
        if os.path.exists(alt):
            cfg_path = alt
    cfg = load_config(cfg_path)
    g, t, c = cfg["gama"], cfg["training"], cfg["checkpoint"]
    base = os.path.dirname(os.path.abspath(cfg_path))

    ckpt_dir = os.path.join(base, c["dir"])
    fname = c["filename"] if args.last else ("best_" + c["filename"])
    ckpt_path = args.ckpt or os.path.join(ckpt_dir, fname)
    out_xlsx = os.path.join(base, "eval_variability_peragent.xlsx")
    out_png = os.path.join(base, "eval_variability_curves.png")

    print(f"Connecting to GAMA at {g['ip_address']}:{g['port']} ...")
    env = StarfarmParallelEnv(
        gaml_experiment_path=g["controler_path"], gaml_experiment_name=g["experiment_name"],
        gama_ip_address=g["ip_address"], gama_port=g["port"])
    env.MIN_DAYS_PER_YEAR = int(g.get("min_days_per_year", env.MIN_DAYS_PER_YEAR))
    env.MAX_DAYS_PER_YEAR = int(g.get("max_days_per_year", env.MAX_DAYS_PER_YEAR))
    env.YEAR_END_MARGIN = int(g.get("year_end_margin", env.YEAR_END_MARGIN))
    env.SUBSTEP_DAYS = int(g.get("substep_days", 0))
    sequential = bool(t.get("sequential_decisions", False))
    env.set_reward_mode(True)
    print(f"Reward mode: PER-AGENT | sequential={sequential} | substep_days={env.SUBSTEP_DAYS}")

    order = sorted(env.possible_agents)
    obs_dim = int(np.prod(env.observation_space(order[0]).shape))
    act_dim = int(np.prod(env.action_space(order[0]).shape))
    agent = MAPPOAgent(
        obs_dim=obs_dim, act_dim=act_dim, n_agents=len(order),
        hidden_dim=t["hidden_dim"], lr=t["lr"], gamma=t["gamma"], gae_lambda=t["gae_lambda"],
        clip_eps=t["clip_eps"], k_epochs=t["k_epochs"], minibatch_size=t["minibatch_size"],
        entropy_coef=t["entropy_coef"], value_coef=t["value_coef"], normalize_obs=t["normalize_obs"],
        critic_hidden_dim=t.get("critic_hidden_dim"))
    if not os.path.exists(ckpt_path):
        raise FileNotFoundError(ckpt_path)
    agent.load(ckpt_path)
    print(f"Loaded checkpoint: {ckpt_path}\n")

    rng = np.random.default_rng(t.get("seed", 0))
    N = args.episodes
    global_profits = []
    farmer_tot = {a: [] for a in order}      # farmer -> [profit per episode]
    pct_prem = {a: [] for a in order}        # farmer -> [% premium years per episode]
    nprem_series = {}                        # episode -> Series(year -> #premium farms)

    for ep in range(N):
        per_year, total_rew, sanity, n_years = run_eval(env, agent, order, sequential, rng)
        gp = sum(total_rew.values())
        global_profits.append(gp)
        for a in order:
            farmer_tot[a].append(total_rew[a])
            sub = per_year[per_year.farmer == a]
            pct_prem[a].append(100.0 * (sub.cultivar == "premium").mean())
        nprem_series[ep] = per_year[per_year.cultivar == "premium"].groupby("year").size()
        print(f"  episode {ep}: global={gp:,.0f}  (sanity {sanity:,.0f})")
    env.close()

    gp_arr = np.array(global_profits)
    cv = 100.0 * gp_arr.std() / gp_arr.mean()
    print(f"\nGlobal profit over {N} eps: mean={gp_arr.mean():,.0f}  std={gp_arr.std():,.0f}  "
          f"min={gp_arr.min():,.0f}  max={gp_arr.max():,.0f}  CV={cv:.1f}%")

    # farmers sorted by mean profit (best first) for stable display / ranking-stability check
    ranked = sorted(order, key=lambda a: -np.mean(farmer_tot[a]))

    # ---- DataFrames ----
    resume = pd.DataFrame({"episode": range(N), "global_profit": gp_arr})
    resume.loc["mean"] = ["", gp_arr.mean()]
    resume.loc["std"] = ["", gp_arr.std()]
    resume.loc["CV_%"] = ["", cv]

    reward_ep = pd.DataFrame({a: farmer_tot[a] for a in ranked}, index=[f"ep{e}" for e in range(N)]).T
    reward_ep["mean"] = reward_ep.mean(axis=1)
    reward_ep["std"] = reward_ep.iloc[:, :N].std(axis=1)
    reward_ep["CV_%"] = 100.0 * reward_ep["std"] / reward_ep["mean"]

    nprem_df = pd.DataFrame(nprem_series).reindex(
        range(max(s.index.max() for s in nprem_series.values()) + 1)).fillna(0).astype(int)
    nprem_df.columns = [f"ep{e}" for e in range(N)]
    nprem_df.index.name = "year"

    with pd.ExcelWriter(out_xlsx, engine="openpyxl") as xl:
        resume.to_excel(xl, sheet_name="resume", index=False)
        reward_ep.to_excel(xl, sheet_name="reward_par_episode")
        nprem_df.to_excel(xl, sheet_name="premium_par_an_episodes")
    print(f"Wrote {out_xlsx}")

    # ---- figure 2x2 ----
    fig, ax = plt.subplots(2, 2, figsize=(14, 9))

    a0 = ax[0, 0]
    a0.bar(range(N), gp_arr / 1000.0, color="#3182bd")
    a0.axhline(gp_arr.mean() / 1000.0, color="#e6550d", ls="--", label=f"moyenne {gp_arr.mean()/1000:,.0f}k")
    a0.set_title(f"1. Profit global par épisode (CV = {cv:.1f}%)")
    a0.set_xlabel("épisode"); a0.set_ylabel("profit global (k€)"); a0.legend(fontsize=9)
    a0.grid(axis="y", alpha=0.3)

    a1 = ax[0, 1]
    for e in range(N):
        a1.plot(nprem_df.index, nprem_df[f"ep{e}"], marker="o", ms=3, lw=1.4, alpha=0.8, label=f"ep{e}")
    a1.set_title("2. # fermes en premium par année — les épisodes")
    a1.set_xlabel("année"); a1.set_ylabel("# fermes premium"); a1.set_ylim(0, len(order))
    a1.legend(fontsize=8, ncol=N); a1.grid(alpha=0.3)

    a2 = ax[1, 0]
    a2.boxplot([farmer_tot[a] for a in ranked], showmeans=True)
    a2.set_xticks(range(1, len(ranked) + 1))
    a2.set_xticklabels([a.replace("Farmer", "F") for a in ranked], rotation=45, fontsize=8)
    a2.set_title("3. Profit total par ferme sur les épisodes (classement stable ?)")
    a2.set_ylabel("profit 25 ans (€)"); a2.grid(axis="y", alpha=0.3)

    a3 = ax[1, 1]
    means = [np.mean(pct_prem[a]) for a in ranked]
    stds = [np.std(pct_prem[a]) for a in ranked]
    a3.bar(range(len(ranked)), means, yerr=stds, capsize=3, color="#31a354")
    a3.set_xticks(range(len(ranked)))
    a3.set_xticklabels([a.replace("Farmer", "F") for a in ranked], rotation=45, fontsize=8)
    a3.set_title("4. % d'années en premium par ferme (moyenne ± écart-type)")
    a3.set_ylabel("% premium"); a3.grid(axis="y", alpha=0.3)

    fig.suptitle(f"Reproductibilité sur {N} épisodes greedy — politique per-agent", fontsize=13)
    fig.tight_layout(rect=[0, 0, 1, 0.97])
    fig.savefig(out_png, dpi=130)
    print(f"Wrote {out_png}")


if __name__ == "__main__":
    main()
