# Optimisations reprises du profil HavenOS `kodi-standalone`.
#
# Niveau 1 — ne touchent QUE l'arbre de dépendances de kodi. Aucun service
# système, aucun paquet d'infrastructure : un utilisateur qui consomme
# `packages.kodi` obtient le même kodi, en plus léger.
#
# Ce qui n'est *pas* ici, volontairement (niveau 2, réservé au profil kiosque) :
#  - pipewire élagué (gstreamer, bluez5, libcamera) : c'est un service système,
#    le couper globalement retirerait l'audio Bluetooth à tout le monde ;
#  - wlroots sans XWayland : ne concerne que cage, absent de ce flake ;
#  - ffmpeg-headless : lié à pipewire, pas à kodi.
#
# Chaque entrée indique le gain mesuré dans le profil HavenOS.
#
# Il n'y a plus d'entrée `libavif` ni `python3Packages.pillow` : kodi 21.3 ne
# lie pas libavif (0 occurrence dans sa fermeture, ni aom). Les deux overrides
# ne servaient à rien et fuyaient par une chaîne de *documentation* :
#   libavif → gd → graphviz(-nox) → wayland → wayland-protocols
#           → mesa, vulkan-loader → ffmpeg-headless → pipewire
# soit neuf paquets d'infrastructure reconstruits (mesa en tête, 1 h 30 sous
# émulation) pour zéro octet gagné dans l'image. Mesure : sans eux, `pipewire`
# revient exactement au drv de nixpkgs (`71mvxq2s…` au lieu de `wxq58hhx…`).
#
# Corollaire : ne jamais surcharger un paquet feuille sous prétexte qu'il est
# « dans l'arbre de kodi » — vérifier d'abord qu'il y est vraiment.
final: prev: {
  # outil de test OpenGL, tiré par kodi sans être utilisé à l'exécution.
  mesa-demos = prev.runCommand "mesa-demos-stub" { } ''
    mkdir -p $out/bin
    echo "mesa-demos retiré (nix-v4l2-request) — retirer l'overlay pour l'avoir" > $out/README
  '';

  # libdecor : décorations Wayland côté client. Le backend cairo suffit en
  # plein écran ; le plugin GTK est le seul à tirer gtk+3 (~42 Mo).
  libdecor = prev.libdecor.overrideAttrs (old: {
    mesonFlags = (old.mesonFlags or [ ]) ++ [ "-Dgtk=disabled" ];
  });

  # cwiid (Wiimote) : seul wmgui (GUI GTK2, ~27 Mo) est inutile.
  # wminput/lswm/libcwiid restent intacts.
  cwiid = prev.cwiid.overrideAttrs (old: {
    postFixup = (old.postFixup or "") + ''
      rm -f $out/bin/wmgui
    '';
  });
}
