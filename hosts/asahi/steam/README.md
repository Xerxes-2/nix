# Steam on Asahi

Steam has no `aarch64-linux` build, so `programs.steam` cannot work here:
it fails with `i686 Linux package set can only be used with the x86 family`.
Fedora 44 packages the FEX x86 rootfs as `fex-emu-rootfs-fedora`.

Two launch paths are available: the native Nix wrapper below, and the tested
Fedora Asahi Remix container (`dnf install steam`) kept as a fallback.

## Native Nix launcher

`inputs.nixos-muvm-steam` pins
<https://github.com/dramforever/nixos-muvm-steam>, following this flake's nixpkgs.
It installs **`muvm-steam-run-free`** (the package attribute is `muvm-steam`).
This removes the Fedora container layer; muvm and FEX are still required.

Build/apply with `sudo nixos-rebuild switch --flake /etc/nixos --option
always-allow-substitutes true`. Upstream recommends this option to prefer cached
`steam-run-free` over building x86 packages through emulation. A missing cache
can still require x86 builds.

Download a `steam_<version>.tar.gz` from
<https://repo.steampowered.com/steam/archive/stable/> and unpack it into a
dedicated directory, for example `~/Games/steam-native`. Then run:

```sh
muvm-steam-run-free
# Inside the guest shell (use the actual path to the extracted steam script):
steam-native-guest
```

The upstream launcher opens a guest shell and prints the second command's
template; it does not download or automatically launch Steam. Its PulseAudio
configuration disables shared memory for the guest connection. It uses the
normal user home, whereas the Fedora box uses `~/Distrobox/steam`; keep these
installs separate during testing, and do not run both clients simultaneously.

`steam-native-guest` launches `~/Games/steam-native/steam` with a private D-Bus
session inside steam-run. Without it, runtime-launcher-service cannot find a
session bus; dbus-run-session with its default config fails with "needs one or
more <listen> elements". The helper supplies an explicit config from /nix/store:
the FHS environment has a private /tmp, so a config created in the guest shell's
/tmp would not be visible inside steam-run.

2026-11-16: the user confirms Steam starts and Isaac is playable with the
explicit session-bus configuration in the shared home directory. The packaged
helper uses the same configuration from /nix/store; that helper still needs a
runtime check after applying. Chinese fonts, audio, Vulkan details, Proton
version and saves were not separately confirmed. Existing Fedora container and
game files are kept as a fallback; its font setup is not applied to this path.

Update this input with `nix run .#update -- nixos-muvm-steam`; nixpkgs updates
also change its muvm/FEX/Mesa dependencies.

## The stack

```
niri on NixOS          aarch64, 16K pages, Honeykrisp Vulkan
  └─ podman/distrobox  Fedora 44 + @asahi COPRs
      └─ muvm          microVM with a 4K-page kernel, GPU passed through
          └─ FEX       x86_64/i386 emulation
              └─ Proton, DXVK/vkd3d-proton
```

x86 code assumes 4K pages while Apple hardware runs 16K, and Linux cannot mix
page sizes between processes - hence the microVM. See
<https://asahilinux.org/2024/10/aaa-gaming-on-asahi-linux/>.

## Fedora container setup

```sh
podman build -t steam:latest /etc/nixos/hosts/asahi/steam
distrobox create --name steam --image localhost/steam:latest --home ~/Distrobox/steam
distrobox enter steam -- /run/host/etc/nixos/hosts/asahi/steam/setup-home.sh
distrobox enter steam -- steam
```

`niri` starts `xwayland-satellite` (see `hosts/asahi/niri/config.kdl`), which is
what gives Steam - an X11-only client - a display.

## Update

`distrobox upgrade steam` updates packages within the container's Fedora release;
it does not follow host NixOS upgrades or change the Fedora release. To move to
a new release, change `FROM` in `Containerfile`, rebuild the image, stop/rename
the old container, and create `steam` again with the **same `--home`**. Keep the
old container until the new one has passed game tests; rebuilding an image alone
does not update an existing container.

An RPM update can replace the patched `/usr/bin/steam`. Reapply the bootstrap
before launching if that happens:

```sh
distrobox enter steam -- sudo python3 \
  /run/host/etc/nixos/hosts/asahi/steam/steam-dbus-bootstrap.py /usr/bin/steam
```

## Container fixes

### 1. "Waiting for network" forever

Steam asks NetworkManager over the D-Bus **system** bus whether the machine is
online. The muvm guest gets a fresh `/run` and no system bus, so the query never
returns. `steam-dbus-bootstrap.py` patches Fedora's launcher to start a bare bus
inside the guest command; nothing answers the NetworkManager call, but it now
fails immediately instead of hanging.

Upstream (<https://github.com/defaultdino/asahi-steam-fix>) uses `muvm -x` for
this. That hook runs too early here - it fails with `ENOENT`, and when it does
run the socket it creates is not the one the payload sees.

TODO revisit: on muvm / Fedora Asahi updates.

- check: inside the guest, `ls /run/dbus/system_bus_socket`
- then: drop `steam-dbus-bootstrap.py` once a system bus is already there, or
  once `muvm -x` runs late enough to be usable
- last: 2026-10, Fedora 44 / muvm 0.7.0 on host kernel 7.2.12: a real
  4K-page guest still has no system bus. The rebuilt image includes the
  launcher patch; bootstrapping inside the payload creates the socket.
  Keep the workaround; a newer muvm alone does not provide the bus.

### 2. Tofu everywhere

The client is an x86 binary under FEX, so it reads fonts from the FEX rootfs,
not from this container. `$HOME` is passed through to the guest, so
`setup-home.sh` copies Noto CJK into `~/.local/share/fonts`.

## Game compatibility

For Isaac, select the Windows build and official **Proton Experimental** under
Properties -> Compatibility. It works on the Fedora 44 stack with the normal
Steam Linux Runtime; no custom compatibility tool is needed. Other games still
need per-game testing.

## Notes

- `PROTON_LOG=1 %command%` in a game's launch options writes
  `~/steam-<appid>.log`. Add `WINEDEBUG=+wgl,+egl` for graphics problems.
- Harmless noise: `gameoverlayrenderer.so ... wrong ELF class`,
  `prctl(PR_SET_SECCOMP, ...): Invalid argument`, `lspci: command not found`,
  `pressure-vessel-wrap: Internal error: ... vulkan/implicit_layer.d`.
- The Steam client itself is not fully stable under FEX; it occasionally dies
  with `fatal stalled cross-thread pipe`. Restart it.
- Machine has 15 GiB of RAM. The emulation overhead means AAA titles are out of
  reach regardless of how well the stack works.
