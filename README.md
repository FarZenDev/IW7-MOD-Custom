# IW7-MOD Custom — EasyMP

Surcouche « jouer entre amis » pour [iw7-mod](https://github.com/auroramod/iw7-mod) :
système d'amis, invitations automatiques, ouverture de port (UPnP), présence P2P,
lancement sans Steam, et interface in-game (menu **JOUER ENTRE AMIS** en MP et Zombies).

## Contenu

- `data/cdata/ui_scripts/EasyMP/` — menu amis in-game
- `data/cdata/ui_scripts/MainMenu/` — boutons ajoutés aux menus MP et Zombies
- `src/client/component/` — composants C++ (easymp, upnp, cdata_sync)
- `README-EASYMP.md` — documentation complète
- `installer-easymp.bat` — installeur

## Mise à jour automatique

Le composant `cdata_sync` télécharge le contenu de `data/cdata/` de ce dépôt vers
`%LOCALAPPDATA%\auroramod\iw7-mod\cdata` à chaque lancement du jeu. Poussez vos
modifications de scripts ici, elles arrivent chez vos amis au prochain lancement.
