"""Compare the reward-objective policies (profit / balanced sweep / pollution) on BOTH
axes: total profit and mean pollution. Reuses run_eval() from eval_per_farmer.py; the env
reward mode is fixed to per-farm PROFIT so total_reward is profit for every policy, while
pollution is read from the per-farm observation (per_year.pollution). Same decision-order
seeds for all policies -> apples-to-apples.

CLI:
  --suffix S      output files eval_objectives_comparison<S>.xlsx / _curves<S>.png
  --stochastic    SAMPLE the policy distribution instead of greedy (mean) actions
  --only LABEL    evaluate a single policy (label substring match, e.g. Pollution)
  --episodes N    episodes per policy; means (+/- std) reported when N > 1

Usage (GAMA server must be running):
    py eval_objectives.py --suffix _greedy10
    py eval_objectives.py --suffix _stoch10 --stochastic --episodes 3
"""
from __future__ import annotations

import argparse
import json
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import torch

from starfarm_env import StarfarmParallelEnv
from mappo_agent import MAPPOAgent
from eval_per_farmer import run_eval, load_config

HERE = os.path.dirname(os.path.abspath(__file__))
# (label, dir, color, checkpoint). The best_ checkpoint is selected by greedy PROFIT, which
# is only meaningful for the Profit policy; objective-trained policies (pollution/balanced)
# use their FINAL checkpoint (converged under their own objective, not profit-cherry-picked).
POLICIES = [("Profit", "saved_models_mappo3_peragent", "#08519c", "best_starfarm_ippo.pth"),
            ("Bal-20k", "saved_models_mappo3_balanced", "#fdae6b", "starfarm_ippo.pth"),
            ("Bal-100k", "saved_models_mappo3_balanced_l100k", "#e6550d", "starfarm_ippo.pth"),
            ("Bal-200k", "saved_models_mappo3_balanced_l200k", "#a63603", "starfarm_ippo.pth"),
            ("Bal-400k", "saved_models_mappo3_balanced_l400k", "#7a0177", "starfarm_ippo.pth"),
            ("Pollution", "saved_models_mappo3_pollution", "#31a354", "starfarm_ippo.pth")]

ap = argparse.ArgumentParser()
ap.add_argument("--suffix", default="", help="output filename suffix (e.g. _bigmodel)")
ap.add_argument("--stochastic", action="store_true",
                help="sample the policy distribution instead of greedy actions")
ap.add_argument("--only", default=None, help="only evaluate policies whose label contains this")
ap.add_argument("--episodes", type=int, default=1, help="episodes per policy")
args = ap.parse_args()

policies = [p for p in POLICIES if args.only is None or args.only.lower() in p[0].lower()]
if not policies:
    raise SystemExit(f"--only {args.only!r} matches no policy label")
MODE = "STOCHASTIC (sampled)" if args.stochastic else "GREEDY (deterministic)"

cfg = load_config(os.path.join(HERE, "config_mappo3_peragent.yaml"))
g, t = cfg["gama"], cfg["training"]

env = StarfarmParallelEnv(gaml_experiment_path=g["controler_path"], gaml_experiment_name=g["experiment_name"],
                          gama_ip_address=g["ip_address"], gama_port=g["port"])
env.MIN_DAYS_PER_YEAR = int(g["min_days_per_year"]); env.MAX_DAYS_PER_YEAR = int(g["max_days_per_year"])
env.YEAR_END_MARGIN = int(g["year_end_margin"]); env.SUBSTEP_DAYS = int(g["substep_days"])
env.set_reward_mode("per_agent")   # rewards = profit for ALL policies (pollution read from obs)
order = sorted(env.possible_agents)
n = len(order)
sequential = bool(t.get("sequential_decisions", True))
print(f"Mode: {MODE} | {len(policies)} policies x {args.episodes} episode(s) | {n} farmers", flush=True)

rows, details = [], []
for label, d, _c, ckpt_name in policies:
    ckpt = os.path.join(HERE, d, ckpt_name)
    ckpt_n = int(torch.load(ckpt, map_location="cpu", weights_only=False).get("n_agents", n))
    agent = MAPPOAgent(obs_dim=int(np.prod(env.observation_space(order[0]).shape)),
                       act_dim=int(np.prod(env.action_space(order[0]).shape)), n_agents=ckpt_n,
                       hidden_dim=t["hidden_dim"], lr=t["lr"], gamma=t["gamma"], gae_lambda=t["gae_lambda"],
                       clip_eps=t["clip_eps"], k_epochs=t["k_epochs"], minibatch_size=t["minibatch_size"],
                       entropy_coef=t["entropy_coef"], value_coef=t["value_coef"],
                       normalize_obs=t["normalize_obs"], critic_hidden_dim=t.get("critic_hidden_dim"))
    agent.load(ckpt)

    ep_prof, ep_poll, pys = [], [], []
    for e in range(args.episodes):
        per_year, total_rew, _sanity, n_years = run_eval(
            env, agent, order, sequential, np.random.default_rng(e), stochastic=args.stochastic)
        prof = sum(total_rew.values())
        ep_prof.append(prof)
        ep_poll.append(per_year.pollution.mean())
        per_year.insert(0, "episode", e)
        pys.append(per_year)
        if args.episodes > 1:
            print(f"    {label} ep{e}: profit={prof:,.0f}  pollution={ep_poll[-1]:.4f}", flush=True)
    allpy = pd.concat(pys, ignore_index=True)
    rows.append({
        "policy": label,
        "global_profit": float(np.mean(ep_prof)), "profit_std": float(np.std(ep_prof)),
        "profit_per_farm": float(np.mean(ep_prof)) / n,
        "mean_pollution": float(np.mean(ep_poll)), "pollution_std": float(np.std(ep_poll)),
        "mean_yield_t_ha": allpy.yield_t_ha.mean(), "mean_soil_health": allpy.soil_health.mean(),
        "pct_premium": 100 * (allpy.cultivar == "premium").mean(),
        "pct_AWD": 100 * (allpy.irrigation == "AWD").mean(),
        "pct_IPM": 100 * (allpy.pesticide == "IPM").mean(),
        "pct_durable": 100 * (allpy.fertil == "durable").mean(),
        "pct_3seasons": 100 * (allpy.seasons == 3).mean(),
        "mean_irr_qty": allpy.irr_qty.mean(),
    })
    allpy.insert(0, "policy", label)
    details.append(allpy)
    print(f"{label:10s}: profit={np.mean(ep_prof):,.0f}"
          + (f" (+/-{np.std(ep_prof):,.0f})" if args.episodes > 1 else "")
          + f"  pollution={np.mean(ep_poll):.4f}"
          + (f" (+/-{np.std(ep_poll):.4f})" if args.episodes > 1 else "")
          + f"  IPM={100*(allpy.pesticide=='IPM').mean():.0f}%  durable={100*(allpy.fertil=='durable').mean():.0f}%  "
          f"AWD={100*(allpy.irrigation=='AWD').mean():.0f}%  premium={100*(allpy.cultivar=='premium').mean():.0f}%",
          flush=True)
env.close()

comp = pd.DataFrame(rows)
det = pd.concat(details, ignore_index=True)
out_xlsx = os.path.join(HERE, f"eval_objectives_comparison{args.suffix}.xlsx")
with pd.ExcelWriter(out_xlsx, engine="openpyxl") as xl:
    comp.to_excel(xl, sheet_name="comparaison", index=False)
    det.to_excel(xl, sheet_name="detail", index=False)
print("Wrote", out_xlsx)

# ------------------------------------------------------------------ figure (skip if --only)
if len(policies) > 1:
    colmap = {p[0]: p[2] for p in POLICIES}
    prof0 = comp.loc[comp.policy == "Profit", "global_profit"].iloc[0] if "Profit" in set(comp.policy) else comp.global_profit.max()
    poll0 = comp.loc[comp.policy == "Profit", "mean_pollution"].iloc[0] if "Profit" in set(comp.policy) else comp.mean_pollution.iloc[0]

    fig, ax = plt.subplots(2, 2, figsize=(14, 9))

    a = ax[0, 0]
    for _, r in comp.iterrows():
        a.errorbar(r.global_profit / 1000, r.mean_pollution,
                   xerr=(r.profit_std / 1000) if args.episodes > 1 else None,
                   yerr=r.pollution_std if args.episodes > 1 else None,
                   fmt="o", ms=11, color=colmap[r.policy], capsize=3, zorder=3)
        a.annotate(r.policy, (r.global_profit / 1000, r.mean_pollution),
                   textcoords="offset points", xytext=(8, 4), fontsize=9)
    a.set_title("1. Compromis profit / pollution (haut-droite = idéal)")
    a.set_xlabel("profit global 25 ans (k€)"); a.set_ylabel("pollution moyenne"); a.grid(alpha=0.3)
    a.invert_yaxis()

    a = ax[0, 1]
    cats = ["premium", "AWD", "IPM", "durable", "3 sais."]
    cols = ["pct_premium", "pct_AWD", "pct_IPM", "pct_durable", "pct_3seasons"]
    x = np.arange(len(cats)); w = 0.8 / len(comp)
    for i, (_, r) in enumerate(comp.iterrows()):
        a.bar(x + (i - (len(comp) - 1) / 2) * w, r[cols].values, w, color=colmap[r.policy], label=r.policy)
    a.set_xticks(x); a.set_xticklabels(cats, fontsize=9)
    a.set_title("2. Mix d'actions moyen (% des années)"); a.set_ylabel("%")
    a.legend(fontsize=8); a.grid(axis="y", alpha=0.3)

    a = ax[1, 0]
    labels = list(comp.policy)
    prof_pct = [100 * v / prof0 for v in comp.global_profit]
    poll_pct = [100 * v / poll0 for v in comp.mean_pollution]
    xx = np.arange(len(labels)); w = 0.38
    a.bar(xx - w / 2, prof_pct, w, color="#3182bd", label="profit (% du Profit)")
    a.bar(xx + w / 2, poll_pct, w, color="#a1d99b", label="pollution (% du Profit)")
    a.axhline(100, color="grey", ls="--", lw=1)
    a.set_xticks(xx); a.set_xticklabels(labels, fontsize=8)
    a.set_title("3. Profit et pollution relatifs (Profit = 100%)"); a.set_ylabel("%")
    a.legend(fontsize=8); a.grid(axis="y", alpha=0.3)

    a = ax[1, 1]
    for label, d, col, _ck in POLICIES:
        p = os.path.join(HERE, d, "eval_returns.json")
        if os.path.exists(p) and label in set(comp.policy):
            seen = {}
            for e in json.load(open(p)):
                seen[int(e["episode"])] = e["return"] / 1000
            xs = sorted(seen)
            a.plot(xs, [seen[x] for x in xs], "o-", color=col, ms=3, lw=1.8, label=label)
    a.set_title("4. Éval greedy — profit au fil de l'entraînement")
    a.set_xlabel("épisode"); a.set_ylabel("profit global (k€)"); a.legend(fontsize=8); a.grid(alpha=0.3)

    fig.suptitle(f"Objectifs de récompense — profit vs pollution | mode {MODE}, "
                 f"{args.episodes} épisode(s)/politique, {n} fermes", fontsize=13)
    fig.tight_layout(rect=[0, 0, 1, 0.97])
    out_png = os.path.join(HERE, f"eval_objectives_curves{args.suffix}.png")
    fig.savefig(out_png, dpi=130)
    print("Wrote", out_png)
