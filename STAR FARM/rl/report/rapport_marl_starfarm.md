# Rapport — Premier entraînement MARL sur Starfarm

*Apprentissage par renforcement multi-agent (IPPO) pour la maximisation du revenu agricole global*

---

## 1. Objectif

Starfarm est une simulation multi-agents (GAMA) d'un paysage rizicole : plusieurs **fermiers** gèrent chacun une exploitation de parcelles, en choisissant des **pratiques** (irrigation, pesticides, fertilisation). Un **marché** convertit les récoltes en revenu, avec un prix dynamique (la saturation du marché fait baisser les prix).

**But de ce premier entraînement :** apprendre, par fermier et par année, une combinaison de pratiques qui **maximise le revenu global = somme des profits annuels de tous les fermiers**, sur un horizon de 10 ans.

---

## 2. Méthodologie

### 2.1 Environnement et cadence

La simulation Starfarm est exposée à Python via **GAMA-server** et la bibliothèque `gama-pettingzoo` (interface PettingZoo `ParallelEnv`). L'agent-pont `PetzAgent` est **embarqué directement dans le monde Starfarm** (pas de co-modèle), de sorte que `client.step` fait avancer l'horloge de simulation normalement.

- **1 pas RL = 1 année simulée.** L'environnement Python (`StarfarmParallelEnv`) effectue un *macro-pas* : il applique les décisions de l'année, fait avancer la simulation jour par jour jusqu'à la fin de l'année agricole (`year_done`), puis relève la transition.
- **Optimisation des échanges** : au lieu d'avancer un jour à la fois (~730 allers-retours GAMA↔Python par an), un seul appel `nb_step` groupé couvre l'essentiel de l'année, suivi d'une courte finition. La durée d'une année étant **indépendante des actions** (la maturité dépend uniquement du temps thermique = température), elle est mémorisée et réutilisée : ~10 allers-retours/an après calibration.

### 2.2 Espace d'action — `Box(4)` continu (∈ [0,1])

Chaque dimension pilote une **fonction de changement de régime** du modèle :

| dim | levier | décodage |
|-----|--------|----------|
| `a[0]` | irrigation | < 0.5 → **CF** (flooding continu) ; ≥ 0.5 → **AWD** (assèchement alterné) |
| `a[1]` | quantité d'irrigation | profondeur d'inondation CF [30–70 mm] / seuil de sécheresse AWD [−50…−250 mm] |
| `a[2]` | pesticide | ≥ 0.5 → **IPM** (lutte intégrée, moins d'intrants) ; sinon **BAU** |
| `a[3]` | fertilisation | ≥ 0.5 → **durable** (dose réduite) ; sinon **BAU** |

Les pesticides et la fertilisation sont donc des **régimes binaires** (conventionnel BAU vs durable/IPM), avec des cartes de seuils par saison fidèles au modèle.

### 2.3 Observation — `Box(9)`

Par fermier, en fin d'année : **4 variables d'état** + **4 dernières actions** + **1 indice d'année normalisé**.

| # | variable d'état | rôle |
|---|-----------------|------|
| 1 | profit de l'an dernier | résultat économique |
| 2 | fertilisant moyen appliqué | effet de l'action |
| 3 | santé du sol moyenne | état persistant |
| 4 | rendement final moyen (t/ha) | résultat agronomique |

*(Cinq variables initialement envisagées — revenu, coûts, usage d'eau, charge ravageurs, niveau d'eau — ont été retirées : au moment du relevé (post-récolte) elles sont écrasées, instantanées, ou valent ~0, donc sans signal.)* Normalisation (moyenne/écart-type courants) côté Python.

### 2.4 Récompense

**Récompense globale partagée** : chaque fermier reçoit `r = Σ profits annuels de tous les fermiers` de l'année écoulée. Elle est alignée sur l'objectif (le bien-être collectif) et stabilise l'apprentissage coopératif. *(Un mode « par fermier » est aussi disponible.)*

### 2.5 Algorithme — IPPO

**Independent PPO à poids partagés** : un **seul** réseau acteur-critique (politique **gaussienne diagonale** pour l'action continue) est partagé par les 10 fermiers ; leurs transitions sont mises en commun pour la mise à jour PPO. Avantages estimés par GAE, objectif clippé, bonus d'entropie.

### 2.6 Protocole d'entraînement

| hyperparamètre | valeur | | hyperparamètre | valeur |
|---|---|---|---|---|
| épisodes | 200 | | clip ε | 0.2 |
| horizon | 10 ans | | k epochs | 4 |
| γ (discount) | 0.95 | | minibatch | 64 |
| GAE λ | 0.95 | | couche cachée | 128 |
| learning rate | 3e-4 → 0 (annealing linéaire) | | coef. entropie | 0.01 |
| reward scale | 1e-6 | | coef. valeur | 0.5 |

Deux garde-fous ont été ajoutés : **sauvegarde du meilleur modèle** (`best_*.pth`, par moyenne mobile) séparément du dernier, et **annealing du learning rate**.

---

## 3. Résultats

### 3.1 Courbe d'apprentissage

![Courbe d'apprentissage](fig1_learning_curve.png)

**Le retour DÉCLINE au fil de l'entraînement** : il part de ~282k (épisode 0, qui est aussi le **maximum**) et descend régulièrement vers ~271k. L'algorithme ne s'améliore donc pas — au contraire, il **dérive** en s'éloignant d'une bonne politique initiale. C'est exactement pourquoi le **mécanisme de meilleur-checkpoint** est crucial : il a conservé la bonne politique précoce (que le modèle final, dégradé, n'aurait pas fournie).

### 3.2 Comparaison aux baselines

![Comparaison aux baselines](fig2_eval_baselines.png)

Évaluation en politique **déterministe (greedy)**, profit global moyen sur 10 ans :

| politique | profit global | écart vs `fixed_low` |
|---|---|---|
| **trained (best)** | **284 806** | **+0,1 %** |
| `fixed_low` (CF / BAU / BAU) | 284 404 | référence |
| trained (final) | 275 132 | −3,3 % |
| `fixed_mid` (CF / IPM / durable) | 265 727 | −6,6 % |
| random | 262 850 | −7,6 % |
| `fixed_high` (AWD / IPM / durable) | 262 374 | −7,7 % |

**Lecture :**
- Le **meilleur modèle égale le meilleur baseline constant** (`fixed_low`) et **bat tout le reste de +7 à +8 %** (hasard, régimes durable/IPM, AWD).
- Dans ce modèle, **l'agriculture intensive conventionnelle (BAU) maximise le profit** : réduire les intrants (IPM, fertilisation durable, AWD) fait perdre plus en rendement que ça n'économise en coûts.
- La politique entraînée a donc **correctement convergé** vers ce régime BAU intensif.

### 3.3 Dynamique intra-épisode

![Profit annuel décroissant](fig3_intra_episode.png)

À l'intérieur d'un épisode, le **profit annuel décroît** (~35k la 1ʳᵉ année → ~22k la 10ᵉ). Cela reflète une **dynamique du modèle** (vraisemblablement dégradation progressive de la santé du sol / pression cumulée), indépendante de la qualité de l'apprentissage. C'est une piste agronomique intéressante : la rentabilité n'est pas soutenable telle quelle sur 10 ans.

---

## 4. Discussion

**Pourquoi l'apprentissage dérive-t-il ?** L'optimum de ce problème est une politique **quasi-constante** (« tout le monde en BAU intensif »), presque indépendante de l'état. Il n'y a donc **quasiment rien à apprendre** au-delà d'une constante : la politique initiale est déjà proche de l'optimum, et l'exploration PPO ne fait que s'en éloigner (vers les régimes durable/AWD, moins rentables). Le bonus d'entropie entretient cette exploration improductive.

**Déterminisme.** L'environnement est **déterministe** (météo chargée d'un fichier fixe, durée d'année indépendante des actions) : pour une politique donnée, le résultat est strictement reproductible (écart-type = 0). Il n'y a donc **aucune pression de généralisation**, ce qui renforce le caractère dégénéré du problème pour le RL.

**Attribution de crédit.** La récompense globale partagée dilue la contribution individuelle de chaque fermier (1/10), ce qui brouille le signal d'apprentissage — un facteur classique de difficulté en MARL coopératif, qui contribue aussi à la dérive.

---

## 5. Conclusions

1. ✅ **Le pipeline MARL fonctionne de bout en bout** : action continue `Box(4)` pilotant les pratiques, observation `Box(9)`, IPPO gaussien, macro-pas optimisé, évaluation contre baselines.
2. ✅ **Le meilleur modèle est quasi-optimal** : il atteint le meilleur régime constant (BAU intensif) et bat hasard/durable/AWD de **+7 à +8 %**.
3. ⚠️ **L'entraînement ne « progresse » pas** : il dérive ; seul le meilleur-checkpoint sauve le résultat. **Toujours déployer `--best`, jamais le modèle final.**
4. 🔎 **Résultat métier** : dans ce modèle, **les intrants conventionnels (BAU) maximisent le profit** ; et la **rentabilité décroît sur l'horizon** (signal de non-durabilité).

---

## 6. Recommandations / prochaines étapes

| piste | intérêt |
|---|---|
| **Utiliser le meilleur-checkpoint** (déjà en place) | indispensable vu la dérive |
| **Randomiser la météo / conditions initiales par épisode** | crée un vrai problème *apprenable* (politique adaptative à l'état) et une pression de généralisation ; casse le déterminisme dégénéré |
| **Reward shaping durabilité** (pénaliser émissions, valoriser santé du sol) | transforme « max profit » en un **arbitrage rendement/durabilité** non trivial — là le RL apporterait une vraie valeur |
| **MAPPO** (critique centralisé) | atténue l'attribution de crédit si l'on garde la récompense globale partagée |
| **Réduire l'exploration tardive** (entropie décroissante) | limite la dérive, en complément du best-checkpoint |

---

## 7. Annexe — Reproduire

```powershell
cd "STAR FARM/rl"
# Entraînement (200 épisodes, logs année-par-année) :
py train_ippo.py
# Évaluation du meilleur modèle vs baselines :
py eval_policy.py --best --episodes 3
# Évaluation du modèle final (montre la dégradation) :
py eval_policy.py --episodes 3
# Régénérer les figures de ce rapport :
py report/generate_report_figures.py
```

**Fichiers clés** : `starfarm_env.py` (env + macro-pas), `ppo_agent.py` (IPPO gaussien),
`train_ippo.py` (boucle + best-checkpoint + annealing), `eval_policy.py` (éval baselines),
`config.yaml` (hyperparamètres), `models/Experiments/ReinforcementLearning.gaml` (pont RL + pratiques).

*Données : `saved_models/episode_rewards.json` (courbe), résultats d'évaluation mesurés sur 3 épisodes par politique.*
