"""Écrit dans chaque .onnx les métadonnées qui disent ce qu'il EST.

Un checkpoint nu ne se documente pas : rien dans le fichier ne dit sur quelle carte il a été
entraîné, avec quelle récompense, ni surtout ce qu'attendent ses 18 entrées. Ces informations
vivaient jusqu'ici dans les configs YAML et les rapports, c'est-à-dire ailleurs que dans le
fichier qu'on livre. Ce script les remet dedans, dans `metadata_props` (des paires
clé/valeur que tout lecteur ONNX sait relire, y compris le plugin GAMA via `.info`).

Le graphe n'est pas touché : seuls `metadata_props` et `doc_string` changent, donc les modèles
restent équivalents à l'inférence.

Relançable sans risque : les clés existantes sont remplacées, pas dupliquées. À relancer après
tout nouvel entraînement.

Usage :
    py onnx_tag.py            # étiquette tous les saved_models_mappo3_*/
    py onnx_tag.py --dry-run  # affiche ce qui serait écrit, sans rien modifier
"""
from __future__ import annotations

import argparse
import glob
import json
import os

import onnx
import yaml

HERE = os.path.dirname(os.path.abspath(__file__))

# Les 18 entrées, dans l'ordre exact où ReinforcementLearning.gaml les assemble
# (PetzAgent.observe_one : rl_obs = 11 valeurs, puis l'action précédente = 6, puis
# l'avancement dans l'épisode = 1). C'est la métadonnée la plus utile du lot : sans elle,
# impossible de nourrir le modèle correctement.
OBS_FIELDS = [
    "prev_profit", "fertilizer", "soil_health", "yield_t_ha", "pollution", "salinity",
    "nb_plots", "area_ha", "premium_share", "premium_price", "decided_frac",
    "prev_action_irrigation", "prev_action_irr_qty", "prev_action_pesticide",
    "prev_action_fertil", "prev_action_cultivar", "prev_action_seasons",
    "year_fraction",
]

ACTION_FIELDS = [
    "irrigation (>=0.5 -> AWD, sinon CF)",
    "irr_qty [0-1] (CF: lame 30-70mm ; AWD: seuil -50 a -250mm)",
    "pesticide (>=0.5 -> IPM, sinon BAU)",
    "fertil (>=0.5 -> durable, sinon BAU)",
    "cultivar (>=0.5 -> premium ST25, sinon standard OM5451)",
    "seasons (>=0.5 -> 3 saisons, sinon 2)",
]

# Étiquette lisible par politique, celle utilisée dans les rapports et dans l'expérience GAMA.
LABELS = {
    "peragent": "Profit", "balanced": "Bal-20k", "balanced_l100k": "Bal-100k",
    "balanced_l200k": "Bal-200k", "balanced_l400k": "Bal-400k", "pollution": "Pollution",
    "l200k_v2": "Bal-200k v2", "dtnew_l20k": "Bal-20k @DT",
    "dtnew_profit": "Profit @DT", "dtnew_pollution": "Pollution @DT",
}


def load_yaml(path):
    if not os.path.exists(path):
        return None
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def read_json(path):
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def build_metadata(model_dir, is_best):
    suffix = os.path.basename(model_dir).replace("saved_models_mappo3_", "")
    cfg = load_yaml(os.path.join(HERE, f"config_mappo3_{suffix}.yaml"))
    if cfg is None:
        print(f"  !! config introuvable pour {suffix} -- metadonnees partielles")
        cfg = {}
    g, t = cfg.get("gama", {}), cfg.get("training", {})

    rewards = read_json(os.path.join(model_dir, "episode_rewards.json")) or []
    evals = read_json(os.path.join(model_dir, "eval_returns.json")) or []

    mode = str(t.get("reward_mode", "?"))
    reward = {"per_agent": "profit par ferme", "pollution": "- pollution",
              "global": "profit global"}.get(mode)
    if reward is None and mode == "balanced":
        reward = f"profit - {float(t.get('balance_weight', 0)):g} * pollution"

    meta = {
        "label": LABELS.get(suffix, suffix),
        "reward_mode": mode,
        "reward": reward or mode,
        "checkpoint": "best (meilleure eval greedy)" if is_best else "final (dernier episode)",
        # Absents du YAML = valeurs par defaut du GAML : Dong Thap old, carte simplifiee.
        "train_province": str(g.get("province", "Dong Thap old")),
        "train_simple_spatial_data": str(bool(g.get("simple_spatial_data", True))).lower(),
        "train_farms": "10",
        "episodes": str(len(rewards) or t.get("num_episodes", "?")),
        "seed": str(t.get("seed", "?")),
        "algo": "MAPPO, acteur gaussien partage (sans identifiant d'agent)",
        "obs_dim": "18",
        "obs_fields": ", ".join(OBS_FIELDS),
        "action_dim": "6",
        "action_fields": " | ".join(ACTION_FIELDS),
        "action_range": "chaque composante est ecretee dans [0,1] cote GAML (apply_rl_action)",
        "normalization": "moyenne/ecart-type des observations FIGES dans le graphe -- ne pas "
                         "normaliser en amont",
        "outputs": "action_mean (a utiliser en deploiement), action_std (exploration seulement)",
        "source_config": f"config_mappo3_{suffix}.yaml",
    }
    if t.get("balance_weight") is not None:
        meta["balance_weight"] = f"{float(t['balance_weight']):g}"
    if evals:
        meta["train_eval_final"] = f"{evals[-1]['return']:.0f}"
        meta["train_eval_best"] = f"{max(e['return'] for e in evals):.0f}"
        meta["train_eval_note"] = ("profit global greedy, comptabilite global_profit de GAMA -- "
                                   "PAS comparable aux chiffres par ferme des rapports")
    return meta


def tag(path, meta, dry_run):
    model = onnx.load(path)

    # Remplacement plutot qu'ajout : relancer le script ne doit pas empiler les cles.
    keep = [p for p in model.metadata_props if p.key not in meta]
    del model.metadata_props[:]
    for p in keep:
        model.metadata_props.append(p)
    for k, v in meta.items():
        entry = model.metadata_props.add()
        entry.key, entry.value = k, str(v)

    model.doc_string = (f"Starfarm MARL - politique {meta['label']} ({meta['checkpoint']}). "
                        f"Recompense : {meta['reward']}. Entrainee sur "
                        f"{meta['train_province']} ({meta['train_farms']} fermes). "
                        f"Entree obs[18], sortie action_mean[6].")

    if not dry_run:
        onnx.save(model, path)
    return len(meta)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true", help="afficher sans ecrire")
    args = ap.parse_args()

    dirs = sorted(glob.glob(os.path.join(HERE, "saved_models_mappo3_*")))
    if not dirs:
        raise SystemExit("Aucun dossier saved_models_mappo3_* trouve.")

    total = 0
    for d in dirs:
        files = sorted(glob.glob(os.path.join(d, "*.onnx")))
        if not files:
            continue
        print(f"\n{os.path.basename(d)}")
        for f in files:
            is_best = os.path.basename(f).startswith("best_")
            meta = build_metadata(d, is_best)
            n = tag(f, meta, args.dry_run)
            total += 1
            print(f"  {os.path.basename(f):28s} {n} cles  |  {meta['label']}"
                  f"  [{meta['checkpoint'].split(' ')[0]}]  {meta['reward']}")

    verb = "seraient etiquetes" if args.dry_run else "etiquetes"
    print(f"\n{total} fichiers .onnx {verb}.")
    if args.dry_run:
        print("(--dry-run : aucun fichier modifie)")


if __name__ == "__main__":
    main()
