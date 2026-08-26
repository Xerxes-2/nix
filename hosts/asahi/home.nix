{ ... }:
{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    users.xerxes2 =
      { lib, pkgs, ... }:
      {
        imports = [ ../../modules/home/cli.nix ];

        programs.home-manager.enable = true;

        # Put a 220-logical-pixel spacer at the exact center of DMS's top bar.
        # This matches the 14-inch MacBook Pro notch at scale 2 while leaving the
        # rest of DMS's settings mutable through its UI.
        home.activation.dmsNotchSpacer = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          settings="$HOME/.config/DankMaterialShell/settings.json"
          marker="$HOME/.local/state/DankMaterialShell/.notch-spacer-v1"

          if [ ! -e "$marker" ]; then
            mkdir -p "$(dirname "$settings")" "$(dirname "$marker")"
            if [ -s "$settings" ] && ${pkgs.jq}/bin/jq -e '.barConfigs | type == "array" and length > 0' "$settings" >/dev/null; then
              tmp="$(mktemp)"
              ${pkgs.jq}/bin/jq '
                .barConfigs[0].position = 0
                | .barConfigs[0].centerWidgets = [
                    "music",
                    { "id": "spacer", "size": 220 },
                    "clock"
                  ]
              ' "$settings" > "$tmp"
              install -m 0600 "$tmp" "$settings"
              rm -f "$tmp"
            else
              install -m 0600 ${./dms/settings.json} "$settings"
            fi
            touch "$marker"
          fi
        '';

        home = {
          username = "xerxes2";
          homeDirectory = "/home/xerxes2";
          stateVersion = "25.05";
        };
      };
  };
}
