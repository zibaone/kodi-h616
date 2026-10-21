# Poids et optimisations

Ce que pèsent réellement `ffmpeg-v4l2request` et `kodi`, quels leviers sont
appliqués, lesquels ne le sont pas et pourquoi.

Les chiffres marqués **mesuré** viennent d'un run CI (`ubuntu-24.04-arm`) ou
d'une mesure locale ; ceux marqués **estimé** sont des ordres de grandeur à
confirmer.

## Comment mesurer (et le piège)

`nix path-info -S` donne la **fermeture** d'un chemin : le paquet plus toutes
ses dépendances. `-rS` liste chaque chemin *avec sa propre fermeture* — les
additionner compte les mêmes paquets des dizaines de fois.

```bash
# FAUX : 31,71 Gio pour kodi (somme de fermetures imbriquées)
nix path-info -rS .#packages.aarch64-linux.kodi | awk '{s+=$2} END {print s}'

# JUSTE : la fermeture de la sortie « out »
nix path-info -S .#packages.aarch64-linux.kodi

# Voir ce qui pèse vraiment (taille propre de chaque chemin)
nix path-info --json -r /nix/store/…-kodi-21.3 \
  | jq -r '.[] | "\(.narSize/1048576|floor)\t\(.path)"' | sort -nr | head -20
```

Deux fermetures ne s'additionnent jamais : celle de `kodi` contient déjà les
libs de ffmpeg. Ce qui compte pour une image, c'est l'**union**.

## État mesuré

| sortie | fermeture | mesure |
|---|---|---|
| `kodi-21.3` | 1 304,7 Mio | CI, aarch64, avant retrait de SDL |
| `ffmpeg-6.1.6-bin` | 1 115,4 Mio | idem — dominé par la chaîne SDL |
| `mesa-26.0.1` | 1 002 Mio (253 Mio sur disque) | local, x86 |

Détail de la fermeture de ffmpeg avant correction — tout ça pour `ffplay` :

```
1010 Mio  sdl2-compat → sdl3 → zenity → libadwaita → GTK4
```

## Leviers appliqués

| levier | où | gain | mesure |
|---|---|---|---|
| encodeurs ffmpeg désactivés (`x264`, `x265`, `libvpx`, `libaom`, `svt-av1`, `rav1e`) | `flake.nix` (`mkFFmpeg`) | ~70 Mio | estimé |
| `withSdl2 = false`, `buildFfplay = false` | `flake.nix` | ~800–900 Mio de fermeture | mesuré : plus aucune entrée `sdl3`/`zenity`/`libadwaita` dans le drv |
| `kodi` sans `bluez`, `libplist`, `lirc` | `pkgs/kodi` | ~10 Mio | estimé |
| `mesa-demos` → stub | `overlays/v4l2-request.nix` | quelques Mio | estimé |
| `libdecor` sans plugin GTK | idem | ~42 Mio (`gtk+3`) | estimé |
| `cwiid` sans `wmgui` | idem | ~27 Mio (`gtk+2`) | estimé |
| `libavif` sans aom | idem | ~8 Mio | estimé |
| Pillow sans test AVIF | idem | — (correction de build) | — |

## Leviers non appliqués, et pourquoi

**`pipewire` élagué** (gstreamer, bluez5, libcamera) : c'est un service système,
pas une dépendance de kodi. Le couper dans un overlay public retirerait l'audio
Bluetooth et le support des webcams à quiconque le consomme. Le profil kiosque
le fait chez lui.

**`wlroots` sans XWayland** : ne concerne que `cage`, absent de ce dépôt.

**`mesa` sans LLVM (~700 Mio)** : le prochain gros levier, mais il faut savoir
quel driver GPU la cible utilise réellement. Sur H618 (Mali G31) c'est
`panfrost`, donc LLVM ne sert qu'au rendu logiciel de secours (`llvmpipe`).
Le couper signifie : si le GPU n'est pas exposé au client, plus aucun rendu.
À décider sur matériel, pas à l'aveugle.

**Dépendances de temps de build** (`rustc` 1,0 Gio, `clang` 0,85, `llvm` 0,53) :
elles n'entrent pas dans l'image. `rustc` vient de
`switch-to-configuration` (vérifié par `nix why-depends`). Utile seulement pour
le disque d'un builder à froid.

## Effet de bord connu

L'override `libavif` (aom désactivé) n'est pas confiné à kodi : `ffmpeg-headless`
8.1 lie aussi libavif, donc son drv change, **et pipewire avec lui** (il utilise
ffmpeg-headless dans ses plugins SPA). Constaté par comparaison des `inputDrvs` :
seul `ffmpeg-headless` diffère, tout le reste est identique.

Conséquence en CI : le run reconstruit pipewire (~20 min) même quand on ne touche
qu'à kodi. À corriger en surchargeant `libavif` **dans kodi** plutôt qu'au niveau
global, pour que l'overlay reste non invasif pour les consommateurs.

## Ce qui va dans une image

Union des fermetures + systemd + noyau + firmware, compressée en zstd.

| | GiB |
|---|---|
| somme naïve des deux fermetures | 2,4 |
| union après retrait de SDL | ~1,4 (dont ~1,0 de mesa/LLVM) |
| système complet décompressé | 2,5–3,5 (estimé) |
| `.img.zst` attendu | 1,2–1,5 (estimé) |

Les deux dernières lignes seront remplacées par des mesures dès qu'une image
aarch64 sera construite.
