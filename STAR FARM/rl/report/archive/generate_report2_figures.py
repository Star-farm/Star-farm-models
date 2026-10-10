"""Figures for the 2nd report (Box(6): + cultivar + seasons). Distinct filenames so the
first report's figures are untouched."""
import json
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
RL = os.path.dirname(HERE)

# Eval numbers measured with eval_policy.py on the Box(6) run.
EVAL = {"trained": 319949, "random": 198311, "fixed_low": 255457,
        "fixed_mid": 234025, "fixed_high": 430668}

# ---------------------------------------------------------------- Fig 1: learning curve (Box6)
rewards = np.array(json.load(open(os.path.join(RL, "saved_models", "episode_rewards.json"))), dtype=float) / 1000.0
ma20 = np.convolve(rewards, np.ones(20) / 20, mode="valid")

fig, ax = plt.subplots(figsize=(9, 5))
ax.plot(rewards, color="#9ecae1", lw=1, label="Retour par épisode")
ax.plot(np.arange(19, len(rewards)), ma20, color="#08519c", lw=2.2, label="Moyenne mobile (20 ép.)")
ax.axhline(EVAL["fixed_high"] / 1000, color="#31a354", ls="--", lw=1.5, label="Plafond fixed_high (premium) = 431k")
ax.axhline(EVAL["fixed_low"] / 1000, color="#e6550d", ls=":", lw=1.4, label="fixed_low (BAU intensif) = 255k")
ax.set_xlabel("Épisode")
ax.set_ylabel("Profit global cumulé sur 10 ans (k€)")
ax.set_title("Box(6) — la courbe MONTE : l'ajout cultivar+saisons rend le problème apprenable")
ax.legend(loc="lower right", fontsize=9)
ax.grid(alpha=0.3)
fig.tight_layout()
fig.savefig(os.path.join(HERE, "fig_box6_learning.png"), dpi=130)
plt.close(fig)

# ---------------------------------------------------------------- Fig 2: eval baselines (Box6)
labels = ["fixed_high\nAWD/IPM/dur/\nPREMIUM/2s", "trained", "fixed_low\nCF/BAU/BAU/\nstd/3s",
          "fixed_mid\nCF/IPM/dur/\nstd/3s", "random"]
values = np.array([EVAL["fixed_high"], EVAL["trained"], EVAL["fixed_low"],
                   EVAL["fixed_mid"], EVAL["random"]]) / 1000.0
colors = ["#31a354", "#08519c", "#969696", "#bdbdbd", "#d9d9d9"]

fig, ax = plt.subplots(figsize=(9, 5))
bars = ax.bar(labels, values, color=colors, edgecolor="black", lw=0.5)
ax.axhline(EVAL["trained"] / 1000, color="#08519c", ls="--", lw=1.0)
for b, v in zip(bars, values):
    ax.text(b.get_x() + b.get_width() / 2, v + 4, f"{v:,.0f}k", ha="center", va="bottom", fontsize=9)
ax.annotate("écart inexploité\n~110k", xy=(0, EVAL["fixed_high"] / 1000), xytext=(0.6, 400),
            fontsize=8.5, color="#31a354",
            arrowprops=dict(arrowstyle="->", color="#31a354"))
ax.set_ylabel("Profit global moyen sur 10 ans (k€)")
ax.set_ylim(150, 460)
ax.set_title("Box(6) — politique vs baselines : le cultivar PREMIUM domine (fixed_high)")
ax.grid(axis="y", alpha=0.3)
fig.tight_layout()
fig.savefig(os.path.join(HERE, "fig_box6_baselines.png"), dpi=130)
plt.close(fig)

# ---------------------------------------------------------------- Fig 3: Box(4) vs Box(6)
groups = ["Box(4)\nirr/pest/fert", "Box(6)\n+ cultivar + saisons"]
trained = np.array([284806, 319949]) / 1000.0
best_base = np.array([284404, 430668]) / 1000.0   # fixed_low (B4) / fixed_high (B6)
rnd = np.array([262850, 198311]) / 1000.0
x = np.arange(2); w = 0.26

fig, ax = plt.subplots(figsize=(9, 5))
ax.bar(x - w, trained, w, label="Politique entraînée", color="#08519c")
ax.bar(x, best_base, w, label="Meilleur baseline fixe", color="#31a354")
ax.bar(x + w, rnd, w, label="Aléatoire", color="#bdbdbd")
for xi, arr in [(x - w, trained), (x, best_base), (x + w, rnd)]:
    for xx, v in zip(xi, arr):
        ax.text(xx, v + 4, f"{v:,.0f}k", ha="center", va="bottom", fontsize=8)
ax.set_xticks(x); ax.set_xticklabels(groups)
ax.set_ylabel("Profit global sur 10 ans (k€)")
ax.set_ylim(0, 470)
ax.set_title("Box(4) vs Box(6) : les nouveaux leviers relèvent le plafond (et l'apprentissage)")
ax.legend(fontsize=9)
ax.grid(axis="y", alpha=0.3)
fig.tight_layout()
fig.savefig(os.path.join(HERE, "fig_box4_vs_box6.png"), dpi=130)
plt.close(fig)

print("Figures écrites: fig_box6_learning.png, fig_box6_baselines.png, fig_box4_vs_box6.png")
