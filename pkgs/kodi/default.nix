# Kodi 21.3 patché pour le décodeur stateless V4L2 Request (sunxi H616/H618).
#
# Deux adaptations par rapport à `kodi-wayland` de nixpkgs :
#  - `ffmpeg` remplacé par le paquet v4l2-request (voir ../ffmpeg-v4l2request) ;
#  - backport xbmc#25467 (mergée dans master, +29/−25) : `FindHWConfig()`
#    n'exige plus `device_type == AV_HWDEVICE_TYPE_DRM`, il accepte toute
#    hw config HW_DEVICE_CTX dont le pix_fmt est DRM_PRIME.
#
# Sur 21.3 + la série ffmpeg 6.0/6.1 (device_type = DRM) le comportement est
# identique SANS ce patch ; il est là pour la variante ffmpeg 7+, où le
# device_type devient V4L2REQUEST (série LibreELEC master) — sans lui, Kodi
# 21.3 retomberait silencieusement sur le décodage CPU.
{
  lib,
  kodi-wayland,
  ffmpeg-v4l2request,
  sambaSupport ? false,
}:
(kodi-wayland.override {
  inherit sambaSupport;
  ffmpeg = ffmpeg-v4l2request;
}).overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [
    ./patches/0001-DVDVideoCodecDRMPRIME-v4l2request-hwdevice.patch
  ];

  # Élagage : bluez (télécommandes BT passent par le noyau/rc-core),
  # libplist (support iOS/USB → openssl ~6 Mo), lirc (les télécommandes
  # passent par rc-core/input, pas par le daemon lirc).
  buildInputs = builtins.filter (
    p:
    let
      n = lib.getName p;
    in
    n != "bluez" && n != "libplist" && n != "lirc"
  ) old.buildInputs;
})
