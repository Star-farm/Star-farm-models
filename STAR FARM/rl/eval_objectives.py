"""Compare the three reward-objective policies (profit / pollution / balanced) on BOTH
axes: total profit and mean pollution. Reuses run_eval() from eval_per_farmer.py; the env
reward mode is fixed to per-farm PROFIT so total_reward is profit for every policy, while
pollution is read from the per-farm observation (per_year.pollution). Same decision-order
seed for all policies -> apples-to-apples.

Writes eval_objectives_comparison.xlsx (comparaison + detail) and eval_objectives_curves.png.
Usage (GAMA server must be running):  py eval_objectives.py
"""
from __future__ import annotations

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
POLICIES = [("Profit", "saved_models_mappo3_peragent", "#08519c"),
            ("Pollution", "saved_models_mappo3_pollution", "#31a354"),
            ("Balanced", "saved_models_mappo3_balanced", "#e6550d")]

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

rows, details = [], []
for label, d, _c in POLICIES:
    ckpt = os.path.join(HERE, d, "best_starfarm_ippo.pth")
    ckpt_n = int(torch.load(ckpt, map_location="cpu", weights_only=False).get("n_agents", n))
    agent = MAPPOAgent(obs_dim=int(np.prod(env.observation_space(order[0]).shape)),
                       act_dim=int(np.prod(env.action_space(order[0]).shape)), n_agents=ckpt_n,
                       hidden_dim=t["hidden_dim"], lr=t["lr"], gamma=t["gamma"], gae_lambda=t["gae_lambda"],
                       clip_eps=t["clip_eps"], k_epochs=t["k_epochs"], minibatch_size=t["minibatch_size"],
                       entropy_coef=t["entropy_coef"], value_coef=t["value_coef"],
                       normalize_obs=t["normalize_obs"], critic_hidden_dim=t.get("critic_hidden_dim"))
    agent.load(ckpt)
    per_year, total_rew, _sanity, n_years = run_eval(env, agent, order, sequential, np.random.default_rng(0))
    profit = sum(total_rew.values())
    rows.append({
        "policy": label, "global_profit": profit, "profit_per_farm": profit / n,
        "mean_pollution": per_year.pollution.mean(), "mean_yield_t_ha": per_year.yield_t_ha.mean(),
        "mean_soil_health": per_year.soil_health.mean(),
        "pct_premium": 100 * (per_year.cultivar == "premium").mean(),
        "pct_AWD": 100 * (per_year.irrigation == "AWD").mean(),
        "pct_IPM": 100 * (per_year.pesticide == "IPM").mean(),
        "pct_durable": 100 * (per_year.fertil == "durable").mean(),
        "pct_3seasons": 100 * (per_year.seasons == 3).mean(),
        "mean_irr_qty": per_year.irr_qty.mean(),
    })
    per_year.insert(0, "policy", label)
    details.append(per_year)
    print(f"{label:10s}: profit={profit:,.0f}  pollution={per_year.pollution.mean():.4f}  "
          f"IPM={100*(per_year.pesticide=='IPM').mean():.0f}%  durable={100*(per_year.fertil=='durable').mean():.0f}%  "
          f"AWD={100*(per_year.irrigation=='AWD').mean():.0f}%  premium={100*(per_year.cultivar=='premium').mean():.0f}%")
env.close()

comp = pd.DataFrame(rows)
det = pd.concat(details, ignore_index=True)
out_xlsx = os.path.join(HERE, "eval_objectives_comparison.xlsx")
with pd.ExcelWriter(out_xlsx, engine="openpyxl") as xl:
    comp.to_excel(xl, sheet_name="comparaison", index=False)
    det.to_excel(xl, sheet_name="detail", index=False)
print("Wrote", out_xlsx)

# reference pollution/profit of the pure-profit policy (for % framing)
prof0 = comp.loc[comp.policy == "Profit", "global_profit"].iloc[0]
poll0 = comp.loc[comp.policy == "Profit", "mean_pollution"].iloc[0]

fig, ax = plt.subplots(2, 2, figsize=(14, 9))

# 1. profit vs pollution trade-off
a = ax[0, 0]
for _, r in comp.iterrows():
    col = dict((p[0], p[2]) for p in POLICIES)[r.policy]
    a.scatter(r.global_profit / 1000, r.mean_pollution, s=140, color=col, zorder=3, label=r.policy)
    a.annotate(r.policy, (r.global_profit / 1000, r.mean_pollution), textcoords="offset points", xytext=(8, 4), fontsize=9)
a.set_title("1. Compromis profit / pollution (haut-gauche = idéal)")
a.set_xlabel("profit global 25 ans (k€)"); a.set_ylabel("pollution moyenne"); a.grid(alpha=0.3)
a.invert_yaxis()

# 2. action mix
a = ax[0, 1]
cats = ["premium", "AWD", "IPM", "durable", "3 sais."]
cols = ["pct_premium", "pct_AWD", "pct_IPM", "pct_durable", "pct_3seasons"]
x = np.arange(len(cats)); w = 0.26
for i, (label, _d, col) in enumerate(POLICIES):
    vals = comp.loc[comp.policy == label, cols].iloc[0].values
    a.bar(x + (i - 1) * w, vals, w, color=col, label=label)
a.set_xticks(x); a.set_xticklabels(cats, fontsize=9)
a.set_title("2. Mix d'actions moyen (% des années)"); a.set_ylabel("%"); a.legend(fontsize=8); a.grid(axis="y", alpha=0.3)

# 3. profit + pollution bars (normalised to the Profit policy = 100%)
a = ax[1, 0]
labels = [p[0] for p in POLICIES]
prof_pct = [100 * comp.loc[comp.policy == l, "global_profit"].iloc[0] / prof0 for l in labels]
poll_pct = [100 * comp.loc[comp.policy == l, "mean_pollution"].iloc[0] / poll0 for l in labels]
xx = np.arange(len(labels)); w = 0.38
a.bar(xx - w / 2, prof_pct, w, color="#3182bd", label="profit (% du Profit)")
a.bar(xx + w / 2, poll_pct, w, color="#a1d99b", label="pollution (% du Profit)")
a.axhline(100, color="grey", ls="--", lw=1)
a.set_xticks(xx); a.set_xticklabels(labels)
a.set_title("3. Profit et pollution relatifs (Profit = 100%)"); a.set_ylabel("%"); a.legend(fontsize=8); a.grid(axis="y", alpha=0.3)

# 4. greedy-profit learning curves
a = ax[1, 1]
for label, d, col in POLICIES:
    p = os.path.join(HERE, d, "eval_returns.json")
    if os.path.exists(p):
        ev = json.load(open(p))
        seen = {}
        for e in ev:
            seen[int(e["episode"])] = e["return"] / 1000
        xs = sorted(seen)
        a.plot(xs, [seen[x] for x in xs], "o-", color=col, ms=3, lw=1.8, label=label)
a.set_title("4. Éval greedy — profit au fil de l'entraînement")
a.set_xlabel("épisode"); a.set_ylabel("profit global (k€)"); a.legend(fontsize=8); a.grid(alpha=0.3)

fig.suptitle("Trois objectifs de récompense — profit vs pollution (politique per-fermier, éval greedy)", fontsize=13)
fig.tight_layout(rect=[0, 0, 1, 0.97])
out_png = os.path.join(HERE, "eval_objectives_curves.png")
fig.savefig(out_png, dpi=130)
print("Wrote", out_png)
