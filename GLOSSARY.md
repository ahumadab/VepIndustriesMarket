# VepIndustries Market

Aide un artisan à savoir si les objets qu'il fabrique se vendent à l'hôtel des ventes, en complément des outils de calcul de profit. Pensé pour un joueur seul d'abord, pour une guilde ensuite.

`_Avoid_` liste les mots à écarter du texte (tickets, specs, messages). Dans le code, en anglais, le concept porte le nom donné par `_Code_`.

## Données

**Scan complet**:
Relevé de toutes les enchères de l'hôtel des ventes à un instant donné, limité à un toutes les 15 minutes par le serveur.
_Avoid_: Full scan, getAll, replicate (sauf pour nommer le mode replicate d'Auctionator)
_Code_: `fullScan`

**Historique**:
Pour un objet, par jour : le prix minimum vu et le stock maximum vu, tel que l'enregistre Auctionator.
_Avoid_: Price history, base de prix
_Code_: `history`

**Stock**:
Nombre total d'unités d'un objet en vente à un instant donné, toutes enchères confondues.
_Avoid_: Disponible, available, quantité
_Code_: `stock`

**Prix minimum**:
Prix unitaire d'achat immédiat le plus bas pour un objet à un instant donné.
_Avoid_: Prix, buyout
_Code_: `price`

**Palier**:
Dans un scan complet, l'ensemble des enchères d'un objet au même prix unitaire et à la même taille de lot. Les enchères n'ayant pas d'identifiant, c'est la plus petite unité qu'on peut suivre d'un scan à l'autre.
_Avoid_: Enchère, ligne, tier
_Code_: `tier`

**Résumé journalier**:
Pour un objet, par jour Auctionator : le prix minimum et le stock maximum vus dans les scans complets du jour, et le nombre de ces scans. Conservé 21 jours.
_Avoid_: Daily, agrégat
_Code_: `daily`

## Analyse

**Tendance**:
Évolution relative du prix minimum et du stock d'un objet entre le dernier jour de l'historique et la médiane des jours précédents de la fenêtre.
_Avoid_: Trend, évolution
_Code_: `trend`

**Ventes estimées**:
Nombre d'unités d'un objet probablement achetées entre deux scans complets, déduit des enchères disparues avant leur expiration.
_Avoid_: Sale rate, ventes, demande
_Code_: `estimatedSales` (`estimatedSalesPerDay` ramené à un jour)

**Verdict**:
Classement d'un objet en Demande, Stable ou Saturé. Il se fonde sur les ventes estimées quand il y en a, sinon sur la tendance.
_Avoid_: Statut, note, score
_Code_: `verdict` (`"demand"`, `"stable"`, `"saturated"`, `"none"` faute de données)

**Demande**:
Verdict d'un objet qui s'écoule : ventes estimées élevées, ou stock qui baisse sans que le prix chute.
_Avoid_: Hot, populaire
_Code_: `demand`

**Saturé**:
Verdict d'un objet dont l'offre dépasse ce que les acheteurs absorbent : le stock s'accumule ou le prix baisse.
_Avoid_: Mort, invendable
_Code_: `saturated`

**Fenêtre**:
Nombre de jours d'historique pris en compte pour la tendance (7 par défaut).
_Avoid_: Période, range
_Code_: `WINDOW`
