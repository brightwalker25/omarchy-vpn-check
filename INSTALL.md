# Installing VPN Check

The plugin is a bar widget for the Omarchy shell. It ships its own collector,
so there is no separate binary to place on `PATH` and no service to enable.

For what the panel reports and why each verdict is decided the way it is, see
the [README](README.md).

## Requirements

| Needed | Used for |
|---|---|
| Omarchy shell with plugin support | the bar widget and panel |
| `iproute2` | every routing verdict, via `ip route get` |
| `systemd-resolved` | the configured resolvers and the DNS-over-TLS setting |
| Python 3 | the collector |

`nmcli` and `iso-codes` are used when they are present and degraded around when
they are not: without `nmcli` the kill switch is judged from the routing table
alone, and without `iso-codes` a country is reported by its code rather than by
name. Neither is required.

## Installing

```bash
omarchy plugin add https://github.com/brightwalker25/omarchy-vpn-check.git
omarchy plugin enable brightwalker25.vpn-check --section right
```

`omarchy plugin add` clones the repository into `~/.config/omarchy/plugins/` and
`enable` writes the widget into `bar.layout` in `~/.config/omarchy/shell.json`.
Passing `--enable` to `add` does both in one step and prompts for the section.

Placement accepts more than a section. To put the shield next to a particular
widget rather than at the end of the row:

```bash
omarchy plugin enable brightwalker25.vpn-check --section right --before omarchy.network
```

`--after <id>` and `--index <n>` work the same way. The section must be `left`,
`center` or `right`.

## Installing for development

Working on the plugin means running it from a checkout rather than from a clone
that `omarchy plugin update` will overwrite. Two steps live outside the
repository, so cloning it alone does not install it.

```bash
git clone https://github.com/brightwalker25/omarchy-vpn-check.git ~/Work/omarchy-vpn-check
ln -s ~/Work/omarchy-vpn-check ~/.config/omarchy/plugins/brightwalker25.vpn-check
omarchy plugin enable brightwalker25.vpn-check --section right
```

The symlink is what makes edits live: the plugin id is the link name, so it has
to be exactly `brightwalker25.vpn-check` whatever the checkout is called. Changes
to the collector take effect on the next refresh, and changes to the QML on the
next shell restart.

Validate the manifest after editing it:

```bash
omarchy plugin validate ~/Work/omarchy-vpn-check
```

## First run

Open the panel once with the VPN disconnected.

Until that has happened, the "Your real IP" row will say the address has not
been recorded, and the identity comparison falls back to the globally routable
IPv6 address the ISP has already assigned to the physical interface. That is a
real answer, but it is not the IPv4 one, and an IPv4 exit can never be compared
against it by address.

This is deliberate rather than a limitation to work around. The panel will not
send traffic outside the tunnel to discover the address, because doing so would
disclose it to whoever answered, which is the exact harm the plugin exists to
detect. The only honest way to learn it is to observe it while no tunnel is up.

Disconnect the VPN, open the panel, and the address is cached in
`~/.cache/omarchy-vpn-check/real-ip.json` for every future comparison. The row
then reports it with the date it was seen, so you can judge how stale it is.

## Running the collector from a terminal

The collector makes every judgement the panel displays, so anything the panel
reports can be reproduced and read at the command line:

```bash
~/.config/omarchy/plugins/brightwalker25.vpn-check/bin/vpn-check --text
```

| Flag | Effect |
|---|---|
| `--text` | human-readable output instead of JSON |
| `--pretty` | indent the JSON |
| `--local` | skip every outbound lookup and report only what the machine knows |
| `--timeout <seconds>` | bound the whole run, not each socket (default 6) |
| `--token <token>` | ipinfo.io token; also read from `IPINFO_TOKEN` |

`--local` is the one to reach for when you want the routing, resolver and kill
switch verdicts without contacting anything at all. The rows that need an
outbound lookup, which are the exit address and its operator and location, are
reported as unknown.

## Settings

Configured through the widget's settings in the Omarchy shell, or by hand in the
widget's entry in `~/.config/omarchy/shell.json`.

| Key | Default | Effect |
|---|---|---|
| `refreshIntervalMs` | 60000 | how often checks re-run while the panel is open |
| `barRefreshIntervalMs` | 60000 | how often the local-only check re-runs for the bar colour while the panel is closed, at least 15 seconds |
| `lookupTimeoutSeconds` | 6 | bound on a lookup, and within two seconds the bound on the whole run |
| `ipinfoToken` | empty | optional ipinfo.io token, raising the anonymous rate limit |

The full check, with its outbound lookups, runs only while the panel is open.
While it is closed, `vpn-check --local` runs every `barRefreshIntervalMs` for
the bar colour and sends no packets.

Address ownership and location come from [ipinfo.io](https://ipinfo.io), queried
through the tunnel and cached on disk for a week, so a repeat check of the same
exit costs no request. The token is optional; without one the anonymous rate
limit applies, which is ample for a panel that only runs while it is open. When
set, it is passed through the environment rather than argv, because argv is
world-readable.

## Troubleshooting

The real IP row says the address has not been recorded. Expected until the panel
has been opened once with the VPN disconnected. See [First run](#first-run).

Rows sit on "checking" and never resolve. The whole run is bounded by
`lookupTimeoutSeconds`, so this should not persist past a few seconds. Run the
collector by hand with `--text` to see which lookup is hanging, and `--local` to
confirm the machine-local verdicts are fine.

The kill switch row says "IPv6 only". Half a kill switch is being reported as
half. A guard counts only when a sink device holds a default route that beats
the open connection's, so this means the IPv6 guard is up and the IPv4 one is
not, and IPv4 would fall back to the named interface if the tunnel dropped. With
some VPN clients the IPv4 guard is a separate connection that stays inactive unless the
permanent kill switch is turned on.

The exit country looks wrong. It is where the operator has registered the
address, not where the machine sits, and registration and geography differ often
enough that it is worth checking the operator and AS on the same row first.

## Uninstalling

```bash
omarchy plugin disable brightwalker25.vpn-check
omarchy plugin remove brightwalker25.vpn-check
```

`disable` takes the widget out of the bar layout and leaves the files in place;
`remove` deletes the plugin directory too. For a development install, remove the
symlink rather than the checkout:

```bash
omarchy plugin disable brightwalker25.vpn-check
rm ~/.config/omarchy/plugins/brightwalker25.vpn-check
```

Neither command touches the cache. To clear the recorded address and the cached
address lookups:

```bash
rm -rf ~/.cache/omarchy-vpn-check
```
