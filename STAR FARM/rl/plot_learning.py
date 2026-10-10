"""Courbes d'apprentissage des politiques MAPPO (400 épisodes chacune).

Deux journaux sont produits pendant l'entraînement, et ils ne mesurent PAS la même chose :

  episode_rewards.json  retour de l'épisode sous la récompense PROPRE à la politique
                        (profit, -pollution, ou profit - lambda*pollution avec lambda
                        jusqu'à 400 000). Ces échelles n'ont aucun rapport entre elles :
                        les tracer sur un axe commun n'aurait aucun sens. D'où les
                        petits multiples, chacun avec sa propre échelle.

  eval_returns.json     profit global en greedy (run_greedy_episode -> _global_profit),
                        tous les 25 épisodes. Même métrique pour toutes les politiques,
                        donc c'est le panneau comparable -- mais SEULEMENT entre runs
                        entraînés sur la MÊME carte. Bal-20k@DT tourne sur Dong Thap : sa
                        courbe est en pointillés et ne se compare pas aux autres.

Attention : ce profit greedy utilise la comptabilité `global_profit` de GAMA, alors que
`eval_conditions.py` somme les récompenses par ferme. Les deux ne coïncident pas exactement
— ne pas comparer les valeurs absolues de cette figure avec celles du rapport de transfert.

Usage :
    py plot_learning.py
"""
from __future__ import annotations

import json
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "report", "fig_apprentissage_mappo3.png")

# (label, dossier, couleur, récompense, même_carte_que_le_sweep)
POLICIES = [
    ("Profit",      "saved_models_mappo3_peragent",       "#08519c", "profit par ferme",   True),
    ("Bal-20k",     "saved_models_mappo3_balanced",       "#fdae6b", "profit − 20k·poll",  True),
    ("Bal-100k",    "saved_models_mappo3_balanced_l100k", "#e6550d", "profit − 100k·poll", True),
    ("Bal-200k",    "saved_models_mappo3_balanced_l200k", "#a63603", "profit − 200k·poll", True),
    ("Bal-400k",    "saved_models_mappo3_balanced_l400k", "#7a0177", "profit − 400k·poll", True),
    ("Pollution",   "saved_models_mappo3_pollution",      "#31a354", "− pollution",        True),
    # Re-run de Bal-200k avec la graine 1 : le run d'origine plafonnait a +34 967 sans
    # jamais decoller, celui-ci monte encore a l'episode 374. Meme carte, donc comparable.
    ("Bal-200k v2", "saved_models_mappo3_l200k_v2",       "#000000",
     "profit − 200k·poll (seed 1)", True),
    # Entraines directement sur Dong Thap : AUTRE CARTE. Comparables entre eux (pointilles),
    # jamais aux six runs du sweep -- l'economie de base y differe (la strategie constante sans
    # IA vaut +4,7 k€/ferme sur DT old contre -8,6 sur Dong Thap).
    ("Bal-20k @DT", "saved_models_mappo3_dtnew_l20k",     "#2171b5",
     "profit − 20k·poll (Dong Thap)", False),
    ("Profit @DT",  "saved_models_mappo3_dtnew_profit",   "#54278f",
     "profit par ferme (Dong Thap)", False),
    ("Pollution @DT", "saved_models_mappo3_dtnew_pollution", "#006d2c",
     "− pollution (Dong Thap)", False),
]

MA = 20  # fenêtre de moyenne mobile : le retour brut est bruité par l'exploration


def moving_average(x, w):
    if len(x) < w:
        return np.array([]), np.array([])
    ma = np.convolve(x, np.ones(w) / w, mode="valid")
    return np.arange(w - 1, len(x)), ma


def load(d):
    p = os.path.join(HERE, d)
    train = json.load(open(os.path.join(p, "episode_rewards.json"), encoding="utf-8"))
    ev_path = os.path.join(p, "eval_returns.json")
    ev = json.load(open(ev_path, encoding="utf-8")) if os.path.exists(ev_path) else []
    return np.asarray(train, dtype=float), ev


def main():
    data = {}
    for label, d, _c, _r, _same in POLICIES:
        if not os.path.isdir(os.path.join(HERE, d)):
            print(f"  (absent, ignoré) {d}")
            continue
        data[label] = load(d)
    if not data:
        raise SystemExit("Aucun saved_models_mappo3_* trouvé.")

    # Une rangee de petits multiples par tranche de 4 politiques, sous le panneau comparable.
    n_rows = (len(POLICIES) + 3) // 4
    fig = plt.figure(figsize=(17, 4.2 + 3.1 * n_rows))
    gs = fig.add_gridspec(1 + n_rows, 4, height_ratios=[1.5] + [1] * n_rows,
                          hspace=0.55, wspace=0.3)

    # ---- panneau comparable : profit greedy tous les 25 épisodes -------------------
    ax = fig.add_subplot(gs[0, :])
    for label, d, col, _r, same in POLICIES:
        if label not in data:
            continue
        ev = data[label][1]
        if not ev:
            continue
        xs = [int(e["episode"]) for e in ev]
        ys = [e["return"] / 1000 for e in ev]
        ax.plot(xs, ys, "o-" if same else "o--", color=col, ms=4, lw=1.9,
                label=label + ("" if same else "  (autre carte)"))
    ax.axhline(0, color="grey", lw=1, ls="--")
    ax.set_title("Profit global en évaluation greedy — comparable entre politiques d'une MÊME "
                 "carte (traits pleins).\nLes pointillés sont entraînés sur Dong Thap : autre "
                 "carte, autre référence, pas de comparaison directe.", fontsize=11)
    ax.set_xlabel("épisode d'entraînement"); ax.set_ylabel("profit global (k€ / 25 ans)")
    ax.legend(fontsize=8, ncol=4, loc="lower center"); ax.grid(alpha=0.3)

    # ---- petits multiples : retour d'entraînement, échelle propre à chaque politique
    for i, (label, d, col, reward, same) in enumerate(POLICIES):
        if label not in data:
            continue
        train, _ev = data[label]
        a = fig.add_subplot(gs[1 + i // 4, i % 4])
        a.plot(train / 1000, color=col, alpha=0.22, lw=0.8)
        xs, ma = moving_average(train / 1000, MA)
        if len(ma):
            a.plot(xs, ma, color=col, lw=2.0)
        a.axhline(0, color="grey", lw=0.8, ls="--")
        a.set_title(f"{label} — {reward}", fontsize=9)
        a.set_xlabel("épisode", fontsize=8)
        a.set_ylabel("retour (milliers)", fontsize=8)
        a.tick_params(labelsize=8); a.grid(alpha=0.3)

    fig.suptitle("Apprentissage MAPPO — 400 épisodes, 10 fermes "
                 "(Dong Thap old sauf mention contraire)", fontsize=14)
    fig.savefig(OUT, dpi=130, bbox_inches="tight")
    plt.close(fig)
    print("Wrote", OUT)

    # ---- résumé chiffré ------------------------------------------------------------
    print(f"\n{'politique':13s} {'retour debut':>13s} {'retour fin':>12s} "
          f"{'eval debut':>12s} {'eval fin':>12s} {'eval max':>12s}  carte")
    for label, d, _c, _r, same in POLICIES:
        if label not in data:
            continue
        train, ev = data[label]
        n = max(1, len(train) // 10)
        first, last = train[:n].mean(), train[-n:].mean()
        e0 = ev[0]["return"] if ev else float("nan")
        e1 = ev[-1]["return"] if ev else float("nan")
        emax = max((e["return"] for e in ev), default=float("nan"))
        carte = "DT old" if same else "Dong Thap"
        print(f"{label:13s} {first:>13,.0f} {last:>12,.0f} {e0:>12,.0f} {e1:>12,.0f} "
              f"{emax:>12,.0f}  {carte}")
    print("\n(retour debut/fin = moyenne des 10 % premiers / derniers episodes, unites propres "
          "a chaque recompense ; eval = profit global greedy)")


if __name__ == "__main__":
    main()
