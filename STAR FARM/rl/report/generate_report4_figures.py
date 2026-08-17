"""Figures for report 4: PER-AGENT reward vs GLOBAL (team) reward, both MAPPO on the
same crisis environment (sequential decisions, obs 18, 25 years horizon, full pack).

Reads the live logs:
  saved_models_mappo3          -> GLOBAL (team) reward run
  saved_models_mappo3_peragent -> PER-AGENT reward run

The greedy-eval metric (eval_returns.json) is the TRUE global profit
(sum of all farmers' yearly profit) in BOTH runs, so the comparison is apples-to-apples.
Distinct filenames (fig4_*.png) — earlier reports' figures are untouched."""
import json
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
RL = os.path.dirname(HERE)

ORANGE, BLUE, GREY, GREEN = "#e6550d", "#08519c", "#969696", "#31a354"


def ma(x, w=20):
    return np.convolve(x, np.ones(w) / w, mode="valid")


def load_evals(name):
    """Load eval_returns.json, de-duplicating by episode (last occurrence wins) so an
    aborted-run prefix in the log is dropped and only the clean 400-ep series remains."""
    ev = json.load(open(os.path.join(RL, name, "eval_returns.json")))
    d = {}
    for e in ev:
        d[int(e["episode"])] = e["return"] / 1000.0
    xs = sorted(d)
    return np.array(xs), np.array([d[x] for x in xs])


pa_x, pa_y = load_evals("saved_models_mappo3_peragent")
gl_x, gl_y = load_evals("saved_models_mappo3")

# Raw stochastic per-episode global return (real for global; per-agent 0-249 is a
# reconstruction, so we only draw its real tail 250+).
gl_r = np.array(json.load(open(os.path.join(RL, "saved_models_mappo3", "episode_rewards.json"))), dtype=float) / 1000.0
pa_r = np.array(json.load(open(os.path.join(RL, "saved_models_mappo3_peragent", "episode_rewards.json"))), dtype=float) / 1000.0

BASELINE = 220.6  # best constant strategy, same crisis env (measured at Gen 3)


def stats(x, y):
    # "Plateau" = mean over the last quarter of each run's episode range, so runs of
    # different lengths (per-agent 400 ep, global 800 ep) are compared on their mature region.
    thr = x.min() + 0.75 * (x.max() - x.min())
    mature = y[x >= thr]
    return dict(best=y.max(), best_ep=int(x[y.argmax()]), final=y[-1],
                plateau=mature.mean(), plateau_from=int(thr))


sp, sg = stats(pa_x, pa_y), stats(gl_x, gl_y)
print("PER-AGENT :", {k: round(v, 1) for k, v in sp.items()})
print("GLOBAL    :", {k: round(v, 1) for k, v in sg.items()})
print(f"best  +{100*(sp['best']-sg['best'])/sg['best']:.0f}%  "
      f"final +{100*(sp['final']-sg['final'])/sg['final']:.0f}%  "
      f"plateau +{100*(sp['plateau']-sg['plateau'])/sg['plateau']:.0f}%")

# ---------------------------------------------------------------- Fig 1: eval curves
fig, ax = plt.subplots(figsize=(9.5, 5))
ax.plot(pa_x, pa_y, "o-", color=ORANGE, lw=2.4, ms=7, label="Recompense PAR FERMIER (greedy)")
ax.plot(gl_x, gl_y, "s-", color=BLUE, lw=2.4, ms=6, label="Recompense GLOBALE / equipe (greedy)")
ax.axhline(BASELINE, color=GREY, ls="--", lw=1.4, label=f"Meilleur baseline constant (~{BASELINE:.0f}k)")
ax.annotate(f"{sp['best']:,.0f}k\n(ep {sp['best_ep']})", (pa_x[pa_y.argmax()], sp['best']),
            textcoords="offset points", xytext=(4, 8), color=ORANGE, fontsize=9, fontweight="bold")
ax.annotate(f"plateau {sg['final']:,.0f}k\n(800 ep)", (gl_x[-1], gl_y[-1]),
            textcoords="offset points", xytext=(-2, -26), color=BLUE, fontsize=9, fontweight="bold")
ax.set_xlabel("Episode d'entrainement (par fermier: 400 ep, globale: 800 ep)")
ax.set_ylabel("Profit global vrai sur 25 ans (k EUR)")
ax.set_title("Recompense par fermier vs recompense globale (eval GREEDY = vrai objectif global)\n"
             "Le profit individuel maximise MIEUX le collectif, et ~10x plus vite")
ax.set_ylim(120, 510)
ax.legend(loc="lower right", fontsize=9)
ax.grid(alpha=0.3)
fig.tight_layout()
fig.savefig(os.path.join(HERE, "fig4_eval_curves.png"), dpi=130)
plt.close(fig)

# ---------------------------------------------------------------- Fig 2: headline bars
fig, ax = plt.subplots(figsize=(9.5, 5))
groups = ["Meilleur greedy", "Greedy final", "Plateau\n(dernier quart)"]
pa_vals = [sp["best"], sp["final"], sp["plateau"]]
gl_vals = [sg["best"], sg["final"], sg["plateau"]]
x = np.arange(3)
w = 0.36
b1 = ax.bar(x - w / 2, pa_vals, w, label="Par fermier", color=ORANGE)
b2 = ax.bar(x + w / 2, gl_vals, w, label="Globale (equipe)", color=BLUE)
for bars in (b1, b2):
    for b in bars:
        ax.text(b.get_x() + b.get_width() / 2, b.get_height() + 5, f"{b.get_height():,.0f}k",
                ha="center", va="bottom", fontsize=9)
ax.axhline(BASELINE, color=GREY, ls="--", lw=1.4, label=f"Baseline constant (~{BASELINE:.0f}k)")
ax.set_xticks(x); ax.set_xticklabels(groups, fontsize=9)
ax.set_ylabel("Profit global vrai sur 25 ans (k EUR)")
ax.set_ylim(0, 540)
ax.set_title("Recompense par fermier vs globale — 3 mesures, meme environnement de crise")
ax.legend(fontsize=9, loc="upper right")
ax.grid(axis="y", alpha=0.3)
fig.tight_layout()
fig.savefig(os.path.join(HERE, "fig4_headline.png"), dpi=130)
plt.close(fig)

# ---------------------------------------------------------------- Fig 3: global still rising
fig, ax = plt.subplots(figsize=(9.5, 5))
ax.plot(gl_r, color="#c6dbef", lw=1, label="Retour par episode (stochastique)")
ax.plot(np.arange(19, len(gl_r)), ma(gl_r), color=BLUE, lw=2, label="Moyenne mobile 20 ep.")
ax.plot(gl_x, gl_y, "s-", color="#e6550d", lw=2, ms=6, label="Eval greedy periodique")
ax.set_xlabel("Episode")
ax.set_ylabel("Profit global sur 25 ans (k EUR)")
ax.set_title("Run recompense GLOBALE etendu (800 ep) — plateau ~375k atteint vers l'ep 720")
ax.legend(loc="lower right", fontsize=9)
ax.grid(alpha=0.3)
fig.tight_layout()
fig.savefig(os.path.join(HERE, "fig4_global_learning.png"), dpi=130)
plt.close(fig)

print("Figures: fig4_eval_curves.png, fig4_headline.png, fig4_global_learning.png")
