"""Synthesis figure for the complete report: profit/pollution Pareto frontiers under the
four evaluation conditions {simple 10 farms, full 748 farms} x {greedy, stochastic}, with
the retrained pollution model everywhere. Reads the eval_objectives_comparison_*.xlsx files.
Writes synthesis_pareto.png."""
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
COL = {"Profit": "#08519c", "Bal-20k": "#fdae6b", "Bal-100k": "#e6550d",
       "Bal-200k": "#a63603", "Bal-400k": "#7a0177", "Pollution": "#31a354"}


def load(name):
    return pd.read_excel(os.path.join(HERE, f"eval_objectives_comparison{name}.xlsx"), sheet_name="comparaison")


greedy10 = load("_greedy10")
stoch10 = load("_stoch10")
stoch748 = load("_stoch748")
# greedy 748: the 5 unchanged policies come from _bigmodel; the Pollution row is replaced by
# the retrained model measured separately (_greedy748_pollution).
big = load("_bigmodel")
newpoll = load("_greedy748_pollution").iloc[0]
big = big[big.policy != "Pollution"].copy()
for c in newpoll.index:
    if c not in big.columns:
        big[c] = np.nan
greedy748 = pd.concat([big, pd.DataFrame([newpoll[big.columns]])], ignore_index=True)

# Deterministic no-AI baselines (constant bundles). Shown on the GREEDY panels only: they
# ignore the observation, so their stochastic run is the same point.
def load_baselines(name):
    p = os.path.join(HERE, f"eval_baselines_comparison{name}.xlsx")
    return pd.read_excel(p, sheet_name="comparaison") if os.path.exists(p) else None


base10, base748 = load_baselines("_simple"), load_baselines("_full")

CONDITIONS = [("Simple (10 fermes) - GREEDY", greedy10, 1e3, "k", base10),
              ("Simple (10 fermes) - STOCHASTIQUE", stoch10, 1e3, "k", None),
              ("Réel (748 fermes) - GREEDY", greedy748, 1e6, "M", base748),
              ("Réel (748 fermes) - STOCHASTIQUE", stoch748, 1e6, "M", None)]

fig, axes = plt.subplots(2, 2, figsize=(14.5, 10))
for ax, (title, df, scale, unit, base) in zip(axes.ravel(), CONDITIONS):
    for _, r in df.iterrows():
        xe = (r.profit_std / scale) if ("profit_std" in df.columns and r.get("profit_std", 0)) else None
        ye = r.get("pollution_std", 0) if "pollution_std" in df.columns else None
        ax.errorbar(r.global_profit / scale, r.mean_pollution, xerr=xe, yerr=(ye or None),
                    fmt="o", ms=11, color=COL.get(r.policy, "#333"), capsize=3, zorder=3)
        ax.annotate(r.policy, (r.global_profit / scale, r.mean_pollution),
                    textcoords="offset points", xytext=(7, 4), fontsize=8.5)
    if base is not None:
        for _, r in base.iterrows():
            ax.plot(r.global_profit / scale, r.mean_pollution, marker="*", ms=17,
                    color="#666666", mec="black", ls="none", zorder=4)
            ax.annotate(f"{r.policy} (sans IA)", (r.global_profit / scale, r.mean_pollution),
                        textcoords="offset points", xytext=(7, -11), fontsize=8.5,
                        color="#444444", style="italic")
    ax.set_title(title, fontsize=11)
    ax.set_xlabel(f"profit global 25 ans ({unit}€)")
    ax.set_ylabel("pollution moyenne")
    ax.grid(alpha=0.3)
    ax.invert_yaxis()  # low pollution at top -> top-right = ideal

fig.suptitle("Frontière profit / pollution — 4 conditions (haut-droite = idéal ; "
             "étoiles = stratégies constantes sans IA)", fontsize=13, fontweight="bold")
fig.tight_layout(rect=[0, 0, 1, 0.97])
out = os.path.join(HERE, "synthesis_pareto.png")
fig.savefig(out, dpi=130)
print("Wrote", out)

# also print a consolidated table for the report
def row(df, pol):
    r = df[df.policy == pol]
    if r.empty:
        return "n/a", "n/a"
    r = r.iloc[0]
    return f"{r.global_profit:,.0f}", f"{r.mean_pollution:.4f}"

print("\npolicy      | g10 prof/poll        | s10                  | g748                 | s748")
for pol in COL:
    g10 = row(greedy10, pol); s10 = row(stoch10, pol); g748 = row(greedy748, pol); s748 = row(stoch748, pol)
    print(f"{pol:10s} | {g10[0]:>10} {g10[1]} | {s10[0]:>10} {s10[1]} | {g748[0]:>12} {g748[1]} | {s748[0]:>12} {s748[1]}")
