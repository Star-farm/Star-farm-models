"""Cross-condition synthesis: one table and one figure answering "what transfers?".

Reads the four workbooks produced by eval_conditions.py and puts the SAME policy side by side
across the four maps. Two rules govern how the numbers are compared:

  * global_profit is never compared across conditions -- 10, 748 and 992 farms cannot be put
    on the same axis. Everything here uses profit_per_farm.
  * even profit_per_farm is not comparable between provinces in absolute terms (different
    soils, salinity, market crowding). What IS comparable is the RATIO to the best no-AI
    baseline measured on that same map, which is why every condition carries its own
    baselines. ratio > 1 means the policy still beats doing nothing clever, there.

Usage (after the four eval_conditions.py runs):
    py plot_conditions.py
"""
from __future__ import annotations

import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))

# (tag, human label, colour). Order = increasing distance from the training setup.
CONDITIONS = [("dtold_simple", "Dong Thap old\nsimple (10)", "#08519c"),
              ("dtold_full", "Dong Thap old\ncomplet (748)", "#3182bd"),
              ("dtnew_simple", "Dong Thap\nsimple (10)", "#e6550d"),
              ("dtnew_full", "Dong Thap\ncomplet (992)", "#a63603")]

BASELINES = ["MaxProfit", "MinPollution"]
POLICY_ORDER = ["Profit", "Bal-20k", "Bal-100k", "Bal-200k", "Bal-400k", "Pollution"]


def load():
    comp, meta = {}, {}
    for tag, label, _c in CONDITIONS:
        path = os.path.join(HERE, f"eval_condition_{tag}.xlsx")
        if not os.path.exists(path):
            print(f"  (absent, ignore) {os.path.basename(path)}")
            continue
        comp[tag] = pd.read_excel(path, sheet_name="comparaison").set_index("policy")
        meta[tag] = pd.read_excel(path, sheet_name="condition").iloc[-1].to_dict()
    if not comp:
        raise SystemExit("Aucun eval_condition_*.xlsx trouve -- lancer eval_conditions.py d'abord.")
    return comp, meta


def matrix(comp, col):
    """policy x condition table for one metric, policies first then baselines."""
    df = pd.DataFrame({tag: c[col] for tag, c in comp.items()})
    order = [p for p in POLICY_ORDER if p in df.index] + [b for b in BASELINES if b in df.index]
    return df.loc[order]


def main():
    comp, meta = load()
    tags = list(comp)

    prof = matrix(comp, "profit_per_farm")
    poll = matrix(comp, "mean_pollution")

    mix = []
    for tag, c in comp.items():
        for pol, r in c.iterrows():
            mix.append({"condition": tag, "policy": pol,
                        "pct_IPM": r.pct_IPM, "pct_durable": r.pct_durable,
                        "pct_AWD": r.pct_AWD, "pct_premium": r.pct_premium,
                        "pct_3seasons": r.pct_3seasons, "mean_irr_qty": r.mean_irr_qty,
                        "mean_yield_t_ha": r.mean_yield_t_ha,
                        "mean_soil_health": r.mean_soil_health})
    mix = pd.DataFrame(mix)

    # Transfer table: each policy against the best no-AI baseline ON THE SAME MAP.
    trans = []
    for tag in tags:
        c = comp[tag]
        base = c.loc[[b for b in BASELINES if b in c.index], "profit_per_farm"]
        best_base = float(base.max()) if len(base) else float("nan")
        ranked = c.loc[[p for p in POLICY_ORDER if p in c.index], "profit_per_farm"] \
                  .sort_values(ascending=False)
        for rank, (pol, v) in enumerate(ranked.items(), start=1):
            # The GAP, not the ratio, is the primary transfer measure. On the new province the
            # best no-AI baseline is itself NEGATIVE (-8,574/farm), and a ratio against a
            # negative denominator inverts the sign: the only profitable policy there would be
            # reported as -3.2x. The ratio is kept, but only where it means something.
            trans.append({"condition": tag, "n_farmers": meta[tag].get("n_farmers"),
                          "policy": pol, "profit_per_farm": v,
                          "best_baseline_per_farm": best_base,
                          "ecart_vs_baseline": v - best_base,
                          "bat_baseline": bool(v > best_base),
                          "ratio_vs_baseline": (v / best_base) if best_base > 0 else float("nan"),
                          "rang": rank})
    trans = pd.DataFrame(trans)

    out_xlsx = os.path.join(HERE, "eval_conditions_synthesis.xlsx")
    with pd.ExcelWriter(out_xlsx, engine="openpyxl") as xl:
        pd.DataFrame(meta).T.to_excel(xl, sheet_name="conditions")
        prof.to_excel(xl, sheet_name="profit_par_ferme")
        poll.to_excel(xl, sheet_name="pollution")
        mix.to_excel(xl, sheet_name="mix_actions", index=False)
        trans.to_excel(xl, sheet_name="transfert", index=False)
    print("Wrote", out_xlsx)

    # ------------------------------------------------------------------ figure
    labels = {t: l for t, l, _ in CONDITIONS}
    colours = {t: c for t, _l, c in CONDITIONS}
    fig, ax = plt.subplots(2, 2, figsize=(15, 9))

    a = ax[0, 0]
    x = np.arange(len(prof.index)); w = 0.8 / max(len(tags), 1)
    for i, tag in enumerate(tags):
        a.bar(x + (i - (len(tags) - 1) / 2) * w, prof[tag] / 1000, w,
              color=colours[tag], label=labels[tag].replace("\n", " "))
    a.set_xticks(x); a.set_xticklabels(prof.index, rotation=30, ha="right", fontsize=8)
    a.set_title("1. Profit par ferme (k€ / 25 ans) — seule mesure comparable entre cartes")
    a.set_ylabel("k€ / ferme"); a.legend(fontsize=7); a.grid(axis="y", alpha=0.3)

    a = ax[0, 1]
    for i, tag in enumerate(tags):
        a.bar(x + (i - (len(tags) - 1) / 2) * w, poll[tag], w, color=colours[tag])
    a.set_xticks(x); a.set_xticklabels(poll.index, rotation=30, ha="right", fontsize=8)
    a.set_title("2. Pollution moyenne (bas = mieux)"); a.set_ylabel("pollution")
    a.grid(axis="y", alpha=0.3)

    a = ax[1, 0]
    for pol in [p for p in POLICY_ORDER if p in trans.policy.unique()]:
        sub = trans[trans.policy == pol].set_index("condition").reindex(tags)
        a.plot(range(len(tags)), sub.ecart_vs_baseline / 1000, "o-", ms=6, lw=1.8, label=pol)
    a.axhline(0.0, color="crimson", ls="--", lw=1.5)
    a.annotate("meilleure baseline sans IA", (0.02, 0.0), xycoords=("axes fraction", "data"),
               fontsize=8, color="crimson", va="bottom")
    a.set_xticks(range(len(tags)))
    a.set_xticklabels([labels[t] for t in tags], fontsize=8)
    a.set_title("3. Transfert : écart à la meilleure baseline de LA MÊME carte")
    a.set_ylabel("k€/ferme au-dessus de la baseline"); a.legend(fontsize=7); a.grid(alpha=0.3)

    a = ax[1, 1]
    cats = [("pct_IPM", "IPM"), ("pct_durable", "durable"), ("pct_AWD", "AWD"),
            ("pct_premium", "premium")]
    pol_only = mix[mix.policy.isin(POLICY_ORDER)]
    xx = np.arange(len(cats)); w2 = 0.8 / max(len(tags), 1)
    for i, tag in enumerate(tags):
        sub = pol_only[pol_only.condition == tag]
        vals = [sub[c].mean() for c, _n in cats]
        a.bar(xx + (i - (len(tags) - 1) / 2) * w2, vals, w2, color=colours[tag])
    a.set_xticks(xx); a.set_xticklabels([n for _c, n in cats], fontsize=9)
    a.set_title("4. Mix d'actions moyen des 6 politiques, par carte"); a.set_ylabel("% des années")
    a.grid(axis="y", alpha=0.3)

    fig.suptitle("Transfert des 6 politiques MAPPO — entraînées sur Dong Thap old simple (10 fermes)",
                 fontsize=13)
    fig.tight_layout(rect=[0, 0, 1, 0.96])
    out_png = os.path.join(HERE, "eval_conditions_curves.png")
    fig.savefig(out_png, dpi=130)
    plt.close(fig)
    print("Wrote", out_png)

    print("\nprofit par ferme (k€) :")
    print((prof / 1000).round(1).to_string())
    print("\nbaseline sans IA de chaque carte (k€/ferme) :")
    print((trans.groupby("condition").best_baseline_per_farm.first()[tags] / 1000)
          .round(1).to_string())
    print("\necart a cette baseline (k€/ferme, >0 = la politique la bat) :")
    print((trans.pivot(index="policy", columns="condition", values="ecart_vs_baseline")
           .reindex([p for p in POLICY_ORDER if p in set(trans.policy)])[tags] / 1000)
          .round(1).to_string())


if __name__ == "__main__":
    main()
