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

## The three fixes

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

### 3. 32-bit OpenGL titles cannot create a GL context

Symptom, from `PROTON_LOG=1 WINEDEBUG=+wgl,+egl`:

```
00d8:warn:wgl:egl_init EGL support is disabled.
00d8:trace:wgl:X11DRV_WineGL_InitOpenglInfo GL version : 4.6 ... Mesa 25.2.8
00d8:trace:wgl:X11DRV_WineGL_InitOpenglInfo Direct rendering enabled: True   <- 64-bit fine
013c:warn:wgl:egl_init EGL support is disabled.
013c:err:wgl:X11DRV_WineGL_InitOpenglInfo  couldn't initialize OpenGL        <- 32-bit dead
013c:warn:wgl:display_funcs_init glAccum not found.    (and every other gl* call)
```

Two independent causes stacked up on Fedora 42's separate Mesa overlays.
Fedora 44 now uses a Fedora FEX rootfs and native GL thunks instead; validate
stock Proton on that stack before assuming these old limitations still apply
or deleting the compatibility tool:

- **Wine 10.15+ made EGL the default GL backend on X11** and new WoW64 maps
  32-bit GL buffers through Vulkan, so 32-bit apps have no GLX fallback. With
  EGL disabled they get no OpenGL at all. This is not Asahi-specific and is
  reproducible on x86-64: <https://bugs.winehq.org/show_bug.cgi?id=58754>,
  <https://github.com/void-linux/void-packages/issues/57503>. Proton 9 (old
  WoW64, real 32-bit wine) still uses GLX and avoids this half.
- **pressure-vessel hides the FEX i386 Mesa overlay.** The Steam Linux Runtime
  builds its own `/usr` for the game, and `mesa-fex-emu-overlay-i386` is not in
  it, so even Proton 9 fails inside the container with
  `set_pixel_format Invalid format 0`. The same run outside pressure-vessel
  works.

`compatibilitytools.d/proton9-nosrt` is the fix: a compat tool whose
`toolmanifest.vdf` omits `require_tool_appid`, so Steam skips the runtime
container and calls Proton directly.

Select it per game under Properties -> Compatibility. DirectX titles do not
need it - DXVK talks to Vulkan, which works inside pressure-vessel.

TODO revisit: when Proton or the Steam Linux Runtime is updated.

- check: the status of <https://bugs.winehq.org/show_bug.cgi?id=58754>, then run
  a 32-bit OpenGL title on stock Proton with `PROTON_LOG=1 WINEDEBUG=+wgl,+egl`
- then: delete `compatibilitytools.d/proton9-nosrt` once a stock Proton gets a
  GL context inside pressure-vessel
- last: 2026-10, rebuilt on Fedora 44 / muvm 0.7.0 / FEX 2604. Native and
  x86_64 guest glxinfo both report accelerated OpenGL 4.6 / Mesa 26.2.5.
  Stock Proton's 32-bit game path is pending a test through the logged-in
  Steam client; earlier isolated-prefix launches stopped at SteamAPI init,
  not a meaningful GL result. Keep `proton9-nosrt` for comparison.

## Notes

- Native Linux builds are often worse than the Windows ones here. Isaac's
  native build segfaults right after its Theora init under both FEX and box64
  (<https://github.com/ptitSeb/box64/issues/542>); the Windows build through
  `proton9-nosrt` runs fine.
- `PROTON_LOG=1 %command%` in a game's launch options writes
  `~/steam-<appid>.log`. Add `WINEDEBUG=+wgl,+egl` for graphics problems.
- Harmless noise: `gameoverlayrenderer.so ... wrong ELF class`,
  `prctl(PR_SET_SECCOMP, ...): Invalid argument`, `lspci: command not found`,
  `pressure-vessel-wrap: Internal error: ... vulkan/implicit_layer.d`.
- The Steam client itself is not fully stable under FEX; it occasionally dies
  with `fatal stalled cross-thread pipe`. Restart it.
- Machine has 15 GiB of RAM. The emulation overhead means AAA titles are out of
  reach regardless of how well the stack works.
