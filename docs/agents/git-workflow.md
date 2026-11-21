# Git workflow : gitflow

- `main` : uniquement des versions publiées, chacune taguée `vX.Y.Z`. Jamais de commit direct.
- `develop` : branche d'intégration, branche par défaut sur GitHub.
- `feature/<n>-<slug>` : une branche par ticket GitHub `#n`, partie de `develop`, fusionnée dans `develop` par pull request (`Closes #n`).
- `release/X.Y.Z` : partie de `develop`. On y monte `version` dans `package.json`, on corrige seulement, puis PR vers `main`. Après la fusion, `npm run release` sur `main` (tag + zip), puis on refusionne `main` dans `develop`.
- `hotfix/X.Y.Z` : partie de `main` pour une correction urgente, fusionnée dans `main` et dans `develop`.

## Commandes

```bash
git switch develop && git pull
git switch -c feature/12-ventes-estimees
# ... commits ...
npm run deploy                       # test en jeu depuis n'importe quelle branche
gh pr create --base develop --fill   # corps : Closes #12
```

`npm run release` refuse de tourner hors de `main` ou avec un arbre git sale.
