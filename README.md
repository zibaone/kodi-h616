# kodi-h616

Kodi 21.3 avec décodage matériel **stateless V4L2 Request** sur les SoC Allwinner
H616/H618 (Orange Pi Zero 3, Zero 2W, T507…).

Nixpkgs ne fournit que `withV4l2` (libv4l2) et `withV4l2M2m` (API *stateful*). Le
décodeur du H616/H618 — driver `cedrus` — passe par la **Request API**, dont le
support n'existe qu'en aval de FFmpeg. Ce dépôt vendorise les deux pièces
nécessaires :

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

Les encodeurs sont désactivés (`x264`, `x265`, `libvpx`, `libaom`, `svt-av1`,
`rav1e`) : jamais utilisés en lecture, ~70 Mo gagnés. Le décodage reste complet,
AV1 compris (`dav1d`). Kodi perd en plus `bluez`, `libplist` et `lirc` — les
télécommandes passent par `rc-core`/input, pas par le daemon lirc.

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
