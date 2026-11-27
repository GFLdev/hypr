# Polkit on FreeBSD

`hyprpolkitagent` shows the password dialog when an app needs root (styled by
`hyprtoolkit.conf`). It is started from `hyprland.lua`, but the system needs the
setup below first. Everything here runs as root unless noted.

## 1. Packages and services

```sh
pkg install polkit consolekit2 hyprpolkitagent
sysrc dbus_enable=YES
service dbus start
```

polkitd and ConsoleKit2 are started by D-Bus on demand, so they don't need
their own rc.conf entries.

## 2. Start Hyprland inside a ConsoleKit session

FreeBSD has no logind, so polkit uses ConsoleKit2 to find out which session an
app belongs to. Start Hyprland from the tty as your user with:

```sh
ck-launch-session start-hyprland
```

Without it, the autostart in `hyprland.lua` can't find a session ID to give
the agent, and polkit refuses every request.

## 3. Let polkitd see your processes

Skip this step if `security.bsd.see_other_uids` and `see_other_gids` are `1`
(the FreeBSD default).

polkitd runs as the `polkitd` user, not root. With the hardening option
"Prevent users from seeing processes of other users"
(`security.bsd.see_other_uids=0` / `see_other_gids=0`), it can't look up the
process asking for permission, and every request fails with:

```
get_kinfo_proc() failed for pid N: No such process
```

To keep that hardening and still let polkitd in, swap it for
`mac_seeotheruids`, which can exempt one group. First get the `polkitd` gid
(565 from the port):

```sh
pw groupshow polkitd
```

Apply it now. The module is loaded before the base sysctls are relaxed, so
other users' processes stay hidden throughout:

```sh
kldload mac_seeotheruids
sysctl security.mac.seeotheruids.specificgid=565
sysctl security.mac.seeotheruids.specificgid_enabled=1
sysctl security.mac.seeotheruids.enabled=1
sysctl security.bsd.see_other_uids=1 security.bsd.see_other_gids=1
```

Keep it after a reboot:

```sh
sysrc -f /boot/loader.conf mac_seeotheruids_load=YES
```

and in `/etc/sysctl.conf`, replace the `see_other_uids=0` / `see_other_gids=0`
lines with:

```
security.bsd.see_other_uids=1
security.bsd.see_other_gids=1
security.mac.seeotheruids.enabled=1
security.mac.seeotheruids.specificgid_enabled=1
security.mac.seeotheruids.specificgid=565
```

Regular users still can't see each other's processes. The module only checks
user IDs, not groups.

## 4. Test

As your user, from a terminal inside Hyprland:

```sh
pgrep -x hyprpolkitagent   # the agent is running
ck-list-sessions           # your session is listed, active = TRUE
pkexec id -u               # the password dialog appears, then prints 0
```

If `pkexec` fails with `No such process`, go back to step 3. If it falls back
to asking for the password in the terminal, the agent isn't registered for
your session, so go back to step 2.
