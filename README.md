# VepIndustries Market

Addon WoW Forever (interface 16001) par VepIndustries : tendance prix/stock des objets de l'hôtel des ventes, à partir de l'historique d'Auctionator.
Chaque Scan complet d'Auctionator (mode replicate) est enregistré en forme compacte (dernier scan + résumé par objet et par jour, ~1 Mo).

- Infobulle : conseil de prix et de délai estimé, puis `≈ N/jour` et valeur estimée vendue par jour sur le marché ; tendance prix/stock à défaut de mesures suffisantes. Les montants utilisent les icônes de pièces du jeu. Les estimations ne sont pas des garanties de vente.
- Nouveautés de la version : `CHANGELOG-PUBLIC.md` (joueurs) et `CHANGELOG.md` (technique).
- `/vim` : fenêtre graphique 21 jours (Prix minimum en ligne ; Stock et Ventes estimées par jour en barres, grisées tant qu'elles ne sont pas fiables). `/vim item <lien>`, `/vim unpin`, `/vim tooltip`, `/vim status` (dernier Scan complet), `/vim relire` (développement : réenregistre le dernier Scan complet gardé en mémoire par le client, sans attendre les 15 min du serveur ; la mémoire est perdue à chaque `/reload`), `/vim echange [Prénom-Nom]` (développement : chuchote nos Comparaisons par le vrai canal des addons, à soi-même par défaut, et dit si chacune revient intacte ; vers un joueur hors ligne, vérifie que « No player named » reste masqué).

## Script de synchro

`src/Sync.ps1` (Windows PowerShell 5.1) envoie au VPS les Comparaisons de la sauvegarde et écrit le fichier de données de l'addon, `Data.lua`, dans l'addon `VepIndustriesMarket_Data`, chargé à la demande à la première ouverture de l'hôtel des ventes de la session : un fichier écrit jeu ouvert y est donc lu. L'addon s'appuie alors sur le Résumé journalier fusionné du fichier et y ajoute ses Comparaisons que le fichier ne compte pas encore ; il signale dans la discussion un fichier qui a plus de 3 jours de retard sur son dernier Scan complet (Script de synchro arrêté). Les jours postérieurs au fichier viennent de son propre Résumé journalier. Le zip d'une nouvelle version ne contient pas `Data.lua` : extrait par-dessus l'ancienne, il le garde. Un double-clic sur `installer.cmd`, dans le dossier de l'addon, demande le code d'invitation (créé par Boris : `POST /v1/sync-codes`) et crée la tâche planifiée `VepIndustriesMarket`, sans droits d'administrateur. Le code n'est redemandé que s'il est refusé.

- Toutes les 15 minutes de la session Windows, sans fenêtre (`conhost --headless`) : rien à faire si aucune sauvegarde n'est plus récente que `Data.lua` ; sinon envoi des Comparaisons pas encore envoyées, par lots de 5, puis `Data.lua` de l'hôtel des ventes du dernier Scan complet.
- La tâche se retire si le dossier de l'addon a disparu, ou après 30 jours sans nouvelle sauvegarde.
- État dans `%LOCALAPPDATA%\VepIndustriesMarket` : `config.json` (adresse de l'API, code chiffré pour l'utilisateur Windows), `sent.txt` (Comparaisons envoyées), `sync.log` (un passage par ligne, erreurs comprises).
- Staging : `npm run staging [-- -Seed]` (`tools/staging.ps1`) installe le Script de synchro sur le staging avec un Code de synchro créé par le jeton d'administrateur du presse-papiers, envoie au besoin la Comparaison réelle de `merge-cases.json`, puis écrit `Data.lua`. Retour en production : `installer.cmd` sans `-Api`.
- Test : `tests/sync.cjs` (dans `npm test`, Windows seulement) installe une vraie tâche `VepIndustriesMarketTest` contre un faux serveur, puis la retire.

**Repli si un antivirus bloque le script** : réécrire `Sync.ps1` en un petit exécutable (C# ou Go, sous-système Windows pour n'ouvrir aucune fenêtre) qui fait la même chose (mêmes fichiers, même API, même état). `installer.cmd` crée alors la tâche sur l'exécutable au lieu de `conhost`, et Boris signe l'exécutable ou le soumet à l'analyse de Microsoft (faux positif Defender) avant de le publier. Il ne télécharge toujours aucun code.

## Échange en jeu

Les membres de la guilde connectés qui ont l'addon s'échangent leurs Comparaisons sans `/reload`, avec ou sans Script de synchro (`src/Exchange.lua`, protocole en tête du fichier) : chacun s'annonce sur le canal de guilde à la connexion et après chaque nouvelle Comparaison, puis les autres lui envoient en chuchotement celles qui lui manquent et qui sont postérieures à son fichier de données. Une Comparaison reçue est gardée comme les nôtres (envoyée au VPS par le Script de synchro, retransmise aux membres connectés ensuite). Les envois passent par ChatThrottleLib (`src/Libs`, domaine public), à ~800 octets/s hors instance et un message par seconde en instance ; un refus pour débit ou un blocage pendant un combat les retarde sans rien perdre, et un transfert interrompu reprend au morceau atteint, tant que le destinataire n'a pas relancé le jeu. `npm run report` donne les Comparaisons gardées par auteur. L'annonce porte aussi la version de l'addon : qui entend une version publiée plus récente que la sienne (pas une version de développement) en est averti une fois dans la discussion.

## Diffusion

Le dépôt est privé et l'addon n'est sur aucun gestionnaire d'addons : Boris envoie lui-même le zip de `npm run release` (`dist/VepIndustriesMarket-x.y.z.zip`) à ses amis.

- Première installation : extraire le zip dans `World of Warcraft\_forever_\Interface\AddOns`, de façon que les deux dossiers `VepIndustriesMarket` et `VepIndustriesMarket_Data` soient directement dans `AddOns` (« Extraire tout » de Windows propose un sous-dossier `VepIndustriesMarket-x.y.z` : le retirer du chemin, sinon le jeu ne voit pas l'addon), double-cliquer sur `AddOns\VepIndustriesMarket\installer.cmd` et y saisir le code d'invitation donné par Boris, puis lancer le jeu.
- Nouvelle version : l'addon la signale en jeu dès qu'un membre de la guilde connecté l'a. Extraire le nouveau zip au même endroit, en remplaçant les fichiers existants ; il sert au lancement suivant du jeu. `Data.lua` et la tâche planifiée restent en place : rien à réinstaller.

## Développement

```bash
npm install
npm test          # logique + smoke test UI (Fengari + doublures de l'API WoW)
npm run deploy    # tests -> copie dans AddOns/VepIndustriesMarket et AddOns/VepIndustriesMarket_Data (version x.y.z-dev+sha, Data.lua gardé)
npm run release   # sur main uniquement : idem + zip dans dist/ (à envoyer aux amis) + tag git vX.Y.Z
```

Dossier du jeu : variable `WOW_ADDONS`, par défaut `C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns`.

Les tests ne prouvent pas le rendu en jeu : vérifier avec `/reload` après chaque deploy.

## Structure

- `src/` : l'addon tel qu'il est copié dans le jeu (`@version@` remplacé dans le `.toc`) ; `src/VepIndustriesMarket_Data/` devient un addon à côté de lui, dont le Script de synchro écrit le `Data.lua`
- `tests/` : `doubles.lua` (doublures de l'API WoW), un fichier `*.test.lua` par module (marché, interface, branchement sur Auctionator, échange), chacun joué dans un état Lua neuf (`node tests/run.cjs exchange.test.lua` n'en joue qu'un), `merge-cases.json` (cas de la fusion par Tranche, partagés avec le serveur ; `npm run merge-case` réécrit le cas réel après un changement de la règle), `fixtures/realdata.lua` (historique Auctionator réel exporté), `fixtures/fullscan.lua` (un objet sur dix du Scan complet réel du 21/11), `fixtures/fullscan-<MMJJ>-<HHMM>.lua` (les mêmes objets dans des Scans complets plus récents, nommés par leur date et heure, extraits des SavedVariables et de leur `.bak` par `npm run fixture`), `fixtures/comparisons.lua` (les Comparaisons d'une vraie sauvegarde, telles que le jeu les écrit, réduites aux mêmes objets, extraites une fois par `npm run fixture` et relues par `sync.cjs` ; l'addon les retire au bout de 24 h : `npm run report` signale une sauvegarde qui en contient tant que le fichier manque)
- `scripts/saved.mjs` : `npm run fixture`, et `npm run report` (ce que l'addon a enregistré depuis la sauvegarde précédente, et le fichier de données chargé)
- `scripts/build.mjs` : deploy / release

Git : gitflow, voir `docs/agents/git-workflow.md`.
