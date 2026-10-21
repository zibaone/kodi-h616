# Niveau 2 — élagage des paquets d'infrastructure du profil kiosque.
#
# Volontairement séparé de `overlays.default` (niveau 1, appliqué d'office) :
# ces entrées touchent des paquets **système**. Un importateur tiers qui les
# prendrait sans le savoir perdrait le plugin GStreamer de pipewire, l'audio
# Bluetooth ou le XWayland de son compositeur. Ici, c'est opt-in.
#
#   overlays = [ nix-v4l2-request.overlays.default
#                nix-v4l2-request.overlays.kiosk ];
#
# L'intérêt n'est pas la propreté : c'est que la CI construise **exactement**
# ces dérivations. Sans ça, un trim côté image (mesa, pipewire) change des
# chemins de store qu'aucun cache ne contient, et il faut les recompiler sous
# émulation — 1 h 30 pour un mesa.
final: prev: {
  # XWayland est inutile quand le compositeur n'affiche qu'un client Wayland
  # (cage + kodi) : retire xwayland, libdecor et gtk+3 de sa chaîne (~75 Mio).
  wlroots_0_20 = prev.wlroots_0_20.override { enableXWayland = false; };

  # v4l-utils : les CLI (v4l2-ctl, v4l2-compliance) restent, les deux GUI
  # (qv4l2, qvidcap) tombent. Sans ça, mesa → libdisplay-info → v4l-utils →
  # qt5compat tire tout Qt 6 dans l'image, pour des fenêtres que personne
  # n'ouvre dans un kiosque.
  v4l-utils = prev.v4l-utils.override { withGUI = false; };

  # ffmpeg embarqué par pipewire : les encodeurs ne servent jamais en lecture
  # seule (x265 ~24 Mio, x264, libvpx, libaom, svt-av1 ~45 Mio au total).
  ffmpeg-headless = prev.ffmpeg-headless.override {
    withX264 = false;
    withX265 = false;
    withVpx = false;
    withAom = false;
    withSvtav1 = false;
    withRav1e = false;
  };

  # pipewire : les plugins inutiles au kiosque sortent —
  #  * plugin GStreamer (aucune app gst) → gst-plugins-base + gstreamer ;
  #  * bluez5 (→ bluez → obexd → libical → icu4c ~52 Mio) : le service
  #    bluetooth n'est pas activé — ré-élargir pour de l'audio BT ;
  #  * libcamera (→ son plugin gst) ; les webcams UVC passent par spa-v4l2.
  pipewire = prev.pipewire.overrideAttrs (old: {
    mesonFlags = map (
      f:
      if
        prev.lib.hasSuffix "=enabled" f
        && prev.lib.any (o: prev.lib.hasPrefix o f) [
          "-Dgstreamer="
          "-Dgstreamer-device-provider="
          "-Dlibcamera="
          "-Dbluez5="
          "-Dbluez5-backend-"
        ]
      then
        (prev.lib.removeSuffix "=enabled" f) + "=disabled"
      else
        f
    ) old.mesonFlags;
    buildInputs = builtins.filter (
      p:
      let
        n = prev.lib.getName p;
      in
      !(prev.lib.hasPrefix "gst" n) && n != "libcamera" && n != "bluez"
    ) old.buildInputs;
  });
}
