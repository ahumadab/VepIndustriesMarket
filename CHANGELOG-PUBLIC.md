# Changelog public — VepIndustries Market

## Unreleased

### Nouveautés

- **Les noms des objets partent vers le site** : l'addon note le nom (anglais) des objets vus pendant les scans de l'hôtel des ventes, et la synchronisation les envoie avec tes mesures. Le site pourra afficher « Runecloth » plutôt qu'un numéro. Rien à faire de ton côté, et la sauvegarde de l'addon ne grossit que d'environ 200 Ko.

## 0.4.0 — 23 novembre 2026

L'addon aide maintenant à choisir **à quel prix vendre**, et pas seulement à voir si un objet est demandé.

### Nouveautés

- **Un conseil en français** dans l'infobulle et la fenêtre `/vim` : un prix proposé et un délai de vente estimé, ou un avertissement si le marché semble saturé.
- **Plusieurs prix à comparer dans `/vim`** : juste sous le prix le plus bas, puis environ 5 % et 10 % au-dessus, chacun avec son délai estimé pour une pile de taille habituelle. De quoi voir si demander un peu plus vaut l'attente.
- **La valeur estimée vendue par jour sur le marché**, tous vendeurs confondus, à côté du nombre d'objets. Ce n'est pas ton bénéfice personnel.
- **Un affichage plus lisible** : pièces d'or, d'argent et de cuivre en icônes, prix présentés en liste, et fenêtre qui s'adapte à son texte.

### Correction

- Une baisse de prix entre deux scans ne fait plus systématiquement disparaître les ventes estimées. Le calcul tient compte des remises en vente possibles pour éviter de les prendre pour des achats.

### À garder en tête

Les prix et les délais sont des **estimations, pas des garanties**. Les nouvelles annonces, retraits et changements de prix peuvent modifier le résultat. Les anciennes mesures ne sont pas recalculées : la correction agit sur les prochaines comparaisons de scans.

### Mettre à jour depuis la 0.3.0

1. Ferme le jeu.
2. Extrais le zip dans `World of Warcraft\_forever_\Interface\AddOns`, en remplaçant les fichiers existants. Les dossiers `VepIndustriesMarket` et `VepIndustriesMarket_Data` doivent être directement dans `AddOns`, pas dans un sous-dossier supplémentaire.
3. Relance le jeu.

**Ne supprime pas les anciens dossiers avant d'extraire le zip.** Les données de synchronisation sont conservées : pas besoin de relancer `installer.cmd` ni de ressaisir ton code.

Continue simplement les scans automatiques à l'ouverture de l'hôtel des ventes. Pour mesurer les ventes, il faut deux scans complets espacés de 15 minutes à 2 heures.
