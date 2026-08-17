# Rapport complet : objectifs de récompense, greedy vs stochastique, deux échelles

*Projet Starfarm, apprentissage par renforcement multi-agents. Juillet 2026*

## Protocole

Six politiques (même pipeline MAPPO, seul l'objectif de récompense change) sont évaluées dans
**quatre conditions** croisées :

- **Échelle** : simulation *simple* (10 fermes) et *réelle* (748 fermes, sans réentraînement).
- **Décision** : *greedy* (action déterministe = moyenne de la gaussienne) et *stochastique*
  (action échantillonnée dans la distribution de la politique).

Le modèle **pollution a été ré-entraîné** (lr abaissé à 1e-4) ; ses résultats remplacent
partout l'ancien run dégénéré. En stochastique 10 fermes, 3 épisodes sont moyennés (moy ±
écart-type) ; les autres conditions sont à 1 épisode (voir Réserves). La récompense d'éval est
toujours le **profit global réel** et la **pollution moyenne**, quel que soit le mode entraîné.
Données détaillées dans `eval_objectives_comparison_*.xlsx`.

## Résultats consolidés

![Frontières profit / pollution, 4 conditions](../synthesis_pareto.png)

Profit global (sur 25 ans) et pollution moyenne, par condition :

| Politique | Simple greedy | Simple stoch. | Réel greedy | Réel stoch. |
|---|---|---|---|---|
| Profit | 485 k / 0,0357 | 472 k / 0,0348 | **35,2 M** / 0,0420 | 18,1 M / 0,0406 |
| Bal-20k | 479 k / 0,0351 | 464 k / 0,0333 | 30,1 M / 0,0471 | 29,6 M / 0,0469 |
| Bal-100k | 373 k / 0,0200 | 379 k / 0,0207 | 27,3 M / 0,0326 | 22,9 M / 0,0316 |
| Bal-200k | 320 k / 0,0312 | 276 k / 0,0221 | 17,9 M / 0,0281 | 19,4 M / 0,0280 |
| Bal-400k | 63 k / 0,0268 | 150 k / 0,0207 | 8,8 M / **0,0181** | 14,4 M / 0,0191 |
| Pollution | 266 k / 0,0332 | 255 k / 0,0341 | 16,0 M / 0,0465 | 2,3 M / 0,0263 |

## Enseignement 1 : greedy et stochastique se comportent très différemment à grande échelle

À **10 fermes**, greedy et stochastique sont quasi identiques pour les politiques rentables
(écart de profit −2 à −3 %, faible variance) : les conclusions greedy des rapports précédents
sont robustes à cette échelle.

À **748 fermes**, l'écart explose et il est **asymétrique** :

- Les politiques à fort premium **perdent** en stochastique : Profit **35,2 M -> 18,1 M
  (−49 %)**, Bal-100k 27,3 -> 22,9 M (−16 %). Le bruit d'échantillonnage casse la coordination
  premium collective (beaucoup de fermes basculent aléatoirement leur choix binaire).
- Les politiques contraintes / vertes **gagnent** en stochastique : Bal-400k **8,8 -> 14,4 M
  (+64 %)**, Bal-200k 17,9 -> 19,4 M (+9 %). L'échantillonnage les sort d'un **mode
  déterministe médiocre** (même mécanisme de diversification de type jeu de minorité déjà
  observé).

**Conséquence pratique** : en déploiement on joue la politique **greedy** (déterministe). Les
chiffres *réel greedy* sont donc la performance réelle attendue ; le stochastique est surtout
un diagnostic de la largeur de la distribution de la politique.

## Enseignement 2 : la frontière de Pareto tient à grande échelle (greedy)

En *réel greedy*, la hiérarchie λ est propre et monotone : Bal-100k (0,0326, 27,3 M) ->
Bal-200k (0,0281, 17,9 M) -> Bal-400k (**0,0181**, 8,8 M). Le curseur λ trace bien le compromis
profit / pollution. **Recommandations de déploiement** :

- **Bal-100k** : scénario « raisonné » (77 % du profit de Profit, −22 % de pollution).
- **Bal-400k** : scénario « priorité environnement » (−57 % de pollution, 25 % du profit).

## Enseignement 3 : le modèle pollution ré-entraîné reste le mauvais choix

Le ré-entraînement a **corrigé l'optimum dégénéré** vu auparavant : à 10 fermes, mix diversifié
(IPM 44 %, durable 43 %, AWD 15 %), profit multiplié par ~6, et pollution (0,0332) enfin
**sous** celle de Profit. Mais :

- il **ne bat toujours pas les Balanced** sur son propre objectif (0,0332 contre 0,0200 pour
  Bal-100k à 10 fermes) ;
- il **transfère mal** : en *réel greedy*, sa pollution (0,0465) est **pire que Profit**
  (0,0420) ; sa version stochastique atteint 0,0263 mais au prix d'un effondrement du profit
  (2,3 M, soit ~8 % de Bal-20k) et d'une variance élevée.

Autrement dit, la politique pollution-seule est **instable et non transférable**, dominée par
les Balanced dans toutes les conditions de déploiement.

## Pourquoi l'objectif « pollution seule » échoue (hypothèses)

La pollution n'est **ajoutée** que par les pulvérisations de pesticide, puis décroît (×0,9/jour)
et **diffuse** vers les cellules voisines ; une boucle pollution -> pression ravageur ->
pulvérisation existe. D'où :

1. **Signal trop plat** : `récompense = −pollution` (~0,03, faible variance entre actions) ->
   gradient faible, exploration effondrée, optimum local médiocre. Le terme de profit du
   Balanced fournit un gradient riche qui découvre incidemment les régimes peu polluants
   (reward shaping).
2. **État retardé et diffusé** : la pollution d'une ferme dépend de ses sprays passés *et* de
   l'import des voisins -> attribution de crédit difficile pour une récompense par fermier.
3. **Externalité collective** : réduire *sa* pollution profite surtout aux voisins (diffusion),
   ce qui plafonne le gradient d'une récompense purement individuelle.
4. **Piège de la boucle ravageur** : sans incitation à garder l'agro-système sain, la politique
   le laisse dériver vers un régime haute-pression / haute-pulvérisation. Le profit maintient au
   contraire le système sain, donc peu polluant. Ceci explique que la pollution-seule ait *plus*
   d'IPM mais *plus* de pollution.
5. **Diffusion dominante à l'échelle** : à 748 fermes la grille est fine (voisinage dense) ->
   l'import de pollution voisine domine, ce qui explique la dégradation spécifique au passage
   à l'échelle.

Fil conducteur : le profit agit comme **guide d'exploration** qui maintient un régime sain où
la pollution est basse ; l'objectif mono-critère retire ce guide. Conclusion : ne jamais
utiliser l'objectif pollution seul, préférer un Balanced à λ élevé.

## Réserves

- **Un seul épisode** en *réel* (les deux échelles/modes sauf simple stochastique, à 3
  épisodes) : les points *réels* sont indicatifs, la variance n'y est pas quantifiée. Les
  écarts fins (ex. Bal-200k vs Bal-100k) sont à confirmer.
- Le *réel greedy* des 5 politiques inchangées provient du run précédent (mêmes modèles),
  fusionné avec le point pollution ré-entraîné mesuré séparément.
- L'écart greedy/stochastique est en partie gouverné par `log_std` (indépendant de l'état) :
  une politique à `log_std` élevé diverge davantage sous échantillonnage.
- Limite modèle (à remonter) : la pollution ne dépend que des pesticides ; ni l'irrigation
  (AWD, méthane) ni la fertilisation (ruissellement azote) n'y contribuent.
