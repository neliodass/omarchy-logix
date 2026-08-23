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
  readonly property bool isMouse: Model.isMouse(device)
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
    Qt.callLater(function() {
      if (root.bar && root.bar.shell && typeof root.bar.shell.summon === "function") {
        var payload = device && device.id ? { device: device.id } : {}
        root.bar.shell.summon("io.openlogi.omarchy", JSON.stringify(payload))
      }
    })
  }

  contentItem: Column {
    id: column
    width: 320
    spacing: 12
    padding: 14

    // Header Card
    Rectangle {
      width: parent.width - 28
      height: 64
      radius: 8
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

      Row {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 12

        OpenLogiIcon {
          anchors.verticalCenter: parent.verticalCenter
          iconSize: 28
          color: root.accent
          lowBattery: mx ? mx.batteryLow : false
          isKeyboard: Model.isKeyboard(device)
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - 44
          spacing: 2

          Text {
            text: device ? Model.plainHidText(device.name) : (mx && mx.message ? mx.message : "No Device")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 14
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
          }

          Row {
            spacing: 6
            Text {
              text: device ? (Model.connectionLabel(device) + " · " + Model.batteryLabel(device)) : "Offline"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: 11
            }
          }
        }
      }
    }

    // Device Switcher (if multiple)
    Column {
      visible: root.showDevices
      width: parent.width - 28
      spacing: 4

      Text {
        text: "Connected Devices"
        color: root.dim
        font.pixelSize: 11
        font.bold: true
      }

      Row {
        spacing: 6
        Repeater {
          model: mx ? mx.displayDevices : []
          delegate: Rectangle {
            width: 135
            height: 30
            radius: 6
            color: (device && modelData.id === device.id) ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

            Text {
              anchors.centerIn: parent
              text: Model.plainHidText(modelData.name)
              color: (device && modelData.id === device.id) ? "#ffffff" : root.foreground
              font.pixelSize: 11
              elide: Text.ElideRight
              width: parent.width - 12
              horizontalAlignment: Text.AlignHCenter
            }

            MouseArea {
              anchors.fill: parent
              onClicked: mx.selectDevice(modelData.id)
            }
          }
        }
      }
    }

    // Smart Ring / Action Ring Banner
    Rectangle {
      visible: root.isMouse && !!(device && device.capabilities && device.capabilities.action_ring)
      width: parent.width - 28
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
          width: parent.width - 110

          Text {
            text: "Smart Ring (Action Ring)"
            color: root.foreground
            font.pixelSize: 12
            font.bold: true
          }
          Text {
            text: "8 radial slots & gestures active"
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

    // DPI Section
    Column {
      visible: root.isMouse
      width: parent.width - 28
      spacing: 6

      Row {
        width: parent.width
        Text {
          text: "Pointer Speed (DPI)"
          color: root.dim
          font.pixelSize: 11
          font.bold: true
        }
        Item { width: 1; height: 1; Layout.fillWidth: true }
        Text {
          anchors.right: parent.right
          text: (device && device.dpi ? device.dpi : 1000) + " DPI"
          color: root.accent
          font.pixelSize: 11
          font.bold: true
        }
      }

      // DPI Preset Pills
      Row {
        spacing: 4
        Repeater {
          model: [800, 1000, 1600, 2400, 4000, 8000]
          delegate: Rectangle {
            width: 44
            height: 24
            radius: 4
            color: (device && device.dpi === modelData) ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

            Text {
              anchors.centerIn: parent
              text: modelData >= 1000 ? (modelData / 1000) + "K" : modelData
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
    }

    // SmartShift Section
    Column {
      visible: root.isMouse && !!(device && device.capabilities && device.capabilities.smartshift)
      width: parent.width - 28
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
        spacing: 6
        Repeater {
          model: [
            { id: "auto", label: "Smart Auto" },
            { id: "ratchet", label: "Click-to-Click" },
            { id: "freewheel", label: "Free Spin" }
          ]
          delegate: Rectangle {
            width: 90
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
      width: parent.width - 28
      spacing: 4

      Text {
        text: "Scroll Settings"
        color: root.dim
        font.pixelSize: 11
        font.bold: true
      }

      Row {
        spacing: 12

        // Invert Y Toggle
        Rectangle {
          width: 135
          height: 28
          radius: 6
          property bool invertY: device && device.scroll ? device.scroll.invert_y : false
          color: invertY ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.2) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

          Row {
            anchors.centerIn: parent
            spacing: 6
            Text { text: "⇅"; color: parent.parent.invertY ? root.accent : root.foreground; font.pixelSize: 12 }
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

        // Hi-Res Scroll Toggle
        Rectangle {
          width: 135
          height: 28
          radius: 6
          property bool hires: device && device.scroll ? device.scroll.hires : true
          color: hires ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.2) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

          Row {
            anchors.centerIn: parent
            spacing: 6
            Text { text: "⚡"; color: parent.parent.hires ? root.accent : root.foreground; font.pixelSize: 12 }
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
      width: parent.width - 28
      height: 1
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
    }

    // Footer Buttons
    Row {
      width: parent.width - 28
      spacing: 8

      Button {
        width: parent.width - 40
        text: "Open Settings & Smart Ring"
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
