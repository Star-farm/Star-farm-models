"""Figures for the project STATUS report (rapport 3). Reads the live training logs
(saved_models_mappo2 = current full-pack run; saved_models_mappo = previous annual run).
Distinct filenames — earlier reports' figures are untouched."""
import json
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
RL = os.path.dirname(HERE)


def ma(x, w=20):
    return np.convolve(x, np.ones(w) / w, mode="valid")


r_new = np.array(json.load(open(os.path.join(RL, "saved_models_mappo2", "episode_rewards.json"))), dtype=float) / 1000.0
r_old = np.array(json.load(open(os.path.join(RL, "saved_models_mappo", "episode_rewards.json"))), dtype=float) / 1000.0
evals = json.load(open(os.path.join(RL, "saved_models_mappo2", "eval_returns.json")))
ev_x = [e["episode"] for e in evals]
ev_y = [e["return"] / 1000.0 for e in evals]

# ---------------------------------------------------------------- Fig 1: generations
fig, ax = plt.subplots(figsize=(9.5, 5))
labels = ["Gen 1\nIPPO Box(4)\nenv fixe, 10 ans", "Gen 2\nIPPO Box(6)\nenv fixe, 10 ans",
          "Gen 3\nMAPPO annuel\nenv CRISE, 25 ans", "Gen 4 (en cours)\nMAPPO + pack\nenv CRISE, 25 ans"]
policy = [284.8, 319.9, 435.3, ev_y[-1]]
basebest = [284.4, 430.7, 220.6, 220.6]
x = np.arange(4)
w = 0.36
b1 = ax.bar(x - w / 2, policy, w, label="Politique apprise (greedy)", color="#08519c")
b2 = ax.bar(x + w / 2, basebest, w, label="Meilleur baseline constant", color="#969696")
for bars in (b1, b2):
    for b in bars:
        ax.text(b.get_x() + b.get_width() / 2, b.get_height() + 6, f"{b.get_height():,.0f}k",
                ha="center", va="bottom", fontsize=9)
ax.text(3, ev_y[-1] + 55, "ep 74/400\n(en cours)", ha="center", fontsize=9, color="#08519c", style="italic")
ax.set_xticks(x); ax.set_xticklabels(labels, fontsize=9)
ax.set_ylabel("Profit global par épisode (k€)")
ax.set_ylim(0, 520)
ax.set_title("4 générations : le RL passe de « inutile » à « irremplaçable »\n"
             "(attention : Gen 1-2 et Gen 3-4 tournent sur des environnements différents)")
ax.legend(fontsize=9)
ax.grid(axis="y", alpha=0.3)
fig.tight_layout()
fig.savefig(os.path.join(HERE, "fig_etat_generations.png"), dpi=130)
plt.close(fig)

# ---------------------------------------------------------------- Fig 2: current run
fig, ax = plt.subplots(figsize=(9.5, 5))
ax.plot(r_new, color="#c6dbef", lw=1, label="Retour par épisode (stochastique, bruit d'exploration)")
ax.plot(np.arange(19, len(r_new)), ma(r_new), color="#08519c", lw=2, label="Moyenne mobile 20 ép.")
ax.plot(ev_x, ev_y, "o-", color="#e6550d", lw=2.2, ms=8, label="Éval GREEDY périodique (vraie performance)")
for xx, yy in zip(ev_x, ev_y):
    ax.annotate(f"{yy:,.0f}k", (xx, yy), textcoords="offset points", xytext=(0, 10),
                ha="center", fontsize=9, color="#e6550d", fontweight="bold")
ax.axhline(435.3, color="#31a354", ls="--", lw=1.4, label="Best du run précédent (435k, ~200+ ép.)")
ax.set_xlabel("Épisode")
ax.set_ylabel("Profit global sur 25 ans (k€)")
ax.set_title("Run actuel (pack efficacité) — la performance GREEDY double en 50 épisodes")
ax.legend(loc="lower right", fontsize=9)
ax.grid(alpha=0.3)
fig.tight_layout()
fig.savefig(os.path.join(HERE, "fig_etat_run_actuel.png"), dpi=130)
plt.close(fig)

# ---------------------------------------------------------------- Fig 3: old vs new
fig, ax = plt.subplots(figsize=(9.5, 5))
ax.plot(np.arange(19, len(r_old)), ma(r_old), color="#9e9e9e", lw=2,
        label=f"Run précédent (annuel, sans pack) — ma20, arrêté à {len(r_old)} ép.")
ax.plot(np.arange(19, len(r_new)), ma(r_new), color="#08519c", lw=2,
        label=f"Run actuel (pack complet) — ma20, {len(r_new)} ép.")
ax.plot(ev_x, ev_y, "o-", color="#e6550d", lw=2, ms=7, label="Run actuel — éval greedy")
ax.set_xlabel("Épisode")
ax.set_ylabel("Profit global sur 25 ans (k€)")
ax.set_title("Comparaison des deux runs MAPPO (courbes stochastiques non directement\n"
             "comparables : obs 15 vs 17, bruit d'exploration différent)")
ax.legend(loc="lower right", fontsize=9)
ax.grid(alpha=0.3)
fig.tight_layout()
fig.savefig(os.path.join(HERE, "fig_etat_comparaison.png"), dpi=130)
plt.close(fig)

print("Figures écrites: fig_etat_generations.png, fig_etat_run_actuel.png, fig_etat_comparaison.png")
