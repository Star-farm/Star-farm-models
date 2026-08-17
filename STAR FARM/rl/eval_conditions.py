"""Cross-MAP evaluation: replay the 6 trained policies on a province/scale they may never
have seen, and report how much of their behaviour survives the transfer.

All six policies were trained on ONE map: "Dong Thap old" with simple_spatial_data (10
farms). The interesting question is therefore not "which policy wins" -- eval_objectives.py
already answers that on the training map -- but "does anything transfer": to the full 748-farm
version of the same province, and to the colleague's new "Dong Thap" (10 simple / 992 full).

Province and scale are set at LOAD time via gaml_experiment_parameters, so one GAML file
serves every condition and nothing has to be edited between runs. The `marl` experiment
exposes both as parameters ("Province", "Simple spatial data").

The two deterministic no-AI baselines from eval_baselines.py are evaluated alongside the
policies in every condition. Without them a profit figure on an unseen 992-farm map means
nothing: only the gap to a constant strategy on the SAME map says whether the policy still
earns its keep.

Reward mode is fixed to per-farm PROFIT for every policy, so total_reward is profit
throughout and pollution is read from the observation -- identical to eval_objectives.py, so
the rows drop straight into the existing Pareto tables.

Usage (GAMA server must be running on --port):
    py eval_conditions.py --province "Dong Thap old" --simple --port 1001 --tag dtold_simple
    py eval_conditions.py --province "Dong Thap" --full  --port 1002 --tag dtnew_full
"""
from __future__ import annotations

import argparse
import os
import time

import numpy as np
import pandas as pd
import torch

from starfarm_env import StarfarmParallelEnv
from mappo_agent import MAPPOAgent
from eval_per_farmer import run_eval, load_config, LEGEND
from eval_baselines import SCENARIOS, FixedPolicy

HERE = os.path.dirname(os.path.abspath(__file__))

# (label, checkpoint dir, checkpoint file). Mirrors eval_objectives.py: the best_ checkpoint is
# selected by greedy PROFIT, which is only meaningful for the Profit policy; the objective-
# trained policies use their FINAL checkpoint (converged under their own objective).
POLICIES = [("Profit", "saved_models_mappo3_peragent", "best_starfarm_ippo.pth"),
            ("Bal-20k", "saved_models_mappo3_balanced", "starfarm_ippo.pth"),
            ("Bal-100k", "saved_models_mappo3_balanced_l100k", "starfarm_ippo.pth"),
            ("Bal-200k", "saved_models_mappo3_balanced_l200k", "starfarm_ippo.pth"),
            ("Bal-400k", "saved_models_mappo3_balanced_l400k", "starfarm_ippo.pth"),
            ("Pollution", "saved_models_mappo3_pollution", "starfarm_ippo.pth"),
            # Deux runs de CONTROLE, hors sweep. A n'evaluer qu'avec --only et un tag dedie :
            # les melanger aux 4 classeurs du rapport reunirait des runs qui repondent a des
            # questions differentes. Checkpoint FINAL, comme les autres politiques balanced.
            #   Bal-200k v2 : meme config que Bal-200k, graine 1 -> mesure l'effet de la graine.
            #   Bal-20k @DT : meme config que Bal-20k, entrainee sur Dong Thap -> separe
            #                 "echec de transfert" de "carte difficile".
            ("Bal-200k v2", "saved_models_mappo3_l200k_v2", "starfarm_ippo.pth"),
            ("Bal-20k @DT", "saved_models_mappo3_dtnew_l20k", "starfarm_ippo.pth"),
            #   Profit @DT    : Profit reentrainee sur Dong Thap -> son transfert coutait ~40 %,
            #                   ce run dit si c'est un cout de transfert ou un plafond de carte.
            #   Pollution @DT : l'objectif pollution reentraine sur place. SEUL ce passage en
            #                   evaluation peut trancher : le journal d'entrainement ne remonte
            #                   que le profit, jamais la pollution -- c'est-a-dire jamais
            #                   l'objectif meme de cette politique.
            ("Profit @DT", "saved_models_mappo3_dtnew_profit", "starfarm_ippo.pth"),
            ("Pollution @DT", "saved_models_mappo3_dtnew_pollution", "starfarm_ippo.pth")]

CONDITION_LEGEND = [
    ("CONDITION", ""),
    ("province", "Carte GAMA evaluee. 'Dong Thap old' = carte d'ENTRAINEMENT ; 'Dong Thap' = nouvelle carte du collegue, jamais vue par les politiques."),
    ("simple_spatial_data", "true = carte simplifiee (10 fermes, celle de l'entrainement) ; false = carte complete (748 ou 992 fermes)."),
    ("n_farmers", "Nombre de fermiers dans cette condition. L'acteur est partage et sans identifiant, donc il se transfere a n'importe quel effectif ; seul le critique centralise depend de n_agents, et il n'est pas utilise en evaluation."),
    ("MaxProfit / MinPollution", "Baselines DETERMINISTES sans IA (eval_baselines.py) : chaque fermier joue le meme bundle chaque annee. Reference obligatoire -- une politique qui ne les bat pas sur cette carte n'a rien transfere."),
    ("global_profit", "Profit cumule sur l'episode, somme sur tous les fermiers (EUR). N'est PAS comparable entre conditions d'effectif different -- utiliser profit_per_farm."),
    ("profit_per_farm", "global_profit / n_farmers : la seule colonne comparable d'une carte a l'autre."),
    ("", ""),
]


def build_agent(ckpt_path, t, obs_dim, act_dim, n_env):
    """Load a checkpoint sized to ITS OWN n_agents.

    The actor is per-farmer, shared and carries no agent id, so it transfers to any number of
    farms -- which is the whole point of this script. Only the centralized critic depends on
    n_agents, and it is unused at evaluation, so sizing it to the checkpoint keeps the load
    valid when the environment now has 748 or 992 farms instead of the 10 seen in training.
    """
    ckpt_n = int(torch.load(ckpt_path, map_location="cpu", weights_only=False).get("n_agents", n_env))
    agent = MAPPOAgent(
        obs_dim=obs_dim, act_dim=act_dim, n_agents=ckpt_n,
        hidden_dim=t["hidden_dim"], lr=t["lr"], gamma=t["gamma"], gae_lambda=t["gae_lambda"],
        clip_eps=t["clip_eps"], k_epochs=t["k_epochs"], minibatch_size=t["minibatch_size"],
        entropy_coef=t["entropy_coef"], value_coef=t["value_coef"],
        normalize_obs=t["normalize_obs"], critic_hidden_dim=t.get("critic_hidden_dim"))
    agent.load(ckpt_path)
    return agent, ckpt_n


def summarise(label, ep_prof, ep_poll, allpy, n):
    return {
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
    }


def per_farmer_rows(label, allpy, total_rew, n_years):
    """One row per (policy, farmer). Kept even at 992 farms: farm-level spread is exactly what
    changes when a 10-farm policy meets a crowded market."""
    out = []
    for a, sub in allpy.groupby("farmer", sort=False):
        out.append({
            "policy": label, "farmer": a,
            "total_reward": total_rew.get(a, float("nan")),
            "mean_annual_reward": total_rew.get(a, float("nan")) / max(n_years, 1),
            "nb_plots": float(sub.nb_plots.iloc[0]), "area_ha": float(sub.area_ha.iloc[0]),
            "mean_soil_health": sub.soil_health.mean(), "mean_yield_t_ha": sub.yield_t_ha.mean(),
            "mean_fertilizer": sub.fertilizer.mean(), "mean_pollution": sub.pollution.mean(),
            "mean_salinity": sub.salinity.mean(),
            "pct_AWD": 100.0 * (sub.irrigation == "AWD").mean(),
            "pct_IPM": 100.0 * (sub.pesticide == "IPM").mean(),
            "pct_durable": 100.0 * (sub.fertil == "durable").mean(),
            "pct_premium": 100.0 * (sub.cultivar == "premium").mean(),
            "pct_3seasons": 100.0 * (sub.seasons == 3).mean(),
            "mean_irr_qty": sub.irr_qty.mean(),
        })
    return out


def write_workbook(path, meta, rows, farmers, details):
    """Rewritten after EVERY policy, not once at the end: a full-map condition is hours of
    simulation, and losing all of it to a crash in the last policy would be absurd."""
    legend = pd.DataFrame(CONDITION_LEGEND + LEGEND, columns=["element", "signification"])
    with pd.ExcelWriter(path, engine="openpyxl") as xl:
        pd.DataFrame(meta).to_excel(xl, sheet_name="condition", index=False)
        legend.to_excel(xl, sheet_name="legende", index=False)
        pd.DataFrame(rows).to_excel(xl, sheet_name="comparaison", index=False)
        pd.DataFrame(farmers).to_excel(xl, sheet_name="synthese_fermiers", index=False)
        pd.concat(details, ignore_index=True).to_excel(xl, sheet_name="detail", index=False)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--province", required=True, help='e.g. "Dong Thap old" or "Dong Thap"')
    scale = ap.add_mutually_exclusive_group(required=True)
    scale.add_argument("--simple", dest="simple", action="store_true", help="simplified map")
    scale.add_argument("--full", dest="simple", action="store_false", help="full map")
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--tag", required=True, help="output goes to eval_condition_<tag>.xlsx")
    ap.add_argument("--episodes", type=int, default=1)
    ap.add_argument("--stochastic", action="store_true", help="sample instead of greedy actions")
    ap.add_argument("--only", default=None,
                    help="comma-separated list; keep policies whose label contains any entry. "
                         "Beware that a bare 'Pollution' also matches 'MinPollution' -- to split "
                         "a queue across two ports without running anything twice, name them "
                         "exactly (e.g. --only 'MaxProfit,MinPollution')")
    ap.add_argument("--no-baselines", action="store_true", help="skip the no-AI baselines")
    ap.add_argument("--resume", action="store_true",
                    help="keep the policies already in the workbook, run only the missing ones "
                         "(a full-map policy costs ~1h; a machine sleep kills the GAMA socket "
                         "and the client then blocks forever on a dead connection)")
    args = ap.parse_args()

    cfg = load_config(os.path.join(HERE, "config_mappo3_peragent.yaml"))
    g, t = cfg["gama"], cfg["training"]

    params = [{"type": "string", "name": "Province", "value": args.province},
              {"type": "bool", "name": "Simple spatial data", "value": str(args.simple).lower()}]

    env = StarfarmParallelEnv(gaml_experiment_path=g["controler_path"],
                              gaml_experiment_name=g["experiment_name"],
                              gaml_experiment_parameters=params,
                              gama_ip_address=g["ip_address"], gama_port=args.port)
    env.MIN_DAYS_PER_YEAR = int(g["min_days_per_year"]); env.MAX_DAYS_PER_YEAR = int(g["max_days_per_year"])
    env.YEAR_END_MARGIN = int(g["year_end_margin"]); env.SUBSTEP_DAYS = int(g["substep_days"])
    env.set_reward_mode("per_agent")

    # Read the map back out of the running simulation. A parameter GAMA silently ignored would
    # otherwise produce a whole workbook of results labelled with the wrong province.
    got_prov = str(env.gama_client._execute_expression(env.experiment_id, "province"))
    got_simple = bool(env.gama_client._execute_expression(env.experiment_id, "simple_spatial_data"))
    if got_prov != args.province or got_simple != args.simple:
        env.close()
        raise SystemExit(f"GAMA ignored the parameters: asked for ({args.province}, "
                         f"simple={args.simple}), got ({got_prov}, simple={got_simple})")

    order = sorted(env.possible_agents)
    n = len(order)
    sequential = bool(t.get("sequential_decisions", True))
    obs_dim = int(np.prod(env.observation_space(order[0]).shape))
    act_dim = int(np.prod(env.action_space(order[0]).shape))
    mode = "STOCHASTIC (sampled)" if args.stochastic else "GREEDY (deterministic)"

    print(f"Condition: province={got_prov!r} simple={got_simple} | {n} farmers | port {args.port}\n"
          f"Mode: {mode} | {args.episodes} episode(s)/policy | sequential={sequential}", flush=True)

    wanted = [s.strip().lower() for s in args.only.split(",") if s.strip()] if args.only else None

    def keep(label):
        return wanted is None or any(w in label.lower() for w in wanted)

    runners = [(lab, os.path.join(HERE, d, ck)) for lab, d, ck in POLICIES if keep(lab)]
    if not args.no_baselines:
        runners += [(lab, vec) for lab, vec in SCENARIOS if keep(lab)]
    if not runners:
        env.close()
        raise SystemExit(f"--only {args.only!r} matches nothing")

    out_xlsx = os.path.join(HERE, f"eval_condition_{args.tag}.xlsx")
    rows, farmers, details = [], [], []
    already = set()
    if args.resume and os.path.exists(out_xlsx):
        prev = pd.read_excel(out_xlsx, sheet_name=None)
        rows = prev["comparaison"].to_dict("records")
        farmers = prev["synthese_fermiers"].to_dict("records")
        details = [prev["detail"]]
        already = {r["policy"] for r in rows}
        print(f"Resume: {len(already)} deja fait(s) -> {sorted(already)}", flush=True)
    t_start = time.time()

    for label, spec in runners:
        if label in already:
            print(f"{label:12s} deja evalue -- ignore (--resume)", flush=True)
            continue
        if isinstance(spec, str):                     # trained checkpoint
            if not os.path.exists(spec):
                print(f"  !! {label}: checkpoint missing ({spec}) -- skipped", flush=True)
                continue
            agent, ckpt_n = build_agent(spec, t, obs_dim, act_dim, n)
            origin = f"MAPPO (trained on {ckpt_n} farms)"
        else:                                          # deterministic no-AI baseline
            agent, origin = FixedPolicy(spec), "baseline sans IA"

        t0 = time.time()
        ep_prof, ep_poll, pys, last_rew, n_years = [], [], [], {}, 0
        for e in range(args.episodes):
            per_year, total_rew, _sanity, n_years = run_eval(
                env, agent, order, sequential, np.random.default_rng(e),
                stochastic=args.stochastic)
            ep_prof.append(sum(total_rew.values()))
            ep_poll.append(per_year.pollution.mean())
            per_year.insert(0, "episode", e)
            pys.append(per_year)
            last_rew = total_rew

        allpy = pd.concat(pys, ignore_index=True)
        rows.append(summarise(label, ep_prof, ep_poll, allpy, n))
        farmers.extend(per_farmer_rows(label, allpy, last_rew, n_years))
        allpy.insert(0, "policy", label)
        details.append(allpy)

        dt = time.time() - t0
        print(f"{label:12s} [{origin:26s}] profit={np.mean(ep_prof):>14,.0f}"
              f"  /ferme={np.mean(ep_prof)/n:>10,.0f}  pollution={np.mean(ep_poll):.4f}"
              f"  IPM={100*(allpy.pesticide=='IPM').mean():>3.0f}%"
              f"  durable={100*(allpy.fertil=='durable').mean():>3.0f}%"
              f"  AWD={100*(allpy.irrigation=='AWD').mean():>3.0f}%"
              f"  premium={100*(allpy.cultivar=='premium').mean():>3.0f}%"
              f"  [{dt/60:.1f} min]", flush=True)

        meta = [{"province": got_prov, "simple_spatial_data": got_simple, "n_farmers": n,
                 "episodes": args.episodes, "mode": mode, "sequential": sequential,
                 "gama_port": args.port, "tag": args.tag,
                 "policies_done": len(rows), "policies_total": len(runners)}]
        write_workbook(out_xlsx, meta, rows, farmers, details)

    env.close()
    print(f"\nWrote {out_xlsx}  ({len(rows)} policies, {(time.time()-t_start)/60:.1f} min)")


if __name__ == "__main__":
    main()
