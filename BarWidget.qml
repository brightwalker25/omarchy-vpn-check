import QtQuick
import qs.Commons
import qs.Ui

// Derived from Omarchy's own `omarchy.weather` bar widget
// (https://github.com/basecamp/omarchy, MIT, Copyright (c) David Heinemeier
// Hansson). The injectPanel / open / close / closeForPopoutSwitch contract
// below is what the bar requires of any widget hosting a panel, and this file
// follows that implementation closely. See LICENSE for the full notice.

// One shield in the bar, tinted green, amber or red; every check lives in
// the panel.
//
// A stale tint is worse than none: it says "protected" long after the tunnel
// has dropped. So while the panel is closed the panel re-runs the local-only
// check once a minute (tunnel, routing, kill switch, DNS configuration; no
// packet leaves the machine, and it takes well under a tenth of a second),
// and the tint is the worst of that and any full check from the last fifteen
// minutes. A check that could not run shows amber.
BarWidget {
  id: root
  moduleName: "brightwalker25.vpn-check"

  // nf-md-shield. Present in JetBrainsMono Nerd Font, which is what the bar
  // falls back to, and already used by Omarchy's own Tailscale panel.
  readonly property string glyph: "󰒃"

  readonly property string status: panelLoader.item ? String(panelLoader.item.barStatus || "") : ""

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.poll) panelLoader.item.poll()
  }

  // Shape contract for shell.summon/hide/toggle routing: Bar.findPanelWidget
  // needs open/close/opened on the bar-widget root, not on the nested panel.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  // The bar prefers closeForPopoutSwitch over close when handing one panel
  // over to another, and reads popoutSwitchClosing back off the owner.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    slotSize: Style.bar.iconSlot
    tooltipText: ""

    // The active colour is how the bar tints a glyph. The same fixed green,
    // amber and red as the panel and the other brightwalker25 widgets.
    useActiveColor: true
    active: root.status !== ""
    activeColor: root.status === "bad" ? "#f85149"
      : (root.status === "warn" ? "#d29922" : "#3fb950")

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}
