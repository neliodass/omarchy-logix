import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.logix.omarchy"
  ipcTarget: "io.logix.omarchy"
  manageIpc: false

  property var sharedMx: null
  readonly property var mx: sharedMx || localMx
  readonly property var device: mx ? mx.selectedDevice : null
  readonly property bool isMouse: device ? !Model.isKeyboard(device) : true
  readonly property bool showDevices: mx && mx.displayDevices && mx.displayDevices.length > 1

  readonly property var barIdentity: root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color surface: Color.popups.background
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property color iconColor: {
    if (!mx.hasDevice) return Qt.darker(barForeground, 1.55)
    if (mx.batteryLow) return bar && bar.urgent ? bar.urgent : Color.urgent
    return mx.online ? barForeground : Qt.darker(barForeground, 1.55)
  }

  function resolveService() {
    if (sharedMx) return
    var host = root.bar ? root.bar.shell : null
    if (!host) return
    var found = null
    if (typeof host.ensureService === "function") found = host.ensureService(root.moduleName) || null
    if (!found && typeof host.serviceFor === "function") found = host.serviceFor(root.moduleName)
    if (found) {
      sharedMx = found
      if ("settings" in found) found.settings = root.settings
      return
    }
    localMx.passive = false
  }

  onBarChanged: resolveService()
  onSettingsChanged: {
    if (sharedMx && "settings" in sharedMx) sharedMx.settings = root.settings
  }

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

  function refresh() {
    mx.refresh()
  }

  function showActionRing() {
    if (overlay) overlay.toggleRing()
  }

  function openFullSettings() {
    root.close()
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", "io.logix.omarchy", "{}"])
  }

  Service {
    id: localMx
    settings: root.settings
    passive: false
  }

  IpcHandler {
    target: "io.logix.omarchy"

    function refresh(): void { root.refresh() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function showActionRing(): void { root.showActionRing() }
  }

  ActionRingOverlay {
    id: overlay
    shell: root.bar ? root.bar.shell : null
    service: root.mx
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: {
      if (!mx.hasDevice) return "LogiX Control — No device connected"
      var name = Model.plainHidText(mx.selectedDevice && mx.selectedDevice.name ? mx.selectedDevice.name : "Logitech Device")
      var link = Model.connectionLabel(mx.selectedDevice)
      var battery = mx.batteryPercent >= 0 ? (" · " + mx.batteryPercent + "%") : ""
      return name + (link ? (" · " + link) : "") + battery
    }
    iconComponent: Component {
      LogiXIcon {
        iconSize: Style.bar.iconCanvas
        color: root.iconColor
        cutoutColor: root.bar ? root.bar.background : Color.background
        lowBattery: mx.batteryLow
        isKeyboard: Model.isKeyboard(mx.selectedDevice)
        badgeColor: root.bar && root.bar.urgent ? root.bar.urgent : Color.urgent
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refresh()
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

              LogiXIcon {
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
                  text: device ? (Model.connectionLabel(device) + " · Battery: " + Model.batteryLabel(device)) : "Scanning HID++ devices"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: 11
                }
              }
            }
          }

          // Permissions Warning Banner
          Rectangle {
            visible: !!(device && device.accessible === false)
            width: parent.width
            height: 48
            radius: 8
            color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.15)
            border.color: root.urgent
            border.width: 1

            RowLayout {
              anchors.fill: parent
              anchors.margins: 8
              spacing: 8

              Text {
                text: "⚠️"
                font.pixelSize: 18
              }

              Column {
                Layout.fillWidth: true
                Text {
                  text: "Permissions Required"
                  color: root.urgent
                  font.pixelSize: 11
                  font.bold: true
                }
                Text {
                  text: "Click to grant uaccess rule"
                  color: root.dim
                  font.pixelSize: 10
                }
              }

              Button {
                text: "Fix"
                onClicked: {
                  Quickshell.execDetached(["python3", root.mx.helperPath, "fix-permissions"])
                  Qt.callLater(root.refresh)
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

            RowLayout {
              anchors.fill: parent
              anchors.margins: 8
              spacing: 8

              Text {
                text: "◎"
                color: root.accent
                font.pixelSize: 20
              }

              Column {
                Layout.fillWidth: true
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

            RowLayout {
              width: parent.width
              Text {
                text: "Pointer Speed (DPI)"
                color: root.dim
                font.pixelSize: 11
                font.bold: true
              }
              Item { Layout.fillWidth: true }
              Text {
                text: (device && device.dpi ? device.dpi : 1000) + " DPI"
                color: root.accent
                font.pixelSize: 11
                font.bold: true
              }
            }

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

            RowLayout {
              width: parent.width
              Text {
                text: "SmartShift (Ratchet Wheel)"
                color: root.dim
                font.pixelSize: 11
                font.bold: true
              }
              Item { Layout.fillWidth: true }
              Text {
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
                        var thresh = device.smartshift && device.smartshift.threshold !== undefined ? device.smartshift.threshold : 10
                        var torq = device.smartshift && device.smartshift.torque !== undefined ? device.smartshift.torque : 75
                        mx.setSmartShift(device.id, modelData.id, thresh, torq)
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

            Rectangle {
              width: parent.width
              height: 36
              radius: 6
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                Text { text: "Invert Wheel Direction"; color: root.foreground; font.pixelSize: 11 }
                Item { Layout.fillWidth: true }
                Switch {
                  checked: device && device.scroll ? device.scroll.invert_y === true : false
                  onToggled: {
                    if (device) {
                      var cur = device.scroll || {}
                      mx.setScroll(device.id, checked, cur.invert_thumb || false, cur.hires !== false)
                    }
                  }
                }
              }
            }

            Rectangle {
              width: parent.width
              height: 36
              radius: 6
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                Text { text: "Invert Thumb Wheel"; color: root.foreground; font.pixelSize: 11 }
                Item { Layout.fillWidth: true }
                Switch {
                  checked: device && device.scroll ? device.scroll.invert_thumb === true : false
                  onToggled: {
                    if (device) {
                      var cur = device.scroll || {}
                      mx.setScroll(device.id, cur.invert_y || false, checked, cur.hires !== false)
                    }
                  }
                }
              }
            }
          }

          // Keyboard Backlight Section
          Column {
            visible: !root.isMouse && !!(device && device.capabilities && device.capabilities.backlight)
            width: parent.width
            spacing: 6

            RowLayout {
              width: parent.width
              Text { text: "Keyboard Backlight"; color: root.dim; font.pixelSize: 11; font.bold: true }
              Item { Layout.fillWidth: true }
              Text {
                text: (device && device.keyboard && device.keyboard.backlight_level !== undefined ? device.keyboard.backlight_level : 50) + "%"
                color: root.accent
                font.pixelSize: 11
              }
            }

            Slider {
              width: parent.width
              from: 0
              to: 100
              stepSize: 5
              value: device && device.keyboard && device.keyboard.backlight_level !== undefined ? device.keyboard.backlight_level : 50
              onMoved: {
                if (device) mx.setKeyboard(device.id, { backlight_level: Math.round(value) })
              }
            }
          }

          // Bottom Bar Actions
          RowLayout {
            width: parent.width
            spacing: 6

            Button {
              Layout.fillWidth: true
              text: "Refresh"
              onClicked: root.refresh()
            }

            Button {
              Layout.fillWidth: true
              text: "Customize..."
              onClicked: root.openFullSettings()
            }
          }
        }
      }
    }
  }
}
