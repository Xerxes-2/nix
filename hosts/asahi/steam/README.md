# Steam on Asahi

Steam runs through muvm (a 4K-page microVM) and FEX on the 16K-page Asahi host.
`programs.steam` itself is x86-only; `inputs.nixos-muvm-steam` supplies the native
wrapper, following the host nixpkgs for muvm/FEX/Mesa.

## Install and launch

Apply with `sudo nixos-rebuild switch --flake /etc/nixos --option always-allow-substitutes true`.
Upstream recommends the substitute option to avoid unnecessary x86 builds.

Download and unpack the official launcher without sudo:

```sh
mkdir -p ~/Games/steam-native
curl -fL https://repo.steampowered.com/steam/archive/stable/steam_latest-stable.tar.gz -o /tmp/steam-launcher.tar.gz
tar -xzf /tmp/steam-launcher.tar.gz -C ~/Games/steam-native --strip-components=1
```

Choose **Steam** in the desktop application menu, or run `steam-native`.
The desktop icon comes from the extracted launcher in `~/Games/steam-native`.
The host command selects `steam-native-guest` as upstream's guest payload through
SHELL, after upstream sets up Mesa, steam-run and PulseAudio. No terminal is needed.
The guest helper restores SHELL to bash before launching Steam.

For debugging, run `muvm-steam-run-free`, then `steam-native-guest` inside its shell.
Do not run multiple Steam clients at the same time.

## D-Bus workaround

The guest has no usable session bus. steam-run's default D-Bus config fails with
"needs one or more <listen> elements". `steam-native-guest` starts a private
session bus with an explicit configuration stored in /nix/store. A configuration
created in the outer /tmp cannot be used: steam-run has a private /tmp.
PulseAudio uses upstream's `/run/pulse.conf` with shared memory disabled.
See the TODO in `../steam.nix` for when to revisit this workaround.

## Verification and migration

2026-11-16: the user confirms the packaged `steam-native-guest` launches Steam
and Isaac is playable. The desktop/host shortcut still needs a click-through
check after applying. Chinese fonts, audio, Vulkan details, Proton version and
saves were not separately confirmed.

The Fedora `steam` container and its dedicated image are retired. Podman and
Distrobox are no longer enabled/installed by the Asahi configuration. Old
`~/Distrobox/steam` data is retained for games and saves; it is not migrated or
removed automatically. Fedora image/build/bootstrap scripts were removed;
recover them from jj history if needed.

## Update and diagnosis

Update the wrapper with `nix run .#update -- nixos-muvm-steam`; nixpkgs updates
also update its dependencies. Steam updates its client and games itself.

`PROTON_LOG=1 %command%` in a game's launch options writes `~/steam-<appid>.log`.
Other games need individual testing. The FEX client can occasionally fail with
`fatal stalled cross-thread pipe`; restart it.
