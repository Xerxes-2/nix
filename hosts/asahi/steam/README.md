# Steam on Asahi

Steam has no `aarch64-linux` build, so `programs.steam` cannot work here:
it fails with `i686 Linux package set can only be used with the x86 family`.
Fedora 44 packages the FEX x86 rootfs as `fex-emu-rootfs-fedora`.

Fedora Asahi Remix packages the whole stack (`dnf install steam`), so we run
that inside a container instead of reproducing it in nixpkgs.

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

## Setup

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
