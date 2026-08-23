import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var service: null
  property string activeTab: "smartring"
  property string selectedSlotId: "Top"
  property string selectedGestureId: "Up"
  property string selectedButtonId: "GestureButton"
  property string actionSearchQuery: ""

  function resolveService() {
    if (service || !shell) return
    if (typeof shell.ensureService === "function")
      service = shell.ensureService("io.openlogi.omarchy") || null
    if (!service && typeof shell.serviceFor === "function")
      service = shell.serviceFor("io.openlogi.omarchy")
  }

  function open(payloadJson) {
    resolveService()
    window.visible = true
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
  }

  function close() {
    window.visible = false
  }

  Service {
    id: localMx
    passive: true
  }

  readonly property var mx: root.service || localMx
  readonly property var device: mx ? mx.selectedDevice : null
  readonly property color foreground: Color.foreground
  readonly property color background: Color.background
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: Style.font.family

  FloatingWindow {
    id: window
    title: "OpenLogi Settings — " + (device ? Model.plainHidText(device.name) : "Logitech")
    width: 820
    height: 600
    visible: false

    Rectangle {
      anchors.fill: parent
      color: Color.background

      ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Titlebar & Tabs
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 56
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            spacing: 12

            OpenLogiIcon {
              iconSize: 24
              color: root.accent
              isKeyboard: Model.isKeyboard(device)
            }

            Column {
              Text {
                text: device ? Model.plainHidText(device.name) : "OpenLogi Devices"
                color: root.foreground
                font.bold: true
                font.pixelSize: 14
              }
              Text {
                text: device ? (Model.connectionLabel(device) + " · Battery: " + Model.batteryLabel(device)) : "No device connected"
                color: root.dim
                font.pixelSize: 11
              }
            }

            Item { Layout.fillWidth: true }

            // Navigation Tabs
            Row {
              spacing: 6

              Repeater {
                model: [
                  { id: "smartring", label: "Smart Ring & Gestures" },
                  { id: "buttons", label: "Button Remapping" },
                  { id: "pointer", label: "Pointer & Scroll" },
                  { id: "keyboard", label: "Keyboard Extras" }
                ]

                delegate: Rectangle {
                  width: tabLabel.implicitWidth + 24
                  height: 32
                  radius: 6
                  property bool isActive: root.activeTab === modelData.id
                  color: isActive ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

                  Text {
                    id: tabLabel
                    anchors.centerIn: parent
                    text: modelData.label
                    color: parent.isActive ? "#ffffff" : root.foreground
                    font.bold: parent.isActive
                    font.pixelSize: 12
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

        // Main Content Area
        StackLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          currentIndex: {
            if (root.activeTab === "smartring") return 0
            if (root.activeTab === "buttons") return 1
            if (root.activeTab === "pointer") return 2
            return 3
          }

          // TAB 1: Smart Ring & Gestures
          Item {
            RowLayout {
              anchors.fill: parent
              anchors.margins: 20
              spacing: 24

              // Left: Action Ring Radial Visualizer
              Rectangle {
                Layout.preferredWidth: 380
                Layout.fillHeight: true
                radius: 12
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)
                border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

                Column {
                  anchors.fill: parent
                  anchors.margins: 14
                  spacing: 12

                  Row {
                    width: parent.width
                    Text {
                      text: "Smart Action Ring (8 Slots)"
                      color: root.foreground
                      font.bold: true
                      font.pixelSize: 13
                    }
                    Item { width: 1; height: 1; Layout.fillWidth: true }
                  }

                  // Radial Wheel View
                  Item {
                    width: 350
                    height: 280

                    // Center Hub
                    Rectangle {
                      anchors.centerIn: parent
                      width: 80
                      height: 80
                      radius: 40
                      color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.2)
                      border.color: root.accent
                      border.width: 2

                      Column {
                        anchors.centerIn: parent
                        Text {
                          text: "◎"
                          color: root.accent
                          font.pixelSize: 22
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

                    // 8 Radial Slot Nodes
                    Repeater {
                      model: Model.getActionRingSlots(device)
                      delegate: Item {
                        id: slotNode
                        property real angleRad: (modelData.angle - 90) * Math.PI / 180
                        property real radius: 100
                        x: 175 + radius * Math.cos(angleRad) - width / 2
                        y: 140 + radius * Math.sin(angleRad) - height / 2
                        width: 72
                        height: 38

                        Rectangle {
                          anchors.fill: parent
                          radius: 8
                          property bool isSelected: root.selectedSlotId === modelData.id
                          color: isSelected ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
                          border.color: isSelected ? "#ffffff" : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.4)
                          border.width: isSelected ? 2 : 1

                          Column {
                            anchors.centerIn: parent
                            spacing: 1
                            Text {
                              text: modelData.glyph + " " + modelData.label
                              color: slotNode.children[0].isSelected ? "#ffffff" : root.dim
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
                            onClicked: root.selectedSlotId = modelData.id
                          }
                        }
                      }
                    }
                  }

                  // 5-Directional Gestures Section
                  Text {
                    text: "Directional Gestures (Hold + Swipe)"
                    color: root.foreground
                    font.bold: true
                    font.pixelSize: 13
                  }

                  Row {
                    spacing: 6
                    Repeater {
                      model: Model.getGestures(device)
                      delegate: Rectangle {
                        width: 65
                        height: 52
                        radius: 8
                        property bool isSelected: root.selectedGestureId === modelData.id
                        color: isSelected ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

                        Column {
                          anchors.centerIn: parent
                          spacing: 2
                          Text {
                            text: modelData.glyph + " " + modelData.label
                            color: parent.parent.isSelected ? "#ffffff" : root.dim
                            font.pixelSize: 9
                            anchors.horizontalCenter: parent.horizontalCenter
                          }
                          Text {
                            text: modelData.customLabel
                            color: parent.parent.isSelected ? "#ffffff" : root.foreground
                            font.bold: true
                            font.pixelSize: 9
                            elide: Text.ElideRight
                            width: 60
                            horizontalAlignment: Text.AlignHCenter
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
              }

              // Right: Action Selector for Selected Slot / Gesture
              Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 12
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)
                border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

                ColumnLayout {
                  anchors.fill: parent
                  anchors.margins: 16
                  spacing: 12

                  Text {
                    text: "Assign Action to Selected Slot: " + root.selectedSlotId
                    color: root.accent
                    font.bold: true
                    font.pixelSize: 14
                  }

                  // Search filter
                  TextField {
                    Layout.fillWidth: true
                    placeholderText: "Search actions (workspaces, media, window, shortcuts)..."
                    text: root.actionSearchQuery
                    onTextChanged: root.actionSearchQuery = text
                  }

                  // Action List
                  ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 6
                    model: Model.AVAILABLE_ACTIONS

                    delegate: Rectangle {
                      width: ListView.view.width
                      height: 40
                      radius: 6
                      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

                      RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12

                        Text {
                          text: modelData.label
                          color: root.foreground
                          font.bold: true
                          font.pixelSize: 12
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                          text: modelData.category
                          color: root.dim
                          font.pixelSize: 10
                        }

                        Button {
                          text: "Assign"
                          onClicked: {
                            if (device) {
                              mx.setActionRingSlot(device.id, root.selectedSlotId, modelData.id, modelData.label)
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

          // TAB 2: Button Remapping
          Item {
            RowLayout {
              anchors.fill: parent
              anchors.margins: 20
              spacing: 24

              // Buttons List
              Rectangle {
                Layout.preferredWidth: 320
                Layout.fillHeight: true
                radius: 12
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)

                ColumnLayout {
                  anchors.fill: parent
                  anchors.margins: 14
                  spacing: 10

                  Text {
                    text: "Physical Buttons"
                    color: root.foreground
                    font.bold: true
                    font.pixelSize: 14
                  }

                  ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 6
                    model: [
                      { id: "GestureButton", label: "Thumb Gesture Button" },
                      { id: "HapticPanel", label: "Smart Ring / Haptic Panel" },
                      { id: "DpiToggle", label: "Mode Shift / Top Button" },
                      { id: "MiddleClick", label: "Scroll Wheel Click" },
                      { id: "Back", label: "Thumb Back Button" },
                      { id: "Forward", label: "Thumb Forward Button" },
                      { id: "Thumbwheel", label: "Horizontal Thumb Wheel" }
                    ]

                    delegate: Rectangle {
                      width: ListView.view.width
                      height: 42
                      radius: 6
                      property bool isSelected: root.selectedButtonId === modelData.id
                      color: isSelected ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

                      RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12

                        Text {
                          text: modelData.label
                          color: parent.parent.isSelected ? "#ffffff" : root.foreground
                          font.bold: true
                          font.pixelSize: 11
                        }
                        Item { Layout.fillWidth: true }
                      }

                      MouseArea {
                        anchors.fill: parent
                        onClicked: root.selectedButtonId = modelData.id
                      }
                    }
                  }
                }
              }

              // Target Action assignment
              Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 12
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)

                ColumnLayout {
                  anchors.fill: parent
                  anchors.margins: 16
                  spacing: 12

                  Text {
                    text: "Map Button: " + root.selectedButtonId
                    color: root.accent
                    font.bold: true
                    font.pixelSize: 14
                  }

                  ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 6
                    model: Model.AVAILABLE_ACTIONS

                    delegate: Rectangle {
                      width: ListView.view.width
                      height: 40
                      radius: 6
                      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

                      RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12

                        Text {
                          text: modelData.label
                          color: root.foreground
                          font.bold: true
                          font.pixelSize: 12
                        }

                        Item { Layout.fillWidth: true }

                        Button {
                          text: "Map to Button"
                          onClicked: {
                            if (device) {
                              mx.setButton(device.id, root.selectedButtonId, modelData.id)
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
              anchors.margins: 24

              Column {
                width: 760
                spacing: 24

                // DPI Card
                Rectangle {
                  width: parent.width
                  height: 120
                  radius: 10
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

                  Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    Row {
                      width: parent.width
                      Text { text: "Sensor Sensitivity (DPI)"; color: root.foreground; font.bold: true; font.pixelSize: 13 }
                      Text { text: (device && device.dpi ? device.dpi : 1000) + " DPI"; color: root.accent; font.bold: true; anchors.right: parent.right }
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

                // SmartShift Card
                Rectangle {
                  width: parent.width
                  height: 140
                  radius: 10
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

                  Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    Text { text: "SmartShift & Ratchet Wheel"; color: root.foreground; font.bold: true; font.pixelSize: 13 }

                    Row {
                      spacing: 12
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
                              var thresh = device.smartshift ? device.smartshift.threshold : 12
                              mx.setSmartShift(device.id, modelData.id, thresh)
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

          // TAB 4: Keyboard Extras
          Item {
            ScrollView {
              anchors.fill: parent
              anchors.margins: 24

              Column {
                width: 760
                spacing: 20

                Rectangle {
                  width: parent.width
                  height: 160
                  radius: 10
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

                  Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 14

                    Text { text: "Keyboard Lighting & Fn Keys"; color: root.foreground; font.bold: true; font.pixelSize: 13 }

                    Row {
                      spacing: 16
                      CheckBox {
                        text: "Swap Fn-Key Behavior (Use F1-F12 as standard function keys)"
                        checked: device && device.keyboard ? device.keyboard.fn_swap : false
                        onToggled: {
                          if (device) {
                            var kb = device.keyboard || {}
                            kb.fn_swap = checked
                            mx.setKeyboard(device.id, kb)
                          }
                        }
                      }
                    }

                    Row {
                      spacing: 16
                      CheckBox {
                        text: "Disable Caps Lock"
                        checked: device && device.keyboard ? device.keyboard.disable_caps_lock : false
                        onToggled: {
                          if (device) {
                            var kb = device.keyboard || {}
                            kb.disable_caps_lock = checked
                            mx.setKeyboard(device.id, kb)
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
}
