#!/usr/bin/env python3
"""Make Fedora's Steam launcher start a D-Bus system bus inside the muvm guest.

Steam asks NetworkManager over the system bus whether the machine is online.
The muvm guest has its own /run and no bus, so the query never completes and
the client stays on "Waiting for network". Wrapping the guest command in a
small bootstrap shell gives it a bus (nothing answers the NetworkManager call,
but it now fails immediately instead of hanging).
"""

import sys

OLD = '    return pexpect.spawn("muvm", ["--"] + cmd)'

NEW = '''    boot = ("mkdir -p /run/dbus; "
            "[ -S /run/dbus/system_bus_socket ] || "
            "/usr/bin/dbus-daemon --system --fork; "
            \'exec "$@"\')
    cmd = ["/bin/sh", "-c", boot, "sh"] + cmd
    return pexpect.spawn("muvm", ["--"] + cmd)'''


def main() -> int:
    path = sys.argv[1]
    with open(path) as f:
        source = f.read()

    if "/run/dbus/system_bus_socket" in source:
        print(f"{path}: already patched")
        return 0

    if OLD not in source:
        print(f"{path}: launcher does not match the expected muvm() body", file=sys.stderr)
        return 1

    with open(path, "w") as f:
        f.write(source.replace(OLD, NEW))

    print(f"{path}: patched muvm() to bootstrap the guest system bus")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
