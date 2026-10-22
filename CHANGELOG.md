# Changelog

Toutes les évolutions notables de `nix-v4l2-request` sont consignées ici.

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et le
versionnage suit [SemVer](https://semver.org/lang/fr/).

Le contrat vérifié en CI porte sur la **construction** des paquets et sur le
contrat hwaccel (`avcodec_get_hw_config`) ; le décodage sur H618 réel n'est
toujours pas mesuré (voir le README, § État vérifié).

## [Unreleased]

## [0.1.0] - 2026-10-22

Première version étiquetée. Base : Kodi 21.3, FFmpeg 6.1.6 + série LibreELEC
`v4l2-request`, nixpkgs `cd4ea8d57de16f4810bc5f14207bac45fbf19f67`.

### Added

- `packages.<system>.kodi-kiosk` : le même Kodi, lié aux paquets système
  élagués de `overlays.kiosk`. Une image qui applique les deux overlays
  n'embarque plus qu'une seule copie de pipewire au lieu de deux
  (`9mcgjgi4…` 674 Mio contre `fmr41nr3…` 525 Mio, 149 Mio de chemins uniques
  avant correction).
- `checks.<system>.formatting` : `nixfmt --check` sur `flake.nix`,
  `overlays/*.nix` et `pkgs/*/default.nix`, exécuté par `nix flake check`.
- `pkgs/kodi/patches/0002-linux-default-useprimedecoder.patch`, avec un
  `postPatch` qui vérifie la valeur finale dans `system/settings/linux.xml`.
- CI : déclenchement sur `pull_request`, `concurrency` (annule le run précédent
  sur la même réf), job `gate-x86_64` sur runner x86 natif.
- CI : contrôle de narinfo après le push Cachix. `cachix-action` a déjà annoncé
  « Pushed » des chemins qu'il n'envoyait pas (404 vérifiés sur
  `havenos.cachix.org`) ; le badge vert ne suffit pas.
- `CHANGELOG.md`.

### Changed

- `checks.<system>.kiosk-closure` construit désormais `cage` et `wireplumber`,
  et plus `sdl3`. `cage` est le compositeur que l'image lance et son narinfo
  était absent du cache (404) ; `wireplumber` manquait aussi alors qu'il est
  dans la fermeture d'exécution ; `sdl3` n'apparaît dans aucune fermeture
  d'image (`withSdl2 = false`) et était donc reconstruit à chaque build.
- `overlays/v4l2-request.nix` ne surcharge plus `libavif` ni
  `python3Packages.pillow`. Kodi 21.3 ne lie pas libavif (zéro occurrence dans
  sa fermeture), et l'override fuyait par une chaîne de documentation :
  `libavif → gd → graphviz → wayland → wayland-protocols → mesa,
  vulkan-loader → ffmpeg-headless → pipewire`. Mesure : `pipewire` revient au
  dérivé exact de nixpkgs.
- README : sections sur `videoplayer.useprimedecoder`, sur `kodi-kiosk`, et
  inventaire exact de ce que construit `kiosk-closure`.

### Fixed

- `videoplayer.useprimedecoder` était `false` (défaut amont) : sans lui,
  `CDVDVideoCodecDRMPRIME::Create()` renvoie `nullptr`, le décodeur n'est jamais
  instancié et Kodi décode en CPU sans le signaler. Le backport xbmc#25467 et le
  hwaccel v4l2-request étaient donc inopérants sur une installation par défaut.
- Le gate `hwconfig` x86_64 était annoncé « passe » sur la foi d'une mesure
  locale : aucune CI ne le construisait. Il a maintenant son job.
- `nixfmt --check` échouait sur `overlays/v4l2-request.nix`,
  `pkgs/ffmpeg-v4l2request/default.nix` et `pkgs/kodi/default.nix`.
- `master` n'était protégé par aucun statut requis.

[Unreleased]: https://github.com/zibaone/nix-v4l2-request/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/zibaone/nix-v4l2-request/releases/tag/v0.1.0
