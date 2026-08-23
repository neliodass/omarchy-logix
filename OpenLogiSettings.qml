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
      service = shell.ensureService("io.openlogi.omarchy") || null
    if (!service && typeof shell.serviceFor === "function")
      service = shell.serviceFor("io.openlogi.omarchy")
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
    closingFromHost = true
    root.opened = false
    closingFromHost = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide("io.openlogi.omarchy")
    else root.opened = false
  }

  function showToast(msg) {
    statusToast = msg
    toastTimer.restart()
  }

  Timer {
    id: toastTimer
    interval: 3000
    repeat: false
    onTriggered: statusToast = ""
  }

  Service {
    id: localMx
    passive: true
  }

  readonly property var mx: root.service || localMx
  readonly property var device: mx ? mx.selectedDevice : null
  readonly property color foreground: Color.foreground
  readonly property color background: Color.popups.background
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: Style.font.family

  function currentActionForButton(btnId) {
    var buttons = Model.getButtons(device)
    for (var i = 0; i < buttons.length; i++) {
      if (buttons[i].id === btnId) return buttons[i].action
    }
    return ""
  }

  function currentActionForSlot(slotId) {
    var slots = Model.getActionRingSlots(device)
    for (var i = 0; i < slots.length; i++) {
      if (slots[i].id === slotId) return slots[i].action
    }
    return ""
  }

  function currentActionForGesture(gestureId) {
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
    WlrLayershell.namespace: "omarchy-openlogi-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Scrim backdrop dismiss area
    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.55)

      MouseArea {
        anchors.fill: parent
        onClicked: root.requestClose()
      }
    }

    // Centered Settings Modal Card
    Rectangle {
      anchors.centerIn: parent
      width: Math.min(parent.width - 40, 920)
      height: Math.min(parent.height - 40, 720)
      radius: 12
      color: root.background
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
      border.width: 1

      MouseArea {
        anchors.fill: parent
      }

      FocusScope {
        anchors.fill: parent
        focus: true

        PanelKeyCatcher {
          id: keyCatcher
          anchors.fill: parent
          onCloseRequested: root.requestClose()
          onTextKey: function(t) {
            if (t === "r" || t === "R") { if (mx) mx.refresh() }
          }

          ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Top Header & Navigation Tabs
            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 60
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12

              OpenLogiIcon {
                iconSize: 26
                color: root.accent
                isKeyboard: Model.isKeyboard(device)
              }

              Column {
                Text {
                  text: device ? Model.plainHidText(device.name) : "OpenLogi Control"
                  color: root.foreground
                  font.bold: true
                  font.pixelSize: 14
                }
                Text {
                  text: device ? (Model.connectionLabel(device) + " · Battery " + Model.batteryLabel(device) + " · HID++ 2.0") : "Scanning..."
                  color: root.dim
                  font.pixelSize: 11
                }
              }

              Item { Layout.fillWidth: true }

              // Navigation Tabs
              RowLayout {
                spacing: 6

                Repeater {
                  model: [
                    { id: "buttons", label: "Button Remaps" },
                    { id: "smartring", label: "Smart Ring" },
                    { id: "gestures", label: "Gestures" },
                    { id: "pointer", label: "DPI & Scroll" },
                    { id: "driver", label: "Driver & Config" }
                  ]

                  delegate: Rectangle {
                    width: tabText.implicitWidth + 20
                    height: 32
                    radius: 6
                    property bool isActive: root.activeTab === modelData.id
                    color: isActive ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

                    Text {
                      id: tabText
                      anchors.centerIn: parent
                      text: modelData.label
                      color: parent.isActive ? "#ffffff" : root.foreground
                      font.bold: parent.isActive
                      font.pixelSize: 11
                    }

                    MouseArea {
                      anchors.fill: parent
                      onClicked: root.activeTab = modelData.id
                    }
                  }
                }
              }
            }
          }

          // Toast notification bar if active
          Rectangle {
            visible: root.statusToast !== ""
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.2)

            Text {
              anchors.centerIn: parent
              text: root.statusToast
              color: root.accent
              font.bold: true
              font.pixelSize: 11
            }
          }

          // Tab Content Stack
          StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: {
              if (root.activeTab === "buttons") return 0
              if (root.activeTab === "smartring") return 1
              if (root.activeTab === "gestures") return 2
              if (root.activeTab === "pointer") return 3
              return 4
            }

            // TAB 0: Button Remapping (Full view with mapped badges)
            Item {
              RowLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 18

                // Physical Buttons List
                Rectangle {
                  Layout.preferredWidth: 360
                  Layout.fillHeight: true
                  radius: 10
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)
                  border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

                  ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 8

                    Text {
                      text: "Physical Hardware Buttons"
                      color: root.foreground
                      font.bold: true
                      font.pixelSize: 13
                    }
                    Text {
                      text: "Select a button to view and change its mapped action:"
                      color: root.dim
                      font.pixelSize: 10
                    }

                    ListView {
                      Layout.fillWidth: true
                      Layout.fillHeight: true
                      clip: true
                      spacing: 6
                      model: Model.getButtons(device)

                      delegate: Rectangle {
                        width: ListView.view.width
                        height: 56
                        radius: 8
                        property bool isSelected: root.selectedButtonId === modelData.id
                        color: isSelected ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
                        border.color: isSelected ? root.accent : "transparent"
                        border.width: isSelected ? 2 : 0

                        RowLayout {
                          anchors.fill: parent
                          anchors.leftMargin: 12
                          anchors.rightMargin: 12
                          spacing: 10

                          Column {
                            Layout.fillWidth: true
                            spacing: 3

                            Text {
                              text: modelData.label
                              color: root.foreground
                              font.bold: true
                              font.pixelSize: 12
                            }

                            // Current mapped action badge
                            RowLayout {
                              spacing: 4
                              Text {
                                text: "Mapped:"
                                color: root.dim
                                font.pixelSize: 10
                              }
                              Rectangle {
                                height: 16
                                width: mappedText.implicitWidth + 8
                                radius: 3
                                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.25)

                                Text {
                                  id: mappedText
                                  anchors.centerIn: parent
                                  text: modelData.actionLabel
                                  color: root.accent
                                  font.bold: true
                                  font.pixelSize: 9
                                }
                              }
                            }
                          }

                          Text {
                            text: parent.parent.isSelected ? "●" : "›"
                            color: parent.parent.isSelected ? root.accent : root.dim
                            font.bold: true
                            font.pixelSize: 14
                          }
                        }

                        MouseArea {
                          anchors.fill: parent
                          onClicked: root.selectedButtonId = modelData.id
                        }
                      }
                    }
                  }
                }

                // Target Action list
                Rectangle {
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  radius: 10
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)
                  border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

                  ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    RowLayout {
                      Layout.fillWidth: true
                      Text {
                        text: "Action Catalog for [" + root.selectedButtonId + "]"
                        color: root.accent
                        font.bold: true
                        font.pixelSize: 13
                      }
                      Item { Layout.fillWidth: true }
                      Text {
                        text: "Current: " + Model.actionLabel(root.currentActionForButton(root.selectedButtonId))
                        color: root.foreground
                        font.bold: true
                        font.pixelSize: 11
                      }
                    }

                    ListView {
                      Layout.fillWidth: true
                      Layout.fillHeight: true
                      clip: true
                      spacing: 5
                      model: Model.AVAILABLE_ACTIONS

                      delegate: Rectangle {
                        width: ListView.view.width
                        height: 42
                        radius: 6
                        property bool isAssigned: root.currentActionForButton(root.selectedButtonId) === modelData.id
                        color: isAssigned ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
                        border.color: isAssigned ? root.accent : "transparent"
                        border.width: isAssigned ? 1 : 0

                        RowLayout {
                          anchors.fill: parent
                          anchors.leftMargin: 12
                          anchors.rightMargin: 12

                          Column {
                            Text {
                              text: modelData.label
                              color: root.foreground
                              font.bold: parent.parent.parent.isAssigned
                              font.pixelSize: 11
                            }
                            Text {
                              text: modelData.category
                              color: root.dim
                              font.pixelSize: 9
                            }
                          }

                          Item { Layout.fillWidth: true }

                          // If currently assigned, show checkmark badge; else show Assign button
                          Rectangle {
                            visible: parent.parent.isAssigned
                            height: 24
                            width: 80
                            radius: 4
                            color: root.accent

                            Text {
                              anchors.centerIn: parent
                              text: "✓ Active"
                              color: "#ffffff"
                              font.bold: true
                              font.pixelSize: 10
                            }
                          }

                          Button {
                            visible: !parent.parent.isAssigned
                            text: "Assign"
                            onClicked: {
                              if (device) {
                                mx.setButton(device.id, root.selectedButtonId, modelData.id)
                                root.showToast("Mapped " + root.selectedButtonId + " to " + modelData.label)
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

            // TAB 1: Smart Ring (Action Ring) Visualizer
            Item {
              RowLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 18

                // Radial Wheel
                Rectangle {
                  Layout.preferredWidth: 400
                  Layout.fillHeight: true
                  radius: 10
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)
                  border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

                  Column {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    RowLayout {
                      width: parent.width
                      Text {
                        text: "8-Slot Smart Action Ring"
                        color: root.foreground
                        font.bold: true
                        font.pixelSize: 13
                      }
                      Item { Layout.fillWidth: true }
                      Text {
                        text: "Selected: " + root.selectedSlotId
                        color: root.accent
                        font.bold: true
                        font.pixelSize: 11
                      }
                    }

                    // Canvas Radial Layout
                    Item {
                      width: 370
                      height: 360

                      // Center Ring Hub
                      Rectangle {
                        anchors.centerIn: parent
                        width: 90
                        height: 90
                        radius: 45
                        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)
                        border.color: root.accent
                        border.width: 2

                        Column {
                          anchors.centerIn: parent
                          spacing: 2
                          Text {
                            text: "◎"
                            color: root.accent
                            font.pixelSize: 24
                            anchors.horizontalCenter: parent.horizontalCenter
                          }
                          Text {
                            text: "Smart Ring"
                            color: root.foreground
                            font.pixelSize: 10
                            font.bold: true
                            anchors.horizontalCenter: parent.horizontalCenter
                          }
                        }
                      }

                      // 8 Radial Nodes
                      Repeater {
                        model: Model.getActionRingSlots(device)
                        delegate: Item {
                          id: slotItem
                          property real angleRad: (modelData.angle - 90) * Math.PI / 180
                          property real radius: 125
                          x: 185 + radius * Math.cos(angleRad) - width / 2
                          y: 180 + radius * Math.sin(angleRad) - height / 2
                          width: 82
                          height: 44

                          Rectangle {
                            anchors.fill: parent
                            radius: 8
                            property bool isSelected: root.selectedSlotId === modelData.id
                            color: isSelected ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                            border.color: isSelected ? "#ffffff" : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.4)
                            border.width: isSelected ? 2 : 1

                            Column {
                              anchors.centerIn: parent
                              spacing: 1
                              Text {
                                text: modelData.glyph + " " + modelData.label
                                color: slotItem.children[0].isSelected ? "#ffffff" : root.dim
                                font.pixelSize: 9
                                anchors.horizontalCenter: parent.horizontalCenter
                              }
                              Text {
                                text: modelData.customLabel
                                color: slotItem.children[0].isSelected ? "#ffffff" : root.foreground
                                font.bold: true
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                width: parent.parent.width - 6
                                horizontalAlignment: Text.AlignHCenter
                              }
                            }

                            MouseArea {
                              anchors.fill: parent
                              onClicked: root.selectedSlotId = modelData.id
                            }
                          }
                        }
                      }
                    }

                    Text {
                      text: "💡 Click a slot node above, then choose an action on the right to assign it."
                      color: root.dim
                      font.pixelSize: 10
                      wrapMode: Text.Wrap
                      width: parent.width
                    }
                  }
                }

                // Action Picker for Selected Slot
                Rectangle {
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  radius: 10
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)
                  border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

                  ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    Text {
                      text: "Choose Action for [" + root.selectedSlotId + "]"
                      color: root.accent
                      font.bold: true
                      font.pixelSize: 13
                    }

                    ListView {
                      Layout.fillWidth: true
                      Layout.fillHeight: true
                      clip: true
                      spacing: 5
                      model: Model.AVAILABLE_ACTIONS

                      delegate: Rectangle {
                        width: ListView.view.width
                        height: 38
                        radius: 6
                        property bool isAssigned: root.currentActionForSlot(root.selectedSlotId) === modelData.id
                        color: isAssigned ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
                        border.color: isAssigned ? root.accent : "transparent"
                        border.width: isAssigned ? 1 : 0

                        RowLayout {
                          anchors.fill: parent
                          anchors.leftMargin: 10
                          anchors.rightMargin: 10

                          Text {
                            text: modelData.label
                            color: root.foreground
                            font.bold: parent.parent.isAssigned
                            font.pixelSize: 11
                          }

                          Item { Layout.fillWidth: true }

                          Rectangle {
                            visible: parent.parent.isAssigned
                            height: 22
                            width: 70
                            radius: 4
                            color: root.accent

                            Text {
                              anchors.centerIn: parent
                              text: "✓ Active"
                              color: "#ffffff"
                              font.bold: true
                              font.pixelSize: 10
                            }
                          }

                          Button {
                            visible: !parent.parent.isAssigned
                            text: "Assign"
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

            // TAB 2: Directional Gestures
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
                            RowLayout {
                              spacing: 4
                              Text { text: "Action:"; color: root.dim; font.pixelSize: 10 }
                              Text { text: modelData.customLabel; color: root.accent; font.bold: true; font.pixelSize: 10 }
                            }
                          }
                        }

                        MouseArea {
                          anchors.fill: parent
                          onClicked: root.selectedGestureId = modelData.id
                        }
                      }
                    }
                  }
                }

                // Action Picker for Gesture
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
                      text: "Assign Action to Gesture: " + root.selectedGestureId
                      color: root.accent
                      font.bold: true
                      font.pixelSize: 13
                    }

                    ListView {
                      Layout.fillWidth: true
                      Layout.fillHeight: true
                      clip: true
                      spacing: 5
                      model: Model.AVAILABLE_ACTIONS

                      delegate: Rectangle {
                        width: ListView.view.width
                        height: 38
                        radius: 6
                        property bool isAssigned: root.currentActionForGesture(root.selectedGestureId) === modelData.id
                        color: isAssigned ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
                        border.color: isAssigned ? root.accent : "transparent"
                        border.width: isAssigned ? 1 : 0

                        RowLayout {
                          anchors.fill: parent
                          anchors.leftMargin: 10
                          anchors.rightMargin: 10

                          Text {
                            text: modelData.label
                            color: root.foreground
                            font.bold: parent.parent.isAssigned
                            font.pixelSize: 11
                          }

                          Item { Layout.fillWidth: true }

                          Rectangle {
                            visible: parent.parent.isAssigned
                            height: 22
                            width: 70
                            radius: 4
                            color: root.accent

                            Text {
                              anchors.centerIn: parent
                              text: "✓ Active"
                              color: "#ffffff"
                              font.bold: true
                              font.pixelSize: 10
                            }
                          }

                          Button {
                            visible: !parent.parent.isAssigned
                            text: "Assign"
                            onClicked: {
                              if (device) {
                                mx.setGesture(device.id, root.selectedGestureId, modelData.id, modelData.label)
                                root.showToast("Assigned " + modelData.label + " to gesture " + root.selectedGestureId)
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

            // TAB 3: Pointer & Scroll
            Item {
              ScrollView {
                anchors.fill: parent
                anchors.margins: 20

                Column {
                  width: 800
                  spacing: 16

                  // DPI Settings
                  Rectangle {
                    width: parent.width
                    height: 110
                    radius: 8
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

                    Column {
                      anchors.fill: parent
                      anchors.margins: 14
                      spacing: 10

                      RowLayout {
                        width: parent.width
                        Text { text: "Sensor Sensitivity (DPI)"; color: root.foreground; font.bold: true; font.pixelSize: 13 }
                        Item { Layout.fillWidth: true }
                        Text { text: (device && device.dpi ? device.dpi : 1000) + " DPI"; color: root.accent; font.bold: true }
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
                  }

                  // SmartShift Settings
                  Rectangle {
                    width: parent.width
                    height: 250
                    radius: 8
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

                    Column {
                      anchors.fill: parent
                      anchors.margins: 14
                      spacing: 12

                      RowLayout {
                        width: parent.width
                        Text { text: "MagSpeed SmartShift & Ratchet Wheel"; color: root.foreground; font.bold: true; font.pixelSize: 13 }
                        Item { Layout.fillWidth: true }
                        Text {
                          text: {
                            var m = device && device.smartshift ? device.smartshift.mode : "auto"
                            if (m === "freewheel") return "Always Free Spin"
                            if (m === "ratchet") return "Always Ratchet"
                            return "Smart Auto-Switch"
                          }
                          color: root.accent
                          font.bold: true
                        }
                      }

                      RowLayout {
                        spacing: 10
                        Repeater {
                          model: [
                            { id: "auto", label: "Smart Auto-Switch" },
                            { id: "ratchet", label: "Always Ratchet" },
                            { id: "freewheel", label: "Always Free Spin" }
                          ]
                          delegate: Button {
                            text: modelData.label
                            selected: device && device.smartshift && device.smartshift.mode === modelData.id
                            onClicked: {
                              if (device) {
                                var thresh = device.smartshift && device.smartshift.threshold !== undefined ? device.smartshift.threshold : 10
                                var torq = device.smartshift && device.smartshift.torque !== undefined ? device.smartshift.torque : 75
                                mx.setSmartShift(device.id, modelData.id, thresh, torq)
                                root.showToast("SmartShift set to " + modelData.label)
                              }
                            }
                          }
                        }
                      }

                      // Auto-Disengage Sensitivity Slider (only in Auto mode)
                      Column {
                        width: parent.width
                        spacing: 4
                        opacity: (device && device.smartshift && device.smartshift.mode === "auto") ? 1.0 : 0.4
                        enabled: device && device.smartshift && device.smartshift.mode === "auto"

                        RowLayout {
                          width: parent.width
                          Text { text: "Próg przełączania na Free Spin (Czułość)"; color: root.foreground; font.pixelSize: 11; font.bold: true }
                          Item { Layout.fillWidth: true }
                          Text {
                            text: (device && device.smartshift && device.smartshift.threshold !== undefined ? device.smartshift.threshold : 10) + " (prędkość obrotu)"
                            color: root.accent
                            font.pixelSize: 11
                          }
                        }
                        Slider {
                          width: parent.width
                          from: 1
                          to: 35
                          stepSize: 1
                          value: device && device.smartshift && device.smartshift.threshold !== undefined ? device.smartshift.threshold : 10
                          onMoved: {
                            if (device) {
                              var curMode = device.smartshift ? device.smartshift.mode : "auto"
                              var curTorq = device.smartshift && device.smartshift.torque !== undefined ? device.smartshift.torque : 75
                              mx.setSmartShift(device.id, curMode, Math.round(value), curTorq)
                            }
                          }
                        }
                      }

                      // Ratchet Force / Torque Slider (in Ratchet & Auto modes)
                      Column {
                        width: parent.width
                        spacing: 4
                        opacity: (device && device.smartshift && device.smartshift.mode === "freewheel") ? 0.4 : 1.0
                        enabled: !device || !device.smartshift || device.smartshift.mode !== "freewheel"

                        RowLayout {
                          width: parent.width
                          Text { text: "Siła oporu zapadki MagSpeed (Ratchet Force)"; color: root.foreground; font.pixelSize: 11; font.bold: true }
                          Item { Layout.fillWidth: true }
                          Text {
                            text: (device && device.smartshift && device.smartshift.torque !== undefined ? device.smartshift.torque : 75) + "%"
                            color: root.accent
                            font.pixelSize: 11
                          }
                        }
                        Slider {
                          width: parent.width
                          from: 1
                          to: 100
                          stepSize: 1
                          value: device && device.smartshift && device.smartshift.torque !== undefined ? device.smartshift.torque : 75
                          onMoved: {
                            if (device) {
                              var curMode = device.smartshift ? device.smartshift.mode : "auto"
                              var curThresh = device.smartshift && device.smartshift.threshold !== undefined ? device.smartshift.threshold : 10
                              mx.setSmartShift(device.id, curMode, curThresh, Math.round(value))
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }

            // TAB 4: Driver & Config
            Item {
              ScrollView {
                anchors.fill: parent
                anchors.margins: 20

                Column {
                  width: 800
                  spacing: 16

                  Rectangle {
                    width: parent.width
                    height: 140
                    radius: 8
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

                    Column {
                      anchors.fill: parent
                      anchors.margins: 14
                      spacing: 8

                      Text { text: "OpenLogi Status & Configuration"; color: root.foreground; font.bold: true; font.pixelSize: 13 }
                      Text {
                        text: "• Driver Mode: Standalone Kernel HID++ & Direct TOML Engine (Active)\n• Configuration File: ~/.config/openlogi/config.toml\n• Active Device: " + (device ? (device.name + " (" + device.id + ")") : "None")
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

