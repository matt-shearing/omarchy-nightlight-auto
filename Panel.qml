import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar widget for nightlight-auto. All state comes from the CLI in bin/, which
// is the same thing the systemd timer drives -- the widget never computes a
// schedule of its own, so what it shows is always what is actually loaded.
Panel {
  id: root
  moduleName: "contra.nightlight"
  ipcTarget: "contra.nightlight"
  manageIpc: false

  property var status: Model.emptyStatus()
  property var steps: []
  property bool busy: false

  readonly property string pluginDir: Model.pluginDirFromUrl(Qt.resolvedUrl("."))
  // Absolute path on purpose: the shell's PATH starts with $OMARCHY_PATH/bin,
  // so a bare name would never reach a user-installed helper.
  readonly property string cli: root.pluginDir + "/bin/nightlight-auto"

  readonly property bool warm: root.status.ok && !root.status.paused
                               && root.status.scheduledTemperature !== null

  function refresh() {
    if (!statusProc.running) statusProc.running = true
    if (root.opened && !stepsProc.running) stepsProc.running = true
  }

  function run(args) {
    if (actionProc.running) return
    root.busy = true
    actionProc.command = [root.cli].concat(args)
    actionProc.running = true
  }

  function togglePause() { run(["toggle"]) }
  function rebuild() { run(["generate", "--force"]) }

  IpcHandler {
    target: "contra.nightlight"
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function pause() { root.run(["pause"]) }
    function resume() { root.run(["resume"]) }
    function rebuild() { root.rebuild() }
  }

  onOpenedChanged: if (opened) refresh()

  Process {
    id: statusProc
    command: [root.cli, "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.status = Model.parseStatus(text)
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
      Qt.callLater(function() { root.refresh() })
    }
  }

  // A restart of hyprsunset takes a moment to settle, so poll a little faster
  // while the panel is open than while it is just sitting in the bar.
  Timer { interval: 30000; running: true; repeat: true; onTriggered: root.refresh() }
  Timer { interval: 2000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  Component.onCompleted: refresh()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.warm ? "󰖔" : "󰖙"
    // Urgent colour is for a fault, not for the normal warm evening: the only
    // real fault here is hyprsunset being down, when nothing is applied at all.
    active: root.status.ok && !root.status.running
    tooltipText: Model.summaryLine(root.status)
    onPressed: function(b) {
      if (b === Qt.RightButton) root.togglePause()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        Text {
          text: "Sunset Night Light"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        PanelSeparator { foreground: root.bar.foreground }

        // What is on the screen right now, and what happens next.
        Column {
          width: parent.width
          spacing: Style.space(4)

          Row {
            width: parent.width
            spacing: Style.space(8)

            Rectangle {
              width: Style.space(12)
              height: Style.space(12)
              radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: Model.temperatureColor(root.status.scheduledTemperature)
              border.width: 1
              border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
                                    root.bar.foreground.b, 0.35)
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: {
                if (!root.status.ok) return "No schedule loaded"
                if (root.status.paused) return "Paused"
                return Model.tempLabel(root.status.scheduledTemperature)
                       + " since " + root.status.scheduledSince
              }
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          Text {
            width: parent.width
            visible: root.status.ok && !root.status.paused && root.status.nextAt !== ""
            text: "Next  " + Model.tempLabel(root.status.nextTemperature)
                  + " at " + root.status.nextAt
            color: root.bar.foreground
            opacity: 0.6
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            width: parent.width
            visible: root.status.paused
            text: "The display stays untinted until you resume."
            color: root.bar.foreground
            opacity: 0.6
            wrapMode: Text.WordWrap
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            width: parent.width
            visible: root.status.ok && !root.status.running
            text: "hyprsunset is not running, so nothing is applied. "
                  + "Start it with: systemctl --user start hyprsunset"
            color: root.bar.urgent
            wrapMode: Text.WordWrap
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        Column {
          width: parent.width
          spacing: Style.space(2)

          Text {
            width: parent.width
            text: "Sun  sets " + root.status.sunset + " · rises " + root.status.sunrise
            color: root.bar.foreground
            opacity: 0.75
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            width: parent.width
            text: Model.locationLabel(root.status) + "  ·  " + root.status.locationSource
            color: root.bar.foreground
            opacity: 0.5
            elide: Text.ElideRight
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            width: parent.width
            visible: root.status.estimated
            text: "The sun does not set here today; using the fallback times."
            color: root.bar.foreground
            opacity: 0.5
            wrapMode: Text.WordWrap
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // Tonight's ladder. Each row carries the tint it will apply, so the
        // ramp is legible as a gradient rather than a column of numbers.
        Column {
          width: parent.width
          spacing: Style.space(2)

          Text {
            visible: root.steps.length === 0
            width: parent.width
            text: "No steps to show."
            color: root.bar.foreground
            opacity: 0.5
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: root.steps
            Row {
              required property var modelData
              width: parent.width
              spacing: Style.space(8)

              Rectangle {
                width: Style.space(10)
                height: Style.space(10)
                radius: 2
                anchors.verticalCenter: parent.verticalCenter
                color: Model.temperatureColor(modelData.temperature)
                border.width: modelData.current ? 1 : 0
                border.color: root.bar.foreground
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.time
                color: root.bar.foreground
                opacity: modelData.current ? 1.0 : 0.7
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: modelData.current === true
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.temperature === null
                      ? "untinted" : (modelData.temperature + "K")
                color: root.bar.foreground
                opacity: modelData.current ? 1.0 : 0.55
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: modelData.current === true
              }
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            text: root.status.paused ? "Resume" : "Pause"
            iconText: root.status.paused ? "󰐊" : "󰏤"
            enabled: !root.busy
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            onClicked: root.togglePause()
          }

          Button {
            text: "Rebuild"
            iconText: "󰑐"
            tooltipText: "Recompute tonight's ramp and reload hyprsunset"
            enabled: !root.busy
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            onClicked: root.rebuild()
          }
        }
      }
    }
  }
}
