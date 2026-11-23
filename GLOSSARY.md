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
Pour un objet, par jour Auctionator : le prix minimum et le stock maximum vus dans les scans complets du jour, le nombre de ces scans et les ventes estimées des Comparaisons fusionnées par Tranche, avec la durée sur laquelle elles portent. Conservé 21 jours.
_Avoid_: Daily, agrégat
_Code_: `daily`

**Comparaison**:
Résultat de la comparaison de deux scans complets consécutifs d'un même joueur : hôtel des ventes (royaume, faction), auteur (le compte du joueur, sous le nom de son premier personnage à avoir scanné), heure de début et de fin, et par objet les unités vendues (ventes estimées), le stock et le prix minimum du second scan. Identifiée par son auteur et son heure de début. C'est ce qui circule entre joueurs et vers le VPS.
_Avoid_: Diff, delta, paire de scans
_Code_: `comparison` (`start`, `finish`, `items`)

**Tranche**:
Demi-heure fixe du jour Auctionator (00:00-00:30, ...), unité de fusion des Comparaisons : chaque Comparaison répartit ses ventes au prorata du temps passé dans chaque Tranche ; sur une même Tranche, les Comparaisons d'un même auteur s'additionnent et celles de plusieurs auteurs donnent leur moyenne, pour ne pas compter deux fois les mêmes achats. Règle et cas communs à l'addon et au serveur : `tests/merge-cases.json`.
_Avoid_: Créneau, slot, bucket
_Code_: `tranche` (`TRANCHE`, `Market.Merge`)

**Script de synchro**:
Script PowerShell livré avec l'addon qui fait le lien entre la sauvegarde du jeu et le VPS : installé une fois par `installer.cmd` avec le code d'invitation de l'ami, il tourne en tâche planifiée toutes les 15 minutes de la session Windows ; quand le jeu a écrit une nouvelle sauvegarde, il envoie les nouvelles Comparaisons au VPS et écrit le fichier de données de l'addon. Il se retire si l'addon disparaît ou après 30 jours sans nouvelle sauvegarde.
_Avoid_: Client, companion, passerelle, synchro (seul, pour le script)
_Code_: `Sync.ps1`; le code d'invitation est le `Sync-Code` de l'API

## Analyse

**Tendance**:
Évolution relative du prix minimum et du stock d'un objet entre le dernier jour de l'historique et la médiane des jours précédents de la fenêtre.
_Avoid_: Trend, évolution
_Code_: `trend`

**Ventes estimées**:
Nombre d'unités d'un objet probablement achetées entre deux scans complets, déduit des enchères disparues avant leur expiration, en supposant que les acheteurs prennent les moins chères : on compte les unités disparues par prix unitaire, jusqu'au nouveau prix minimum ; une enchère plus chère qui disparaît est une annulation.
_Avoid_: Sale rate, ventes, demande
_Code_: `estimatedSales` (`estimatedSalesPerDay` ramené à un jour)

**Valeur vendue par jour**:
Or qui passe chaque jour sur un objet, tous vendeurs confondus : ventes estimées par jour × prix minimum actuel. Un seul chiffre comparable d'un objet à l'autre, pour savoir où va l'argent (un objet cher peu vendu peut peser moins qu'un objet bon marché très vendu).
_Avoid_: Chiffre d'affaires, volume, CA
_Code_: `goldPerDay` (cuivre)

**Fiable**:
Se dit des ventes estimées d'un objet quand au moins deux jours de la fenêtre ont une comparaison de scans complets (donc au moins trois scans) et qu'elles portent sur au moins une heure, et d'un jour quand il est dans la fenêtre d'un objet fiable. Non fiables, elles sont grisées et le verdict se fonde sur la tendance ; sous une heure comparée (sur la fenêtre, ou sur un jour), l'addon affiche « pas assez de scans » au lieu d'un nombre.
_Avoid_: Sûr, confiance (sauf dans le code)
_Code_: `confidence = "high"` pour l'objet, `reliable` pour un jour du résumé journalier

**Verdict**:
Classement d'un objet en Demande, Stable ou Saturé. Il se fonde sur les ventes estimées quand elles sont fiables, sinon sur la tendance ; l'infobulle indique laquelle.
_Avoid_: Statut, note, score
_Code_: `verdict` (`"demand"`, `"stable"`, `"saturated"`, `"none"` faute de données), sa source `source` (`"sales"`, `"trend"`)

**Demande**:
Verdict d'un objet qui s'écoule : au rythme des ventes estimées, le stock actuel part en moins de quelques jours ; sans ventes estimées fiables, stock qui baisse sans que le prix chute.
_Avoid_: Hot, populaire
_Code_: `demand` (seuil `DEMAND_DAYS`)

**Saturé**:
Verdict d'un objet dont l'offre dépasse ce que les acheteurs absorbent : au rythme des ventes estimées, le stock actuel tient plus d'une semaine environ, ou rien ne se vend ; sans ventes estimées fiables, le stock s'accumule ou le prix baisse.
_Avoid_: Mort, invendable
_Code_: `saturated` (seuil `SATURATED_DAYS`)

**Fenêtre**:
Nombre de jours d'historique pris en compte pour la tendance (7 par défaut).
_Avoid_: Période, range
_Code_: `WINDOW`
