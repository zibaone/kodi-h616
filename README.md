# nix-v4l2-request

Paquets Nix pour le décodage matériel **stateless V4L2 Request** : FFmpeg 6.1
patché, et Kodi 21.3 qui l'utilise.

Écrit et validé sur Allwinner H616/H618 (Orange Pi Zero 3, driver `cedrus`),
mais rien ici n'est propre à ce SoC : la même série de patches couvre `rkvdec`
(Rockchip), `hantro` (i.MX8M) et `meson-vdec`. Le nom suit l'API et la série
amont, pas la carte.

Nixpkgs ne fournit que `withV4l2` (libv4l2) et `withV4l2M2m` (API *stateful*).
Les décodeurs stateless passent par la **Request API**, dont le support n'existe
qu'en aval de FFmpeg. Ce dépôt vendorise les deux pièces nécessaires :

| pièce | origine | ce qu'elle fait |
|---|---|---|
| `pkgs/ffmpeg-v4l2request` | jeu LibreELEC 12 (`ffmpeg-001-v4l2-request.patch`, 170 Ko), rebasé sur FFmpeg 6.1.6 | ajoute `--enable-v4l2-request` et les hwaccels `h264_v4l2request` / `hevc_v4l2request` |
| `pkgs/kodi` | xbmc#25467 (+29/−25, mergée dans master), backporté sur 21.3 | `FindHWConfig()` n'exige plus `device_type == AV_HWDEVICE_TYPE_DRM` |

Le second patch est indispensable pour la variante FFmpeg 7 (série LibreELEC
master), où le `device_type` devient `V4L2REQUEST` ; avec la série 6.x il est
sans effet de bord, Kodi accepte déjà `DRM`.

## Utilisation

```bash
nix build .#kodi                    # kodi-wayland + ffmpeg v4l2-request
nix build .#ffmpeg-v4l2request      # la couche ffmpeg seule
nix build .#checks.$(nix eval --impure --raw --expr builtins.currentSystem).hwconfig
```

Le *gate* `hwconfig` est un test C qui interroge `avcodec_get_hw_config()` et
exige, pour h264 **et** hevc : `pix_fmt = DRM_PRIME`, méthode `HW_DEVICE_CTX`,
`device_type = DRM`. C'est exactement le contrat que `FindHWConfig()` de Kodi
21.3 vérifie. `ffmpeg -hwaccels` ne peut pas servir de gate : il liste les
`AVHWDeviceType`, et `V4L2REQUEST` n'existe que dans la série 7+.

## Élagage

Deux niveaux, séparés volontairement.

**Niveau 1 — appliqué par défaut** (`overlays/v4l2-request.nix`), ne touche que
l'arbre de kodi : `mesa-demos` remplacé par un stub, `libdecor` sans le plugin
GTK (→ pas de `gtk+3`), `cwiid` sans `wmgui` (GTK2), `libavif` sans l'encodeur
aom, Pillow sans son test AVIF. Les encodeurs ffmpeg sont désactivés (`x264`,
`x265`, `libvpx`, `libaom`, `svt-av1`, `rav1e`) : jamais utilisés en lecture,
~70 Mo gagnés, décodage complet (AV1 via `dav1d`). Kodi perd en plus `bluez`,
`libplist` et `lirc`.

**Niveau 2 — non inclus**, car ce sont des services système et non des paquets
de kodi : `pipewire` élagué (gstreamer, bluez5, libcamera), `wlroots` sans
XWayland, `ffmpeg-headless`. Les couper ici retirerait l'audio Bluetooth et le
support des webcams à quiconque consomme l'overlay. Le profil kiosque (cage +
pipewire) les active chez lui.

## État

- `ffmpeg` + `kodi` se construisent pour `aarch64-linux` (dérivations évaluées,
  builds mesurés en CI) ;
- le gate `hwconfig` passe ;
- **le décodage n'est pas prouvé sur matériel** : cela demande un H618 réel,
  `v4l2-ctl --list-formats-out`, `dmesg` du VPU et `kodi.log`. Tant que ce n'est
  pas fait, ce dépôt ne prétend pas que le hwdec fonctionne.

## Provenance et licences

- patch FFmpeg : LibreELEC (`libreelec-12.0`, GPL-2.0), rebasé 6.0 → 6.1 ;
- patch Kodi : Team Kodi, PR #25467 (GPL-2.0) ;
- le reste : MIT.

## CI

`.github/workflows/build.yml` construit les deux paquets sur un runner ARM natif
(`ubuntu-24.04-arm`), monte `/mnt` (74 Go) sur `/nix` pour la fermeture, et
publie les durées ainsi que les tailles réelles dans le résumé du run.
