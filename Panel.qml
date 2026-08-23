import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.openlogi.omarchy"
  ipcTarget: "io.openlogi.omarchy"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var mx: null

  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color surface: Color.popups.background
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var device: mx ? mx.selectedDevice : null
  readonly property bool isMouse: device ? !Model.isKeyboard(device) : true
  readonly property bool showDevices: mx && mx.displayDevices && mx.displayDevices.length > 1

  function open() {
    root.controller.show()
    if (mx) {
      mx.ensureDaemon()
      mx.refresh()
    }
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) close()
    else open()
  }

  function openFullSettings() {
    root.close()
    // Directly summon settings window via Omarchy shell
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", "io.openlogi.omarchy", "{}"])
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(Math.max(column.implicitHeight, Style.space(280)), Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "r" || t === "R") { if (mx) mx.refresh() }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        anchors.margins: Style.space(12)
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: column
          width: panelFlick.width
          spacing: 10

          // Header Card
          Rectangle {
            width: parent.width
            height: 60
            radius: 8
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

            Row {
              anchors.fill: parent
              anchors.margins: 10
              spacing: 10

              OpenLogiIcon {
                anchors.verticalCenter: parent.verticalCenter
                iconSize: 26
                color: root.accent
                lowBattery: mx ? mx.batteryLow : false
                isKeyboard: Model.isKeyboard(device)
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 40
                spacing: 2

                Text {
                  text: device ? Model.plainHidText(device.name) : (mx && mx.message ? mx.message : "No Logitech Device")
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: 13
                  font.bold: true
                  elide: Text.ElideRight
                  width: parent.width
                }

                Text {
                  text: device ? (Model.connectionLabel(device) + " · Battery: " + Model.batteryLabel(device)) : "Scanning sysfs / HID++"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: 11
                }
              }
            }
          }

          // Smart Ring / Action Ring Banner
          Rectangle {
            visible: root.isMouse && !!(device && device.capabilities && device.capabilities.action_ring)
            width: parent.width
            height: 48
            radius: 8
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)
            border.color: root.accent
            border.width: 1

            Row {
              anchors.fill: parent
              anchors.margins: 8
              spacing: 8

              Text {
                text: "◎"
                color: root.accent
                font.pixelSize: 20
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 105

                Text {
                  text: "Smart Ring & Gestures"
                  color: root.foreground
                  font.pixelSize: 12
                  font.bold: true
                }
                Text {
                  text: "8 radial slots configured"
                  color: root.dim
                  font.pixelSize: 10
                }
              }

              Button {
                anchors.verticalCenter: parent.verticalCenter
                text: "Customize"
                onClicked: root.openFullSettings()
              }
            }
          }

          // Pointer Speed (DPI) Section
          Column {
            visible: root.isMouse
            width: parent.width
            spacing: 6

            Row {
              width: parent.width
              Text {
                text: "Pointer Speed (DPI)"
                color: root.dim
                font.pixelSize: 11
                font.bold: true
              }
              Item { width: 1; height: 1 }
              Text {
                anchors.right: parent.right
                text: (device && device.dpi ? device.dpi : 1000) + " DPI"
                color: root.accent
                font.pixelSize: 11
                font.bold: true
              }
            }

            // Perfectly fitted 6 DPI Preset Pills
            Row {
              id: dpiRow
              width: parent.width
              spacing: 4

              readonly property int pillWidth: Math.max(36, Math.floor((width - (5 * spacing)) / 6))

              Repeater {
                model: [800, 1000, 1600, 2400, 4000, 8000]
                delegate: Rectangle {
                  width: dpiRow.pillWidth
                  height: 24
                  radius: 4
                  color: (device && device.dpi === modelData) ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

                  Text {
                    anchors.centerIn: parent
                    text: modelData >= 1000 ? (modelData / 1000) + "K" : String(modelData)
                    color: (device && device.dpi === modelData) ? "#ffffff" : root.foreground
                    font.pixelSize: 10
                    font.bold: true
                  }

                  MouseArea {
                    anchors.fill: parent
                    onClicked: if (device) mx.setDpi(device.id, modelData)
                  }
                }
              }
            }

            // Fine DPI Slider
            Slider {
              width: parent.width
              from: 200
              to: 8000
              stepSize: 50
              value: device && device.dpi ? device.dpi : 1000
              onMoved: {
                if (device) mx.setDpi(device.id, Math.round(value))
              }
            }
          }

          // SmartShift Section
          Column {
            visible: root.isMouse && !!(device && device.capabilities && device.capabilities.smartshift)
            width: parent.width
            spacing: 6

            Row {
              width: parent.width
              Text {
                text: "SmartShift (Ratchet Wheel)"
                color: root.dim
                font.pixelSize: 11
                font.bold: true
              }
              Text {
                anchors.right: parent.right
                text: device && device.smartshift ? device.smartshift.mode.toUpperCase() : "AUTO"
                color: root.accent
                font.pixelSize: 11
              }
            }

            Row {
              id: smartShiftRow
              width: parent.width
              spacing: 4

              readonly property int btnWidth: Math.max(70, Math.floor((width - (2 * spacing)) / 3))

              Repeater {
                model: [
                  { id: "auto", label: "Smart Auto" },
                  { id: "ratchet", label: "Ratchet" },
                  { id: "freewheel", label: "Free Spin" }
                ]
                delegate: Rectangle {
                  width: smartShiftRow.btnWidth
                  height: 26
                  radius: 5
                  property bool isSelected: device && device.smartshift && device.smartshift.mode === modelData.id
                  color: isSelected ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

                  Text {
                    anchors.centerIn: parent
                    text: modelData.label
                    color: parent.isSelected ? "#ffffff" : root.foreground
                    font.pixelSize: 10
                  }

                  MouseArea {
                    anchors.fill: parent
                    onClicked: {
                      if (device) {
                        var thresh = device.smartshift ? device.smartshift.threshold : 12
                        mx.setSmartShift(device.id, modelData.id, thresh)
                      }
                    }
                  }
                }
              }
            }
          }

          // Scroll Options
          Column {
            visible: root.isMouse
            width: parent.width
            spacing: 4

            Text {
              text: "Scroll Settings"
              color: root.dim
              font.pixelSize: 11
              font.bold: true
            }

            Row {
              id: scrollRow
              width: parent.width
              spacing: 6

              readonly property int toggleWidth: Math.max(100, Math.floor((width - spacing) / 2))

              Rectangle {
                width: scrollRow.toggleWidth
                height: 28
                radius: 6
                property bool invertY: device && device.scroll ? device.scroll.invert_y : false
                color: invertY ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.2) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

                Row {
                  anchors.centerIn: parent
                  spacing: 4
                  Text { text: "⇅"; color: parent.parent.invertY ? root.accent : root.foreground; font.pixelSize: 11 }
                  Text { text: "Invert Wheel"; color: parent.parent.invertY ? root.accent : root.foreground; font.pixelSize: 10 }
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    if (device && device.scroll) {
                      mx.setScroll(device.id, !device.scroll.invert_y, device.scroll.invert_thumb, device.scroll.hires)
                    }
                  }
                }
              }

              Rectangle {
                width: scrollRow.toggleWidth
                height: 28
                radius: 6
                property bool hires: device && device.scroll ? device.scroll.hires : true
                color: hires ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.2) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

                Row {
                  anchors.centerIn: parent
                  spacing: 4
                  Text { text: "⚡"; color: parent.parent.hires ? root.accent : root.foreground; font.pixelSize: 11 }
                  Text { text: "Smooth Scroll"; color: parent.parent.hires ? root.accent : root.foreground; font.pixelSize: 10 }
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    if (device && device.scroll) {
                      mx.setScroll(device.id, device.scroll.invert_y, device.scroll.invert_thumb, !device.scroll.hires)
                    }
                  }
                }
              }
            }
          }

          // Divider
          Rectangle {
            width: parent.width
            height: 1
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
          }

          // Footer Buttons
          Row {
            width: parent.width
            spacing: 6

            Button {
              width: parent.width - 38
              text: "All Settings & Button Remaps"
              onClicked: root.openFullSettings()
            }

            Button {
              width: 32
              text: "↻"
              onClicked: if (mx) mx.refresh()
            }
          }
        }
      }
    }
  }
}
