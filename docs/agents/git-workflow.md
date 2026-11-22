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
gh pr create --base develop --title "feat(market): add estimated sales" --body-file pr.md   # corps : Closes #12
```

Sujets de commit et titres de PR : `type(scope): sujet` en anglais, 72 caractères au plus. GitHub fusionne une PR de plusieurs commits sous son titre, qui devient donc le sujet du commit sur `develop`. `scripts/commit-subject.mjs` le vérifie, au commit par le hook `.githooks/commit-msg` et sur la PR par `.github/workflows/pr-title.yml`.

`npm run release` refuse de tourner hors de `main` ou avec un arbre git sale.

Branches fusionnées : GitHub supprime la branche distante à la fusion de la PR, et le hook `.githooks/post-merge` (branché par `npm install`) supprime au `git pull` suivant les branches locales dont la branche distante a disparu.
