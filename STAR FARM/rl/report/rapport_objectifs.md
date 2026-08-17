# Trois objectifs de récompense — profit / pollution / équilibré

*Projet Starfarm — MARL · 26 juin 2026*

## Contexte

Même pipeline MAPPO per-fermier, **seul l'objectif de récompense change** :

| Politique | Récompense entraînée | Épisodes |
|---|---|---|
| **Profit** | profit propre de chaque ferme | 400 |
| **Pollution** | − pollution propre | 600 |
| **Balanced** | profit − λ·pollution (λ = 20000) | 400 |

Chaque politique est **rejouée en greedy** (25 ans, mêmes fermes, même ordre de décision)
et mesurée sur les **deux axes** : profit global et pollution moyenne. Détails par
fermier/année dans `eval_objectives_comparison.xlsx`.

## Résultats

![Comparaison des objectifs](../eval_objectives_curves.png)

| Politique | Profit global | Pollution moy. | Premium | IPM | Durable | AWD |
|---|---:|---:|---:|---:|---:|---:|
| **Profit** | **484,7 k€** | 0,0357 | 86 % | 4 % | 0 % | 0 % |
| **Pollution** | 155 k€* | **0,0285** (−20 %) | 2 % | **30 %** | 5 % | 0 % |
| **Balanced** (λ=20000) | 479,5 k€ (99 %) | 0,0351 (−2 %) | 82 % | 4 % | 4 % | 12 % |

<small>\* le profit de la politique Pollution est **incident** (elle ne l'optimise pas) et
très variable selon l'aléa — l'éval d'entraînement donnait même ~40 k€. Le chiffre robuste
pour cette politique est la **pollution**, sa vraie cible.</small>

## Lecture

- **Profit** — le levier appris est le **cultivar premium** (86 %), en intensif
  conventionnel (pas d'IPM/durable/AWD). Profit maximal (485 k€) → **pollution la plus haute**.
- **Pollution** — abandonne le premium (2 %) et adopte l'**IPM** (30 %, moins de pesticide)
  + un peu de fertilisation durable (5 %). Elle réduit la pollution de **~20 %**… mais
  **effondre le profit** (−68 % ou pire). Le **seul vrai levier anti-pollution** dans le
  modèle est l'IPM.
- **Balanced (λ=20000)** — se comporte **quasiment comme Profit** : profit à 99 %, pollution
  à peine −2 %. **λ est trop faible** pour que le terme pollution pèse.

## Constats clés

1. **La pollution est largement inélastique** aux actions disponibles : même la politique
   *100 % pollution* ne la baisse que de ~20 % (plancher ~0,0285). L'essentiel de la pollution
   est structurel (irrigation/fertilisation incompressibles) ; seul l'IPM la déplace un peu.
2. **Le compromis est défavorable** : gagner −20 % de pollution coûte plus de −68 % de profit.
   Il n'y a pas de « repas gratuit » vert dans ce modèle.
3. **λ=20000 est insuffisant.** Pour obtenir un vrai point intermédiaire (ex. −10 % pollution
   pour −15 % profit), il faut **augmenter fortement λ** (≈ 100 000–200 000) et ré-entraîner —
   sinon Balanced ≈ Profit.

## Recommandations

- **Balanced utile** = ré-entraîner avec λ nettement plus grand (balayer 100k / 200k / 400k)
  pour tracer la vraie **frontière de Pareto** profit↔pollution.
- **Côté modèle** : la faible élasticité suggère que peu de pratiques agissent sur la
  pollution (surtout l'IPM). À discuter avec le collègue — ajouter des leviers
  environnementaux ou revoir le calcul de `pollution_level` rendrait l'arbitrage plus riche.
- **Statu quo profit** reste le choix économique ; la version « verte » n'a de sens que si la
  pollution est valorisée (taxe/subvention) — ce qui reviendrait justement à choisir λ.
