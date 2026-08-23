import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.openlogi.omarchy"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property color barForeground: bar ? bar.barForeground : Color.foreground
  readonly property color iconColor: {
    if (!mx.hasDevice) return Qt.darker(barForeground, 1.55)
    if (mx.batteryLow) return bar && bar.urgent ? bar.urgent : Color.urgent
    return mx.online ? barForeground : Qt.darker(barForeground, 1.55)
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function refresh() {
    mx.refresh()
  }

  function showActionRing() {
    if (overlayLoader.item) overlayLoader.item.showRing()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("mx" in target) target.mx = mx

    if (overlayLoader.item) {
      if ("service" in overlayLoader.item) overlayLoader.item.service = mx
      if ("shell" in overlayLoader.item && root.bar) overlayLoader.item.shell = root.bar.shell
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: {
    resolveService()
    injectPanel()
  }
  onSettingsChanged: {
    if (sharedMx && "settings" in sharedMx) sharedMx.settings = root.settings
    injectPanel()
  }

  property var sharedMx: null
  readonly property var mx: sharedMx || localMx

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
      injectPanel()
      return
    }
    localMx.passive = false
  }

  Service {
    id: localMx
    settings: root.settings
    passive: true
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  Loader {
    id: overlayLoader
    active: true
    source: Qt.resolvedUrl("ActionRingOverlay.qml")
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "io.openlogi.omarchy"

    function refresh(): void { root.refresh() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function showActionRing(): void { root.showActionRing() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: {
      if (!mx.hasDevice) return "OpenLogi Control — No device"
      var name = Model.plainHidText(mx.selectedDevice && mx.selectedDevice.name ? mx.selectedDevice.name : "Logitech MX")
      var link = Model.connectionLabel(mx.selectedDevice)
      var battery = mx.batteryPercent >= 0 ? (" · " + mx.batteryPercent + "%") : ""
      return name + (link ? (" · " + link) : "") + battery
    }
    iconComponent: Component {
      OpenLogiIcon {
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
}
