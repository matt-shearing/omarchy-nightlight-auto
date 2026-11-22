import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// The night light mark for a cloned indicators widget.
//
// Click to pause the sunset ramp (screen goes untinted and stays that way),
// click again to resume it. The glyph follows how deep the ramp has got: sun
// before it starts or while paused, then setting sun, moon, and new moon at
// the floor.
//
// This mark runs `nightlight-auto` itself rather than going through the
// contra.nightlight service. Omarchy's shell only hands a plugin its own
// service, and this file lives in the indicators widget, so the service is out
// of reach. The mark is instantiated more than once (active strip, hover
// fold-out, each monitor), so every copy re-reads the status on a short timer
// and right after any click; they settle on the same answer within seconds.
BarIndicator {
  id: root

  readonly property string cli: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/contra.nightlight/bin/nightlight-auto"

  property bool ok: false
  property bool isSetup: false
  property bool running: false
  property bool paused: false
  property var temperature: null
  property int eveningTemp: 0
  property int nightTemp: 0
  property string sunsetAt: ""
  property bool busy: false

  readonly property bool tinted: ok && !paused && temperature !== null

  // 0 at the start of the evening ramp, 1 at its deepest. In mireds, as the
  // ladder is built.
  readonly property real rampFraction: {
    if (temperature === null || !eveningTemp || !nightTemp) return 0
    if (eveningTemp === nightTemp) return 1
    var f = (1e6 / temperature - 1e6 / eveningTemp) / (1e6 / nightTemp - 1e6 / eveningTemp)
    return Math.max(0, Math.min(1, f))
  }
  readonly property string stage: !tinted ? "day"
    : rampFraction < 0.34 ? "dusk"
    : rampFraction < 0.75 ? "night" : "deep"

  // Paused counts as active so the mark stays on screen: an inactive indicator
  // is hidden from the strip, and a click that hid the only control for undoing
  // it would strand you. Paused is worth seeing in daylight too.
  active: tinted || paused

  activeText: paused ? "󰖙"
    : stage === "dusk" ? "󰖜"
    : stage === "night" ? "󰖔" : "󰽤"
  inactiveText: "󰖙"

  activeTooltipText: {
    if (paused) return "Night light off - click to turn it back on"
    var label = stage === "dusk" ? "Warming" : stage === "night" ? "Warm" : "Warmest"
    return label + " · " + temperature + "K - click to turn off"
  }
  inactiveTooltipText: {
    if (!ok) return "Night light - nightlight-auto not found"
    if (!isSetup) return "Night light - run: nightlight-auto setup"
    if (!running) return "Night light - hyprsunset is not running"
    return "Night light starts at sunset (" + sunsetAt + ") - click to keep it off"
  }

  onPressed: function() {
    if (root.busy || !root.ok || !root.isSetup) return
    root.busy = true
    // Optimistic, so the click shows at once; the status read confirms it.
    root.paused = !root.paused
    actionProc.command = [root.cli, "toggle"]
    actionProc.running = true
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function applyStatus(raw) {
    try {
      var d = JSON.parse(String(raw || "").trim())
      root.ok = true
      root.isSetup = d.setup === true
      root.running = d.running === true
      root.paused = d.paused === true
      var t = Number(d.scheduled_temperature)
      root.temperature = d.scheduled_temperature === null || !isFinite(t) ? null : t
      root.eveningTemp = Number(d.evening_temp) || 0
      root.nightTemp = Number(d.night_temp) || 0
      root.sunsetAt = String(d.sunset || "")
    } catch (e) {
      root.ok = false
    }
  }

  Process {
    id: statusProc
    command: [root.cli, "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
  }

  Process {
    id: actionProc
    onExited: {
      root.busy = false
      root.refresh()
      // hyprsunset restarts on pause/resume; read again once it has settled.
      settleTimer.restart()
    }
  }

  Timer {
    id: settleTimer
    interval: 1500
    onTriggered: root.refresh()
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
