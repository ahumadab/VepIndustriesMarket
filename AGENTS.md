# AGENTS.md - VepIndustries Market

Addon World of Warcraft (serveur WoW Forever, interface 16001, API moderne `C_AuctionHouse`) par VepIndustries. Voir `README.md`.

## Règles

- `src/` est la seule source. Ne jamais éditer `AddOns/VepIndustriesMarket` dans le dossier du jeu : passer par `npm run deploy`.
- `npm test` doit passer avant tout deploy (le script le garantit). Les tests (Fengari + doublures de l'API WoW) ne prouvent pas le rendu en jeu : faire valider par Boris avec `/reload`.
- Lua du jeu : 5.1, Fengari : 5.3. Arrondir avant `%d`/`%x` dans `string.format`.
- Textes visibles en jeu : français avec accents. Code et commentaires : anglais.
- Forever est `WOW_PROJECT_CAMELOT`, traité comme mainline par Auctionator (branche `Source_ModernAH`). Vérifier dans le code installé d'un addon avant de s'appuyer sur une API ou un guide retail/classic.
- Les scans complets viennent d'Auctionator en mode replicate + autoscan (option Advanced « Use alternate slower scan mode by default » = `replicate_scan_3`). Le scan incrémental ne donne pas le détail par palier.

## Agent skills

### Issue tracker

Les tickets vivent dans les GitHub Issues de `ahumadab/VepIndustriesMarket` (CLI `gh`). See `docs/agents/issue-tracker.md`.

### Triage labels

Étiquettes par défaut : `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context : `GLOSSARY.md` + `docs/adr/` à la racine. See `docs/agents/domain.md`.
