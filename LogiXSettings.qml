import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var service: null
  property string activeTab: "buttons"
  property string selectedSlotId: "Top"
  property string selectedGestureId: "Up"
  property string selectedButtonId: "GestureButton"
  property string actionSearchQuery: ""
  property string statusToast: ""
  property bool closingFromHost: false

  property bool opened: false

  function resolveService() {
    if (service || !shell) return
    if (typeof shell.ensureService === "function")
      service = shell.ensureService("io.logix.omarchy") || null
    if (!service && typeof shell.serviceFor === "function")
      service = shell.serviceFor("io.logix.omarchy")
  }

  function open(payloadJson) {
    closingFromHost = false
    resolveService()
    root.opened = true
    if (mx) {
      mx.ensureDaemon()
      mx.refresh()
      if (payloadJson) {
        try {
          var parsed = JSON.parse(String(payloadJson))
          if (parsed && parsed.device) mx.selectDevice(parsed.device)
        } catch (e) { /* ignore */ }
      }
    }
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function toggle() {
    if (root.opened) close()
    else open()
  }

  readonly property var mx: service
  readonly property var device: mx ? mx.selectedDevice : null
  readonly property bool isMouse: device ? !Model.isKeyboard(device) : true

  readonly property color foreground: Color.foreground
  readonly property color background: Color.popups.background
  readonly property color surface: Color.background
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color borderCol: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)

  function showToast(msg) {
    statusToast = msg
    toastTimer.restart()
  }

  Timer {
    id: toastTimer
    interval: 3000
    onTriggered: root.statusToast = ""
  }

  function filteredActions() {
    var list = Model.AVAILABLE_ACTIONS
    if (!actionSearchQuery) return list
    var q = actionSearchQuery.toLowerCase()
    var res = []
    for (var i = 0; i < list.length; i++) {
      if (list[i].label.toLowerCase().indexOf(q) !== -1 || list[i].category.toLowerCase().indexOf(q) !== -1) {
        res.push(list[i])
      }
    }
    return res
  }

  function currentAssignedAction() {
    if (activeTab === "ring") {
      return getSlotAction(selectedSlotId)
    } else if (activeTab === "gestures") {
      return getGestureAction(selectedGestureId)
    } else if (activeTab === "buttons") {
      return getButtonAction(selectedButtonId)
    }
    return ""
  }

  function getButtonAction(buttonId) {
    if (!device) return ""
    var btns = Model.getButtons(device)
    for (var i = 0; i < btns.length; i++) {
      if (btns[i].id === buttonId) return btns[i].action
    }
    return ""
  }

  function getSlotAction(slotId) {
    if (!device) return ""
    var slots = Model.getActionRingSlots(device)
    for (var i = 0; i < slots.length; i++) {
      if (slots[i].id === slotId) return slots[i].action
    }
    return ""
  }

  function getGestureAction(gestureId) {
    if (!device) return ""
    var gestures = Model.getGestures(device)
    for (var i = 0; i < gestures.length; i++) {
      if (gestures[i].id === gestureId) return gestures[i].action
    }
    return ""
  }

  PanelWindow {
    id: window
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-logix-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Scrim backdrop dismiss area
    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.55)

      MouseArea {
        anchors.fill: parent
        onClicked: root.close()
      }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.close()

      // Center Modal Dialog
      Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(1080, parent.width - 60)
        height: Math.min(760, parent.height - 60)
        radius: 12
        color: root.background
        border.color: root.borderCol
        border.width: 1
        clip: true

        MouseArea {
          anchors.fill: parent
          onClicked: {} // Catch clicks to prevent backdrop dismiss
        }

        ColumnLayout {
          anchors.fill: parent
          spacing: 0

          // Top Header Bar
          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            color: root.surface
            border.color: root.borderCol
            border.width: 1

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 16
              anchors.rightMargin: 16
              spacing: 12

              LogiXIcon {
                iconSize: 24
                color: root.accent
                isKeyboard: !root.isMouse
              }

              Column {
                Layout.fillWidth: true
                Text {
                  text: "LogiX Hardware & Gesture Control"
                  color: root.foreground
                  font.bold: true
                  font.pixelSize: 14
                }
                Text {
                  text: device ? (device.name + " (" + Model.connectionLabel(device) + ") · Battery " + Model.batteryLabel(device)) : "Scanning HID++ devices…"
                  color: root.dim
                  font.pixelSize: 11
                }
              }

              Button {
                text: "✕"
                onClicked: root.close()
              }
            }
          }

          // Main Tabs & Content
          RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Left Navigation Sidebar
            Rectangle {
              Layout.preferredWidth: 200
              Layout.fillHeight: true
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.02)
              border.color: root.borderCol
              border.width: 1

              Column {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6

                Repeater {
                  model: [
                    { id: "ring", label: "Smart Ring", glyph: "◎" },
                    { id: "gestures", label: "Gestures", glyph: "🡹" },
                    { id: "dpi", label: "DPI & Scroll", glyph: "⚡" },
                    { id: "buttons", label: "Buttons", glyph: "🖱️" },
                    { id: "info", label: "Device Info", glyph: "ℹ️" }
                  ]
                  delegate: Rectangle {
                    width: parent.width
                    height: 42
                    radius: 8
                    property bool isSelected: root.activeTab === modelData.id
                    color: isSelected ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15) : "transparent"
                    border.color: isSelected ? root.accent : "transparent"
                    border.width: 1

                    RowLayout {
                      anchors.fill: parent
                      anchors.leftMargin: 12
                      anchors.rightMargin: 12
                      spacing: 10

                      Text {
                        text: modelData.glyph
                        color: parent.parent.isSelected ? root.accent : root.dim
                        font.pixelSize: 15
                      }
                      Text {
                        text: modelData.label
                        color: parent.parent.isSelected ? root.foreground : root.dim
                        font.bold: parent.parent.isSelected
                        font.pixelSize: 12
                      }
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.activeTab = modelData.id
                    }
                  }
                }
              }
            }

            // Right Tab Pages
            StackLayout {
              Layout.fillWidth: true
              Layout.fillHeight: true
              currentIndex: {
                if (root.activeTab === "ring") return 0
                if (root.activeTab === "gestures") return 1
                if (root.activeTab === "dpi") return 2
                if (root.activeTab === "buttons") return 3
                return 4
              }

              // TAB 0: Smart Ring
              Item {
                RowLayout {
                  anchors.fill: parent
                  anchors.margins: 18
                  spacing: 18

                  // Radial Visualizer
                  Rectangle {
                    Layout.preferredWidth: 380
                    Layout.fillHeight: true
                    radius: 10
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)

                    Item {
                      anchors.centerIn: parent
                      width: 320
                      height: 320

                      // Center Hub
                      Rectangle {
                        anchors.centerIn: parent
                        width: 90
                        height: 90
                        radius: 45
                        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.2)
                        border.color: root.accent
                        border.width: 2

                        Column {
                          anchors.centerIn: parent
                          spacing: 2
                          Text { text: "◎"; color: root.accent; font.pixelSize: 22; anchors.horizontalCenter: parent.horizontalCenter }
                          Text { text: "Smart Ring"; color: root.foreground; font.pixelSize: 10; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                        }
                      }

                      // 8 Radial Slots
                      Repeater {
                        model: Model.getActionRingSlots(device)
                        delegate: Item {
                          id: slotNode
                          property real angleRad: (modelData.angle - 90) * Math.PI / 180
                          property real radius: 105
                          x: 160 + radius * Math.cos(angleRad) - width / 2
                          y: 160 + radius * Math.sin(angleRad) - height / 2
                          width: 74
                          height: 44

                          Rectangle {
                            anchors.fill: parent
                            radius: 8
                            property bool isSelected: root.selectedSlotId === modelData.id
                            color: isSelected ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                            border.color: isSelected ? "#ffffff" : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
                            border.width: 1

                            Column {
                              anchors.centerIn: parent
                              spacing: 1
                              Text {
                                text: modelData.glyph + " " + modelData.label
                                color: slotNode.children[0].isSelected ? "#ffffff" : root.accent
                                font.pixelSize: 9
                                anchors.horizontalCenter: parent.horizontalCenter
                              }
                              Text {
                                text: modelData.customLabel
                                color: slotNode.children[0].isSelected ? "#ffffff" : root.foreground
                                font.bold: true
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                width: parent.parent.width - 6
                                horizontalAlignment: Text.AlignHCenter
                              }
                            }

                            MouseArea {
                              anchors.fill: parent
                              cursorShape: Qt.PointingHandCursor
                              onClicked: root.selectedSlotId = modelData.id
                            }
                          }
                        }
                      }
                    }
                  }

                  // Action Picker
                  Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 10
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)

                    ColumnLayout {
                      anchors.fill: parent
                      anchors.margins: 14
                      spacing: 10

                      Text {
                        text: "Assign Action to " + root.selectedSlotId
                        color: root.foreground
                        font.bold: true
                        font.pixelSize: 13
                      }

                      TextField {
                        Layout.fillWidth: true
                        placeholderText: "Search actions (e.g. Workspace, Volume, Tile)…"
                        text: root.actionSearchQuery
                        onTextChanged: root.actionSearchQuery = text
                      }

                      ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 6
                        model: root.filteredActions()

                        delegate: Rectangle {
                          width: ListView.view.width
                          height: 40
                          radius: 6
                          property bool isAssigned: root.currentAssignedAction() === modelData.id
                          color: isAssigned ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

                          RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text { text: modelData.label; color: root.foreground; font.pixelSize: 12; font.bold: parent.parent.isAssigned }
                            Text { text: "(" + modelData.category + ")"; color: root.dim; font.pixelSize: 10 }
                            Item { Layout.fillWidth: true }

                            Button {
                              text: parent.parent.isAssigned ? "Active" : "Assign"
                              enabled: !parent.parent.isAssigned
                              onClicked: {
                                if (device) {
                                  mx.setActionRingSlot(device.id, root.selectedSlotId, modelData.id, modelData.label)
                                  root.showToast("Assigned " + modelData.label + " to " + root.selectedSlotId)
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }

              // TAB 1: Directional Gestures
              Item {
                RowLayout {
                  anchors.fill: parent
                  anchors.margins: 18
                  spacing: 18

                  // Gesture list
                  Rectangle {
                    Layout.preferredWidth: 340
                    Layout.fillHeight: true
                    radius: 10
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)

                    ColumnLayout {
                      anchors.fill: parent
                      anchors.margins: 14
                      spacing: 10

                      Text {
                        text: "5-Way Directional Gestures"
                        color: root.foreground
                        font.bold: true
                        font.pixelSize: 13
                      }

                      // Gesture Swipe Distance / Sensitivity Slider
                      Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 64
                        radius: 8
                        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)

                        Column {
                          anchors.fill: parent
                          anchors.margins: 8
                          spacing: 4

                          RowLayout {
                            width: parent.width
                            Text { text: "Swipe Distance (Flick Sensitivity)"; color: root.foreground; font.pixelSize: 11; font.bold: true }
                            Item { Layout.fillWidth: true }
                            Text {
                              text: (device && device.gesture_distance ? device.gesture_distance : 15) + " px " + (device && device.gesture_distance <= 12 ? "(Ultra Short)" : (device && device.gesture_distance <= 20 ? "(Short Flick)" : "(Standard)"))
                              color: root.accent
                              font.pixelSize: 10
                              font.bold: true
                            }
                          }

                          Slider {
                            width: parent.width
                            from: 6
                            to: 45
                            stepSize: 1
                            value: device && device.gesture_distance ? device.gesture_distance : 15
                            onMoved: {
                              if (device) mx.setGestureDistance(device.id, Math.round(value))
                            }
                          }
                        }
                      }

                      ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 8
                        model: Model.getGestures(device)

                        delegate: Rectangle {
                          width: ListView.view.width
                          height: 56
                          radius: 8
                          property bool isSelected: root.selectedGestureId === modelData.id
                          color: isSelected ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
                          border.color: isSelected ? root.accent : "transparent"
                          border.width: isSelected ? 2 : 0

                          RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12

                            Text {
                              text: modelData.glyph
                              color: root.accent
                              font.pixelSize: 20
                              font.bold: true
                            }

                            Column {
                              Layout.fillWidth: true
                              spacing: 2
                              Text {
                                text: modelData.label
                                color: root.foreground
                                font.bold: true
                                font.pixelSize: 12
                              }
                              Text {
                                text: modelData.customLabel
                                color: root.dim
                                font.pixelSize: 11
                              }
                            }
                          }

                          MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectedGestureId = modelData.id
                          }
                        }
                      }
                    }
                  }

                  // Action Picker
                  Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 10
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)

                    ColumnLayout {
                      anchors.fill: parent
                      anchors.margins: 14
                      spacing: 10

                      Text {
                        text: "Assign Action to " + root.selectedGestureId
                        color: root.foreground
                        font.bold: true
                        font.pixelSize: 13
                      }

                      TextField {
                        Layout.fillWidth: true
                        placeholderText: "Search actions…"
                        text: root.actionSearchQuery
                        onTextChanged: root.actionSearchQuery = text
                      }

                      ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 6
                        model: root.filteredActions()

                        delegate: Rectangle {
                          width: ListView.view.width
                          height: 40
                          radius: 6
                          property bool isAssigned: root.currentAssignedAction() === modelData.id
                          color: isAssigned ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

                          RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text { text: modelData.label; color: root.foreground; font.pixelSize: 12; font.bold: parent.parent.isAssigned }
                            Text { text: "(" + modelData.category + ")"; color: root.dim; font.pixelSize: 10 }
                            Item { Layout.fillWidth: true }

                            Button {
                              text: parent.parent.isAssigned ? "Active" : "Assign"
                              enabled: !parent.parent.isAssigned
                              onClicked: {
                                if (device) {
                                  mx.setGesture(device.id, root.selectedGestureId, modelData.id, modelData.label)
                                  root.showToast("Assigned " + modelData.label + " to " + root.selectedGestureId)
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }

              // TAB 2: DPI & Scroll Engine
              Item {
                ScrollView {
                  anchors.fill: parent
                  anchors.margins: 20
                  clip: true

                  Column {
                    width: parent.width - 20
                    spacing: 16

                    Text { text: "Pointer Speed & Hardware DPI"; color: root.foreground; font.bold: true; font.pixelSize: 14 }

                    Rectangle {
                      width: parent.width
                      height: 80
                      radius: 8
                      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

                      Column {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 8

                        RowLayout {
                          width: parent.width
                          Text { text: "Sensor Sensitivity"; color: root.foreground; font.pixelSize: 12 }
                          Item { Layout.fillWidth: true }
                          Text { text: (device && device.dpi ? device.dpi : 1000) + " DPI"; color: root.accent; font.bold: true; font.pixelSize: 13 }
                        }

                        Slider {
                          width: parent.width
                          from: 200
                          to: 8000
                          stepSize: 50
                          value: device && device.dpi ? device.dpi : 1000
                          onMoved: if (device) mx.setDpi(device.id, Math.round(value))
                        }
                      }
                    }

                    Text { text: "SmartShift Ratchet & Auto-Disengage"; color: root.foreground; font.bold: true; font.pixelSize: 14 }

                    Rectangle {
                      width: parent.width
                      height: 200
                      radius: 8
                      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

                      Column {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12

                        Row {
                          spacing: 10
                          Repeater {
                            model: [
                              { id: "auto", label: "Smart Auto-Switch" },
                              { id: "ratchet", label: "Always Ratchet" },
                              { id: "freewheel", label: "Always Free Spin" }
                            ]
                            delegate: Button {
                              text: modelData.label
                              highlighted: device && device.smartshift && device.smartshift.mode === modelData.id
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

                        Column {
                          width: parent.width
                          spacing: 4
                          RowLayout {
                            width: parent.width
                            Text { text: "Ratchet Motor Torque / Force"; color: root.foreground; font.pixelSize: 11 }
                            Item { Layout.fillWidth: true }
                            Text { text: (device && device.smartshift && device.smartshift.torque !== undefined ? device.smartshift.torque : 75) + "%"; color: root.accent; font.pixelSize: 11 }
                          }
                          Slider {
                            width: parent.width
                            from: 1
                            to: 100
                            stepSize: 1
                            value: device && device.smartshift && device.smartshift.torque !== undefined ? device.smartshift.torque : 75
                            onMoved: {
                              if (device) {
                                var curMode = device.smartshift && device.smartshift.mode ? device.smartshift.mode : "auto"
                                var thresh = device.smartshift && device.smartshift.threshold !== undefined ? device.smartshift.threshold : 10
                                mx.setSmartShift(device.id, curMode, thresh, Math.round(value))
                              }
                            }
                          }
                        }

                        Column {
                          width: parent.width
                          spacing: 4
                          RowLayout {
                            width: parent.width
                            Text { text: "Auto-Disengage Sensitivity"; color: root.foreground; font.pixelSize: 11 }
                            Item { Layout.fillWidth: true }
                            Text { text: String(device && device.smartshift && device.smartshift.threshold !== undefined ? device.smartshift.threshold : 10); color: root.accent; font.pixelSize: 11 }
                          }
                          Slider {
                            width: parent.width
                            from: 1
                            to: 35
                            stepSize: 1
                            value: device && device.smartshift && device.smartshift.threshold !== undefined ? device.smartshift.threshold : 10
                            onMoved: {
                              if (device) {
                                var curMode = device.smartshift && device.smartshift.mode ? device.smartshift.mode : "auto"
                                var torq = device.smartshift && device.smartshift.torque !== undefined ? device.smartshift.torque : 75
                                mx.setSmartShift(device.id, curMode, Math.round(value), torq)
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }

              // TAB 3: Hardware Buttons
              Item {
                RowLayout {
                  anchors.fill: parent
                  anchors.margins: 18
                  spacing: 18

                  // Button List
                  Rectangle {
                    Layout.preferredWidth: 340
                    Layout.fillHeight: true
                    radius: 10
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)

                    ColumnLayout {
                      anchors.fill: parent
                      anchors.margins: 14
                      spacing: 10

                      Text { text: "Reprogrammable Hardware Buttons"; color: root.foreground; font.bold: true; font.pixelSize: 13 }

                      ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 8
                        model: Model.getButtons(device)

                        delegate: Rectangle {
                          width: ListView.view.width
                          height: 52
                          radius: 8
                          property bool isSelected: root.selectedButtonId === modelData.id
                          color: isSelected ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
                          border.color: isSelected ? root.accent : "transparent"
                          border.width: isSelected ? 2 : 0

                          RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12

                            Column {
                              Layout.fillWidth: true
                              spacing: 2
                              Text { text: modelData.label; color: root.foreground; font.bold: true; font.pixelSize: 12 }
                              Text { text: modelData.actionLabel; color: root.dim; font.pixelSize: 11 }
                            }
                          }

                          MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectedButtonId = modelData.id
                          }
                        }
                      }
                    }
                  }

                  // Action Picker
                  Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 10
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)

                    ColumnLayout {
                      anchors.fill: parent
                      anchors.margins: 14
                      spacing: 10

                      Text { text: "Assign Action to " + root.selectedButtonId; color: root.foreground; font.bold: true; font.pixelSize: 13 }

                      TextField {
                        Layout.fillWidth: true
                        placeholderText: "Search actions…"
                        text: root.actionSearchQuery
                        onTextChanged: root.actionSearchQuery = text
                      }

                      ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 6
                        model: root.filteredActions()

                        delegate: Rectangle {
                          width: ListView.view.width
                          height: 40
                          radius: 6
                          property bool isAssigned: root.currentAssignedAction() === modelData.id
                          color: isAssigned ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

                          RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text { text: modelData.label; color: root.foreground; font.pixelSize: 12; font.bold: parent.parent.isAssigned }
                            Text { text: "(" + modelData.category + ")"; color: root.dim; font.pixelSize: 10 }
                            Item { Layout.fillWidth: true }

                            Button {
                              text: parent.parent.isAssigned ? "Active" : "Assign"
                              enabled: !parent.parent.isAssigned
                              onClicked: {
                                if (device) {
                                  mx.setButton(device.id, root.selectedButtonId, modelData.id)
                                  root.showToast("Assigned " + modelData.label + " to " + root.selectedButtonId)
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }

              // TAB 4: Device Info
              Item {
                ScrollView {
                  anchors.fill: parent
                  anchors.margins: 20

                  Column {
                    width: parent.width - 20
                    spacing: 14

                    Text { text: "Connected Device Details"; color: root.foreground; font.bold: true; font.pixelSize: 14 }

                    Rectangle {
                      width: parent.width
                      height: 140
                      radius: 8
                      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

                      Column {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 6

                        Text { text: "• Name: " + (device ? device.name : "None"); color: root.foreground; font.pixelSize: 12 }
                        Text { text: "• Connection: " + (device ? Model.connectionLabel(device) : "N/A"); color: root.foreground; font.pixelSize: 12 }
                        Text { text: "• Battery Level: " + (device ? Model.batteryLabel(device) : "N/A"); color: root.foreground; font.pixelSize: 12 }
                        Text { text: "• Device Path: " + (device && device.path ? device.path : "N/A"); color: root.foreground; font.pixelSize: 12 }
                        Text { text: "• Driver Protocol: HID++ 2.0 (Direct Kernel HIDRAW)"; color: root.foreground; font.pixelSize: 12 }
                      }
                    }

                    Rectangle {
                      width: parent.width
                      height: 100
                      radius: 8
                      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

                      Column {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 8

                        Text { text: "LogiX Engine Status"; color: root.foreground; font.bold: true; font.pixelSize: 13 }
                        Text {
                          text: "• Configuration File: ~/.config/logix/config.toml\n• Active Driver: Direct Kernel HID++ 2.0\n• Omarchy 4.0 Integration: Active"
                          color: root.dim
                          font.pixelSize: 11
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
