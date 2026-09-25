# Changelog

Notable changes to the VPN Check plugin. Versions follow
[semantic versioning](https://semver.org), and the format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Every entry below is a correction to a verdict the panel was reporting, so
each one is described in terms of what it used to say and what it says now.

## [0.2.1] - 2026-09-25

### Changed

- The bar shield is now tinted green, amber or red. While the panel is closed
  it runs `vpn-check --local` once a minute, which sends no packets, and the
  tint is the worst of that and any full check from the last fifteen minutes.
  A check that could not run shows amber. Full checks still run only while
  the panel is open.

### Fixed

- DNS location is measured over IPv6 as well as IPv4. Only the IPv4 egress was
  ever looked up, so the panel said Zürich while ipleak.net, whose lookups the
  resolver answered over IPv6, found the same resolver surfacing in New York.
  The IPv6 egress is now found with `whoami.v6.powerdns.org`, which can only be
  answered over IPv6. "Queries come from" lists both addresses. "DNS resolves
  from" names both places and turns amber when either is outside the exit
  country. The leak row takes the worse of the two verdicts, so an IPv6 path
  surfacing on the ISP is red even when IPv4 is clean.
- IPv6 carried by the tunnel is no longer reported as "Blocked". The exit
  lookup asked ipinfo.io over IPv6, but ipinfo.io has no IPv6 address, so it
  always failed, and a failed lookup was read as a working block. It now asks
  `v6.ipinfo.io`, and reports "Carried by the tunnel" with the exit address.
  When the tunnel holds the IPv6 default and the lookup still fails, the row
  says "Unverified" instead of guessing.
- "Traffic routing" reads "IPv4 and IPv6 via" the tunnel when the tunnel holds
  both defaults, instead of naming IPv4 alone.

## [0.2.0] - 2026-09-05

A full review of the collector, and the corrections it produced. Nine verdicts
were resting on a test narrower than the claim it supported. No new checks were
added; the existing ones were made to mean what they said.

### Fixed

- A tunnel that has dropped behind a working kill switch is no longer reported
  as a leak. The panel had two states where it needed three. A VPN that is off
  and a VPN that has dropped with the kill switch holding were both red, and
  the routing row named the kill switch's own dummy device as the place traffic
  was going. Off with nothing to catch it stays red, because packets really are
  going out in the clear. Dropped with the switch holding is now amber, with the
  headline "VPN down, traffic blocked", and the tunnel row says to reconnect.
  The routing, resolver and DNS leak rows all defer to that state instead of
  describing an escape that cannot happen.
- The kill switch is reported per address family rather than as one verdict. It
  was found by looking for "killswitch" or "leak" in the name of an active
  NetworkManager connection, and one VPN client's IPv6 guard is always up, so the row
  read "Active" and the headline read "Protected" on a machine whose IPv4 guard
  was off and whose IPv4 would fall straight back to the open connection. A
  guard now counts only when a sink device holds a default route that beats the
  open connection's, and only a family with an address on the uplink is asked
  for one. Half a kill switch is reported as half, naming the family that would
  fall back and the interface it would fall back to.
- The tunnel and the uplink are identified by the routing table rather than by
  name or position. The tunnel was taken as the first tunnel-shaped device in
  interface-index order, so a Tailscale or tap device created at boot took the
  verdict from the real tunnel, which NetworkManager rebuilds with a higher
  index on every connect. The uplink was whatever held the main-table default
  without excluding tunnels, so a VPN that installs its default there rather
  than in a private table, such as NetworkManager's OpenVPN plugin or wg-quick
  with `Table=main`, became its own uplink and every identity row then compared
  the tunnel against itself.
- Both ways out of an interface are now tested. The routing and IPv6 rows asked
  `ip route get ... from <address>` and called the answer general, but a socket
  bound to the interface with `SO_BINDTODEVICE` takes a different lookup and, on
  a policy-routed VPN, a different path, because the fwmark rule that catches
  the address never sees the device.
- The exit is compared with the recorded real address by operator as well as by
  address. Equality only ever fires within one address family, so while the
  recorded address is the uplink's IPv6 it could never match an IPv4 exit, and
  an exit sitting on the user's own ISP was reported green on three rows.
- The IPv6 own-prefix cross-check examines every global address on the uplink
  rather than the first. An exit inside a second prefix on the same link read as
  carried by the tunnel, and so did an address neither side could parse. An
  impossible comparison is now reported as unverified rather than as clean.
- DNS encryption accepts only `DNSOverTLS=yes` as green. Any value other than
  "no" was accepted, which included `opportunistic`: it encrypts when the
  resolver offers it and sends cleartext when it does not, silently, on exactly
  the networks that block port 853. Opportunistic is now amber and says why.
- `--timeout` bounds the whole run rather than each socket. Four lookups were
  each granted the full timeout in turn, a fifth ran after them, and both the
  executor and `concurrent.futures`' atexit hook joined workers still blocked in
  `getaddrinfo` on a resolver down a tunnel that had just dropped. With every
  lookup hung and `--timeout 2`, the collector took over 90 seconds to exit and
  now takes 4.1. The panel sat on "checking" for all of it.

### Changed

- A bypass is graded apart from a leak. Forcing the output interface skips the
  fwmark rule by construction, so that lookup names the physical interface on
  almost any policy-routed VPN, with or without a kill switch. Grading it red
  lit the row for every user in every state. An address that escapes stays red,
  because a working policy-routed VPN sends it down the tunnel and an escape
  there means ordinary traffic is at risk.
- The device-bound bypass is a sentence on the green routing row rather than a
  verdict of its own, and is mentioned once rather than on both families. As a
  warning it could never clear, and two permanent ambers on a working connection
  made the panel read as broken while burying the kill-switch row that was
  genuinely worth acting on. This is the rule the whole panel now follows: amber
  means something you can act on, not a fact about how Linux routing works.
- The routing row's detail claims only what was tested. It said "Binding to the
  physical address does not escape the tunnel", which is broader than the lookup
  behind it.

## [0.1.0] - 2026-09-04

First release.

### Added

- A bar widget and panel reporting VPN and DNS posture behind one glyph: the
  tunnel interface and protocol, the exit address with the operator hosting it
  and its AS number, the city and country, the real address underneath, the ISP
  that issued it, where DNS queries surface, and whether IPv6 is carried,
  blocked or leaking. Every row carries a green, amber or red indicator.
- A collector, `bin/vpn-check`, that prints one JSON verdict and makes every
  judgement, so the whole policy lives in one file that also runs from a
  terminal. The QML panel renders that verdict and decides nothing.
- Checks that never cause the leak they test for. Whether traffic can escape the
  tunnel is answered with `ip route get`, which consults the routing tables and
  returns without transmitting. Probing past the tunnel to see where a packet
  lands would disclose the real address to whoever answered, which is the harm
  being tested for.
- A real-address source that never bypasses the tunnel: observed live while no
  tunnel was up and cached, read back from that cache with a date, or the
  globally routable IPv6 address the ISP has already assigned to the physical
  interface.
- Unencrypted DNS judged by where the queries travel rather than by whether the
  setting is on. If every configured resolver is reachable only down the tunnel,
  plaintext is green, because encrypting to the VPN's own resolver would encrypt
  to the party already answering the query.

### Fixed

- A blocked IPv6 route is no longer called a leak. The row read the interface an
  IPv6 packet would leave by and called anything other than the tunnel an
  escape. A VPN that cannot carry IPv6 may block it with a default route into
  a dummy device such as `ipv6leakintrf0`, held up by the `pvpn-killswitch-ipv6`
  connection. A dummy discards what is routed into it, so those packets never
  reach the wire, but `ip route get` names that interface exactly as it would
  name a real escape. The panel reported "Leaking" while sitting directly below
  its own green "Kill switch: Active". The interface kind is now checked before
  the verdict, and the IPv4 routing row takes the same rule.
- IPv6 prefixes are compared as networks rather than as text. The old check
  compared the first four colon-separated groups, which are not the first 64
  bits whenever `::` or a leading zero falls inside them: `2001:db8::5` and
  `2001:db8::a1b2:c3d4:e5f6:7890` are one /64 that a text compare reads as two.
  The failure was silent and went one way, reporting an exit address inside the
  ISP's own prefix as carried by the tunnel, and it needed a zero group inside
  the /64, so a prefix whose four groups are all non-zero was never affected.

[0.2.0]: https://github.com/brightwalker25/omarchy-vpn-check/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/brightwalker25/omarchy-vpn-check/releases/tag/v0.1.0
