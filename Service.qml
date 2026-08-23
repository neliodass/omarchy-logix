import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property var shell: null
  property bool passive: false

  property bool openlogiInstalled: false
  property bool openlogiRunning: false
  property bool accessible: true
  property bool refreshing: false
  property bool daemonWanted: false
  property bool userPicked: false
  property string statusText: "Checking…"
  property string message: ""
  property string lastError: ""
  property var devices: []
  property var adapters: []
  property string selectedId: ""

  readonly property string runtimeDir: {
    var dir = Quickshell.env("XDG_RUNTIME_DIR")
    if (dir && dir !== "") return String(dir) + "/omarchy-openlogi"
    var uid = Quickshell.env("UID") || "1000"
    return "/run/user/" + String(uid) + "/omarchy-openlogi"
  }
  readonly property string statusPath: runtimeDir + "/status.json"
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 15, 5, 300)
  readonly property string preferredId: String(setting("selectedDevice", selectedId || ""))
  readonly property string helperPath: resolvedHelper()

  readonly property var bluetoothDevices: Bluetooth.devices ? Bluetooth.devices.values : []
  readonly property var displayDevices: devices
  readonly property var selectedDevice: Model.pickDefaultDevice(displayDevices, preferredId, userPicked)
  readonly property int batteryPercent: Model.batteryPercent(selectedDevice)
  readonly property bool batteryLow: batteryPercent >= 0 && batteryPercent <= 20
  readonly property bool online: !!(selectedDevice && selectedDevice.online !== false)
  readonly property bool hasDevice: !!selectedDevice
  readonly property bool hasActionRing: !!(selectedDevice && selectedDevice.capabilities && selectedDevice.capabilities.action_ring)
  readonly property bool hasSmartShift: !!(selectedDevice && selectedDevice.capabilities && selectedDevice.capabilities.smartshift)

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function resolvedHelper() {
    var url = String(Qt.resolvedUrl("openlogictl.py"))
    if (url.indexOf("file://") === 0) url = decodeURIComponent(url.substring(7))
    return url
  }

  function selectDevice(id) {
    userPicked = true
    selectedId = String(id || "")
  }

  function refresh() {
    if (discoverProcess.running) return
    refreshing = true
    discoverProcess.running = true
  }

  function ensureDaemon() {
    daemonWanted = true
    if (!serveProcess.running) {
      serveProcess.running = true
    }
  }

  function sendCommand(type, deviceId, payload) {
    var devId = deviceId || (selectedDevice ? selectedDevice.id : "")
    if (!devId) return
    var payloadJson = JSON.stringify(payload || {})
    var cmd = [helperPath, "write-cmd", type, devId, payloadJson]
    Quickshell.exec(cmd, function() {
      // Re-trigger refresh after command
      Qt.callLater(refresh)
    })
  }

  function setDpi(deviceId, dpi) {
    sendCommand("set_dpi", deviceId, { dpi: dpi })
  }

  function setSmartShift(deviceId, mode, threshold) {
    sendCommand("set_smartshift", deviceId, { mode: mode, threshold: threshold })
  }

  function setScroll(deviceId, invertY, invertThumb, hires) {
    sendCommand("set_scroll", deviceId, { invert_y: invertY, invert_thumb: invertThumb, hires: hires })
  }

  function setActionRing(deviceId, enabled, haptics) {
    sendCommand("set_action_ring", deviceId, { enabled: enabled, haptics: haptics })
  }

  function setActionRingSlot(deviceId, slot, action, label) {
    sendCommand("set_action_ring_slot", deviceId, { slot: slot, action: action, label: label })
  }

  function setGesture(deviceId, direction, action, label) {
    sendCommand("set_gesture", deviceId, { direction: direction, action: action, label: label })
  }

  function setButton(deviceId, button, action) {
    sendCommand("set_button", deviceId, { button: button, action: action })
  }

  function setKeyboard(deviceId, kbSettings) {
    sendCommand("set_keyboard", deviceId, kbSettings)
  }

  function applyStatusData(data) {
    root.openlogiInstalled = data.openlogiInstalled
    root.openlogiRunning = data.openlogiRunning
    root.accessible = data.accessible
    root.devices = data.devices || []
    root.adapters = data.adapters || []
    root.message = data.message || ""
    root.refreshing = false
  }

  Process {
    id: discoverProcess
    command: [root.helperPath, "discover"]
    running: false
    stdout: StderrMode.Pipe

    onExited: function(code) {
      root.refreshing = false
      if (code === 0) {
        var raw = discoverProcess.readAll()
        var parsed = Model.parseStatus(raw)
        root.applyStatusData(parsed)
      }
    }
  }

  Process {
    id: serveProcess
    command: [root.helperPath, "serve"]
    running: false
  }

  Timer {
    id: pollTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: !root.passive
    triggeredOnStart: true
    onTriggered: {
      root.refresh()
    }
  }

  Component.onCompleted: {
    if (!root.passive) {
      root.refresh()
    }
  }

  Component.onDestruction: {
    if (serveProcess.running) {
      serveProcess.running = false
    }
    Quickshell.exec([root.helperPath, "cleanup"])
  }
}
