# Normes de code - VepIndustries Market

Règles de jugement, appliquées en revue. Les règles mécaniques vivent dans les vérifications (`tests/run.cjs`, CI).

## Calcul dans Market, affichage dans UI

Tout calcul sur les données (moyennes, ramenés à un jour, fiabilité, seuils, filtrage par Fenêtre) vit dans `src/Market.lua` ou `src/Trend.lua` et sort par `Market.Report`, où les tests le vérifient. `src/UI.lua` lit `Market.Report` et le dessine : positions, tailles, couleurs, mise en forme des nombres. Une décision prise dans `UI.lua` à partir de champs bruts du rapport (`estimatedSales`, `seconds`, `confidence`...) est un calcul à déplacer dans `Market`.

## Formats lus par une autre version

Dans une guilde, plusieurs versions de l'addon se côtoient : le zip passe de main en main et rien ne le met à jour tout seul. Un message d'addon (`src/Exchange.lua`) et le fichier de données (`Data.lua`, le même pour toutes les versions) n'ajoutent un champ qu'à la fin, et leur lecteur ignore ceux qui suivent les siens : un motif ancré par `$` sur un message est à revoir.

## Constantes de l'interface

Chaque couleur et chaque dimension de l'interface a une seule définition (`COLOR`, `PRICE`, `STOCK`, `SALES`, `W`, `H`, `SPAN`...), réutilisée par les textures, les textes et les codes `|cff` (via `hex` ; `tests/run.cjs` refuse ceux écrits en dur dans `src/UI.lua`). Les tests qui reconnaissent un élément à sa couleur le disent dans un commentaire qui nomme la constante.
