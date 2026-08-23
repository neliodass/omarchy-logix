import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Scope {
  id: root

  property var shell: null
  property var service: null
  property var activeDevice: service ? service.selectedDevice : null
  property bool active: false
  property string highlightedSlot: ""

  function resolveService() {
    if (service || !shell) return
    if (typeof shell.ensureService === "function")
      service = shell.ensureService("io.openlogi.omarchy") || null
    if (!service && typeof shell.serviceFor === "function")
      service = shell.serviceFor("io.openlogi.omarchy")
  }

  function showRing() {
    resolveService()
    root.active = true
    overlayWindow.visible = true
  }

  function hideRing() {
    root.active = false
    overlayWindow.visible = false
    highlightedSlot = ""
  }

  function executeSlot(slotId) {
    var slots = Model.getActionRingSlots(activeDevice)
    for (var i = 0; i < slots.length; i++) {
      if (slots[i].id === slotId) {
        // Trigger action via Omarchy shell
        var act = slots[i].action
        if (shell && typeof shell.dispatchAction === "function") {
          shell.dispatchAction(act)
        }
        break
      }
    }
    hideRing()
  }

  FloatingWindow {
    id: overlayWindow
    width: 380
    height: 380
    visible: false
    color: "transparent"

    Item {
      anchors.fill: parent

      // Dim backdrop dismiss area
      MouseArea {
        anchors.fill: parent
        onClicked: root.hideRing()
      }

      // Center Radial Hub
      Rectangle {
        anchors.centerIn: parent
        width: 100
        height: 100
        radius: 50
        color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 0.95)
        border.color: Color.accent
        border.width: 2

        Column {
          anchors.centerIn: parent
          spacing: 2
          Text {
            text: "◎"
            color: Color.accent
            font.pixelSize: 26
            anchors.horizontalCenter: parent.horizontalCenter
          }
          Text {
            text: root.highlightedSlot ? root.highlightedSlot : "Smart Ring"
            color: Color.foreground
            font.pixelSize: 11
            font.bold: true
            anchors.horizontalCenter: parent.horizontalCenter
          }
        }
      }

      // 8 Action Slots
      Repeater {
        model: Model.getActionRingSlots(root.activeDevice)
        delegate: Item {
          id: node
          property real angleRad: (modelData.angle - 90) * Math.PI / 180
          property real radius: 130
          x: 190 + radius * Math.cos(angleRad) - width / 2
          y: 190 + radius * Math.sin(angleRad) - height / 2
          width: 82
          height: 48

          Rectangle {
            anchors.fill: parent
            radius: 10
            property bool isHovered: root.highlightedSlot === modelData.id
            color: isHovered ? Color.accent : Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 0.9)
            border.color: isHovered ? "#ffffff" : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.2)
            border.width: isHovered ? 2 : 1

            Column {
              anchors.centerIn: parent
              spacing: 2
              Text {
                text: modelData.glyph + " " + modelData.label
                color: node.children[0].isHovered ? "#ffffff" : Color.accent
                font.pixelSize: 10
                anchors.horizontalCenter: parent.horizontalCenter
              }
              Text {
                text: modelData.customLabel
                color: node.children[0].isHovered ? "#ffffff" : Color.foreground
                font.bold: true
                font.pixelSize: 11
                elide: Text.ElideRight
                width: parent.parent.width - 8
                horizontalAlignment: Text.AlignHCenter
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onEntered: root.highlightedSlot = modelData.id
              onExited: if (root.highlightedSlot === modelData.id) root.highlightedSlot = ""
              onClicked: root.executeSlot(modelData.id)
            }
          }
        }
      }
    }
  }
}
