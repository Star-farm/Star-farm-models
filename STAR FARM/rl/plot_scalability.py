"""Scalability validation figure: compare the SAME per-agent policy on the simplified model
(N=10 farms) vs the full model (N=748 farms), reading both per-farmer eval workbooks.
If the per-farm economics, the %premium<->profit relation and the premium cycle match, the
shared (id-free) actor scales. Writes eval_scalability_curves.png."""
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
SMALL = os.path.join(HERE, "eval_per_farmer_peragent.xlsx")   # N=10 (reference)
BIG = os.path.join(HERE, "eval_per_farmer_bigmodel.xlsx")     # N=748 (full model)
OUT = os.path.join(HERE, "eval_scalability_curves.png")

C10, C748 = "#969696", "#08519c"


def load(path):
    return pd.read_excel(path, sheet_name="synthese_fermiers"), pd.read_excel(path, sheet_name="detail")


syn_s, det_s = load(SMALL)
syn_b, det_b = load(BIG)
ns, nb = len(syn_s), len(syn_b)
gs, gb = syn_s.total_reward.sum(), syn_b.total_reward.sum()


def cycle_frac(det, n):
    years = sorted(det.year.unique())
    nprem = det[det.cultivar == "premium"].groupby("year").size().reindex(years, fill_value=0)
    return np.array(years), nprem.values / n


def reg(ax, x, y, color, label):
    b, a = np.polyfit(x, y, 1)
    xs = np.array([x.min(), x.max()])
    ax.plot(xs, a + b * xs, color=color, lw=1.6)
    return np.corrcoef(x, y)[0, 1]


fig, ax = plt.subplots(2, 3, figsize=(16.5, 9))

# 1. per-farm profit distribution
a = ax[0, 0]
a.hist(syn_b.total_reward / 1000, bins=30, color=C748, alpha=0.8, density=True, label=f"N=748 (n={nb})")
a.axvline(syn_b.total_reward.mean() / 1000, color=C748, lw=2, label=f"moy. 748 = {syn_b.total_reward.mean()/1000:.1f}k")
a.axvline(syn_s.total_reward.mean() / 1000, color=C10, ls="--", lw=2, label=f"moy. 10 = {syn_s.total_reward.mean()/1000:.1f}k")
a.set_title("1. Distribution du profit par ferme")
a.set_xlabel("profit 25 ans (k€)"); a.set_ylabel("densité"); a.legend(fontsize=8)

# 2. %premium vs profit
a = ax[0, 1]
a.scatter(syn_b.pct_premium, syn_b.total_reward / 1000, s=10, alpha=0.3, color=C748)
a.scatter(syn_s.pct_premium, syn_s.total_reward / 1000, s=45, color=C10, edgecolor="k", zorder=3)
rb = reg(a, syn_b.pct_premium.values, (syn_b.total_reward / 1000).values, C748, "748")
rs = reg(a, syn_s.pct_premium.values, (syn_s.total_reward / 1000).values, C10, "10")
a.set_title(f"2. % premium vs profit  (r: N10={rs:+.2f}, N748={rb:+.2f})")
a.set_xlabel("% années premium"); a.set_ylabel("profit total (k€)"); a.grid(alpha=0.3)

# 3. %premium vs yield
a = ax[0, 2]
a.scatter(syn_b.pct_premium, syn_b.mean_yield_t_ha, s=10, alpha=0.3, color=C748)
a.scatter(syn_s.pct_premium, syn_s.mean_yield_t_ha, s=45, color=C10, edgecolor="k", zorder=3)
rb = reg(a, syn_b.pct_premium.values, syn_b.mean_yield_t_ha.values, C748, "748")
rs = reg(a, syn_s.pct_premium.values, syn_s.mean_yield_t_ha.values, C10, "10")
a.set_title(f"3. % premium vs rendement  (r: N10={rs:+.2f}, N748={rb:+.2f})")
a.set_xlabel("% années premium"); a.set_ylabel("rendement moyen (t/ha)"); a.grid(alpha=0.3)

# 4. premium cycle (as a fraction of farms, so N is comparable)
a = ax[1, 0]
ys, fs = cycle_frac(det_s, ns)
yb, fb = cycle_frac(det_b, nb)
a.plot(ys, fs * 100, "o-", color=C10, lw=2, ms=4, label="N=10")
a.plot(yb, fb * 100, "s-", color=C748, lw=2, ms=4, label="N=748")
a.set_title("4. Cycle premium : part des fermes en premium / an")
a.set_xlabel("année"); a.set_ylabel("% fermes en premium"); a.set_ylim(0, 105)
a.legend(fontsize=9); a.grid(alpha=0.3)

# 5. action mix (mean % across farms)
a = ax[1, 1]
cats = ["premium", "AWD", "IPM", "durable", "3 sais."]
cols = ["pct_premium", "pct_AWD", "pct_IPM", "pct_durable", "pct_3seasons"]
vs = [syn_s[c].mean() for c in cols]
vb = [syn_b[c].mean() for c in cols]
x = np.arange(len(cats)); w = 0.38
a.bar(x - w / 2, vs, w, color=C10, label="N=10")
a.bar(x + w / 2, vb, w, color=C748, label="N=748")
a.set_xticks(x); a.set_xticklabels(cats, fontsize=9)
a.set_title("5. Mix d'actions moyen (% des années)")
a.set_ylabel("%"); a.legend(fontsize=9); a.grid(axis="y", alpha=0.3)

# 6. headline summary
a = ax[1, 2]
mean_s, mean_b = syn_s.total_reward.mean() / 1000, syn_b.total_reward.mean() / 1000
bars = a.bar(["N=10", "N=748"], [mean_s, mean_b], color=[C10, C748])
for bb, v in zip(bars, [mean_s, mean_b]):
    a.text(bb.get_x() + bb.get_width() / 2, v + 0.5, f"{v:.1f}k", ha="center", fontsize=11, fontweight="bold")
a.text(0.5, 0.92, f"profit/ferme N748 = {100*mean_b/mean_s:.0f}% de N10",
       transform=a.transAxes, ha="center", fontsize=10, style="italic")
a.set_title(f"6. Profit moyen / ferme  (global: {gs/1000:.0f}k -> {gb/1e6:.1f}M€)")
a.set_ylabel("profit moyen / ferme (k€)"); a.grid(axis="y", alpha=0.3)

fig.suptitle(f"Validation de scalabilité — même politique per-agent : modèle simplifié (10 fermes) vs réel ({nb} fermes)",
             fontsize=13)
fig.tight_layout(rect=[0, 0, 1, 0.97])
fig.savefig(OUT, dpi=130)
print("Wrote", OUT)
print(f"N=10  : per-farm mean {mean_s:.1f}k | global {gs/1000:.0f}k")
print(f"N=748 : per-farm mean {mean_b:.1f}k | global {gb/1e6:.2f}M | ratio {100*mean_b/mean_s:.0f}%")
