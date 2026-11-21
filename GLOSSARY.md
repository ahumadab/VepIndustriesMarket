# VepIndustries Market

Aide un artisan à savoir si les objets qu'il fabrique se vendent à l'hôtel des ventes, en complément des outils de calcul de profit. Pensé pour un joueur seul d'abord, pour une guilde ensuite.

## Données

**Scan complet**:
Relevé de toutes les enchères de l'hôtel des ventes à un instant donné, limité à un toutes les 15 minutes par le serveur.
_Avoid_: Full scan, getAll, replicate

**Historique**:
Pour un objet, par jour : le prix minimum vu et le stock maximum vu, tel que l'enregistre Auctionator.
_Avoid_: Price history, base de prix

**Stock**:
Nombre total d'unités d'un objet en vente à un instant donné, toutes enchères confondues.
_Avoid_: Disponible, available, quantité

**Prix minimum**:
Prix unitaire d'achat immédiat le plus bas pour un objet à un instant donné.
_Avoid_: Prix, buyout

## Analyse

**Tendance**:
Évolution relative du prix minimum et du stock d'un objet entre le dernier jour de l'historique et la médiane des jours précédents de la fenêtre.
_Avoid_: Trend, évolution

**Ventes estimées**:
Nombre d'unités d'un objet probablement achetées entre deux scans complets, déduit des enchères disparues avant leur expiration.
_Avoid_: Sale rate, ventes, demande

**Verdict**:
Classement d'un objet en Demande, Stable ou Saturé. Il se fonde sur les ventes estimées quand il y en a, sinon sur la tendance.
_Avoid_: Statut, note, score

**Demande**:
Verdict d'un objet qui s'écoule : ventes estimées élevées, ou stock qui baisse sans que le prix chute.
_Avoid_: Hot, populaire

**Saturé**:
Verdict d'un objet dont l'offre dépasse ce que les acheteurs absorbent : le stock s'accumule ou le prix baisse.
_Avoid_: Mort, invendable

**Fenêtre**:
Nombre de jours d'historique pris en compte pour la tendance (7 par défaut).
_Avoid_: Période, range
