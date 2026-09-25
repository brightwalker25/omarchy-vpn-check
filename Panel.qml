import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The panel scaffolding here -- the open/close and IPC contract -- is derived
// from Omarchy's `omarchy.weather` and `omarchy.agents` plugins
// (https://github.com/basecamp/omarchy, MIT, Copyright (c) David Heinemeier
// Hansson). See LICENSE for the full notice.

// The panel behind the bar glyph: where your traffic surfaces, who runs that
// address, where DNS resolves from, and what your own address is underneath.
//
// It renders whatever `bin/vpn-check` hands it and decides nothing itself.
// Every judgement -- what counts as a leak, when amber becomes red -- is made
// in that script, which runs fine from a terminal with no compositor
// involved. The panel's only job is to draw the verdict.
Panel {
  id: root
  moduleName: "brightwalker25.vpn-check"
  ipcTarget: "brightwalker25.vpn-check"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  // The bar tracks the widget mounted in its slot, not this nested panel, so
  // the popout coordinator has to be handed that widget as the identity.
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Traffic-light colours are fixed rather than drawn from the theme. A theme
  // is free to define its urgent colour as a soft pink, and a danger signal
  // that reads as decoration is not a danger signal. These three are chosen
  // to hold their contrast on both light and dark backgrounds.
  readonly property color okColor: "#3fb950"
  readonly property color warnColor: "#d29922"
  readonly property color badColor: "#f85149"

  function statusColor(status) {
    if (status === "ok") return root.okColor
    if (status === "warn") return root.warnColor
    if (status === "bad") return root.badColor
    return root.dim
  }

  readonly property int refreshMs: Math.max(10000, Number(setting("refreshIntervalMs", 60000)))
  readonly property int lookupTimeout: Math.max(2, Number(setting("lookupTimeoutSeconds", 6)))
  readonly property string ipinfoToken: String(setting("ipinfoToken", ""))

  // How often the bar re-runs the local-only check while the panel is closed.
  readonly property int barRefreshMs: Math.max(15000, Number(setting("barRefreshIntervalMs", 60000)))
  // How long a full check's network verdict (exit address, DNS leak) still
  // counts toward the bar tint after the panel closes.
  readonly property int fullVerdictMs: 15 * 60 * 1000

  property var rep: null
  property string error: ""
  property bool checking: false
  property real repAt: 0

  // The bar's own snapshot, from `vpn-check --local`: tunnel, routing, kill
  // switch and DNS configuration, all read from the kernel and resolver
  // without sending a packet. Kept apart from `rep` so a closed panel never
  // shows local-only rows in place of the full check.
  property var localRep: null
  property string localError: ""
  property real clock: 0

  // ok, warn or bad for the bar glyph: the worst of the latest local check
  // and any full check from the last fifteen minutes. A check that could not
  // run is warn, since a silent failure would otherwise look like all is well.
  readonly property string barStatus: {
    var rank = { "ok": 1, "warn": 2, "bad": 3 }
    var worst = ""
    var seen = []
    if (root.localRep) seen.push(String(root.localRep.overall || ""))
    if (root.rep && (root.opened || root.clock - root.repAt < root.fullVerdictMs))
      seen.push(String(root.rep.overall || ""))
    if (seen.length === 0) return (root.localError !== "" || root.error !== "") ? "warn" : ""
    for (var i = 0; i < seen.length; i++) {
      var s = rank[seen[i]] ? seen[i] : "warn"
      if (!worst || rank[s] > rank[worst]) worst = s
    }
    return worst
  }

  // Shipped inside the plugin and found relative to it, so there is no PATH
  // step to forget on the next machine.
  readonly property string collector: String(Qt.resolvedUrl("bin/vpn-check")).replace(/^file:\/\//, "")

  readonly property var grouped: {
    var out = []
    if (!rep || !rep.sections || !rep.checks) return out
    for (var i = 0; i < rep.sections.length; i++) {
      var name = rep.sections[i]
      var items = []
      for (var j = 0; j < rep.checks.length; j++)
        if (rep.checks[j].section === name) items.push(rep.checks[j])
      if (items.length > 0) out.push({ section: name, items: items })
    }
    return out
  }

  function poll() {
    if (proc.running) return
    root.checking = true
    proc.running = true
  }

  function ingest(text) {
    var parsed = null
    try {
      parsed = JSON.parse(String(text))
    } catch (e) {
      root.error = "Could not parse collector output"
      return
    }
    if (!parsed || typeof parsed !== "object") return
    root.error = ""
    root.rep = parsed
    root.repAt = Date.now()
    root.clock = root.repAt
  }

  function ingestLocal(text) {
    var parsed = null
    try {
      parsed = JSON.parse(String(text))
    } catch (e) {
      root.localError = "Could not parse collector output"
      root.localRep = null
      return
    }
    if (!parsed || typeof parsed !== "object") return
    root.localError = ""
    root.localRep = parsed
  }

  Process {
    id: proc
    command: [root.collector, "--timeout", String(root.lookupTimeout)]
    // The token goes through the environment rather than argv, because argv
    // is readable by every process on the machine and a token is a secret.
    environment: ({ "IPINFO_TOKEN": root.ipinfoToken })
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.ingest(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || "").trim()
        if (t !== "") root.error = t
      }
    }
    onExited: function(exitCode) {
      root.checking = false
      if (exitCode !== 0 && root.error === "")
        root.error = "Collector exited " + exitCode
    }
  }

  Process {
    id: localProc
    command: [root.collector, "--local"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.ingestLocal(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.localError = "Collector exited " + exitCode
        root.localRep = null
      }
    }
  }

  // Keeps the bar tint current while the panel is closed. Local only, so
  // nothing reaches out to the network when nobody is looking; the full
  // check with its outbound lookups still runs only while the panel is open.
  Timer {
    running: !root.opened
    interval: root.barRefreshMs
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.clock = Date.now()
      if (!localProc.running) localProc.running = true
    }
  }

  // Runs only while the panel is open, because it reaches out to the network.
  Timer {
    running: root.opened
    interval: root.refreshMs
    repeat: true
    triggeredOnStart: true
    onTriggered: root.poll()
  }

  function fmtChecked() {
    if (!root.rep || !root.rep.generatedAt) return ""
    var d = new Date(root.rep.generatedAt * 1000)
    return "checked " + Qt.formatTime(d, "HH:mm:ss")
  }

  // ------------------------------------------------------- open/close contract

  property bool openedFromHotkey: false

  function open() {
    openedFromHotkey = false
    root.controller.show()
    root.poll()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    root.poll()
  }

  function close() { root.controller.hide() }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      root.bar.switchPanelFrom(root.barIdentity, direction)
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.poll() }
  }

  // ------------------------------------------------------------- components

  // The indicator itself. Small, and the only thing on the row carrying
  // colour, so the colour means one thing and is never decorative.
  component StatusDot: Rectangle {
    property string status: "unknown"
    implicitWidth: Style.space(9)
    implicitHeight: Style.space(9)
    radius: width / 2
    color: root.statusColor(status)
    Behavior on color { ColorAnimation { duration: 180 } }
  }

  // One check: dot, what was checked, and what it came back as. The detail
  // line underneath carries the reasoning, so the row above stays scannable.
  component CheckRow: Column {
    id: checkRow
    property var item: null
    spacing: Style.spacing.xxs

    Item {
      width: checkRow.width
      implicitHeight: Math.max(dot.height, rowLabel.implicitHeight, rowValue.implicitHeight)

      StatusDot {
        id: dot
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        status: checkRow.item ? checkRow.item.status : "unknown"
      }

      Text {
        id: rowLabel
        anchors.left: dot.right
        anchors.leftMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
        text: checkRow.item ? checkRow.item.label : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        id: rowValue
        anchors.right: parent.right
        anchors.left: rowLabel.right
        anchors.leftMargin: Style.spacing.controlGap
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        // An address that has been elided is not an address, so the value
        // wraps rather than truncating and the row grows to fit it.
        wrapMode: Text.WrapAnywhere
        text: checkRow.item ? checkRow.item.value : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }

    Text {
      width: checkRow.width - Style.space(9) - Style.spacing.sm
      x: Style.space(9) + Style.spacing.sm
      visible: text !== ""
      text: checkRow.item && checkRow.item.detail ? checkRow.item.detail : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }

  component SectionHeading: Column {
    id: heading
    property string title: ""
    spacing: Style.spacing.sm
    PanelSeparator { width: heading.width; foreground: root.foreground }
    PanelSectionHeader {
      text: heading.title
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
  }

  // ------------------------------------------------------------------ layout

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(820))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: column
          width: flick.width
          spacing: Style.spacing.lg

          // ---- Hero: the address the internet currently sees, the verdict
          // over it in one word, and who owns that address. Everything below
          // is the working behind these three lines.
          Column {
            width: parent.width
            spacing: Style.spacing.xxs

            Row {
              spacing: Style.spacing.sm

              StatusDot {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(11)
                height: Style.space(11)
                status: root.rep ? root.rep.overall : "unknown"
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.rep ? root.rep.headline : (root.checking ? "Checking" : "Not checked yet")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }

            Text {
              width: parent.width
              text: root.rep && root.rep.exitIp !== "" ? root.rep.exitIp : "—"
              color: root.foreground
              font.family: root.fontFamily
              // Hero read-out, deliberately outside the Style.font.* scale.
              font.pixelSize: 28
              font.bold: true
              wrapMode: Text.WrapAnywhere
            }

            Text {
              width: parent.width
              visible: text !== ""
              text: root.rep && root.rep.summary ? root.rep.summary : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Text {
              visible: text !== ""
              text: root.checking ? "checking…" : root.fmtChecked()
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // ---- Every check, grouped as the collector grouped them. The panel
          // does not know what the sections are or what order they come in.
          Repeater {
            model: root.grouped
            delegate: Column {
              required property var modelData
              width: column.width
              spacing: Style.spacing.lg

              SectionHeading { width: parent.width; title: modelData.section }

              Column {
                width: parent.width
                spacing: Style.spacing.md

                Repeater {
                  model: modelData.items
                  delegate: CheckRow {
                    required property var modelData
                    width: parent.width
                    item: modelData
                  }
                }
              }
            }
          }

          // Collector failures are shown rather than swallowed. A panel that
          // silently draws stale results is the failure mode worth avoiding.
          Column {
            width: parent.width
            spacing: Style.spacing.xs
            visible: root.error !== "" || (root.rep && root.rep.errors && root.rep.errors.length > 0)

            PanelSeparator { width: parent.width; foreground: root.foreground }

            Text {
              width: parent.width
              visible: root.error !== ""
              text: root.error
              color: root.badColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: root.rep && root.rep.errors ? root.rep.errors : []
              delegate: Text {
                required property var modelData
                width: column.width
                text: modelData
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
          }
        }
      }
    }
  }
}
