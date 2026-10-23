# Fenêtrage de Kodi : GBM direct plutôt que Wayland + cage

**Statut** : décision appliquée (Kodi 21.3, image kiosque H616/H618).
**Décideur** : contrainte technique — le compositeur ne peut pas afficher Kodi.

## Symptôme

Kodi démarre, initialise son renderer, joue le son de démarrage, répond au
JSON-RPC, reçoit ses *frame callbacks* Wayland et attache des buffers — et
l'écran reste noir. Aucune erreur fatale dans `kodi.log`.

## Cause racine (amont)

Kodi appelle `xdg_toplevel.set_fullscreen` **avant** le premier
`wl_surface.commit` de sa surface. Un compositeur conforme au protocole
(`xdg-shell`) ignore cette requête ; Kodi gère mal ce refus, ne reçoit jamais de
`configure` exploitable et ne dessine plus rien.

- <https://github.com/xbmc/xbmc/issues/20629> — « [wayland] black screen when
  starting fullscreen », analyse et contournement (démarrer fenêtré).
- <https://github.com/xbmc/xbmc/issues/27882> — même défaut via gamescope ;
  correctif proposé : déplacer `Initialize()` avant `SetFullScreen()`.

Ce n'est donc ni le GPU, ni le décodeur, ni le format de buffer.

## Preuves mesurées (Orange Pi Zero 3, H616)

| Test | Résultat |
| --- | --- |
| Client EGL 1920x1080, 8 bits | affiché (rouge) |
| Client EGL 3840x2160, `AR30` 10 bits + modificateur AFBC `0x08100000/0x00000001` | affiché (rouge plein écran) |
| Client `wl_shm` ARGB8888 | affiché (vert) |
| Kodi sous **cage** (wlroots) | noir |
| Kodi sous **weston 15.0.1** (shell kiosk) | noir |
| Trame composée, lue sur le plan qui scanne (`kmsgrab -plane_id`) | noir, sauf une bordure d'1 px à `x=3830` et `y=2117` |
| Taille négociée par Kodi | `3830x2117` au lieu de `3840x2160` |
| Kodi en **GBM direct** | interface affichée, `GLES 3.1 Mesa`, `Mali-G31 (Panfrost)` |

La bordure d'un pixel est la signature du défaut : la surface *est* compositée,
à sa taille, avec un contenu vide. Deux compositeurs différents donnant le même
noir, la faute est dans le client.

## Décision

Kodi prend directement la main sur le nœud DRM : plus de compositeur.

- paquet : `kodi-gbm` de nixpkgs (et non `kodi-wayland`), patché ici pour le
  décodeur V4L2 Request ;
- lanceur : `kodi --standalone --windowing=gbm` ;
- service : unité `kodi-gbm` sur `tty1` (voir le profil HavenOS
  `modules/profiles/kodi-standalone.nix`).

## Ce qu'on gagne

- Une couche en moins : plus de wlroots, plus de repli logiciel, moins de RAM
  et de CPU, pas de latence de composition.
- Plus de négociation `xdg-shell` à rater : le défaut amont devient inopérant.
- C'est le chemin des appliances de référence (LibreELEC) : code éprouvé.

## Ce qu'on perd

1. **Aucun autre client graphique ne peut partager l'écran.** Kodi est maître du
   nœud DRM et du VT : pas de second client Wayland/X11, pas de surcouche, pas
   de lanceur. Un besoin de ce type impose de revenir à un compositeur.
2. **Pas de mode fenêtré.** Kodi occupe toujours l'écran — sans conséquence pour
   un kiosque, mais on perd le contournement « démarrer fenêtré » utile au
   diagnostic.
3. **Un point d'observation en moins.** Avec cage, un écran noir se départageait
   entre « le client n'a rien dessiné » et « le compositeur n'a rien présenté ».
   Ici, l'unique preuve est le log de Kodi plus l'état DRM.
4. **Entrée en direct.** Kodi lit `/dev/input` lui-même : l'utilisateur doit être
   dans le groupe `input` (c'est le cas dans le profil). Avec cage, le
   compositeur lisait et transmettait.
5. **La CI construit encore `cage`** via `kiosk-closure`, alors que l'image ne
   l'utilise plus : temps de CI et closure à rogner quand ce sera stabilisé.

## Revenir à cage (si l'amont corrige le défaut)

Le correctif amont est en revue (<https://github.com/xbmc/xbmc/pull/27894>,
« Move Initialize() before SetFullScreen() »). Quand la version de Kodi retenue
l'inclut, la bascule ne demande **aucune modification du paquet** : il expose
déjà les deux fenêtrages (argument `windowing`, attributs `kodi-wayland` et
`kodi-kiosk-wayland`).

1. Dans le profil HavenOS, consommer `kodi-kiosk-wayland` au lieu de
   `kodi-kiosk`, retirer `--windowing=gbm` du lanceur, et rétablir
   `services.cage = { enable = true; user = "kodi"; program = kodiLauncher; }`
   avec `WLR_RENDERER_ALLOW_SOFTWARE` et `WLR_LIBINPUT_NO_DEVICES` sur l'unité
   (board dont le GPU peut échouer au probe) — voir l'historique du profil avant
   le commit « kiosque GBM direct ».
2. Réintégrer `cage` et `wlroots` dans `checks.kiosk-closure` : ils en sont
   sortis avec la bascule, et sans eux la CI ne mettra pas en cache ce dont
   l'image a besoin (c'est mesuré : 1 h 30 de `mesa` sous émulation).
3. **Vérifier avant de flasher**, avec le test qui a servi ici : lancer un client
   EGL de la taille et du format de Kodi sous le compositeur (il doit s'afficher),
   puis Kodi. Si Kodi reste noir alors que le client s'affiche, le correctif
   n'est pas dans la version utilisée — ne pas déployer.

La variante Wayland n'est pas compilée par la CI (elle doublerait le build de
Kodi) mais son évaluation est vérifiée par `checks.kodi-wayland-eval` : elle ne
peut pas pourrir en silence.

Ne pas rebasculer « pour l'élégance » : cage ajoute une couche qui n'apporte rien
tant qu'aucun second client n'est nécessaire.
