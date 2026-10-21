# nix-v4l2-request

Paquets Nix pour le décodage matériel **stateless V4L2 Request** : FFmpeg 6.1
patché, et Kodi 21.3 qui l'utilise.

> **Statut : expérimental.** Les paquets se construisent et le contrat hwaccel est
> vérifié en CI, mais **le décodage n'a pas été validé sur matériel**. Rien ici ne
> doit être lu comme « le hwdec fonctionne » avant les mesures listées en § État.

## Périmètre

Ce dépôt fournit **deux paquets**, et rien d'autre :

- `ffmpeg-v4l2request` — FFmpeg 6.1.6 + série LibreELEC `v4l2-request` ;
- `kodi` — `kodi-wayland` 21.3 lié à ce ffmpeg, avec le backport xbmc#25467.

Il ne fournit **ni noyau, ni image, ni module NixOS**. Il ne dépend d'aucun dépôt
de noyau : la compilation n'a besoin que des en-têtes V4L2 de `linux-headers`.
Le noyau n'intervient qu'à l'exécution — driver `cedrus`, `/dev/media0`, API
Request.

Écrit pour Allwinner H616/H618 (Orange Pi Zero 3, driver `cedrus`), mais rien
n'est propre à ce SoC : la même série couvre `rkvdec` (Rockchip), `hantro`
(i.MX8M), `meson-vdec`. Le nom suit l'API amont, pas la carte.

## Pourquoi ces patches

Nixpkgs n'expose que `withV4l2` (libv4l2) et `withV4l2M2m` (API *stateful*). Les
décodeurs stateless passent par la **Request API**, dont le support n'existe
qu'en aval de FFmpeg.

| pièce | ce qu'elle fait |
|---|---|
| `pkgs/ffmpeg-v4l2request` | `--enable-v4l2-request` + hwaccels `h264_v4l2request` / `hevc_v4l2request` |
| `pkgs/kodi` | `FindHWConfig()` accepte `pix_fmt = DRM_PRIME` + `HW_DEVICE_CTX`, sans exiger `device_type == DRM` |

Le second patch est indispensable pour la variante FFmpeg 7 (série LibreELEC
master), où `device_type` devient `V4L2REQUEST` ; avec la série 6.x il est sans
effet de bord, Kodi 21.3 accepte déjà `DRM`.

## Utilisation

```bash
nix build .#kodi                    # kodi-wayland + ffmpeg v4l2-request
nix build .#ffmpeg-v4l2request      # la couche ffmpeg seule
nix build .#checks.$(nix eval --impure --raw --expr builtins.currentSystem).hwconfig
```

## Le gate `hwconfig`

Test C (`pkgs/ffmpeg-v4l2request/test-hwconfig.c`) qui interroge
`avcodec_get_hw_config()` et exige, pour h264 **et** hevc : `pix_fmt =
DRM_PRIME`, méthode `HW_DEVICE_CTX`, `device_type = DRM`. C'est exactement le
contrat que `FindHWConfig()` de Kodi 21.3 vérifie.

`ffmpeg -hwaccels` ne peut pas servir de gate : il liste les `AVHWDeviceType`, et
`V4L2REQUEST` n'existe que dans la série 7+.

## Élagage

Deux niveaux, séparés volontairement. Le détail chiffré et les leviers restants
sont dans [`docs/poids-et-optimisations.md`](docs/poids-et-optimisations.md).

**Niveau 1 — appliqué par défaut** (`overlays/v4l2-request.nix`), ne touche que
l'arbre de kodi : `mesa-demos` remplacé par un stub, `libdecor` sans le plugin
GTK (→ pas de `gtk+3`), `cwiid` sans `wmgui` (GTK2), `libavif` sans l'encodeur
aom, Pillow sans son test AVIF. Les encodeurs ffmpeg sont désactivés (`x264`,
`x265`, `libvpx`, `libaom`, `svt-av1`, `rav1e`) : jamais utilisés en lecture,
décodage complet (AV1 via `dav1d`). `ffplay` et SDL2 sont coupés — inutiles dans
une image kiosque, et ils tiraient GTK4. Kodi perd en plus `bluez`, `libplist`
et `lirc`.

**Niveau 2 — non inclus**, car ce sont des services système et non des paquets
de kodi : `pipewire` élagué (gstreamer, bluez5, libcamera), `wlroots` sans
XWayland, `ffmpeg-headless`. Les couper ici retirerait l'audio Bluetooth et le
support des webcams à quiconque consomme l'overlay.

## État vérifié

| vérification | résultat |
|---|---|
| `nix build .#packages.aarch64-linux.ffmpeg-v4l2request` | construit en CI (runner ARM natif) |
| `nix build .#packages.aarch64-linux.kodi` | construit en CI |
| gate `hwconfig` (h264 + hevc) sur aarch64 | passe : `pix_fmt=drm_prime methods=HW_DEVICE_CTX device_type=drm` |
| gate `hwconfig` sur x86_64 | passe |
| **décodage sur H618 réel** | **non fait** |

Ce qui reste à prouver, et comment :

1. `v4l2-ctl --list-formats-out -d /dev/video*` expose H264 et HEVC ;
2. `dmesg | grep -i -E "cedrus|video-engine"` montre le VPU et le node VE ;
3. `kodi.log` contient la création d'un device hwaccel (`creating … hwdevice
   context`) et non plus « using drm device for av_hwdevice_ctx » ;
4. lecture d'un 1080p H.264 : charge CPU par cœur nettement en dessous de 100 %
   sur les cœurs A53.

Tant que ces quatre points ne sont pas mesurés, ce dépôt ne prétend pas que le
décodage matériel fonctionne.

## Provenance, auteurs, licences

| élément | auteur | source | licence |
|---|---|---|---|
| série FFmpeg `v4l2-request` | projet **LibreELEC** (chaque patch garde la signature de son auteur) | [`LibreELEC.tv` @ `7cf13a1fbde5`](https://github.com/LibreELEC/LibreELEC.tv/blob/7cf13a1fbde5/packages/multimedia/ffmpeg/patches/v4l2-request/ffmpeg-001-v4l2-request.patch), `ffmpeg-001-v4l2-request.patch`, 170 543 octets, `sha256:0f638d58feb19dfd…` | GPL-2.0 |
| rebase 6.0.1 → 6.1.6 | ce dépôt | `pkgs/ffmpeg-v4l2request/patches/0001-v4l2-request-ffmpeg-6.1.6.patch` — le diff source appliqué, suivi des seules adaptations, listées en tête de fichier | GPL-2.0 |
| patch Kodi | **Jonas Karlman** ([@Kwiboo](https://github.com/Kwiboo)), commit `ed324259c8b9` | [xbmc#25467](https://github.com/xbmc/xbmc/pull/25467) « CDVDVideoCodecDRMPRIME: Fix use of v4l2request hwdevice », 1 fichier, +29/−25, mergée le 2024-12-21 | GPL-2.0 |
| `test-hwconfig.c`, flake, overlays, CI | ce dépôt | — | MIT (voir `LICENSE`) |

Aucun patch n'est réécrit de mémoire : le fichier FFmpeg est le diff source
appliqué, la liste des adaptations est en tête du fichier, et l'empreinte du
patch d'origine permet de le vérifier.

## CI

`.github/workflows/build.yml` construit les deux paquets sur un runner ARM natif
(`ubuntu-24.04-arm`), chronomètre chaque étape et publie les tailles réelles
(`nix path-info -S`) dans le résumé du run. Le montage de `/mnt` sur `/nix` est
conditionnel : les runners actuels ont 145 Go sur `/`, le bind ne sert que si
`/mnt` est un volume séparé.
