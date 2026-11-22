# Partager les données entre amis et avec le VPS

Recherche du 21/11/2026. Question : comment l'addon peut-il échanger ses Comparaisons et son Résumé journalier avec d'autres joueurs (même royaume, même faction) et avec le VPS de Boris, sans programme supplémentaire chez les amis ?

`<jeu>` désigne `C:/Program Files (x86)/World of Warcraft/_forever_`. Les tailles viennent de `tests/fixtures/` (voir § 3.3).

## En bref

- Un addon n'a ni réseau, ni accès aux fichiers. Seul un programme qui tourne hors du jeu peut parler au VPS, et ce qu'il dépose n'est lu qu'au `/reload` suivant.
- Tous les outils connus (TSM, Raider.IO, WeakAuras Companion, WowUp, Archon) reposent sur ce même schéma : un programme Windows plus un addon de données généré. Aucun n'offre de point d'extension qu'un autre addon pourrait réutiliser.
- Entre joueurs connectés en même temps, les messages d'addon suffisent : une Comparaison compressée pèse ~36 Ko et part en 1 à 3 minutes.
- Seul montage sans programme chez les amis : synchro en jeu entre amis, et un seul programme sur le PC de Boris pour faire le lien avec le VPS.

## 1. Limites du bac à sable

| Limite | Ce que disent les sources |
|---|---|
| Pas de fichiers ni de système | « operating system and file I/O libraries are not present » ([Lua functions](https://warcraft.wiki.gg/wiki/Lua_functions)) : ni `io`, ni `os`, donc pas de lecture de fichier à l'exécution. |
| Pas de réseau | Aucune API HTTP ou socket dans la liste des fonctions Lua ([Lua functions](https://warcraft.wiki.gg/wiki/Lua_functions)). Les seules sorties sont les canaux de discussion et de jeu (§ 3). |
| SavedVariables : seule persistance | Écrites « when you log out, disconnect, quit the game » ou au `/reload`. `PLAYER_LOGOUT` est « the last event before your saved variables are written to disk ». Lues une seule fois, au chargement de l'addon, juste avant `ADDON_LOADED` ([Saving variables](https://warcraft.wiki.gg/wiki/Saving_variables_between_game_sessions)). Aucune limite de taille documentée. |
| Fichiers d'addon | Les nouveaux fichiers et les nouveaux addons sont pris en compte au `/reload`. Depuis la 9.0.1, les changements de `.toc` le sont aussi ([TOC format](https://warcraft.wiki.gg/wiki/TOC_format)). Un fichier modifié par un programme externe est donc relu au `/reload` suivant, pas avant. |
| Nouveautés récentes | `import` (ex-`require`) ne renvoie que des modules d'addon déjà chargés et ne lit aucun fichier ([API import](https://warcraft.wiki.gg/wiki/API:import), [notes 1.60.1](https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes)). `C_EncodingUtil` (11.1.5, présent dans Forever 1.60.1) ajoute en natif la compression Deflate, les encodages Base64 et CBOR, et le JSON ([CompressString](https://warcraft.wiki.gg/wiki/API_C_EncodingUtil.CompressString), [11.1.5 API changes](https://warcraft.wiki.gg/wiki/Patch_11.1.5/API_changes)). Ces nouveautés aident à empaqueter les données, mais n'ouvrent aucune sortie vers l'extérieur. |

Ce qui pourrait changer la donne : un `LoadOnDemand` charge son addon à l'appel de `C_AddOns.LoadAddOn` ([TOC format](https://warcraft.wiki.gg/wiki/TOC_format)). Si le client lit le fichier à ce moment-là, un programme externe pourrait déposer des données en cours de session, mais une seule fois par session. Rien ne le documente ; c'est à vérifier en jeu (§ 5).

## 2. Comment font les autres

| Outil | Ce qui tourne hors du jeu | Retour dans le jeu |
|---|---|---|
| TradeSkillMaster | L'application de bureau : il faut se connecter, choisir le dossier du jeu, cocher `TradeSkillMaster` et `TSM_AppHelper`, puis les royaumes ([mise en place](https://support.tradeskillmaster.com/tsm-desktop-application/how-do-i-set-up-the-tsm-desktop-application)) | `TSM_AppHelper` « is used to store pricing data distributed by the Desktop Application » ([support TSM](https://support.tradeskillmaster.com/en_US/addon/how-do-i-fix-an-error-about-appdatalua-being-empty)). Si le jeu était ouvert, il faut le fermer complètement puis le relancer ([mise en place](https://support.tradeskillmaster.com/tsm-desktop-application/how-do-i-set-up-the-tsm-desktop-application)). |
| Raider.IO | RaiderIO Client, qui « will automatically keep your RaiderIO Addon updated » ([support](https://support.raider.io/kb/raider-dot-io-mythic-plus-addon/how-do-i-install-the-raiderio-client)) | Les données sont livrées dans l'addon lui-même : « storing a snapshot of character data », mis à jour « multiple times each day » ([CurseForge](https://www.curseforge.com/wow/addons/raiderio)), « every night » ([support](https://support.raider.io/kb/raider-dot-io-mythic-plus-addon/why-is-this-addon-updated-so-frequently)). |
| WeakAuras Companion | Application Electron avec icône dans la zone de notification et option de lancement à l'ouverture de session Windows (`Tray`, `app.setLoginItemSettings({ openAtLogin })` dans [electron/main/index.ts](https://github.com/WeakAuras/WeakAuras-Companion/blob/main/electron/main/index.ts)) | Elle génère l'addon `WeakAurasCompanion` (`.toc`, `data.lua` « generated automatically », `init.lua`) dans `Interface/AddOns` ([write-addon-data.ts](https://github.com/WeakAuras/WeakAuras-Companion/blob/main/src/libs/write-addon-data.ts)). Au premier lancement, il faut redémarrer le jeu ou faire un `/reload` ([README](https://github.com/WeakAuras/WeakAuras-Companion)). |
| WowUp | Le gestionnaire d'addons | Il écrit un addon de données qui remplit `WOWUP_DATA`, lu par l'addon « Addon Update Notifications » : « How this is created or added to wow doesn't matter » ([AddonManagers.md](https://github.com/WowUp/WowUp.Addon/blob/master/AddonManagers.md)). |
| Warcraft Logs / Archon | L'application Archon surveille le journal de combat et envoie les nouveaux combats ([aide Archon](https://www.archon.gg/wow/articles/help/archon-app-help-and-faq), [auto logging](https://www.archon.gg/wow/articles/news/archon-app-auto-logging)) | Sens jeu → programme seulement. L'addon `!ArchonLogger`, installé ici, se contente d'activer `LoggingCombat` (`<jeu>/Interface/AddOns/!ArchonLogger/Init.lua`). |
| ForeverSVBridge (Forever) | Un `setup.bat` lancé une seule fois, qui crée une jonction vers `SavedVariables` ([CurseForge](https://www.curseforge.com/wow/addons/foreversvbridge)) | Les fichiers sauvegardés sont listés dans son `.toc` et chargés comme du code. C'était un contournement d'un bug de la bêta, corrigé en 1.60.1 70009 (« Fixed SavedVariables not loading », [notes 1.60.1](https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes)). |

**Points d'accroche réutilisables ?** Aucun. WowUp ne prévoit qu'un format de données pour ses propres notifications de mise à jour, sans greffon tiers ([AddonManagers.md](https://github.com/WowUp/WowUp.Addon/blob/master/AddonManagers.md)). WeakAuras Companion ne gère que WeakAuras et Plater ([README](https://github.com/WeakAuras/WeakAuras-Companion)). Je n'ai trouvé aucune API publique de greffons pour l'application CurseForge ni pour l'application Wago. Le seul relais existant est **la mise à jour automatique d'un addon** par le gestionnaire que les amis utilisent déjà (CurseForge le fait, sauf pour les addons « Modified » ou « Working Copy », [FAQ CurseForge](https://support.curseforge.com/support/solutions/articles/9000198422-addons-faq)) : c'est le modèle Raider.IO, mais dans un seul sens, vers les joueurs.

## 3. Synchronisation en jeu par messages d'addon

### 3.1 L'API

`C_ChatInfo.SendAddonMessage(prefix, message, chatType, target)` ([wiki](https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendAddonMessage)) :

- préfixe de 16 caractères au plus, à enregistrer chez le destinataire avec `RegisterAddonMessagePrefix` ;
- message de **255 octets** au plus, tous les octets permis sauf `\0`. AceComm le confirme : « Char 256+ get silently truncated » (`<jeu>/Interface/AddOns/Details/Libs/AceComm-3.0/AceComm-3.0.lua`) ;
- canaux : `PARTY`, `RAID`, `INSTANCE_CHAT`, `GUILD`, `OFFICER`, `WHISPER` (cible sur le même royaume ou un royaume connecté), et `CHANNEL` (canal personnalisé, retail uniquement) ;
- **limitation par préfixe** : « Each registered prefix is given an allowance of 10 addon messages », « regains its allowance at a rate of 1 message per second ». Elle s'applique à tous les canaux depuis la 10.2.7, mais « does not apply to whispers outside of instanced content ». Le serveur peut changer ces valeurs. Trop de données envoyées d'un coup peut déconnecter le joueur ;
- résultats `Enum.SendAddonMessageResult` : `AddonMessageThrottle` (3), `ChannelThrottle` (8), `AddOnMessageLockdown` (11, 12.0) et `TargetOffline` (12, 12.0) ;
- « *Forever* and modern clients starting in patch 12.1.7 prohibit trial and veteran accounts from sending addon messages » : **un ami en compte d'essai ne pourra rien envoyer**.

`SendAddonMessageLogged` a les mêmes paramètres ; il sert aux contenus écrits par les joueurs, que Blizzard peut examiner après un signalement (même page).

`C_BattleNet.SendGameData(gameAccountID, prefix, data)` existe aussi dans Forever 1.60.1 ([wiki](https://warcraft.wiki.gg/wiki/API_C_BattleNet.SendGameData)). Il remplace `BNSendGameData`, dont les messages allaient jusqu'à **4078 octets** ([wiki](https://warcraft.wiki.gg/wiki/API_BNSendGameData)), soit 16 fois plus. Il passe par les amis Battle.net, mais ni sa limite de taille ni sa limitation de débit ne sont documentées.

### 3.2 Bibliothèques

- **ChatThrottleLib** (v31 et v32 installées) : file d'attente à trois priorités. `MAX_CPS = 800` (« 2000 seems to be safe if NOTHING ELSE is happening »), `BURST = 4000` (« seen disconnects on _some_ servers »), débit réduit sous 20 images/s. Depuis ces versions, un envoi refusé avec `AddonMessageThrottle` est remis en file au lieu d'être perdu (`<jeu>/Interface/AddOns/Details/Libs/AceComm-3.0/ChatThrottleLib.lua`).
- **AceComm-3.0** : découpe un message long en morceaux de 255 octets, marqués par les caractères de contrôle `\001`, `\002` et `\003`, et les réassemble à l'arrivée (même dossier).
- **LibDeflate** : taux de compression ~3,7 sur une chaîne WeakAuras de 132 Ko. `EncodeForWoWAddonChannel` retire les `\0` ([README](https://github.com/SafeteeWoW/LibDeflate)).
- **LibSerialize** : sérialisation de tables, recommandée avec LibDeflate puis `SendCommMessage` ([README](https://github.com/rossnichols/LibSerialize)).
- En natif, `C_EncodingUtil.SerializeCBOR`, `CompressString` et `EncodeBase64` remplacent LibSerialize et LibDeflate, mais Base64 ajoute 33 % ; la sortie compressée peut contenir des `\0`, d'où ce passage obligé (§ 1).

### 3.3 Ordre de grandeur

Mesure sur les fixtures réelles : `fullscan-1121-2023` et `fullscan-1121-2039` contiennent un objet sur dix. Une ligne par objet `itemID vendus stock prixMin` en base 36, compressée avec zlib (Deflate niveau 9), puis multipliée par 10 :

| Charge | Brut | Compressé | Messages de 250 o |
|---|---|---|---|
| Une Comparaison (~6 800 objets) | ~71 Ko | **~36 Ko** | ~145 (~190 en Base64) |
| Un jour de Résumé journalier (format de l'addon) | ~264 Ko (~170 Ko d'après `Market.lua`) | **~53 Ko** | ~210 (~280 en Base64) |
| 21 jours de Résumé | ~5,6 Mo | ~1,1 Mo | ~4 500 |

Durée d'envoi estimée :

- **GUILD / PARTY / RAID, un préfixe** : 10 messages d'un coup, puis 1 par seconde. Une Comparaison prend **~2,5 à 3 min**, un jour de Résumé **~4 à 5 min**, 21 jours **~1 h 15 à 1 h 30**.
- **WHISPER hors instance** : seul ChatThrottleLib freine, à 800 o/s, en-têtes compris. Une Comparaison prend **~45 à 60 s**, un jour de Résumé ~1 à 1,5 min, 21 jours ~25 à 30 min.
- **CHANNEL** : OneForAll, un addon propre à Forever, espace ses messages de 1,2 s, contre 0,35 s en guilde : « channel messages are throttled harder by the server » (`<jeu>/Interface/AddOns/OneForAll/UI/ProfessionGuild.lua`, l. 38-41).
- **C_BattleNet.SendGameData** : à 4 Ko par message, une Comparaison tiendrait en ~10 messages. Le débit réel reste à mesurer.

Conséquence : n'échanger que les **Comparaisons**, petites et sans doublon puisque chacune est identifiée par son couple début/fin. Chaque addon reconstruit ensuite son Résumé localement. Un rattrapage de 21 jours n'est envisageable qu'en chuchotement, une seule fois.

### 3.4 Limites

- Il faut que **les deux joueurs soient connectés en même temps**. TSM l'impose aussi pour synchroniser deux comptes : un personnage « online and on the same realm and faction » ([réglages TSM](https://support.tradeskillmaster.com/en_US/tsm-addon-documentation/tsm-addon-general-settings)). Pour contourner, chaque addon garde tout et le retransmet au prochain ami en ligne (relais de proche en proche).
- La synchro s'arrête au `/reload` ou à la déconnexion : un transfert interrompu est à reprendre. Il faut donc des envois idempotents, morceau par morceau.
- Un débit trop élevé peut déconnecter le joueur (avertissement du wiki, commentaire `BURST` de ChatThrottleLib). Il faut rester sous ChatThrottleLib, en priorité `BULK`.
- `AddOnMessageLockdown` : `C_ChatInfo.InChatMessagingLockdown()` renvoie vrai quand des « API security restrictions regarding chat messaging are in effect » ([wiki](https://warcraft.wiki.gg/wiki/API_C_ChatInfo.InChatMessagingLockdown)), dans des cas non documentés. DungeonForever attend 2 s puis réessaie (`<jeu>/Interface/AddOns/DungeonForever/Share.lua`, l. 18-73).

### 3.5 Exemples d'addons qui envoient de gros volumes

- **WeakAuras** : LibSerialize, puis LibDeflate, puis `EncodeForWoWAddonChannel`, puis `SendCommMessage(..., "WHISPER", ..., "BULK", callback)`, avec une barre de progression envoyée sur un second préfixe ([Transmission.lua](https://github.com/WeakAuras/WeakAuras2/blob/main/WeakAuras/Transmission.lua), l. 278-301 et 602-630).
- **DungeonForever** (Forever) : morceaux de 240 caractères, 0,2 s entre deux envois, nouvelle tentative 1 s après un refus pour débit, abandon après 120 s sans nouveau morceau (`Share.lua`, l. 14-20).
- **OneForAll** (Forever) : partage des recettes de la guilde en lots `B` (annonce) et `D` (données) de 240 caractères au plus, avec trois tentatives après un refus pour débit (`ProfessionGuild.lua`, l. 485-531 et 604-615).

## 4. Options hybrides

**H1, synchro en jeu seule.** Comparaisons échangées en guilde, ou en chuchotement entre amis listés, avec relais de proche en proche. Le VPS ne reçoit rien.

**H2, synchro en jeu et passerelle sur le PC de Boris.** L'addon de Boris reçoit tout ce qui circule en jeu et l'enregistre dans ses SavedVariables. Un seul programme, sur son PC, fait trois choses :

1. surveiller `VepIndustriesMarket.lua` (réécrit à chaque `/reload` ou déconnexion) et envoyer les nouvelles Comparaisons au VPS, comme le fait déjà `scripts/saved.mjs`, qui lit ce fichier ;
2. récupérer les données fusionnées et générer un addon de données `VepIndustriesMarket_Data`, sur le modèle de `WeakAurasCompanion/data.lua` ou de `WOWUP_DATA`, lu au `/reload` suivant ;
3. démarrer avec Windows (tâche planifiée ou dossier Démarrage), comme le fait WeakAuras Companion avec `openAtLogin`.

L'addon de Boris diffuse ensuite en jeu ce que les autres n'ont pas. Le VPS n'a que ce que Boris a reçu : les Comparaisons faites pendant ses absences n'y arrivent qu'à la prochaine rencontre en jeu, grâce au relais.

**H3, H2 et diffusion par CurseForge.** Le VPS publie chaque jour une version de l'addon de données, mise à jour automatiquement par l'application CurseForge des amis (modèle Raider.IO). L'envoi vers le VPS passe toujours par le jeu.

**H4, un programme chez chaque ami** (modèle TSM ou Raider.IO). C'est complet et frais, mais il faut installer un programme : exclu par la demande.

| Option | Contrainte pour les amis | Fraîcheur | Complétude sur le VPS | Effort |
|---|---|---|---|---|
| H1 en jeu seul | Aucune | Dès que deux amis sont connectés ensemble | Nulle | Moyen (protocole, relais, reprise) |
| **H2 en jeu + passerelle Boris** | **Aucune** | Comme H1 ; données du VPS après un `/reload` de Boris | Bonne, avec du retard | Moyen + petit (Node, déjà amorcé) |
| H3 = H2 + CurseForge | Avoir l'application CurseForge avec la mise à jour automatique | Quotidienne, même sans rencontre | Comme H2 | H2 + publication automatique |
| H4 programme chez chacun | Installer un programme et le laisser tourner | Au `/reload` de chacun | Totale | Élevé (installateur, mises à jour, assistance) |

## 5. Incertitudes propres à Forever

D'après le wiki, Forever est une version officielle de Blizzard qui « shares Mainline WoW's UI architecture, including the vast majority of APIs available in 12.1.5 ». Les restrictions de Midnight s'y appliquent aussi ([notes 1.60.1](https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes)). Les limites de débit côté serveur, elles, ne sont documentées nulle part pour Forever. À vérifier en jeu, une seule fois, sans nouveau Scan complet. La sonde `tools/probe` (`npm run probe`, ticket #19) fait ces mesures et les enregistre :

- **Débit par préfixe** : `/run local r={} for i=1,20 do r[i]=C_ChatInfo.SendAddonMessage("VIMTEST",("x"):rep(250),"GUILD") end print(table.concat(r," "))`. On attend dix `0` puis des `3`. Recommencer avec `"WHISPER", UnitName("player")` pour vérifier l'exemption des chuchotements.
- **APIs présentes** : `/dump C_EncodingUtil ~= nil, C_BattleNet.SendGameData ~= nil, C_ChatInfo.InChatMessagingLockdown()`.
- **Taille admise par SendGameData** : envoyer à un ami Battle.net connecté des messages de 1 000, 2 000 puis 4 000 octets, et regarder ce qui arrive (`BN_CHAT_MSG_ADDON`).
- **LoadOnDemand relu en cours de session** : modifier le fichier d'un addon `LoadOnDemand` jeu ouvert, puis `/run C_AddOns.LoadAddOn("...")`. Si le client lit le fichier à ce moment-là, H2 peut livrer des données une fois par session, sans `/reload`.
- **Comptes d'essai** : demander à chaque ami s'il a un compte payant (voir la restriction citée au § 3.1).

### Résultats en jeu (22/11/2026, ticket #19)

Mesuré par Boris avec la sonde, hors instance, en messages de 250 octets :

- **`GUILD`** : 10 messages acceptés d'un coup, puis 1 par seconde (20 et 21 en 20 s), et chaque message accepté est reçu. Au-delà, l'envoi est refusé avec le code `3` (`AddonMessageThrottle`). C'est la limite du wiki.
- **`WHISPER`** : aucun refus à 12 messages d'un coup puis 5 par seconde (1 250 o/s pendant 20 s), et 112 messages reçus sur 112. La limite réelle, si elle existe, est au-dessus.
- **Noms** : un royaume de Forever n'a pas de nom (`GetNormalizedRealmName()` renvoie `""`). Un personnage a un prénom et un nom de famille, que `UnitName` donne en deuxième résultat. Un chuchotement n'atteint le joueur que sous la forme `Prénom-NomDeFamille`. `CHAT_MSG_ADDON` donne l'expéditeur sous la forme `Prénom NomDeFamille`, avec une espace : pour lui répondre, il faut remplacer l'espace par un tiret.
- **Destinataire déconnecté ou introuvable** : l'envoi est accepté (code `0`, jamais `12`). Puis le serveur affiche dans la discussion, pour chaque message, « No player named 'Prénom NomDeFamille' is currently playing. » (client en anglais). Un transfert vers un joueur parti remplit donc la discussion tant que ce message n'est pas filtré.
- **Addon `LoadOnDemand`** : le fichier modifié jeu ouvert est relu par `C_AddOns.LoadAddOn`. Le fichier du VPS peut donc arriver en cours de partie, une fois par session.
- **APIs** : `C_EncodingUtil` (`CompressString`, `SerializeCBOR`, `EncodeBase64`) et `C_BattleNet.SendGameData` sont présents. `AreOutgoingAddonChatMessagesRestricted()` répond `true`, alors que les envois passent : il ne faut pas s'y fier.
- **Non mesuré** : le débit en `WHISPER` dans un donjon et le blocage pendant un combat de boss. Le test demandait d'autres joueurs, et Boris y a renoncé. On suit le wiki (limite de débit sur les chuchotements en instance) et DungeonForever, qui traite le code `11` (`AddOnMessageLockdown`) et `InChatMessagingLockdown()` en réessayant 2 s plus tard. L'échange doit donc supporter un refus pour débit comme un blocage.

## 6. Recommandation

1. Retenir **H2** : une synchro en jeu des Comparaisons seules, compressées, avec envoi idempotent par morceaux et relais de proche en proche, plus une passerelle Node sur le PC de Boris seul, lancée avec Windows, qui envoie au VPS et génère `VepIndustriesMarket_Data`. Les amis n'ont rien à lancer.
2. Envoyer en **chuchotement** entre amis connus, par une liste d'amis dans l'addon ou par le roster de guilde : c'est le seul canal hors instance sans limite par préfixe, trois fois plus rapide que `GUILD`. Ne réserver `GUILD` qu'aux annonces (« j'ai les Comparaisons X à Y »).
3. Garder `C_BattleNet.SendGameData` comme accélérateur possible, si le test du § 5 confirme ~4 Ko par message.
4. N'ajouter H3 (publication sur CurseForge) que si la fraîcheur entre amis qui ne se croisent jamais pose un vrai problème.
5. Avant d'écrire du code, faire les tests du § 5 : ils fixent les débits réels et décident entre chuchotement et Battle.net.
