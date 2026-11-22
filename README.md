# VepIndustries Market

Addon WoW Forever (interface 16001) par VepIndustries : tendance prix/stock des objets de l'hôtel des ventes, à partir de l'historique d'Auctionator.
Chaque Scan complet d'Auctionator (mode replicate) est enregistré en forme compacte (dernier scan + résumé par objet et par jour, ~1 Mo).

- Infobulle : `Tendance 7 j  Demande | Stable | Saturé  prix ±x %  stock ±y %  (n j)  ≈ N/jour` (ventes estimées sur 7 jours entre Scans complets à moins de 2 h d'écart, grisées tant qu'elles ne portent pas sur 2 jours, soit au moins 3 Scans complets)
- `/vim` : fenêtre graphique 21 jours (Prix minimum en ligne ; Stock et Ventes estimées par jour en barres, grisées tant qu'elles ne sont pas fiables). `/vim item <lien>`, `/vim unpin`, `/vim tooltip`, `/vim status` (dernier Scan complet), `/vim relire` (développement : réenregistre le dernier Scan complet gardé en mémoire par le client, sans attendre les 15 min du serveur ; la mémoire est perdue à chaque `/reload`).

## Script de synchro

`src/Sync.ps1` (Windows PowerShell 5.1) envoie au VPS les Comparaisons de la sauvegarde et écrit le fichier de données de l'addon, `Data.lua`. Un double-clic sur `installer.cmd`, dans le dossier de l'addon, demande le code d'invitation (créé par Boris : `POST /v1/sync-codes`) et crée la tâche planifiée `VepIndustriesMarket`, sans droits d'administrateur. Le code n'est redemandé que s'il est refusé.

- Toutes les 15 minutes de la session Windows, sans fenêtre (`conhost --headless`) : rien à faire si aucune sauvegarde n'est plus récente que `Data.lua` ; sinon envoi des Comparaisons pas encore envoyées, par lots de 5, puis `Data.lua` de l'hôtel des ventes du dernier Scan complet.
- La tâche se retire si le dossier de l'addon a disparu, ou après 30 jours sans nouvelle sauvegarde.
- État dans `%LOCALAPPDATA%\VepIndustriesMarket` : `config.json` (adresse de l'API, code chiffré pour l'utilisateur Windows), `sent.txt` (Comparaisons envoyées), `sync.log` (un passage par ligne, erreurs comprises).
- Staging : `installer.cmd -Api https://api-staging.vepindustries.com` depuis une console.
- Test : `tests/sync.cjs` (dans `npm test`, Windows seulement) installe une vraie tâche `VepIndustriesMarketTest` contre un faux serveur, puis la retire.

**Repli si un antivirus bloque le script** : réécrire `Sync.ps1` en un petit exécutable (C# ou Go, sous-système Windows pour n'ouvrir aucune fenêtre) qui fait la même chose (mêmes fichiers, même API, même état). `installer.cmd` crée alors la tâche sur l'exécutable au lieu de `conhost`, et Boris signe l'exécutable ou le soumet à l'analyse de Microsoft (faux positif Defender) avant de le publier. Il ne télécharge toujours aucun code.

## Développement

```bash
npm install
npm test          # logique + smoke test UI (Fengari + doublures de l'API WoW)
npm run deploy    # tests -> copie dans AddOns/VepIndustriesMarket (version x.y.z-dev+sha)
npm run release   # sur main uniquement : idem + zip dans dist/ + tag git vX.Y.Z
```

Dossier du jeu : variable `WOW_ADDONS`, par défaut `C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns`.

Les tests ne prouvent pas le rendu en jeu : vérifier avec `/reload` après chaque deploy.

## Structure

- `src/` : l'addon tel qu'il est copié dans le jeu (`@version@` remplacé dans le `.toc`)
- `tests/` : `test.lua`, `merge-cases.json` (cas de la fusion par Tranche, partagés avec le serveur ; `npm run merge-case` réécrit le cas réel après un changement de la règle), `fixtures/realdata.lua` (historique Auctionator réel exporté), `fixtures/fullscan.lua` (un objet sur dix du Scan complet réel du 21/11), `fixtures/fullscan-<MMJJ>-<HHMM>.lua` (les mêmes objets dans des Scans complets plus récents, nommés par leur date et heure, extraits des SavedVariables et de leur `.bak` par `npm run fixture`)
- `scripts/saved.mjs` : `npm run fixture`, et `npm run report` (ce que l'addon a enregistré depuis la sauvegarde précédente)
- `scripts/build.mjs` : deploy / release

Git : gitflow, voir `docs/agents/git-workflow.md`.
