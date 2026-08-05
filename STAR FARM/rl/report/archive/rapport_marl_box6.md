# Rapport 2 — Expansion de l'espace d'action : cultivar + nombre de saisons

*Suite du premier rapport. On ajoute deux leviers de décision et on mesure l'effet sur le revenu.*

---

## 1. Contexte

Le premier rapport établissait un pipeline MARL fonctionnel avec une action `Box(4)` (irrigation, quantité d'irrigation, pesticide, fertilisation). Conclusion : l'optimum était une politique **quasi-constante** (BAU intensif) — il n'y avait presque rien à apprendre, et l'entraînement dérivait.

Hypothèse de cette étape : **ajouter des leviers à fort impact** pourrait (a) rendre le problème réellement *apprenable*, et (b) révéler de meilleures stratégies. On ajoute les deux fonctions de changement de pratique du collègue restées inutilisées :

- **`change_rice_cultivar`** — riz **standard (OM5451)** vs **premium (ST25)** ;
- **`change_number_seasons`** — calendrier **2 vs 3 saisons**.

---

## 2. Changements

### 2.1 Espace d'action — `Box(4)` → `Box(6)`

| dim | levier | décodage (seuil 0.5) |
|-----|--------|----------------------|
| `a[0]` | irrigation | CF / AWD |
| `a[1]` | quantité irrigation | profondeur CF / seuil AWD |
| `a[2]` | pesticide | BAU / IPM |
| `a[3]` | fertilisation | BAU / durable |
| **`a[4]`** | **cultivar** | **standard / premium (ST25)** |
| **`a[5]`** | **saisons** | **2 / 3 saisons** |

Observation : `Box(9)` → **`Box(11)`** (4 état + **6** action + 1 indice d'année).

### 2.2 Conséquence technique : la durée d'année devient dépendante des actions

Le cultivar (temps thermique de maturité différent) et le nombre de saisons changent la **date de récolte**, donc la **durée de l'année RL** (jusqu'à ce que tous les fermiers aient fini leurs saisons). Observé : de ~360 jours (tout-3-saisons) à **485–579 jours** quand des fermiers passent en 2 saisons / premium.

Le macro-pas Python a été rendu **robuste à l'overshoot** : si le grand saut groupé dépasse la frontière, l'estimation est rétractée (la récompense, elle, reste correcte car lue sur le *snapshot* de fin d'année).

> **À garder en tête :** un « épisode de 10 ans RL » peut désormais couvrir **~13–16 années calendaires** selon les choix de saisons. L'interprétation de l'horizon et du discount `γ` se décale d'autant.

---

## 3. Résultats

### 3.1 Courbe d'apprentissage — elle MONTE

![Courbe d'apprentissage Box(6)](fig_box6_learning.png)

Contrairement à Box(4) (courbe descendante), la moyenne mobile **progresse de +17 %** (304k → 355k). Les leviers cultivar/saisons ont transformé un problème quasi-dégénéré en un **vrai problème d'optimisation** : l'agent apprend.

### 3.2 Comparaison aux baselines

![Baselines Box(6)](fig_box6_baselines.png)

| politique | profit global | vs trained |
|---|---|---|
| **fixed_high** — AWD / IPM / durable / **premium** / 2 saisons | **430 668** | **+34,6 %** |
| **trained (best = final)** | **319 949** | référence |
| fixed_low — CF / BAU / BAU / standard / 3 saisons | 255 457 | −20,2 % |
| fixed_mid — CF / IPM / durable / standard / 3 saisons | 234 025 | −26,9 % |
| random | 198 311 | −38,0 % |

La politique entraînée **bat random (+61 %), fixed_low (+25 %) et fixed_mid (+37 %)** — mais reste **−26 % sous `fixed_high`**.

### 3.3 Box(4) vs Box(6)

![Box4 vs Box6](fig_box4_vs_box6.png)

L'ajout des deux leviers **relève le plafond de profit** (meilleur baseline : 284k → **431k**) et **améliore la politique apprise** (285k → 320k). L'espace plus grand fait aussi chuter l'aléatoire (263k → 198k) : il y a beaucoup plus de mauvaises combinaisons possibles.

---

## 4. Interprétation

**1. L'apprentissage devient efficace.** C'est le premier run où l'agent progresse nettement et bat la plupart des baselines de 25 à 61 %. Donner des leviers à fort impact était la bonne piste.

**2. Le cultivar premium est un game-changer.** `fixed_high` atteint **431k** — presque le double de fixed_low — porté par le **riz premium (ST25)**, qui se vend bien plus cher. Cela **renverse l'optimum** identifié dans le rapport 1 (où le BAU intensif dominait) : désormais c'est la **montée en gamme** qui paie.

**3. La politique sous-exploite ce filon (320k vs 431k).** Elle a trouvé une bonne stratégie mixte mais **n'a pas convergé** vers « tous les fermiers en premium + 2 saisons » (le cultivar premium reste minoritaire dans ses choix). Elle laisse **~110k** sur la table.

**4. Pourquoi ce plafonnement ?** L'optimum (`fixed_high`) est, là encore, un **coin quasi-constant** presque indépendant de l'état. Avec la **récompense globale partagée** (crédit dilué ÷10) et 200 épisodes sur un espace 6D plus vaste, PPO se fixe sur un **optimum local** sans engager tous les fermiers sur le premium.

---

## 5. Conclusions

1. ✅ **Ajouter cultivar + saisons a un effet majeur et positif** : l'entraînement apprend vraiment (+17 % de courbe) et bat la plupart des baselines.
2. 🔎 **Le riz premium (ST25) est la stratégie gagnante** (`fixed_high` ≈ 431k) ; elle redéfinit complètement l'optimum par rapport au BAU intensif du rapport 1.
3. ⚠️ **La politique n'en capture que ~74 %** (320k) : elle reste sous le meilleur coin constant, freinée par l'attribution de crédit (récompense partagée) et la taille de l'espace.
4. ⚠️ **Effet structurel** : le passage en 2 saisons / premium **allonge fortement la durée d'année** (jusqu'à ~580 jours), décalant l'interprétation de l'horizon.

**Pistes pour combler l'écart (~110k)** : récompense **par-agent** (meilleure attribution de crédit, l'optimum étant ~constant), **plus d'épisodes / exploration ciblée**, ou décroissance de l'entropie en fin d'entraînement.
