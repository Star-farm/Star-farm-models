# STAR FARM — RL (MARL sur la simulation rizicole)

Entraînement multi-agents (MAPPO, acteur partagé + critique centralisé) par-dessus la
simulation GAMA via `gama-pettingzoo` (lib externe dans `Gama-petz/`, jamais modifiée ici :
tout le sur-mesure vit dans `starfarm_env.py`).

## Pipeline

| Fichier | Rôle |
|---|---|
| `starfarm_env.py` | Pont GAMA <-> PettingZoo : 1 step RL = 1 année de culture, sous-steps saisonniers, décisions séquentielles, écritures via action-call GAML (le serveur rejette les affectations `<-`) |
| `mappo_agent.py` | MAPPO : acteur gaussien partagé (transférable à N fermes), critique centralisé, normalisation obs/valeur |
| `train_mappo.py` | Entraînement (config YAML en argument), checkpoints + best_ + sauvegarde de secours |
| `eval_per_farmer.py` | Éval par fermier -> Excel multi-feuilles ; expose `run_eval()` réutilisé par les autres évals |
| `eval_objectives.py` | Compare les 6 politiques (Profit / Bal-λ / Pollution) sur profit ET pollution ; `--stochastic`, `--episodes`, `--suffix` |
| `eval_baselines.py` | Baselines déterministes SANS IA (MaxProfit 100% premium, MinPollution 100% vert) |
| `eval_variability.py` | Variance inter-épisodes d'une politique |
| `plot_*.py` | Figures (synthèse Pareto 4 conditions, per-farmer, scalabilité) |
| `report/` | Rapports .md + `generate_pdf.py <fichier.md>` pour produire les PDF |
| `archive/`, `report/archive/` | Anciens scripts/rapports conservés pour référence (ère IPPO, générateurs one-shot) |

## Configs

`config_mappo3_*.yaml` (gitignorés, locaux) : un par objectif de récompense —
`peragent` (profit par ferme), `pollution`, `balanced[_l100k/_l200k/_l400k]` (λ).
`config.yaml` est l'exemple commité. Le port GAMA varie selon le lancement
(les scripts d'éval acceptent `--port`).

## Échelle de la simulation

`simple_spatial_data` dans `models/Experiments/ReinforcementLearning.gaml` (expérience
`marl`) : `true` = carte simplifiée (~10 fermes, entraînement), `false` = carte réelle
(748 fermes, éval de transfert). L'acteur partagé transfère sans réentraînement.
NE PAS éditer le GAML pendant qu'un run tourne (`env.reset()` relit le fichier).

## Artefacts

`eval_*_comparison*.xlsx` (feuilles `comparaison` + `detail`), `eval_objectives_curves*.png`,
`synthesis_pareto.png` ; suffixes : `_greedy10`/`_stoch10` (10 fermes), `_bigmodel`/`_stoch748`
(748), `_simple`/`_full` (baselines). Checkpoints dans `saved_models_mappo3_<objectif>/`
(gitignorés).
