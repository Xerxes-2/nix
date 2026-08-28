{ pkgs, ... }:
let
  # Open (MIT) reverse-engineered firmware for AVD, Apple's video decode block.
  # Without it the in-kernel `avd` driver bails out at probe:
  #
  #   avd 287080000.avd: Direct firmware load for apple/avd-fw-v3-t1.bin failed with error -2
  #   avd 287080000.avd: probe with driver avd failed with error -2
  #
  # which is why /dev/video0 is apple-isp (the webcam) and nothing else. The
  # blob is not extracted from macOS - it is built from source here. t6020
  # (M2 Pro) wants v3-t1; the other variants cost nothing and keep this file
  # valid if the machine ever changes.
  avd-fw = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "avd-fw";
    version = "0-unstable-2026-07-26";

    src = pkgs.fetchFromGitHub {
      owner = "AsahiLinux";
      repo = "avd-fw";
      rev = "5e34aca83906f12ef3c2bfacb6712797de4bb7d5";
      hash = "sha256-cq/gOgmbCg5IX0GSiS7Z5lBhpursB1Num8LSANw5fpI=";
    };

    nativeBuildInputs = [
      pkgs.clang
      pkgs.llvmPackages.bintools
    ];

    # The firmware runs on the AVD's Cortex-M3, so this is a freestanding
    # cross build. Nix's cc-wrapper injects -fzero-call-used-regs=used-gpr,
    # which clang rejects for thumbv7m-unknown-none-eabi.
    hardeningDisable = [ "all" ];

    # "<AVD_VER> <AVD_TIER>", mirroring avd_variants in the upstream meson.build.
    variants = [
      "2 0"
      "3 0"
      "3 1"
      "4 0"
      "5 0"
      "5 1"
    ];

    buildPhase = ''
      runHook preBuild
      mkdir -p staging
      for v in ${builtins.concatStringsSep " " (map (v: "\"${v}\"") finalAttrs.variants)}; do
        set -- $v
        make AVD_VER="$1" AVD_TIER="$2"
        # `make clean` would wipe the earlier variants, so stage each blob and
        # drop the build dir instead - the pad size is derived from VER/TIER.
        mv "build/avd-fw-v$1-t$2.bin" staging/
        rm -rf build
      done
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm444 -t "$out/lib/firmware/apple" staging/*.bin
      runHook postInstall
    '';

    meta = {
      description = "Firmware for the Apple AVD video decoder";
      homepage = "https://github.com/AsahiLinux/avd-fw";
      license = pkgs.lib.licenses.mit;
      platforms = pkgs.lib.platforms.linux;
    };
  });

  # AVD is a stateless decoder, so it speaks the V4L2 Stateless API. Desktop
  # software speaks VA-API and essentially nothing else - V4L2 Stateless never
  # got adopted outside embedded, so mpv/Firefox/ffmpeg cannot drive AVD
  # directly. This is megi's VA-API -> V4L2 Stateless translation layer (the
  # revival of Bootlin's abandoned one), in the fork the Asahi folks use.
  libva-v4l2-request = pkgs.stdenv.mkDerivation {
    pname = "libva-v4l2-request";
    version = "1.2-unstable-2026-07-16";

    src = pkgs.fetchFromGitHub {
      owner = "sofus13";
      repo = "libva-v4l2_request";
      rev = "cfe6c2ab1b5346d1e973625d01b79fcb648fcf5e";
      hash = "sha256-qN/IEte/kFd2Zi9DSPTYSehCkE3MenV9a8n0LBXuICQ=";
    };

    nativeBuildInputs = with pkgs; [
      meson
      ninja
      pkg-config
    ];
    buildInputs = with pkgs; [
      libva
      libdrm
    ];

    # Upstream defaults driverdir to libva's own pkg-config value, which is an
    # absolute path into libva's store output and thus unwritable. Install into
    # our own $out/lib/dri instead - hardware.graphics.extraPackages merges that
    # into /run/opengl-driver/lib/dri, which is the first entry in the driverdir
    # list nixpkgs' libva is built with.
    mesonFlags = [ "-Ddriverdir=${placeholder "out"}/lib/dri" ];

    meta = {
      description = "VA-API backend for V4L2 stateless decoders, used here to reach AVD";
      homepage = "https://github.com/sofus13/libva-v4l2_request";
      license = pkgs.lib.licenses.gpl3Only;
      platforms = pkgs.lib.platforms.linux;
    };
  };
in
{
  hardware.firmware = [ avd-fw ];

  hardware.graphics.extraPackages = [ libva-v4l2-request ];

  # libva picks its driver from the DRM driver name of the render node, which
  # here is "asahi" - there is no asahi_drv_video.so and never will be, so
  # without this every VA-API client silently falls back to software. Nothing
  # else on this machine ships a VA-API driver, so pinning it globally costs
  # nothing. (It does leak into the muvm/FEX guest, where the name resolves to
  # nothing and VA-API init fails - harmless, games use Vulkan, not VA-API.)
  environment.sessionVariables.LIBVA_DRIVER_NAME = "v4l2_request";

  # vainfo, for checking the above actually took.
  environment.systemPackages = [ pkgs.libva-utils ];
}
