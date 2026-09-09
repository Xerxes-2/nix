{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  display = import ./display.nix { };

  # Hardware video decoding through AVD (see avd.nix) reaches the decoder over
  # the V4L2 Stateless / Request API, which needs both /dev/video* and
  # /dev/media*. Firefox's RDD sandbox only ever whitelists M2M /dev/video*
  # nodes plus a read-only /dev - see AddV4l2Dependencies in
  # SandboxBrokerPolicyFactory, added for the stateful v4l2m2m decoders on
  # boards like the Raspberry Pi, which need no media controller. There is no
  # /dev/media* rule and no pref to add one, so the sandbox is all-or-nothing
  # for our path; without this the RDD process silently falls back to software
  # decoding.
  #
  # This is a real tradeoff: RDD parses untrusted media bitstreams and is
  # exactly the process you want sandboxed. Scoped to Zen rather than set in
  # environment.sessionVariables so it does not apply to every process on the
  # system (`firefox` below still gets the full sandbox, and software decode).
  #
  # TODO revisit: drop this once Firefox's RDD sandbox learns about
  #   /dev/media*, which would make the Request API usable with the sandbox on.
  #   check: AddV4l2Dependencies in
  #          security/sandbox/linux/broker/SandboxBrokerPolicyFactory.cpp of
  #          mozilla-firefox/firefox - it walks /dev itself, so a `media` match
  #          in that file is the signal
  #   then:  drop the MOZ_DISABLE_RDD_SANDBOX wrapper below
  #   last:  2026-09, firefox 155 / zen 1.21.16b - the file mentions nothing but
  #          /dev/video*, on release and on main
  #
  # The flake's own `env` option would do this, but it lives in its home-manager
  # module and hangs the var off the *unwrapped* derivation (gappsWrapperArgs
  # only exists there); `default` is already wrapFirefox'd, so overriding it is
  # a no-op. Enabling that module to get one variable would also hand it this
  # profile, so wrap the finished package instead. The desktop entries are
  # `Exec=zen-beta` without a path, so PATH resolution reaches this wrapper too.
  zen-browser =
    let
      zen = inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default;
    in
    pkgs.symlinkJoin {
      name = "zen-beta-wrapped";
      paths = [ zen ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/zen-beta --set MOZ_DISABLE_RDD_SANDBOX 1

        # `defaults/pref/*.js` is read before the profile, so these stay
        # overridable in about:config. lndir gives us a real directory here, but
        # its name carries the version - fail the build rather than silently
        # shipping a browser without the prefs if that ever changes.
        shopt -s failglob
        for prefs in "$out"/lib/zen-bin-*/defaults/pref; do
          install -Dm444 ${widevinePrefs} "$prefs/gmpwidevine.js"
        done
      '';
      inherit (zen) meta;
    };

  # Widevine, i.e. whether DRM streaming (Netflix, Spotify Web, Prime) plays at
  # all rather than showing an error page.
  #
  # Mozilla ships no aarch64 build of the CDM, so Firefox's usual "fetch it from
  # our CDN on first use" path has nothing to download. nixpkgs' `widevine-cdm`
  # does what the Asahi installer does instead: pull the arm64 CDM out of a
  # ChromeOS lacros image and rewrite its ELF for vanilla glibc
  # (AsahiLinux/widevine-installer, widevine_fixup.py). Proprietary and
  # non-redistributable, hence the entry in modules/unfree.nix.
  #
  # Two halves, and neither works without the other:
  #
  # 1. The library. Gecko picks up MOZ_GMP_PATH directly, without going through
  #    the addon manager (GeckoMediaPluginServiceParent::LoadFromEnvironment),
  #    and wants a directory laid out as `gmp-<id>/<version>`. The version is
  #    just a label; upstream uses the literal string "system-installed" and the
  #    prefs below have to agree with it. The nixpkgs package only installs the
  #    Chromium layout (share/google/chrome/...), so assemble that directory.
  #
  # 2. The prefs. `media.gmp-widevinecdm.visible` is false on platforms Mozilla
  #    has no CDM for, and EME rejects the key system before anything ever looks
  #    at the library - which is why the DRM checkbox is missing from the
  #    settings UI on arm64 to begin with. Copied from conf/gmpwidevine.js of
  #    the installer.
  #
  # TODO revisit: on nixpkgs bumps
  #   check: whether wrapFirefox learned about Widevine (`grep -i widevine` in
  #          pkgs/applications/networking/browsers/firefox/wrapper.nix), and
  #          whether widevine-cdm still installs only the Chromium layout
  #   then:  drop the prefs/GMP dir in favour of whatever option it exposes
  #   last:  2026-09, widevine-cdm 120.0.6098.0-7a3928f - unchanged, and
  #          wrapper.nix still has no mention of gmp/widevine at all
  widevineGmp = pkgs.runCommand "widevine-gmp" { } ''
    cdm=${pkgs.widevine-cdm}/share/google/chrome/WidevineCdm
    install -Dm444 "$cdm/manifest.json" $out/gmp-widevinecdm/system-installed/manifest.json
    install -Dm555 "$cdm/_platform_specific/linux_arm64/libwidevinecdm.so" \
      $out/gmp-widevinecdm/system-installed/libwidevinecdm.so
  '';

  widevinePrefs = pkgs.writeText "gmpwidevine.js" ''
    pref("media.gmp-widevinecdm.version", "system-installed");
    pref("media.gmp-widevinecdm.visible", true);
    pref("media.gmp-widevinecdm.enabled", true);
    pref("media.gmp-widevinecdm.autoupdate", false);
    pref("media.eme.enabled", true);
    pref("media.eme.encrypted-media-encryption-scheme.enabled", true);
  '';

  # Same prefs for the fallback browser. wrapFirefox appends these to its
  # autoconfig `mozilla.cfg`, which only touches defaults - the sandbox and
  # everything else this package does stay untouched.
  firefox = pkgs.firefox.override { extraPrefsFiles = [ widevinePrefs ]; };

  # Night light, in the renderer. See the long note next to `programs.niri`.
  niri = pkgs.niri.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./niri/software-gamma.patch ];
  });
in
{
  # Wayland compositor. The shell on top of it is noctalia, declared on the
  # home-manager side (hosts/asahi/home.nix) because that is where its
  # config.toml lives; that module installs the package and the user unit.
  programs.niri = {
    enable = true;
    package = niri;
  };

  # Give Qt applications a real platform theme so they follow the selected icon
  # theme. Noctalia is not a Qt application and resolves tray icons itself, so
  # this now only serves the Qt apps on the system.
  qt = {
    enable = true;
    platformTheme = "qt5ct";
  };

  # Login screen. Unlike dms-greeter, which ran inside a second copy of the
  # session's compositor, this one brings its own bundled wlroots. That is the
  # one place on this machine where the software-gamma patch below does not
  # apply, so night light does not reach the login screen - no loss there, but
  # it also means the greeter is the part most likely to break on a wlroots or
  # DCP change, and a greeter that will not start is a machine that will not
  # log in. `systemctl status greetd` and Ctrl+Alt+F2 are the way back.
  #
  # `services.displayManager.defaultSession` is deliberately gone: greetd runs
  # the greeter, and the greeter's own `session.default` picks what to launch,
  # so there is one place that decides instead of two.
  services.displayManager.noctalia-greeter = {
    enable = true;

    cursorTheme = {
      package = pkgs.adwaita-icon-theme;
      name = "Adwaita";
    };

    settings = {
      # `noctalia-greeter sessions` prints the picker label, which is the
      # desktop entry's Name= - "Niri", not the niri.desktop id.
      session.default = "Niri";
      # Skips the user list and opens straight on the password prompt.
      user.default = "xerxes2";

      appearance = {
        # Palette and wallpaper come from the desktop, pushed over by
        # `noctalia msg greeter-sync`. Until that has run once the greeter
        # falls back to its own default look; it is not automatic, so re-run it
        # after changing the wallpaper if you want the two to match.
        scheme = "Synced";
        theme_mode = "dark";
        font_family = "Inter";
      };

      # Left alone, the greeter's compositor derives a scale from the panel
      # geometry, which is not necessarily the session's. Pin it to the same
      # source of truth the niri output uses so login and desktop are one size.
      output.scale = display.scale;
    };
  };

  # Two warnings the greeter logs on every start are expected here and not
  # worth chasing:
  #
  #   [WRN] [greeter-config] failed to open '/var/lib/noctalia-greeter/greeter.toml' for write
  #   [WRN] [greeter-config] migrated sync.toml but failed to strip runtime keys from [...]
  #
  # It wants to write back the last-used session and user, but the module
  # symlinks greeter.toml into the store (`L+` tmpfiles rule), so the file is
  # read-only by construction. The nixpkgs module documents this as an upstream
  # limitation - state is due to move to its own file. Nothing is lost while
  # `session.default` and `user.default` above pin exactly the state it wanted
  # to persist.
  #
  # TODO revisit: on noctalia-greeter bumps
  #   check: journalctl -b -u greetd | grep greeter-config
  #   then:  drop this note once upstream stops writing to greeter.toml
  #   last:  2026-09, noctalia-greeter 1.3.1 - still warns on every start

  # Desktop plumbing.
  services.dbus.enable = true;
  services.gvfs.enable = true;
  services.libinput.enable = true;
  security.polkit.enable = true;
  xdg.mime.enable = true;

  # The user avatar on the lock screen and in the control centre is
  # AccountsService's IconFile. `programs.dms-shell` used to switch the daemon
  # on for us with mkDefault, and nothing took over: noctalia is declared
  # through its home-manager module, which cannot enable a system service, and
  # the NixOS `programs.noctalia` module does not enable it either. Without
  # this the shell logs
  #   accounts service disabled: [...ServiceUnknown] The name is not activatable
  # at startup and shows no avatar at all.
  services.accounts-daemon.enable = true;

  # System services the bar widgets talk to directly.
  # Without UPower the battery widget/popout has no data at all.
  services.upower.enable = true;

  # The shell ships its own Bluetooth UI on top of BlueZ.
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false;

    # Battery levels reach BlueZ through the Battery Provider D-Bus API, which
    # is gated behind the experimental flag - both the generic BAS/GATT provider
    # and the Apple vendor extension AirPods use. Without this every device
    # simply reports no battery at all and the popout has nothing to show.
    settings.General.Experimental = true;
  };

  # Night light needs a patched niri (the `niri` package in the let block above).
  # Apple's DCP display controller exposes only the CTM color matrix and no
  # GAMMA_LUT, while niri implements zwlr_gamma_control_v1 through GAMMA_LUT
  # only, so the whole class of tools - noctalia night light, wlsunset,
  # gammastep - reported success and changed nothing:
  #
  #   $ wlsunset -l -37.8 -L 144.9 -t 2000
  #   gamma control of output eDP-1 (44) failed
  #
  # CTM cannot stand in for the protocol's three 1D ramps - a 3x3 matrix has no
  # per-level curve - which is why that request was closed. So the ramp has to
  # be applied in the renderer instead: the patch advertises a 256-entry ramp
  # (one entry per 8-bit framebuffer level, so nothing is lost against a
  # hardware LUT) and looks every channel up in a shader, the same fallback
  # wlroots grew in !5166.
  #
  # A ramp is a per-pixel function, so the patch transforms exactly the damage
  # rectangles and costs proportionally to the damaged area. The first version
  # instead used niri's blur machinery (`is_framebuffer_effect`), which repaints
  # the whole element whenever anything below it changes because blur is a
  # neighborhood operation; that turned every blinking cursor into a full-output
  # recomposite and measured +0.5 W on this panel. Measurements are in the
  # commit message of the jj change that added this.
  #
  # What is still lost while a ramp is set is direct scanout, so a fullscreen
  # video at night gets composited instead of being handed straight to the
  # display. An identity ramp counts as no ramp, so night mode that is merely
  # scheduled costs nothing during the day, and the cursor stays on its own
  # plane - which also means the cursor itself stays untinted.
  #
  #   niri CTM request:  https://github.com/niri-wm/niri/issues/3672 (closed)
  #   why not CTM:       https://gitlab.freedesktop.org/wlroots/wlroots/-/issues/1078
  #   wlroots fallback:  https://gitlab.freedesktop.org/wlroots/wlroots/-/merge_requests/5166
  #   Asahi kernel side: https://github.com/AsahiLinux/linux/issues/91
  #
  # TODO revisit: on every niri bump
  #   check: whether the patch still applies (a failing build is the signal),
  #          and whether upstream has grown its own software gamma:
  #          `niri msg version` plus a look for `software_gamma` in the niri
  #          source, or for a fallback in src/backend/tty.rs
  #   then:  drop the overrideAttrs and hosts/asahi/niri/software-gamma.patch
  #   test:  nix run nixpkgs#wlsunset -- -t 2000 -T 2001 -S 23:59 -s 00:01
  #          should warm the screen within a second; Ctrl-C restores it
  #   last:  2026-09, niri 26.04 - no upstream support (no `software_gamma`,
  #          tty.rs still only does DRM gamma props), patch applies clean

  # No geoclue any more. Noctalia resolves its own coordinates for the weather
  # widget and the night-light schedule (`[location]` in home.nix), so both the
  # service and the conf.d workaround for its missing [ip] section left with
  # DMS. Nothing else on this host used it.

  # Where Gecko finds the CDM assembled in the let block above. Set globally
  # rather than per-wrapper because both browsers need it and, unlike
  # MOZ_DISABLE_RDD_SANDBOX, it takes nothing away from anything else that
  # happens to inherit it.
  environment.sessionVariables.MOZ_GMP_PATH = "${widevineGmp}/gmp-widevinecdm/system-installed";

  # Audio stack.
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Useful GUI/session tools.
  environment.systemPackages = with pkgs; [
    adwaita-icon-theme
    alacritty
    # `with pkgs` binds looser than `let`, so both of the browsers below are the
    # overridden ones from the let block, not the bare nixpkgs attributes.
    firefox
    nautilus
    pavucontrol
    telegram-desktop
    vesktop # Discord client; official Discord has no aarch64-linux build.
    wl-clipboard
    xdg-utils
    zen-browser
  ];

  fonts.packages = with pkgs; [
    fira-code
    inter
    material-symbols
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
  ];
}
