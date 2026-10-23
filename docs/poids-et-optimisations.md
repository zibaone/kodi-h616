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
| ~~`libavif` sans aom~~ | — | **retiré** : kodi ne lie pas libavif | mesuré : 0 occurrence de `libavif`/`aom`/`pillow` dans la fermeture de kodi |

## Leviers non appliqués, et pourquoi

**`pipewire` élagué** (gstreamer, bluez5, libcamera) : c'est un service système,
pas une dépendance de kodi. Le couper dans un overlay public retirerait l'audio
Bluetooth et le support des webcams à quiconque le consomme. Le profil kiosque
le fait chez lui — et depuis `packages.kodi-kiosk`, il le fait sans payer deux
copies de pipewire dans l'image.

**`wlroots` sans XWayland** : ne concerne que `cage`, que l'image ne lance
plus depuis le passage du kiosque en GBM direct (`docs/fenetrage-kodi-gbm.md`).

**`mesa` sans LLVM (532 Mio mesurés, `llvm-21.1.8-lib`)** : le prochain gros levier, mais il faut savoir
quel driver GPU la cible utilise réellement. Sur H618 (Mali G31) c'est
`panfrost`, donc LLVM ne sert qu'au rendu logiciel de secours (`llvmpipe`).
Le couper signifie : si le GPU n'est pas exposé au client, plus aucun rendu.
À décider sur matériel, pas à l'aveugle.

**Dépendances de temps de build** (`rustc` 1,0 Gio, `clang` 0,85, `llvm` 0,53) :
elles n'entrent pas dans l'image. `rustc` vient de
`switch-to-configuration` (vérifié par `nix why-depends`). Utile seulement pour
le disque d'un builder à froid.

## Effet de bord corrigé : la fuite `libavif`

L'override `libavif` (aom désactivé) n'était pas confiné à kodi — il ne servait
même à rien pour kodi. Mesure : `nix-store -qR` sur la sortie de kodi ne contient
**aucune** entrée `libavif`, `libaom` ni `pillow`. Ce que l'override changeait,
c'était la *documentation* des paquets voisins :

```
libavif → gd → graphviz(-nox) → wayland → wayland-protocols
        → mesa, vulkan-loader → ffmpeg-headless → pipewire
```

soit neuf paquets d'infrastructure reconstruits (et republiés au cache) pour un
paquet que kodi ne lie pas. Vérification : avec l'override retiré,
`pipewire` revient exactement au dérivé de nixpkgs (`71mvxq2s…` au lieu de
`wxq58hhx…`), alors que l'ancienne analyse — « seul `ffmpeg-headless` diffère » —
s'arrêtait au premier niveau et manquait le reste de la chaîne. L'override Pillow
existait uniquement pour faire passer le test AVIF suite à la disparition d'aom :
il tombe avec lui.

Leçon générale : ne jamais surcharger un paquet au motif qu'il est « dans l'arbre
de kodi » sans le vérifier dans la fermeture réelle ; `gd`, `graphviz` et
`wayland` ne sont dans la fermeture de *construction* que comme outillage.

## Ce qui va dans une image

Union des fermetures + systemd + noyau + firmware, compressée en zstd.

Mesuré sur une image `sd-card` aarch64 construite avec ce dépôt (Kodi kiosque,
noyau 7.0.14, systemd 260.5) :

| | GiB | mesure |
|---|---|---|
| fermeture du système (NAR) | **3,61** | `nix path-info -S` sur le toplevel |
| image décompressée | **5,60** | `zstd -l` |
| `.img.zst` | **1,66** | ratio 3,37 — 4 h 57 de build, majoritairement sous qemu |

L'écart entre 3,61 et 5,60 n'est pas du contenu : c'est la partition racine
dimensionnée large (`rootPartitionSize` par défaut). La ramener à « fermeture
+ 512 Mio » ne change rien au système installé et fait tomber l'image autour de
4 Gio décompressé.

### Où sont les octets (mesuré, `narSize` de chaque chemin)

| Mio | chemin | caractère |
|---|---|---|
| 825 | `linux-firmware` complet | ❌ défaut du module de carte, inutile sans Wi-Fi/BT |
| 532 | `llvm-21.1.8-lib` | ❌ tiré par `mesa` (llvmpipe) |
| 261 | `mesa` | ✅ |
| 197 | source nixpkgs | ❌ aucun paquet ne devrait l'embarquer |
| 141 | `deno` | ✅ délibéré (runtime JS exigé par `yt-dlp`) |
| 131 | `python3-3.13` | ✅ (env Kodi + yt-dlp) |
| 75 | `kodi` | ✅ |
| 73 | `systemd` | ✅ structurel |
| 58 | modules noyau | ✅ |
| 57 + 43 | `perl`, `vim` | ❌ héritage d'une base « boîte à outils » |

Trois leviers d'image, non applicables depuis ce dépôt — ils dépendent de
l'hôte qui assemble l'image :

| levier | gain | remarque |
|---|---|---|
| firmware restreint à la carte | ~825 Mio | `hardware.enableRedistributableFirmware` est vrai par défaut |
| `mesa` sans LLVM | ~532 Mio | voir plus haut : à décider sur matériel |
| base de paquets allégée | ~300 Mio | un kit de secours (btrfs, ddrescue, efibootmgr) n'a rien à faire dans une image Kodi sur ext4/ARM |

Reste la limite structurelle : ~300 Mo pour LibreELEC (buildroot, busybox, ni
systemd ni store) contre ~2 Gio pour un NixOS élagué. La comparaison vaut pour
le téléchargement, pas pour la conception.
