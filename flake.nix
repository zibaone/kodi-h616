{
  description = "Kodi 21.3 + FFmpeg v4l2-request : hwaccel stateless V4L2 pour sunxi H616/H618";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/cd4ea8d57de16f4810bc5f14207bac45fbf19f67";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # Élagage des encodeurs : jamais utilisés en lecture (x265 ~24 Mo, x264,
      # libvpx, libaom, svt-av1 ~45 Mo au total). Le décodage reste intact,
      # AV1 compris (dav1d).
      mkFFmpeg =
        pkgs:
        pkgs.callPackage ./pkgs/ffmpeg-v4l2request {
          ffmpeg_6 = pkgs.ffmpeg_6.override {
            withX264 = false;
            withX265 = false;
            withVpx = false;
            withAom = false;
            withSvtav1 = false;
            withRav1e = false;
          };
        };
    in
    {
      packages = forAll (pkgs: {
        ffmpeg-v4l2request = mkFFmpeg pkgs;
        kodi = pkgs.callPackage ./pkgs/kodi {
          ffmpeg-v4l2request = mkFFmpeg pkgs;
        };
        default = self.packages.${pkgs.system}.kodi;
      });

      # Contrat hwaccel : h264 et hevc exposent DRM_PRIME / HW_DEVICE_CTX /
      # device_type DRM. C'est ce que FindHWConfig() de Kodi 21.3 exige.
      checks = forAll (pkgs: {
        hwconfig = self.packages.${pkgs.system}.ffmpeg-v4l2request.passthru.tests.hwconfigTest;
      });

      formatter = forAll (pkgs: pkgs.nixfmt-rfc-style);
    };
}
