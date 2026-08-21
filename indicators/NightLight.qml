import QtQuick
import qs.Ui

// Visual only. Every side effect and all state live in the contra.nightlight
// service singleton: this file is instantiated twice over (the active strip
// and the hover fold-out) and again per monitor, so a local property plus a
// Process here would desync -- click one copy off and the others keep thinking
// it is on.
//
// The glyph tracks how deep the sunset ramp has got: sun before it starts,
// then setting sun, moon, and waning crescent at the floor.
BarIndicator {
  id: root

  readonly property var sunset: bar?.shell?.serviceFor("contra.nightlight")
  // Falls back to the stock toggle if the plugin is disabled or removed, so
  // this mark keeps working either way.
  readonly property var builtin: bar?.shell?.firstPartyServiceFor("omarchy.nightlight")

  readonly property string stage: sunset ? sunset.stage : "day"
  readonly property bool paused: sunset ? sunset.paused : false

  active: sunset ? sunset.tinted : (builtin ? builtin.enabled : false)

  activeText: stage === "dusk" ? "󰖜" : stage === "night" ? "󰖔" : "󰽤"
  inactiveText: "󰖙"

  activeTooltipText: {
    if (!root.sunset) return "Day Light"
    var t = root.sunset.temperature
    var now = (t === null ? "off" : t + "K")
    return root.sunset.stageLabel + " · " + now + " — click to pause"
  }

  inactiveTooltipText: {
    if (!root.sunset) return "Night Light"
    if (root.paused) return "Night light paused — click to resume"
    if (!root.sunset.running) return "hyprsunset is not running"
    return "Night light starts at sunset (" + root.sunset.status.sunset + ")"
  }

  onPressed: function() {
    if (root.sunset) root.sunset.togglePause()
    else if (root.builtin) root.builtin.setNightlight(!root.active)
  }
}
