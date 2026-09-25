# omarchy-vpn-check

A VPN and DNS posture panel for the Omarchy bar. Click the shield and it tells
you where your traffic is surfacing, who runs that address, where your DNS
queries are being answered, and what your own address is underneath it all.
Every line carries a green, amber or red indicator.

```bash
omarchy plugin add https://github.com/brightwalker25/omarchy-vpn-check.git
omarchy plugin enable brightwalker25.vpn-check --section right
```

The collector ships inside the plugin and is found relative to it, so there is
no symlink or PATH step. Open the panel once with the VPN disconnected, so it
can record your real IPv4 address; until then the identity rows work from your
IPv6. [INSTALL.md](INSTALL.md) covers that, the development install, the
settings, running the collector by hand, and uninstalling.

## What it reports

| Section | Rows |
|---|---|
| Connection | tunnel interface and protocol, whether traffic actually uses it, kill switch |
| Exit | external IP, the operator hosting it and its AS number, the city and country |
| Identity | your own address, and the ISP that issued it |
| DNS | which resolvers can answer, the address queries surface from, where that is, whether it constitutes a leak, whether it is encrypted |
| IPv6 | carried, blocked, or leaking |

## Design

A collector script prints one JSON verdict; the QML panel renders it and
decides nothing. This is the same shape as `omarchy-system`, and it means the
whole judgement lives in one testable file that runs fine from a terminal:

```bash
./bin/vpn-check --text          # the same checks, human readable
./bin/vpn-check --local --text  # no outbound lookups at all
./bin/vpn-check --pretty        # the JSON the panel consumes
```

### The checks never cause the leak they test for

The obvious way to test whether traffic can escape a tunnel is to send some
outside it and see where it lands. That works, and it discloses your real
address to whoever answers. That disclosure is the exact harm the plugin
exists to detect.

So the routing checks send nothing. `ip route get 1.1.1.1 from <your address>`
asks the kernel which interface a packet *would* leave by and returns the
answer without transmitting. That is how the "traffic routing" and IPv6 rows
are decided: by reading the routing tables, not by probing past them.

Two lookups are needed, not one, because a program can bind to an address or
to an interface and the kernel answers those differently. A policy-routed VPN
catches traffic by fwmark, which matches the address; a socket that sets
`SO_BINDTODEVICE` skips the rule and leaves through the interface it named.
That takes no privilege. Both lookups are made, `from <address>` and `oif
<interface>`, but only the first carries a verdict.

The address lookup is the one that discriminates: a working policy-routed VPN
sends it down the tunnel, so an answer outside means the routing is broken and
ordinary traffic is at risk. The device lookup names the physical interface on
almost any such VPN, kill switch or not, because forcing the output interface
skips the fwmark rule by construction, and no VPN setting changes that.
Closing it takes a firewall rule. So it is reported as a sentence on the green
row rather than as a warning. A row that is amber for every user in every state
is not a check, and it drowns the rows that do mean something.

That is the rule the whole panel follows. Amber means something you can act on:
a kill switch that is off, DNS in plaintext on a network you do not control, a
real address never recorded. It does not mean a fact about how Linux routing
works.

### Down is not the same as leaking

A VPN that is off, or one whose tunnel has dropped with nothing to catch the
traffic, is red: packets are going out in the clear under your own address.

A tunnel that has dropped with the kill switch holding is amber. The default
route the kill switch parked outbids the open connection, so packets are
discarded on this machine and nothing reaches the internet. The VPN has failed
and you should reconnect, but nothing has escaped, and the panel says so in
those terms rather than reporting the sink device as the place your traffic is
going. The routing, resolver and DNS leak rows all defer to that state instead
of describing an escape that cannot happen.

Every lookup that does go out uses the default route, so while the tunnel is
up they are all inside it. Nothing is ever bound to the physical interface.

### Which interface is which

Every verdict rests on naming two interfaces correctly, and neither name can
be taken from the interface list in order. The tunnel is whichever candidate
the default route actually resolves to, not the first tunnel-shaped device on
the machine: `ip link show` lists in interface-index order, NetworkManager
rebuilds the real tunnel with a fresh index on every connect, and a Tailscale
or tap device created at boot would otherwise take the verdict. The uplink is
the lowest-metric default route once tunnels and sinks are excluded, because a
VPN that installs its default in the main table rather than a private one
(NetworkManager's OpenVPN plugin, or `wg-quick` with `Table=main`) would
otherwise be named as the uplink, and then every identity row would be
comparing the tunnel against itself.

### Your real IP, without asking for it

The panel will not bypass the tunnel to find out what your address is. It uses
the best honest source available, in this order:

1. **Observed live** while no tunnel was up, and cached for next time.
2. **Read from that cache**, dated, so you know how stale it is.
3. **The globally routable IPv6 address your ISP has already assigned** to the
   physical interface. It is sitting on the interface where anything can read
   it, so reporting it costs nothing and gives away nothing.

Open the panel once with the VPN disconnected and it remembers your IPv4
address for every future comparison. Until then it works from your IPv6.

The comparison against the exit is by operator as well as by address. An exact
address match is the certain answer but it only ever fires within one family,
and while the recorded address is the uplink's IPv6 it can never equal an IPv4
exit however badly the tunnel is failing. Matching the autonomous system
catches that case, and is the same test the DNS leak check already uses.

### What counts as a leak

DNS is judged by comparing *who owns the resolver's egress address* against
who owns the VPN exit. Same operator, or same country, is the clean case.
Surfacing on your own ISP is the leak, and it is called that in plain words.
A resolver in a third country is amber, because it is unusual but not proof
of anything.

The resolver's egress is measured once per address family, because a resolver
can ask over IPv4 from one address and over IPv6 from another, and the two need
not be in the same country. The IPv4 address comes from lookups answerable over
IPv4. The IPv6 one comes from `whoami.v6.powerdns.org`, whose nameservers have
only IPv6 addresses, so the resolver must use IPv6 to reach them; a SERVFAIL
there is reported as the resolver having no IPv6 path. The leak row takes the
worse of the two verdicts. The location row turns amber when either family
surfaces outside the exit country, since that is no leak but can still place
you somewhere other than where you chose to appear.

Separately, any interface other than the tunnel that both carries a default
DNS route and has servers of its own is a red finding on its own merits: it
is a path queries can take around the tunnel whether or not they currently do.

A route leaving the tunnel is only a leak if it goes anywhere. Where a VPN
cannot carry IPv6 it commonly blocks it instead, by pointing the default IPv6
route at a dummy device. With one common client that device is `ipv6leakintrf0`, held up
by the `pvpn-killswitch-ipv6` connection. A dummy device discards everything routed
into it, so packets are dropped on this machine and never reach the wire.
`ip route get` names that interface exactly as it would name a real escape, so
the interface kind is checked before the verdict: a route into a sink is the
kill switch working, and is reported green as "blocked". The same reasoning
applies to the IPv4 routing row.

That same dummy device is why the kill switch is reported per address family
rather than as one verdict. With that client the IPv6 guard is always up, and the IPv4
guard is a separate connection that stays inactive unless the permanent kill
switch is turned on, so a machine can easily have one and not the other. A
guard counts only when a sink device holds a default route that beats the open
connection's, and only the families that have an address on the uplink are
asked for one. Half a kill switch is reported as half: "IPv6 only", amber,
naming the family that would fall back and the interface it would fall back
to.

Unencrypted DNS is judged by where the queries travel, not by whether the
setting is on. Every configured resolver is put through `ip route get`; if all
of them are reachable only down the tunnel, plaintext is green and says so.
Encrypting to the VPN's own resolver would encrypt to the party already
answering the query, over a leg that WireGuard has already encrypted. The same
configuration turns amber the moment a resolver becomes reachable outside the
tunnel, or the tunnel goes away, because then the plaintext is on a network
you do not control.

### The bar glyph's colour

The shield in the bar is green, amber or red. A tint that is merely stale is
worse than none, because it says "protected" long after the tunnel has
dropped, so while the panel is closed the widget runs `vpn-check --local` once
a minute. That checks the tunnel, routing, the kill switch and the DNS
configuration from the kernel and the resolver alone: no packet leaves the
machine, and it takes well under a tenth of a second. The tint is the worst of
that and of any full check from the last fifteen minutes, so a DNS leak found
with the panel open stays red after it closes. A check that could not run
shows amber.

The full check, with its outbound lookups, still runs only while the panel is
open.

## Settings

| Key | Default | Effect |
|---|---|---|
| `refreshIntervalMs` | 60000 | How often checks re-run while the panel is open |
| `barRefreshIntervalMs` | 60000 | How often the local-only check re-runs for the bar colour while the panel is closed, at least 15 seconds |
| `lookupTimeoutSeconds` | 6 | Per-lookup timeout, and within two seconds the bound on the whole run |
| `ipinfoToken` | empty | Optional ipinfo.io token, raising the anonymous rate limit |

The timeout bounds the collector, not just each socket inside it. The lookups
share one deadline rather than each being granted the full timeout in turn,
and the process leaves as soon as the report is written instead of waiting for
a worker still blocked on a resolver down a tunnel that has just dropped. That
last case is the one that matters: it is when the panel is most worth reading,
and it used to be when the panel sat on "checking" indefinitely.

Address ownership and location come from [ipinfo.io](https://ipinfo.io), which
is queried through the tunnel. Results are cached on disk for a week, so a
repeat check of the same exit costs no request. The token, if set, is passed
through the environment rather than argv, because argv is world-readable.

## Requirements

`iproute2`, `systemd-resolved` and Python 3. `nmcli` and `iso-codes` are used
when present and degraded around when not; see
[INSTALL.md](INSTALL.md#requirements) for what each one is used for.

## Changelog

[CHANGELOG.md](CHANGELOG.md). Every entry is a correction to a verdict the
panel was reporting, described in terms of what it used to say and what it says
now.

## Written with AI help

This was written with help from AI. I have checked the code, but if you would
prefer not to use it because AI was involved, that is your choice.

## Licence

MIT. The bar widget and panel scaffolding derive from Omarchy's own shell
plugins; see `LICENSE`.
