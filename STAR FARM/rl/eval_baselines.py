"""Deterministic NO-AI baselines: every farmer plays the SAME hard-coded practice bundle
every year, whatever the state. These are the reference points the trained policies must be
judged against (a policy that cannot beat a constant strategy has learned nothing).

Two scenarios, the two extremes of the profit/pollution trade-off:

  MaxProfit    premium cultivar for EVERYONE, on the bundle the trained Profit policy
               converged to (CF, minimal flood depth, BAU pesticide, BAU fertiliser, 2
               seasons -- it measured premium 86%, AWD 0%, IPM 4%, durable 0%, irr_qty
               0.006, 3-seasons 0%). Forcing premium to 100% isolates the market-saturation
               effect that the policy learns to avoid by modulating it.
  MinPollution all-in on the green practices: IPM + durable + AWD, standard cultivar, 2
               seasons, mild AWD trigger. NB: pollution is added ONLY by pesticide spraying,
               so IPM is the sole direct lever; durable/AWD act indirectly (pest pressure),
               and a drier AWD trigger only costs yield without cutting pollution.

Two deliberate calibration choices, both informed by measurement rather than intuition:
  * 2 seasons, not 3. No trained policy ever picks 3 seasons (pct_3seasons = 0 across all
    six). Measured on the 3-season calendar: soil drops 0.015/year (= degradation_rate 0.005
    x 3 seasons, no fallow), and obs[3] (yield) reads 0 forever -- the RL decision instant
    falls after a sowing, which resets final_yield_ton_ha (Practices.gaml:245) before the
    harvest sets it (line 283). So 3 seasons both degrades the soil 3x faster and blinds one
    of the 18 observations.
  * irr_qty 0, not 1. The Profit policy converged to ~0.006 (CF flood depth ~30mm, the low
    end of [30,70]); a drier AWD trigger costs yield (4.6 -> 2.8 t/ha) for no pollution gain.

Unlike eval_policy.py's fixed baselines (profit only, different bundles, no export), this
reports BOTH axes with the same schema as eval_objectives_comparison*.xlsx, so the rows drop
straight into the Pareto tables. The env reward is fixed to per-farm PROFIT, so total_reward
IS profit; pollution is read from the per-farm observation, exactly as in eval_objectives.py.

The scenarios ignore the observation entirely, so the sequential decision order cannot change
their actions; only weather/market stochasticity moves the results between episodes.

Usage (GAMA server must be running; scale is set by `simple_spatial_data` in the GAML):
    py eval_baselines.py --suffix _simple
    py eval_baselines.py --suffix _full --episodes 3
"""
from __future__ import annotations

import argparse
import os

import numpy as np
import pandas as pd

from starfarm_env import StarfarmParallelEnv
from eval_per_farmer import run_eval, load_config, decode_action

HERE = os.path.dirname(os.path.abspath(__file__))

# Action layout (see decode_action in eval_per_farmer.py):
#   [0] irrigation >=0.5 -> AWD else CF      [3] fertil    >=0.5 -> durable else BAU
#   [1] irr_qty [0-1]                        [4] cultivar  >=0.5 -> premium else standard
#   [2] pesticide  >=0.5 -> IPM else BAU     [5] seasons   >=0.5 -> 3 else 2
SCENARIOS = [
    ("MaxProfit",    [0.0, 0.0, 0.0, 0.0, 1.0, 0.0]),
    ("MinPollution", [1.0, 0.0, 1.0, 1.0, 0.0, 0.0]),
]


class FixedPolicy:
    """Constant policy: returns the same action for every farmer, every year, ignoring the
    observation. Exposes the act_* surface run_eval() expects, so the whole evaluation
    pipeline (sequential injection, per-year recording, pollution readout) is reused as-is."""

    def __init__(self, vec):
        self._a = np.asarray(vec, dtype=np.float32)

    def act_greedy(self, obs):
        return self._a.copy()

    # Deterministic by construction: sampling a constant yields the constant.
    act_sample = act_greedy


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--suffix", default="", help="output filename suffix (e.g. _simple)")
    ap.add_argument("--episodes", type=int, default=1, help="episodes per scenario")
    ap.add_argument("--only", default=None, help="only run scenarios whose label contains this")
    ap.add_argument("--port", type=int, default=None, help="override the GAMA port from the config")
    args = ap.parse_args()

    scen = [s for s in SCENARIOS if args.only is None or args.only.lower() in s[0].lower()]
    if not scen:
        raise SystemExit(f"--only {args.only!r} matches no scenario label")

    cfg = load_config(os.path.join(HERE, "config_mappo3_peragent.yaml"))
    g, t = cfg["gama"], cfg["training"]

    port = args.port or int(g["port"])
    env = StarfarmParallelEnv(gaml_experiment_path=g["controler_path"], gaml_experiment_name=g["experiment_name"],
                              gama_ip_address=g["ip_address"], gama_port=port)
    env.MIN_DAYS_PER_YEAR = int(g["min_days_per_year"]); env.MAX_DAYS_PER_YEAR = int(g["max_days_per_year"])
    env.YEAR_END_MARGIN = int(g["year_end_margin"]); env.SUBSTEP_DAYS = int(g["substep_days"])
    env.set_reward_mode("per_agent")   # total_reward = profit, comparable with eval_objectives
    order = sorted(env.possible_agents)
    n = len(order)
    sequential = bool(t.get("sequential_decisions", True))
    print(f"Mode: DETERMINISTIC BASELINES (no AI) | {len(scen)} scenarios x {args.episodes} "
          f"episode(s) | {n} farmers | GAMA port {port}", flush=True)
    for label, vec in scen:
        d = decode_action(vec)
        print(f"  {label:13s} = {d['irrigation']}|q{d['irr_qty']:.2f}|{d['pesticide']}|"
              f"{d['fertil']}|{d['cultivar']}|{d['seasons']}s", flush=True)

    rows, details = [], []
    for label, vec in scen:
        agent = FixedPolicy(vec)
        ep_prof, ep_poll, pys = [], [], []
        for e in range(args.episodes):
            per_year, total_rew, _sanity, _n_years = run_eval(
                env, agent, order, sequential, np.random.default_rng(e))
            prof = sum(total_rew.values())
            ep_prof.append(prof)
            ep_poll.append(per_year.pollution.mean())
            per_year.insert(0, "episode", e)
            pys.append(per_year)
            if args.episodes > 1:
                print(f"    {label} ep{e}: profit={prof:,.0f}  pollution={ep_poll[-1]:.4f}", flush=True)
        allpy = pd.concat(pys, ignore_index=True)
        rows.append({
            "policy": label,
            "global_profit": float(np.mean(ep_prof)), "profit_std": float(np.std(ep_prof)),
            "profit_per_farm": float(np.mean(ep_prof)) / n,
            "mean_pollution": float(np.mean(ep_poll)), "pollution_std": float(np.std(ep_poll)),
            "mean_yield_t_ha": allpy.yield_t_ha.mean(), "mean_soil_health": allpy.soil_health.mean(),
            "pct_premium": 100 * (allpy.cultivar == "premium").mean(),
            "pct_AWD": 100 * (allpy.irrigation == "AWD").mean(),
            "pct_IPM": 100 * (allpy.pesticide == "IPM").mean(),
            "pct_durable": 100 * (allpy.fertil == "durable").mean(),
            "pct_3seasons": 100 * (allpy.seasons == 3).mean(),
            "mean_irr_qty": allpy.irr_qty.mean(),
        })
        allpy.insert(0, "policy", label)
        details.append(allpy)
        print(f"{label:13s}: profit={np.mean(ep_prof):,.0f}"
              + (f" (+/-{np.std(ep_prof):,.0f})" if args.episodes > 1 else "")
              + f"  pollution={np.mean(ep_poll):.4f}"
              + (f" (+/-{np.std(ep_poll):.4f})" if args.episodes > 1 else "")
              + f"  yield={allpy.yield_t_ha.mean():.2f}  soil={allpy.soil_health.mean():.2f}", flush=True)
    env.close()

    comp = pd.DataFrame(rows)
    det = pd.concat(details, ignore_index=True)
    out_xlsx = os.path.join(HERE, f"eval_baselines_comparison{args.suffix}.xlsx")
    with pd.ExcelWriter(out_xlsx, engine="openpyxl") as xl:
        comp.to_excel(xl, sheet_name="comparaison", index=False)
        det.to_excel(xl, sheet_name="detail", index=False)
    print("Wrote", out_xlsx)


if __name__ == "__main__":
    main()
