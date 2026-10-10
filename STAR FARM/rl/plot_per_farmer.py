"""Curves from the per-farmer evaluation workbook (eval_per_farmer_peragent.xlsx).

Reads the 'detail' (one row per year x farmer) and 'synthese_fermiers' sheets and draws a
2x3 panel of the most informative views:
  1. cumulative profit per farmer        -> how the gap between farms builds over 25 years
  2. #farms in premium + premium price   -> the minority/turn-taking dynamic over time
  3. price vs #premium farms (scatter)    -> market saturation law (more premium -> lower price)
  4. %premium vs total profit (scatter)   -> the headline correlation
  5. annual reward: premium vs standard   -> the per-year incentive to go premium
  6. %premium vs mean yield               -> premium/yield trade-off

Usage:  py plot_per_farmer.py [path/to/eval_per_farmer_peragent.xlsx]
"""
from __future__ import annotations

import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
XLSX = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "eval_per_farmer_peragent.xlsx")
OUT = os.path.join(os.path.dirname(os.path.abspath(XLSX)), "eval_per_farmer_curves.png")

det = pd.read_excel(XLSX, sheet_name="detail")
syn = pd.read_excel(XLSX, sheet_name="synthese_fermiers")
syn = syn.sort_values("total_reward", ascending=False).reset_index(drop=True)
farmers = list(syn.farmer)
years = sorted(det.year.unique())
cmap = plt.cm.viridis(np.linspace(0, 0.95, len(farmers)))

fig, axes = plt.subplots(2, 3, figsize=(16.5, 9))

# 1) cumulative profit per farmer (k EUR), best->worst colour
ax = axes[0, 0]
piv = det.pivot(index="year", columns="farmer", values="reward_year").sort_index() / 1000.0
for col, c in zip(farmers, cmap):
    ax.plot(piv.index, piv[col].cumsum(), color=c, lw=1.8, label=col)
ax.set_title("1. Profit cumulé par fermier")
ax.set_xlabel("Année"); ax.set_ylabel("Profit cumulé (k€)")
ax.legend(fontsize=6, ncol=2, loc="upper left")
ax.grid(alpha=0.3)

# 2) #premium farms + realised global yearly profit (twin axis)
ax = axes[0, 1]
nprem = det[det.cultivar == "premium"].groupby("year").size().reindex(years, fill_value=0)
gprof = det.groupby("year").reward_year.sum().reindex(years) / 1000.0
ax.bar(years, nprem.values, color="#9ecae1", label="# fermes en premium")
ax.set_ylabel("# fermes premium", color="#3182bd")
ax.set_xlabel("Année"); ax.set_ylim(0, len(farmers))
ax2 = ax.twinx()
ax2.plot(years, gprof.values, color="#e6550d", lw=2.2, marker="o", ms=4, label="profit global")
ax2.set_ylabel("profit global de l'année (k€)", color="#e6550d")
ax.set_title("2. # fermes en premium vs profit global, par année")

# 3) realised saturation: a farm's premium-year profit vs how many farms went premium
ax = axes[0, 2]
prem = det[det.cultivar == "premium"].copy()
prem["nprem_year"] = prem.year.map(nprem)
xx = prem.nprem_year.values.astype(float)
yy = prem.reward_year.values / 1000.0
ax.scatter(xx, yy, c=prem.year.values, cmap="cividis", s=28, alpha=0.8)
if xx.std() > 0:
    b, a0 = np.polyfit(xx, yy, 1)
    xs = np.array([xx.min(), xx.max()])
    ax.plot(xs, a0 + b * xs, "k--", lw=1.3)
    ax.text(0.05, 0.05, f"r = {np.corrcoef(xx, yy)[0,1]:+.2f}", transform=ax.transAxes, fontsize=10)
ax.set_title("3. Saturation réelle : profit premium d'une ferme\nvs # fermes premium la même année")
ax.set_xlabel("# fermes en premium (année)"); ax.set_ylabel("profit premium de la ferme (k€)")
ax.grid(alpha=0.3)

# 4) %premium vs total profit per farmer
ax = axes[1, 0]
x, y = syn.pct_premium.values, (syn.total_reward / 1000.0).values
ax.scatter(x, y, color="#31a354", s=55)
for xi, yi, name in zip(x, y, farmers):
    ax.annotate(name.replace("Farmer", "F"), (xi, yi), fontsize=7,
                textcoords="offset points", xytext=(4, 2))
b, a0 = np.polyfit(x, y, 1)
xs = np.array([x.min(), x.max()])
ax.plot(xs, a0 + b * xs, "k--", lw=1.3)
ax.text(0.05, 0.9, f"r = {np.corrcoef(x, y)[0,1]:+.2f}", transform=ax.transAxes, fontsize=10)
ax.set_title("4. % d'années en premium vs profit total")
ax.set_xlabel("% années en premium"); ax.set_ylabel("Profit total 25 ans (k€)")
ax.grid(alpha=0.3)

# 5) annual reward: premium vs standard farmer-years
ax = axes[1, 1]
prem_r = (det[det.cultivar == "premium"].reward_year / 1000.0).values
std_r = (det[det.cultivar == "standard"].reward_year / 1000.0).values
ax.boxplot([std_r, prem_r], showmeans=True)
ax.set_xticks([1, 2]); ax.set_xticklabels(["standard", "premium"])
ax.set_title("5. Profit annuel : année standard vs premium")
ax.set_ylabel("Profit de l'année (k€)")
ax.text(0.5, 0.04, f"moy: std={std_r.mean():.1f}k  premium={prem_r.mean():.1f}k",
        transform=ax.transAxes, ha="center", fontsize=9)
ax.grid(axis="y", alpha=0.3)

# 6) %premium vs mean yield (the trade-off)
ax = axes[1, 2]
x, y = syn.pct_premium.values, syn.mean_yield_t_ha.values
ax.scatter(x, y, color="#756bb1", s=55)
for xi, yi, name in zip(x, y, farmers):
    ax.annotate(name.replace("Farmer", "F"), (xi, yi), fontsize=7,
                textcoords="offset points", xytext=(4, 2))
b, a0 = np.polyfit(x, y, 1)
xs = np.array([x.min(), x.max()])
ax.plot(xs, a0 + b * xs, "k--", lw=1.3)
ax.text(0.05, 0.9, f"r = {np.corrcoef(x, y)[0,1]:+.2f}", transform=ax.transAxes, fontsize=10)
ax.set_title("6. Compromis : % premium vs rendement moyen")
ax.set_xlabel("% années en premium"); ax.set_ylabel("Rendement moyen (t/ha)")
ax.grid(alpha=0.3)

fig.suptitle("Évaluation par fermier (politique per-agent, greedy, 25 ans) — "
             f"profit global {syn.total_reward.sum()/1000:,.0f}k€", fontsize=13)
fig.tight_layout(rect=[0, 0, 1, 0.97])
fig.savefig(OUT, dpi=130)
print("Wrote", OUT)
