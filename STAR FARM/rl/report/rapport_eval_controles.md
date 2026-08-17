# Évaluation des deux runs de contrôle

Les deux entraînements de contrôle (`l200k_v2`, `dtnew_l20k`) ont été repassés dans
`eval_conditions.py`, sur les **deux échelles de leur propre province**. Objectif : obtenir
des chiffres dans la même métrique que le rapport de transfert — le `greedy_return` affiché
pendant l'entraînement utilise la comptabilité `global_profit` de GAMA, celle du rapport somme
les récompenses par ferme, et les deux ne coïncident pas.

Protocole : actions greedy, 3 épisodes sur carte simplifiée, 1 seul sur carte complète
(45–60 min l'épisode). Baselines non rejouées — les valeurs mesurées pour ces mêmes conditions
dans le rapport de transfert servent de référence.

---

## 1. Bal-200k : la graine change l'ampleur, pas le verdict

Profit par ferme (k€ / 25 ans) et écart à la baseline sans IA de la même carte :

| carte | seed 0 | seed 1 (v2) | baseline |
|---|---|---|---|
| DT old simplifiée (10) | 3,2 → **−1,5** | **12,9 → +8,2** | +4,7 |
| DT old complète (748) | −6,1 → **−17,3** | **4,9 → −6,2** | +11,1 |

L'écart entre graines observé à l'entraînement (×3,7) se retrouve en évaluation : ×4 sur la
carte simplifiée, et un passage du négatif au positif sur la carte complète.

**Mais la conclusion opérationnelle ne change pas.** Sur la carte réelle, même la bonne graine
reste **sous la baseline sans IA** (−6,2 k€/ferme). λ=200k ne produit pas de politique
utilisable à l'échelle réelle, quelle que soit la graine ; la graine déplace l'ampleur de
l'échec, pas sa nature.

À noter, `Bal-200k v2` ne conserve que **38 %** de son profit par ferme en passant de 10 à
748 fermes (12,9 → 4,9), là où Profit en conserve 97 %.

## 2. Bal-20k réentraînée sur place : meilleure que tout ce qui a été transféré

| carte | Bal-20k transférée | **Bal-20k @DT** | Profit transférée | baseline |
|---|---|---|---|---|
| DT simplifiée (10) | −10,2 → −1,7 | **36,6 → +45,2** | 27,5 → +36,1 | −8,6 |
| DT complète (992) | 8,9 → +2,2 | **27,6 → +21,0** | 26,6 → +20,0 | +6,6 |

C'est le résultat le plus net de la série. La même récompense, entraînée sur la bonne carte,
passe de **sous la baseline** (−1,7) à **+45,2 k€/ferme** — et dépasse la meilleure politique
transférée, Profit, aux deux échelles.

Le mix d'actions diffère de celui de la version transférée : 41 % d'AWD et 52 % de premium sur
carte simplifiée, 49 % et 62 % sur carte complète. La politique réentraînée exploite la carte,
elle ne rejoue pas un réglage appris ailleurs.

### La contrepartie : moins robuste à l'échelle

| politique | 10 fermes | carte complète | conservé |
|---|---|---|---|
| Profit (DT old) | 46,2 | 45,0 (748) | **97 %** |
| Profit (DT) | 27,5 | 26,6 (992) | **97 %** |
| **Bal-20k @DT** | 36,6 | 27,6 (992) | **75 %** |
| Bal-200k v2 (DT old) | 12,9 | 4,9 (748) | 38 % |

Le réentraînement sur place donne une politique meilleure mais **plus sensible à l'échelle**.
Son avance sur Profit fond presque entièrement à pleine échelle : +21,0 contre +20,0, soit
1 k€/ferme.

**Sur ce dernier point je ne conclus pas.** Les cartes complètes n'ont qu'un épisode, et
1 k€/ferme est précisément l'ordre de grandeur que ce protocole ne distingue pas du bruit.
L'écart sur carte simplifiée (+45,2 contre +36,1, mesuré sur 3 épisodes) est lui bien réel.

## 3. Pollution

| carte | Bal-20k @DT | Bal-20k transférée | Profit | baseline MaxProfit |
|---|---|---|---|---|
| DT simplifiée | 0,0056 | **0,0034** | 0,0066 | 0,0086 |
| DT complète | 0,0071 | **0,0058** | 0,0095 | 0,0113 |

La politique réentraînée pollue **moins que Profit** mais **plus que la version transférée**,
aux deux échelles. Cohérent avec le reste : elle a gagné en profit sans que la récompense λ=20k
lui fasse pour autant minimiser la pollution — l'observation déjà établie sur quatre cartes,
à savoir que cet axe ne répond pas au levier IPM, reste valable ici.

## 3 bis. Profit et Pollution réentraînés sur Dong Thap

Deux contrôles supplémentaires, mêmes hyperparamètres que leurs homologues du sweep, graine 0,
seule la province change.

### Profit @DT — le gain du réentraînement ne survit pas à l'échelle

| Profit | 10 fermes | 992 fermes | conservé |
|---|---|---|---|
| transférée | 27,5 → +36,1 | **26,6 → +20,0** | 97 % |
| **@DT (réentraînée)** | **37,4 → +45,9** | **26,1 → +19,5** | **70 %** |

Sur carte simplifiée, le réentraînement rapporte **+9,9 k€/ferme**. Sur la carte de
déploiement, il rapporte **−0,5 k€** — rien, et même marginalement moins que le transfert.

À 992 fermes, les trois meilleures politiques tiennent dans 1,5 k€/ferme (Bal-20k @DT +21,0 ;
Profit transférée +20,0 ; Profit @DT +19,5), soit moins que ce qu'un seul épisode permet de
distinguer.

Sur carte simplifiée en revanche, rapportée à la baseline de chaque carte, Profit @DT (+45,9)
fait **mieux que Profit sur sa propre carte d'origine** (+41,4) : la perte de ~40 % constatée
en transfert était bien un coût de transfert, pas un plafond de la nouvelle province.

### Pollution @DT — la récompense est mal posée, transfert hors de cause

| échelle | profit/ferme | pollution | IPM |
|---|---|---|---|
| 10 fermes | −13,1 → **−4,6** | 0,0084 (avant-dernière) | 20 % |
| 992 fermes | −27,2 → **−33,8** | 0,0109 (avant-dernière) | **0 %** |

Entraînée directement sur la carte, sans aucun transfert en jeu, elle reste **sous la baseline
sans IA** et n'obtient la pollution la plus basse à aucune échelle. Battue par Bal-20k (0,0058),
par la baseline 100 % IPM (0,0090) et par Profit (0,0095), qui ne vise pourtant pas cet
objectif.

Le détail décisif : elle passe de **20 % d'IPM à 10 fermes à 0 % à 992**. La politique
entraînée à minimiser la pollution **abandonne le seul levier censé la réduire**. Ce n'est pas
un échec d'apprentissage mais son contraire : elle a correctement appris que, dans ce modèle,
pulvériser moins ne réduit pas la pollution mesurée — la boucle pollution → pression ravageur →
nouveaux épandages annule le bénéfice — et elle a réaffecté ses actions ailleurs (94 % d'AWD,
21 % de durable, 0 % de premium).

## 4. Ce qu'on peut en conclure

1. **La graine doit être traitée comme une variable expérimentale**, pas comme un détail :
   elle déplace le résultat d'un facteur 4 en évaluation.
2. **λ=200k reste inutilisable à l'échelle réelle**, cette fois établi sur deux graines.
3. **Le réentraînement sur place gagne sur petite carte et ne gagne plus à l'échelle réelle.**
   +9,9 k€/ferme sur 10 fermes pour Profit, −0,5 k€ sur 992. Le gain mesuré sur carte
   simplifiée ne préjuge pas du gain en déploiement. *(Cette conclusion corrige une version
   antérieure de ce rapport, qui recommandait le réentraînement sur la seule foi des cartes
   simplifiées — les seules disponibles alors.)*
4. **Les politiques transférées passent mieux à l'échelle que celles entraînées sur place** :
   97 % et 97 % pour Profit transférée sur deux provinces, contre 75 % (Bal-20k @DT), 70 %
   (Profit @DT) et 38 % (Bal-200k v2). Systématique sur quatre mesures.
   L'explication la plus économique serait un surajustement à la configuration des dix fermes
   d'entraînement — en particulier aux dynamiques de saturation du marché premium, très
   différentes à 10 et à 992 — alors qu'une politique venue d'ailleurs n'a pas pu s'y ajuster.
   **Hypothèse non testée** : cohérente avec les quatre points, pas établie par eux.
5. **L'objectif pollution est inexploitable en l'état**, désormais établi sur quatre cartes,
   deux provinces, deux échelles, en transfert **comme en entraînement direct**.

## 5. Limites

- **1 épisode sur les cartes complètes**, 3 sur les simplifiées. Aucune barre d'erreur là où
  les écarts sont les plus serrés.
- **Baselines non rejouées** : celles du rapport de transfert sont réutilisées. Elles sont
  déterministes côté politique, mais la stochasticité interne de GAMA n'est pas
  re-échantillonnée.
- **n = 2 graines sur un seul λ**, et **un seul réentraînement sur la nouvelle province**.
- Checkpoint **final** retenu pour les deux modèles, comme pour les autres politiques
  balanced. Pour `Bal-200k v2` ce choix pèse : son `best_` (ép. 374) est le maximum d'une
  courbe encore montante et l'aurait flatté.

## 6. Fichiers

`eval_condition_v2_dtold_simple.xlsx`, `eval_condition_v2_dtold_full.xlsx`,
`eval_condition_dtnew20k_simple.xlsx`, `eval_condition_dtnew20k_full.xlsx`
(feuilles `condition`, `legende`, `comparaison`, `synthese_fermiers`, `detail`).

Séparés des quatre classeurs du rapport de transfert : ces deux runs sont des contrôles hors
sweep, et les mélanger réunirait des runs qui répondent à des questions différentes.

```bash
py eval_conditions.py --province "Dong Thap old" --simple --port 1001 \
   --tag v2_dtold_simple --episodes 3 --no-baselines --only "Bal-200k v2"
py eval_conditions.py --province "Dong Thap" --full --port 1002 \
   --tag dtnew20k_full --episodes 1 --no-baselines --only "Bal-20k @DT"
```
