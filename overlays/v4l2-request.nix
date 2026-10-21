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

  # libavif : kodi ne fait que décoder l'AVIF (dav1d) ; l'encodeur aom
  # (~8 Mo) n'est jamais utilisé.
  libavif = prev.libavif.overrideAttrs (old: {
    cmakeFlags = map (
      f: if f == "-DAVIF_CODEC_AOM=SYSTEM" then "-DAVIF_CODEC_AOM=OFF" else f
    ) (old.cmakeFlags or [ ]);
    propagatedBuildInputs = builtins.filter (
      p: final.lib.getName p != "libaom"
    ) (old.propagatedBuildInputs or [ ]);
    doCheck = false;
  });

  # Pillow (via kodi.pythonPackages) : sa suite AVIF encode et exige aom,
  # retiré ci-dessus. On ne désélectionne que ce fichier de tests.
  python3Packages = prev.python3Packages.overrideScope (
    _pyself: pysuper: {
      pillow = pysuper.pillow.overrideAttrs (old: {
        disabledTestPaths = (old.disabledTestPaths or [ ]) ++ [
          "Tests/test_file_avif.py"
        ];
      });
    }
  );
}
