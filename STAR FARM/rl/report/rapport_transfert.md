# Entraînement MAPPO et test de transfert — 6 politiques × 4 cartes

**Question posée.** Les six politiques ont toutes été entraînées sur *une seule* carte :
Dong Thap old simplifiée, 10 fermes. Ce rapport mesure ce qu'il en reste ailleurs — sur la
carte réelle de la même province (748 fermes) et sur la nouvelle province Dong Thap
(10 et 992 fermes), jamais vue à l'entraînement.

**Réponse courte.** Sur six politiques, **une seule transfère** de façon convaincante.

---

## 1. Entraînement

MAPPO, acteur gaussien partagé (sans identifiant d'agent, donc transférable à N fermes) +
critique centralisé. 1 step RL = 1 année de culture, décisions séquentielles en ordre
aléatoire, sous-steps de 122 jours. **400 épisodes** par politique.

| lr | γ | GAE λ | clip | k_epochs | hidden | critic | entropie |
|---|---|---|---|---|---|---|---|
| 3e-4 | 0,97 | 0,95 | 0,2 | 4 | 128 | 256 | 0,01 → 0,001 |

Six objectifs de récompense, tout le reste identique :

| politique | récompense |
|---|---|
| Profit | profit par ferme |
| Bal-20k … Bal-400k | `profit − λ · pollution`, λ ∈ {20k, 100k, 200k, 400k} |
| Pollution | `− pollution` |

Checkpoints en `.pth` **et `.onnx`** (normalisation des observations figée dans le graphe,
export inference-only).

## 2. Protocole de test

Quatre conditions, obtenues en passant `province` et `simple_spatial_data` en paramètres de
l'expérience `marl` au chargement — un seul fichier GAML, aucune édition entre les runs.
Le script relit les deux valeurs dans la simulation en cours et refuse de produire un
classeur si GAMA a ignoré un paramètre.

| condition | province | carte | fermes |
|---|---|---|---|
| `dtold_simple` | Dong Thap old | simplifiée | 10 ← entraînement |
| `dtold_full` | Dong Thap old | complète | 748 |
| `dtnew_simple` | Dong Thap | simplifiée | 10 |
| `dtnew_full` | Dong Thap | complète | 992 |

Récompense fixée à **profit par ferme** pour toutes les politiques (la pollution est lue dans
l'observation), actions **greedy**, même graine d'ordre de décision partout.

Chaque condition embarque ses **deux baselines déterministes sans IA** (`MaxProfit` =
100 % premium ; `MinPollution` = IPM + durable + AWD). C'est indispensable : un profit sur une
carte inconnue n'est pas interprétable seul, et la baseline change de signe d'une carte à
l'autre.

## 3. Résultats

### Profit par ferme (k€ / 25 ans)

| politique | old simple (10) | old complet (748) | new simple (10) | new complet (992) |
|---|---|---|---|---|
| **Profit** | **46,2** | **45,0** | **27,5** | **26,6** |
| Bal-20k | 31,6 | 27,6 | −10,2 | 8,9 |
| Bal-100k | 23,6 | 13,6 | 5,9 | 7,9 |
| Bal-400k | 13,5 | 4,1 | −19,6 | 2,0 |
| Bal-200k | 3,2 | −6,1 | −5,0 | −6,7 |
| Pollution | −5,4 | −24,2 | −30,6 | −28,4 |
| *MaxProfit (sans IA)* | *4,7* | *11,1* | *−8,6* | *6,6* |
| *MinPollution (sans IA)* | *−110,0* | *−105,4* | *−121,4* | *−115,1* |

Le profit **global** n'est pas comparable entre cartes (10 vs 992 fermes) : seule cette
colonne par ferme l'est.

### Écart à la meilleure baseline sans IA de la même carte (k€/ferme)

C'est la mesure de transfert : `> 0` = la politique bat une stratégie qui ignore l'état.
Un ratio serait trompeur, la baseline étant négative sur `dtnew_simple`.

| politique | old simple | old complet | new simple | new complet |
|---|---|---|---|---|
| **Profit** | **+41,4** | **+33,9** | **+36,1** | **+20,0** |
| Bal-100k | +18,9 | +2,4 | +14,5 | +1,3 |
| Bal-20k | +26,9 | +16,4 | **−1,7** | +2,2 |
| Bal-400k | +8,8 | **−7,0** | **−11,1** | **−4,6** |
| Bal-200k | **−1,5** | **−17,3** | +3,6 | **−13,3** |
| Pollution | **−10,2** | **−35,3** | **−22,0** | **−35,0** |

### Pollution moyenne (bas = mieux)

| politique | old simple | old complet | new simple | new complet |
|---|---|---|---|---|
| Bal-20k | **0,0348** | **0,0055** | **0,0034** | **0,0058** |
| Bal-100k | 0,0451 | 0,0112 | 0,0077 | 0,0087 |
| Pollution | 0,0479 | 0,0131 | 0,0084 | 0,0110 |
| *MinPollution (100 % IPM)* | *0,0681* | *0,0108* | *0,0064* | *0,0090* |

## 4. Ce que ça montre

**Une seule politique transfère.** Profit bat la baseline sur les quatre cartes avec une marge
franche (+20 à +41 k€/ferme). Bal-100k est la seule autre jamais négative, mais son avance
s'effondre à pleine échelle (+18,9 → +2,4). Les trois dernières perdent contre une stratégie
constante sur trois cartes sur quatre.

**L'acteur partagé généralise à l'échelle.** Profit conserve **97 %** de son profit par ferme
en passant de 10 à 748 fermes *et* de 10 à 992. La propriété visée par l'architecture — un
acteur par fermier, sans identifiant — est vérifiée sur deux provinces.

**La carte simplifiée surestime les performances.** La baseline sans IA *s'améliore* avec
l'échelle sur les deux provinces (4,7 → 11,1 et −8,6 → +6,6) pendant que les politiques se
dégradent. Sur 10 fermes, quatre politiques semblent bonnes ; sur la carte réelle, une seule
garde une marge solide. **Bon terrain d'entraînement, mauvais terrain de mesure.**

**La récompense pollution ne pilotait rien.** Sur les quatre cartes, la politique entraînée
pour minimiser la pollution ne l'obtient jamais — et la baseline à 100 % d'IPM non plus.
Celle qui atteint la pollution la plus basse partout est Bal-20k. Or l'IPM est le **seul**
levier direct : la pollution n'est ajoutée que par un épandage (`Practices.gaml:481`). Le
sweep λ optimisait donc contre une cible hors de sa portée, ce qui explique les runs
dégénérés bien mieux qu'un « λ trop grand ».

**Bal-200k est un entraînement raté, pas un effet de λ.** Il est l'anomalie aux deux échelles
et sur les deux provinces (Bal-400k fait mieux que lui partout), et il ne bat pas la baseline
sur sa propre carte d'entraînement.

## 5. Limites

- **Cartes complètes : 1 épisode** (45–60 min chacun), simplifiées : 3. Pas de barre d'erreur
  sur les deux conditions les plus coûteuses. Les écarts de Profit dépassent largement la
  variabilité observée sur cartes simples (~1 %), mais les marges de Bal-20k et Bal-100k à
  pleine échelle (+2,2 et +1,3) sont trop minces pour être départagées sans répétitions.
- **Le mécanisme de la pollution n'est pas établi.** L'hypothèse d'une boucle pollution →
  pression parasitaire → épandages (`Farms and Plots.gaml:445`) reste **non vérifiée** :
  `pesticide_count` existe sur la parcelle mais pas dans l'observation. L'exposer changerait
  la dimension d'observation et interdirait de réutiliser ces checkpoints.
- **Une seule graine par politique.** « Entraînement raté » pour Bal-200k reste une inférence
  à partir du comportement en évaluation, pas une comparaison multi-graines.

## 6. Reproduction

```bash
py eval_conditions.py --province "Dong Thap old" --simple --port 1001 --tag dtold_simple --episodes 3
py eval_conditions.py --province "Dong Thap old" --full   --port 1001 --tag dtold_full
py eval_conditions.py --province "Dong Thap"     --simple --port 1002 --tag dtnew_simple --episodes 3
py eval_conditions.py --province "Dong Thap"     --full   --port 1002 --tag dtnew_full
py plot_conditions.py
```

`--resume` reprend un classeur existant en ne rejouant que les politiques manquantes.

**Artefacts** : `eval_condition_<tag>.xlsx` (feuilles `condition`, `legende`, `comparaison`,
`synthese_fermiers`, `detail`), `eval_conditions_synthesis.xlsx`, `eval_conditions_curves.png`.

**Prérequis GAML** : `Dong Thap old` doit fournir `plot_shapefile_simple.*` et
`salinity_vulnerability_map_simple.tif`. Le renommage amont (`-simple` → `_simple`) avait
laissé cette province de côté, rendant la carte d'entraînement inchargeable.
