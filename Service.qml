import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// The single owner of night light state.
//
// Everything that reads this can exist more than once on screen: bar widgets
// are instantiated once per monitor, and an indicator mark is instantiated
// twice over (the active strip and the hover fold-out). If each copy ran its
// own Process they would drift, and a click on one copy would leave the others
// showing stale state. So all the shelling out happens here, exactly once, and
// the visual pieces only read properties and call these functions.
Item {
  id: root

  // Injected by omarchy-shell's service loader.
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null

  readonly property string pluginDir: Model.pluginDirFromUrl(Qt.resolvedUrl("."))
  // Absolute path: the shell's PATH starts with $OMARCHY_PATH/bin, so a bare
  // name would resolve to a packaged command and never reach ours.
  readonly property string cli: root.pluginDir + "/bin/nightlight-auto"

  property var status: Model.emptyStatus()
  property var steps: []
  property bool busy: false

  readonly property bool ok: status.ok
  readonly property bool running: status.running
  readonly property bool paused: status.paused
  // "Tinted" means the schedule is actually warming the screen right now, as
  // opposed to sitting on the untinted day profile.
  readonly property bool tinted: status.ok && !status.paused
                                 && status.scheduledTemperature !== null
  readonly property var temperature: status.scheduledTemperature

  // 0 at the start of the evening ramp, 1 at its deepest point.
  readonly property real rampFraction: Model.rampFraction(
    status.scheduledTemperature, status.eveningTemp, status.nightTemp)

  // "day" | "dusk" | "night" | "deep". Consumers map this to a glyph; keeping
  // the thresholds here means the bar widget and any indicator mark reading
  // this service can never disagree about which stage we are in.
  readonly property string stage: Model.rampStage(root.tinted, root.rampFraction)
  readonly property string stageLabel: Model.stageLabel(root.stage)

  signal changed()

  function refresh() {
    if (!statusProc.running) statusProc.running = true
    if (!stepsProc.running) stepsProc.running = true
  }

  function run(args) {
    if (root.busy) return
    root.busy = true
    actionProc.command = [root.cli].concat(args)
    actionProc.running = true
  }

  function pause() { run(["pause"]) }
  function resume() { run(["resume"]) }
  function togglePause() { run(["toggle"]) }
  function rebuild() { run(["generate", "--force"]) }

  Process {
    id: statusProc
    command: [root.cli, "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.status = Model.parseStatus(text)
        root.changed()
      }
    }
  }

  Process {
    id: stepsProc
    command: [root.cli, "show", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || "").trim())
          root.steps = (data && data.steps) ? data.steps : []
        } catch (e) {
          root.steps = []
        }
      }
    }
  }

  Process {
    id: actionProc
    onExited: {
      root.busy = false
      // A pause or rebuild restarts hyprsunset, which takes a moment to come
      // back and answer, so re-read once it has settled as well as immediately.
      Qt.callLater(root.refresh)
      settleTimer.restart()
    }
  }

  Timer { id: settleTimer; interval: 1500; onTriggered: root.refresh() }

  // The schedule only steps every few minutes, so this can be lazy.
  Timer { interval: 60000; running: true; repeat: true; onTriggered: root.refresh() }

  Component.onCompleted: refresh()

  IpcHandler {
    target: "contra.nightlight"

    function status(): string {
      return JSON.stringify({
        paused: root.paused,
        running: root.running,
        temperature: root.temperature,
        tinted: root.tinted
      })
    }

    function refresh(): void { root.refresh() }
    function pause(): string { root.pause(); return "paused" }
    function resume(): string { root.resume(); return "resumed" }
    function toggle(): string { root.togglePause(); return root.paused ? "resuming" : "pausing" }
    function rebuild(): string { root.rebuild(); return "rebuilding" }
  }
}
