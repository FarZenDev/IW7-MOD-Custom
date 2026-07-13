# IW7-Mod EasyMP — Jouer entre amis, simplement

Version modifiée de [iw7-mod](https://github.com/auroramod/iw7-mod) qui rend le multijoueur entre amis
aussi simple que sur Plutonium : un bouton **JOUER ENTRE AMIS** dans le menu, une liste d'amis,
des invitations automatiques et l'ouverture du port de votre box sans configuration.

> Vous devez posséder légalement Call of Duty®: Infinite Warfare sur Steam.

---

## Installation

1. Compilez le projet (ou utilisez le binaire déjà compilé dans `build\bin\x64\Release\`) :
   - `generate.bat` puis ouvrir `build\iw7-mod.sln` dans Visual Studio 2022 → Build Release x64
2. Lancez **`installer-easymp.bat`** : il copie l'exe dans le dossier du jeu et les scripts
   d'interface dans `%LOCALAPPDATA%\auroramod\iw7-mod\cdata`.
3. Lancez `iw7-mod.exe` depuis le dossier du jeu.

---

## Sans Steam par défaut

Cette version **ne passe plus par Steam** : la vérification de possession qui affichait
« Steam must be running to play this game! » est désactivée par défaut. Vous lancez `iw7-mod.exe`
directement, Steam n'a pas besoin d'être ouvert.

- L'installeur écrit un `steam_path.txt` dans le dossier du jeu pour que le client retrouve les
  fichiers du jeu même quand Steam est fermé.
- Pour **rétablir l'ancien comportement** (vérification via Steam) : lancez `iw7-mod.exe -steam`.

> À savoir : ceci évite d'avoir Steam lancé, ça ne remplace pas la possession du jeu. Vous devez
> posséder Infinite Warfare et avoir ses fichiers installés sur la machine.

## Utilisation in-game

Le bouton **JOUER ENTRE AMIS** est présent dans le menu **MULTIJOUEUR** *et* dans le menu
**ZOMBIES**. Il ouvre le menu EasyMP :

| Élément | Action |
|---|---|
| `>> CREER UNE PARTIE ENTRE AMIS` | Ouvre le salon de partie personnalisée (**zombies ou multijoueur selon le menu d'où vous venez**). Au lancement de la map : le port est ouvert automatiquement (UPnP) et **tous vos amis reçoivent une invitation**. |
| `>> INVITATION DE X <<` | Apparaît quand un ami vous invite — cliquez pour le rejoindre. |
| `[EN PARTIE] Ami` (vert) | L'ami est en partie — **cliquez pour le rejoindre**. |
| `[EN LIGNE] Ami` (jaune) | L'ami a le jeu ouvert (dans les menus). |
| `[HORS LIGNE] Ami` (rouge) | Injoignable actuellement. |
| `[+] Joueur récent` | Toute personne croisée en partie — **un clic = ajouté en ami** (aucune IP à taper). |

En bas de l'écran : **votre code ami** (ex : `A3F2-9K1M-P7Q2`), à partager une seule fois à un ami
pour qu'il vous ajoute.

Les statuts se rafraîchissent automatiquement toutes les 3 secondes tant que le menu est ouvert.

### Zombies

Le flux complet fonctionne en Zombies : créez votre partie zombies via le menu (choix de la map
dans le salon natif), vos amis sont invités au lancement et vous rejoignent en cours de partie.
**Bonus** : si un ami est en partie Zombies alors que vous êtes dans le menu Multijoueur (ou
l'inverse), cliquer « rejoindre » **bascule automatiquement le jeu dans le bon mode** puis vous
connecte — plus d'erreur « Invalid playmode ».

## Ajouter un ami

Trois façons, de la plus simple à la plus manuelle :

1. **Jouer une fois ensemble** (via code ou Discord), puis cliquer sur son nom dans *Joueurs récents*.
2. **Par code ami** (console `²` ou `~`) : `friend_add Kevin A3F2-9K1M-P7Q2`
3. **Par IP** : `friend_add Kevin 82.65.12.34:27017`

Les amis sont stockés dans `%LOCALAPPDATA%\auroramod\iw7-mod\friends.txt` (une ligne par ami :
`nom<TAB>ip:port`) — modifiable à la main.

## Commandes console

| Commande | Effet |
|---|---|
| `host <map> [mode] [joueurs] [motdepasse]` | Héberge en une commande (MP : `host mp_crash_iw war 12`, Zombies : `host cp_zmb` depuis le menu Zombies — le gametype actuel est conservé). UPnP + invitations automatiques. |
| `join <ami \| code \| ip:port>` | Rejoint un ami par son nom, un code d'invitation ou une IP. |
| `friends` | Liste vos amis avec leur statut en ligne. |
| `friend_add / friend_remove` | Gère la liste d'amis. |
| `invite` | Renvoie une invitation à tous vos amis (pendant que vous hébergez). |
| `invite_code` | Affiche votre code ami (copié dans le presse-papiers). |
| `accept_invite` / `decline_invite` | Accepte / refuse la dernière invitation reçue. |
| `upnp` | Force l'ouverture du port UDP sur la box. |

## Discord

- Quand vous hébergez, votre statut Discord expose un bouton **Rejoindre** : vos amis Discord
  peuvent vous rejoindre depuis votre profil, même sans être dans votre liste d'amis EasyMP.
- Les demandes « Demander à rejoindre » sont **acceptées automatiquement**.

## Comment ça marche (technique)

- **Amis / invitations** : pair-à-pair en UDP sur le port du jeu (packets `getInfo` / `gameInvite`),
  aucun serveur externe. La liste d'amis est locale.
- **UPnP** : à chaque partie hébergée, le client découvre la box (SSDP) et mappe le port UDP
  (`AddPortMapping`). Si la box refuse ou n'a pas d'UPnP, un port forwarding manuel du port
  `net_port` (UDP, 27017 par défaut) reste nécessaire pour héberger.
- **Code ami** : votre IP publique + port encodés en base32 (12 caractères + somme de contrôle).
  L'IP publique est détectée au lancement (api.ipify.org).
- **Mise à jour auto désactivée** : l'updater officiel écraserait cette version custom.
  Pour revenir à la version officielle : lancez avec `-autoupdate`.

## Fichiers modifiés / ajoutés par rapport à iw7-mod

- `src/client/component/easymp.cpp/.hpp` — amis, invitations, codes, commande `host` *(nouveau)*
- `src/client/component/upnp.cpp/.hpp` — ouverture de port automatique *(nouveau)*
- `src/client/component/party.cpp` — hooks statuts/joueurs récents/démarrage d'hébergement + bascule auto MP↔Zombies au join
- `data/cdata/ui_scripts/MainMenu/CPMainMenuButtons.lua` — bouton du menu Zombies
- `src/client/component/discord.cpp` — join secret en partie privée + acceptation auto
- `src/client/component/ui_scripting.cpp` — API Lua `friendslist`
- `src/client/component/updater.cpp` — auto-update désactivé
- `src/client/component/steam_proxy.cpp` — vérification Steam désactivée par défaut (`-steam` pour la réactiver)
- `data/cdata/ui_scripts/EasyMP/` — menu Jouer entre amis *(nouveau)*
- `data/cdata/ui_scripts/MainMenu/MPMainMenuButtons.lua` — bouton du menu principal
