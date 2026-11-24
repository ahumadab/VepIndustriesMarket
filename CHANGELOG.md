# Changelog technique — VepIndustries Market

## Unreleased

### Noms des objets — #63

- `Capture.lua` lit le nom de chaque objet dans le lien d'objet du Scan complet (`|h[Runecloth]|h`, client anglais), y compris par `/vim relire` (`C_AuctionHouse.GetReplicateItemLink`). Noms vides ou de plus de 120 caractères ignorés.
- `Market.Ingest(scan, now, realm, faction, author, names)` garde `VepIndustriesMarketDB.names = { [itemID] = nom }` pour les objets du scan, et retire un nom avec le Résumé journalier de son objet (21 jours). Taille : ~30 octets par objet, ~200 Ko pour les ~6 900 objets d'un vrai Scan complet, à côté de ~1,75 Mo de sauvegarde actuelle.
- `Sync.ps1` envoie, après les Comparaisons, les noms pas encore envoyés à `POST /v1/item-names` (en-tête `Sync-Code`, `{ names: [{ itemId, name }] }`, 500 par requête), retenus dans `%LOCALAPPDATA%\VepIndustriesMarket\names.txt` (`itemID<tab>nom`). Première erreur : arrêt des noms pour ce passage, ligne dans `sync.log`, Comparaisons et `Data.lua` inchangés, code de sortie 0 ; les noms restants repartent au passage suivant qui trouve une nouvelle sauvegarde (pas d'appel toutes les 15 min tant que la route manque en production).
- Protocole des Comparaisons, `Data.lua` et échange en jeu inchangés.

### Rapport par jour — #7

- `npm run report` affiche, pour chaque jour du Résumé journalier de la sauvegarde puis de `Data.lua` : objets comparés, durée couverte (la plus longue d'un objet), épuisés, quantiles du rapport ventes estimées par jour / stock du jour et répartition en jours de stock (< 1 j, 1-2 j, 2-4 j, 4-7 j, 7-14 j, > 14 j, aucune vente). Code dans `scripts/daily.mjs`, tests dans `tests/report.test.mjs` (ajouté à `npm test`).
- Les seuils du Verdict (`DEMAND_DAYS` = 2, `SATURATED_DAYS` = 7) ne changent pas : proposition chiffrée dans #7, à choisir avec Boris.

## 0.4.0 — 2026-11-23

Différence fonctionnelle depuis `v0.3.0`. PR intégrées : #58, #59, #60 et #61.

### Marché

- **Valeur vendue par jour — #55 / PR #58** : `Market.Report.goldPerDay`, en cuivre, égale aux ventes estimées par jour multipliées par le prix minimum du dernier scan complet. Absente si l'une des données manque. Indicateur de valeur échangée estimée, tous vendeurs confondus, pas de bénéfice individuel.
- **Temps de vente — #56 / PR #59** : `Market.Report.selling` propose trois prix : minimum moins 1 cuivre (plancher 1), minimum × 1,05 et minimum × 1,10, arrondis à l'entier inférieur. Chaque entrée contient `price`, `ahead` et `seconds`. Le délai correspond aux unités en vente à un prix inférieur ou égal au prix proposé, plus une pile de taille habituelle, divisées par le rythme des ventes estimées. La taille habituelle est celle regroupant le plus d'unités dans le dernier scan. Délai infini si aucune vente n'est mesurée ; liste absente quand les mesures sont insuffisantes.
- **Ventes malgré une baisse du minimum — #50 / PR #61** : le calcul existant est conservé. Quand le nouveau minimum est inférieur à l'ancien, un second calcul considère les disparitions jusqu'à l'ancien minimum, déduit les expirations possibles puis toutes les augmentations nettes de quantités aux autres prix comme remises en vente possibles. On garde le plus grand des deux résultats, sans les additionner. Les disparitions plus chères que les deux minimums ne sont pas ajoutées.

### Interface — PR #59 et #60

- `GM.AdviceText` formule un conseil : prix le plus élevé parmi les trois propositions dont le délai estimé ne dépasse pas 12 h ; sinon proposition juste sous le minimum. Cas spécifiques pour saturation, absence de mesures et mesures non fiables.
- Infobulle : conseil en premier, puis quantités et valeur estimées par jour quand le temps de vente est disponible ; tendance conservée sinon.
- `/vim` : conseil, tendance, prix et stock actuels, puis trois propositions de vente en liste indentée ; graphique conservé dessous.
- `GM.Money` et les montants journaliers utilisent les textures de pièces du client à la place des lettres g/s/c. Prix complets, cuivre compris.
- La largeur de la fenêtre suit la ligne de résultat la plus longue, avec un minimum de 370 px. La hauteur et la position du graphique suivent la hauteur réelle du texte ; graphique centré de largeur inchangée.
- Durées affichées : `< 1 h`, `~N h`, `~N j`, `> 7 j`. Estimations non fiables grisées ; durée mesurée ajoutée au conseil à confirmer.

### Compatibilité et limites

- Aucun changement du format des SavedVariables, des Comparaisons partagées, du protocole en jeu ou du contrat API. Pas de migration ni de réinstallation du Script de synchro.
- Pas de recalcul rétroactif : les anciennes Comparaisons restent telles qu'enregistrées. Seul le dernier scan complet est conservé.
- Pas d'identifiant d'enchère : un retrait au prix le plus bas peut rester indiscernable d'un achat ; des apports indépendants peuvent masquer des achats. Les délais extrapolent un rythme observé, sans garantir une vente.
- Les seuils de verdict restent provisoires : Demande sous 2 jours de stock, Saturé au-dessus de 7 jours ; calibration à poursuivre dans #7. Validations multi-joueurs et mise à jour depuis un zip restent suivies par #44 et #39.

### Vérifications avant préparation de la release

- Fonctionnalités et rendu validés en jeu par Boris ; tests locaux et CI des PR intégrées verts.
- 14 scénarios dédiés aux baisses du minimum : ventes partielles, remises en vente à plusieurs prix, expirations possibles, tailles de piles, annulations chères et comportement existant hors baisse.
- Rejeu de deux paires de scans réels, avec décompte Python indépendant : 7 165 → 7 191 unités estimées sur la première paire ; 4 227 → 4 333 sur celle de 919 s. Les flèches 2512 restent à zéro et la Silk à 1 315 sur la seconde paire.
- La règle de fusion par Tranche ne change pas : le cas historique partagé avec l'API reste valide et n'est pas régénéré.

Le changelog destiné aux joueurs est dans `CHANGELOG-PUBLIC.md`.
