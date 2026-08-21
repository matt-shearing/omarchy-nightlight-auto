import QtQuick
import Quickshell
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

  // One singleton owns the state; this widget is instantiated once per monitor
  // and only reads from it. See Service.qml.
  readonly property var service: bar?.shell?.serviceFor("contra.nightlight")
  readonly property var status: service ? service.status : Model.emptyStatus()
  readonly property var steps: service ? service.steps : []
  readonly property bool busy: service ? service.busy : false

  readonly property string stage: service ? service.stage : "day"
  readonly property bool isSetup: service ? service.isSetup : false

  function refresh() { if (root.service) root.service.refresh() }
  function togglePause() { if (root.service) root.service.togglePause() }
  function rebuild() { if (root.service) root.service.rebuild() }
  function acceptSetup() { if (root.service) root.service.acceptSetup() }

  // No IpcHandler here on purpose: Service.qml already claims the
  // "contra.nightlight" target, and two handlers cannot share one. The panel
  // is summoned the standard way, with `omarchy-shell shell toggle
  // contra.nightlight`.

  onOpenedChanged: if (opened) refresh()

  // The service polls on its own; refresh faster only while the panel is open.
  Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  Component.onCompleted: refresh()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.stage === "day" ? "󰖙"
          : root.stage === "dusk" ? "󰖜"
          : root.stage === "night" ? "󰖔" : "󰽤"
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
    // Wider while onboarding: the disclosure is laid out in columns and wraps
    // badly if it is squeezed into the width the ladder needs.
    contentWidth: panel.fittedContentWidth(Style.space(root.isSetup ? 360 : 560))
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

        // Nothing has been written to the user's configuration at this point.
        // The disclosure below is `nightlight-auto setup --print` verbatim, so
        // what the button agrees to is exactly what the button then does.
        Column {
          visible: !root.isSetup
          width: parent.width
          spacing: Style.space(10)

          Text {
            width: parent.width
            text: "Not set up yet. Nothing on this machine has been changed."
            color: root.bar.foreground
            wrapMode: Text.WordWrap
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          Text {
            width: parent.width
            text: root.service && root.service.disclosure !== ""
                  ? root.service.disclosure
                  : "Reading what setup would change…"
            color: root.bar.foreground
            opacity: 0.75
            wrapMode: Text.WordWrap
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Button {
            text: root.busy ? "Setting up…" : "I agree — enable night light"
            enabled: !root.busy && root.service && root.service.disclosure !== ""
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            onClicked: root.acceptSetup()
          }
        }

        // What is on the screen right now, and what happens next.
        Column {
          visible: root.isSetup
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

        PanelSeparator { foreground: root.bar.foreground; visible: root.isSetup }

        Column {
          visible: root.isSetup
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

        PanelSeparator { foreground: root.bar.foreground; visible: root.isSetup }

        // Tonight's ladder. Each row carries the tint it will apply, so the
        // ramp is legible as a gradient rather than a column of numbers.
        Column {
          visible: root.isSetup
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

        PanelSeparator { foreground: root.bar.foreground; visible: root.isSetup }

        Row {
          visible: root.isSetup
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
