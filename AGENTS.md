# AGENTS.md - VepIndustries Market

Addon World of Warcraft (serveur WoW Forever, interface 16001, API moderne `C_AuctionHouse`) par VepIndustries. Voir `README.md`.

## Règles

- `src/` est la seule source. Ne jamais éditer `AddOns/VepIndustriesMarket` dans le dossier du jeu : passer par `npm run deploy`.
- `npm test` doit passer avant tout deploy (le script le garantit). Les tests (Fengari + doublures de l'API WoW) ne prouvent pas le rendu en jeu : faire valider par Boris avec `/reload`.
- Les données réelles déjà enregistrées servent de banc d'essai : la logique se teste sur `tests/fixtures/` (historique Auctionator, deux Scans complets réels ; `npm run fixture` y ajoute le dernier scan des SavedVariables), et la validation en jeu porte sur le rendu, juste après `/reload`, avec les données déjà sauvegardées. Un nouveau Scan complet ne se demande que pour une donnée qu'aucune sauvegarde ne contient encore, une seule fois, puis elle devient une fixture.
- Lua du jeu : 5.1, Fengari : 5.3. Arrondir avant `%d`/`%x` dans `string.format`.
- Textes visibles en jeu : français avec accents. Code et commentaires : anglais.
- État de l'addon en jeu (`VepIndustriesMarketDB`, dont `errors`) : `<jeu>/WTF/Account/<compte>/SavedVariables/VepIndustriesMarket.lua`, réécrit à chaque `/reload` ou déconnexion. Le relire après la validation de Boris.
- Forever est `WOW_PROJECT_CAMELOT`, traité comme mainline par Auctionator (branche `Source_ModernAH`). Vérifier dans le code installé d'un addon avant de s'appuyer sur une API ou un guide retail/classic.
- Les Scans complets viennent d'Auctionator en mode replicate avec autoscan : `replicate_scan_3` (Advanced, « Use alternate slower scan mode by default ») et `autoscan_2` (« Run autoscan when Auction House is opened ») à `true` dans `SavedVariables/Auctionator.lua`, où `AUCTIONATOR_CHARACTER_CONFIG` du personnage prime s'il n'est pas `nil`. Les vérifier avant de demander une validation en jeu. Le serveur limite à un scan par 15 min ; `/vim relire` réenregistre celui que le client garde en mémoire, perdu à chaque `/reload`. Le scan incrémental ne donne pas le détail par Palier.

## Agent skills

### Git workflow

Gitflow : `main` (versions taguées), `develop` (intégration, par défaut), `feature/<n>-<slug>` par ticket, `release/X.Y.Z`, `hotfix/X.Y.Z`. See `docs/agents/git-workflow.md`.

### Issue tracker

Les tickets vivent dans les GitHub Issues de `ahumadab/VepIndustriesMarket` (CLI `gh`). Lire un ticket : `gh issue view <n> --json title,body,labels,comments`. See `docs/agents/issue-tracker.md`.

### Triage labels

Étiquettes par défaut : `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context : `GLOSSARY.md` + `docs/adr/` à la racine. See `docs/agents/domain.md`.
