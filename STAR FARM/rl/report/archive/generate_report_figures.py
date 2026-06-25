"""Generate the figures for the MARL training report.

Reads the real training reward log (saved_models/episode_rewards.json) and embeds the
evaluation numbers measured with eval_policy.py. Saves PNGs into this report/ folder.
"""
import json
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
RL = os.path.dirname(HERE)
OUT = HERE

# ---------------------------------------------------------------- Figure 1: learning curve
rewards = np.array(json.load(open(os.path.join(RL, "saved_models", "episode_rewards.json"))), dtype=float)
rewards_k = rewards / 1000.0
ma20 = np.convolve(rewards_k, np.ones(20) / 20, mode="valid")

fig, ax = plt.subplots(figsize=(9, 5))
ax.plot(rewards_k, color="#9ecae1", lw=1, label="Retour par épisode")
ax.plot(np.arange(19, len(rewards_k)), ma20, color="#08519c", lw=2.2, label="Moyenne mobile (20 ép.)")
best_ep = int(rewards.argmax())
ax.scatter([best_ep], [rewards_k[best_ep]], color="#e6550d", zorder=5, s=45,
           label=f"Meilleur épisode (#{best_ep})")
ax.axhline(284.4, color="#31a354", ls="--", lw=1.4, label="Baseline fixed_low (BAU intensif) = 284k")
ax.set_xlabel("Épisode")
ax.set_ylabel("Profit global cumulé sur 10 ans (k€)")
ax.set_title("Courbe d'apprentissage IPPO — le retour DÉCLINE au fil de l'entraînement")
ax.legend(loc="upper right", fontsize=9)
ax.grid(alpha=0.3)
fig.tight_layout()
fig.savefig(os.path.join(OUT, "fig1_learning_curve.png"), dpi=130)
plt.close(fig)

# ---------------------------------------------------------------- Figure 2: eval vs baselines
labels = ["trained\n(best)", "fixed_low\nCF/BAU/BAU", "trained\n(final)",
          "fixed_mid\nCF/IPM/dur.", "random", "fixed_high\nAWD/IPM/dur."]
values = np.array([284806, 284404, 275132, 265727, 262850, 262374]) / 1000.0
colors = ["#08519c", "#31a354", "#6baed6", "#969696", "#bdbdbd", "#969696"]

fig, ax = plt.subplots(figsize=(9, 5))
bars = ax.bar(labels, values, color=colors, edgecolor="black", lw=0.5)
ax.axhline(284.4, color="#31a354", ls="--", lw=1.2)
for b, v in zip(bars, values):
    ax.text(b.get_x() + b.get_width() / 2, v + 1, f"{v:,.0f}k", ha="center", va="bottom", fontsize=9)
ax.set_ylabel("Profit global moyen sur 10 ans (k€)")
ax.set_ylim(255, 292)
ax.set_title("Politique entraînée vs baselines (profit global — plus haut = mieux)")
ax.grid(axis="y", alpha=0.3)
fig.tight_layout()
fig.savefig(os.path.join(OUT, "fig2_eval_baselines.png"), dpi=130)
plt.close(fig)

# ---------------------------------------------------------------- Figure 3: intra-episode profit
# Per-year global profit within one episode (measured, early policy) — shows the decline.
years = np.arange(1, 11)
per_year = np.array([34737, 36571, 32553, 31978, 30400, 25259, 23747, 23170, 22573, 21694]) / 1000.0

fig, ax = plt.subplots(figsize=(9, 5))
ax.plot(years, per_year, marker="o", color="#08519c", lw=2)
ax.fill_between(years, per_year, alpha=0.12, color="#08519c")
ax.set_xlabel("Année simulée dans l'épisode")
ax.set_ylabel("Profit global de l'année (k€)")
ax.set_xticks(years)
ax.set_title("Profit annuel DÉCROISSANT au fil d'un épisode (≈ dégradation du sol)")
ax.grid(alpha=0.3)
fig.tight_layout()
fig.savefig(os.path.join(OUT, "fig3_intra_episode.png"), dpi=130)
plt.close(fig)

print("Figures écrites :")
for f in ("fig1_learning_curve.png", "fig2_eval_baselines.png", "fig3_intra_episode.png"):
    print("  report/" + f)
