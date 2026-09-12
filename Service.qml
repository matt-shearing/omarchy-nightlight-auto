import QtQuick
import Quickshell
import Quickshell.Io

// The shell-hosted host of the night light state owner.
//
// Service.qml is mounted by omarchy-shell (kinds: service) and is what
// bar.shell.serviceFor("contra.nightlight") resolves to under the trusted
// built-in bar. All state lives in the single embedded Client; everything
// below just forwards, so consumers (widgets, indicator marks, IPC) see the
// exact same surface they always have.
//
// Under a replacement/third-party bar this host is out of reach -- the facade
// cannot resolve live service objects (Omarchy 4.0.3 scopes them to the
// trusted built-in bar). The widget then embeds its own Client instead; see
// Client.qml for how both hosts share one definition of the state.
Item {
  id: root

  // Injected by omarchy-shell's service loader.
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null

  Client { id: client; onChanged: root.changed() }

  readonly property var status: client.status
  readonly property var steps: client.steps
  readonly property bool busy: client.busy
  readonly property bool ok: client.ok
  readonly property bool isSetup: client.isSetup
  readonly property string disclosure: client.disclosure
  readonly property bool running: client.running
  readonly property bool paused: client.paused
  readonly property bool tinted: client.tinted
  readonly property var temperature: client.temperature
  readonly property real rampFraction: client.rampFraction
  readonly property string stage: client.stage
  readonly property string stageLabel: client.stageLabel

  signal changed()

  function refresh() { client.refresh() }
  function acceptSetup() { client.acceptSetup() }
  function pause() { client.pause() }
  function resume() { client.resume() }
  function togglePause() { client.togglePause() }
  function rebuild() { client.rebuild() }

  IpcHandler {
    target: "contra.nightlight"

    function status(): string {
      return JSON.stringify({
        setup: root.isSetup,
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