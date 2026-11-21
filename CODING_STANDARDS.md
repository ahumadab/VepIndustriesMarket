# Normes de code - VepIndustries Market

Règles de jugement, appliquées en revue. Les règles mécaniques vivent dans les vérifications (`tests/run.cjs`, CI).

## Calcul dans Market, affichage dans UI

Tout calcul sur les données (moyennes, ramenés à un jour, fiabilité, seuils, filtrage par Fenêtre) vit dans `src/Market.lua` ou `src/Trend.lua` et sort par `Market.Report`, où les tests le vérifient. `src/UI.lua` lit `Market.Report` et le dessine : positions, tailles, couleurs, mise en forme des nombres. Une décision prise dans `UI.lua` à partir de champs bruts du rapport (`estimatedSales`, `seconds`, `confidence`...) est un calcul à déplacer dans `Market`.

## Constantes de l'interface

Chaque couleur et chaque dimension de l'interface a une seule définition (`COLOR`, `PRICE`, `STOCK`, `SALES`, `W`, `H`, `SPAN`...), réutilisée par les textures, les textes et les codes `|cff` (via `hex`). Les tests qui reconnaissent un élément à sa couleur le disent dans un commentaire qui nomme la constante.
