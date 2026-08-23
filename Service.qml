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
  property bool hasSnapshot: false
  property string statusText: "Checking…"
  property string message: ""
  property string lastError: ""
  property var devices: []
  property var adapters: []
  property string selectedId: ""
  property double lastStatusMs: 0
  property bool peerServing: false

  property string probedUid: ""
  readonly property string runtimeUid: {
    var uid = Quickshell.env("UID")
    if (uid && /^\d+$/.test(String(uid))) return String(uid)
    return probedUid
  }

  readonly property string runtimeDir: {
    var dir = Quickshell.env("XDG_RUNTIME_DIR")
    if (dir && dir !== "") return String(dir) + "/omarchy-openlogi"
    return "/run/user/" + String(runtimeUid || "") + "/omarchy-openlogi"
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

  function applyStatus(raw, source) {
    try {
      var parsed = Model.parseStatus(raw)
      if (source === "file") lastStatusMs = Date.now()
      openlogiInstalled = parsed.openlogiInstalled === true
      openlogiRunning = parsed.openlogiRunning === true
      accessible = parsed.accessible === true
      devices = parsed.devices || []
      adapters = parsed.adapters || []
      message = String(parsed.message || "")
      hasSnapshot = devices.length > 0
      refreshing = false

      var picked = Model.pickDefaultDevice(devices, preferredId, userPicked)
      if (picked && picked.id) selectedId = String(picked.id)
      statusText = !devices.length ? (message || "No Logitech device") : (picked ? picked.name : "OpenLogi")
    } catch (e) {
      console.warn("openlogi applyStatus error:", e)
    }
  }

  function discover() {
    if (discoverProcess.running || helperPath === "") return
    refreshing = true
    discoverProcess.command = ["python3", helperPath, "discover"]
    discoverProcess.running = true
  }

  function ensureDaemon() {
    daemonWanted = true
    peerServing = false
    lastStatusMs = Date.now()
    if (!daemon.running && !peerServing) {
      daemon.running = true
    }
  }

  function refresh(force) {
    if (daemonWanted) {
      if (statusFile) statusFile.reload()
      return
    }
    discover()
  }

  function selectDevice(id) {
    userPicked = true
    selectedId = String(id || "")
  }

  function writeCmd(type, payload) {
    if (helperPath === "") return
    var devId = selectedDevice ? selectedDevice.id : ""
    var payloadJson = JSON.stringify(payload || {})
    Quickshell.execDetached(["python3", helperPath, "write-cmd", type, devId, payloadJson])
    Qt.callLater(function() {
      if (statusFile) statusFile.reload()
      discover()
    })
  }

  function setDpi(deviceId, dpi) {
    writeCmd("set_dpi", { dpi: dpi })
  }

  function setSmartShift(deviceId, mode, threshold) {
    writeCmd("set_smartshift", { mode: mode, threshold: threshold })
  }

  function setScroll(deviceId, invertY, invertThumb, hires) {
    writeCmd("set_scroll", { invert_y: invertY, invert_thumb: invertThumb, hires: hires })
  }

  function setActionRing(deviceId, enabled, haptics) {
    writeCmd("set_action_ring", { enabled: enabled, haptics: haptics })
  }

  function setActionRingSlot(deviceId, slot, action, label) {
    writeCmd("set_action_ring_slot", { slot: slot, action: action, label: label })
  }

  function setGesture(deviceId, direction, action, label) {
    writeCmd("set_gesture", { direction: direction, action: action, label: label })
  }

  function setButton(deviceId, button, action) {
    writeCmd("set_button", { button: button, action: action })
  }

  function setKeyboard(deviceId, kbSettings) {
    writeCmd("set_keyboard", kbSettings)
  }

  FileView {
    id: statusFile
    path: root.statusPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyStatus(text(), "file")
    onFileChanged: reload()
  }

  Process {
    id: uidProbe
    running: {
      var dir = Quickshell.env("XDG_RUNTIME_DIR")
      if (dir && dir !== "") return false
      var uid = Quickshell.env("UID")
      if (uid && /^\d+$/.test(String(uid))) return false
      return root.probedUid === ""
    }
    command: ["id", "-u"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var uid = String(text).trim()
        if (/^\d+$/.test(uid)) root.probedUid = uid
      }
    }
  }

  Process {
    id: mkdirProcess
    running: false
    command: ["python3", root.helperPath, "runtime-dir"]
    onExited: Qt.callLater(function() { if (statusFile) statusFile.reload() })
  }

  Process {
    id: daemon
    running: root.daemonWanted && !root.peerServing
    command: ["python3", root.helperPath, "serve"]
    onExited: function(exitCode) {
      if (!root.daemonWanted) return
      root.peerServing = false
      Qt.callLater(function() {
        if (root.daemonWanted && !root.peerServing && !daemon.running)
          daemon.running = true
      })
    }
  }

  Process {
    id: discoverProcess
    running: false
    command: ["python3", root.helperPath, "discover"]
    stdout: StdioCollector {
      id: discoverStdout
      waitForEnd: true
      onStreamFinished: {
        root.refreshing = false
        if (text) root.applyStatus(text, "discover")
      }
    }
    onExited: root.refreshing = false
  }

  Timer {
    id: pollTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: !root.passive
    triggeredOnStart: true
    onTriggered: root.discover()
  }

  Component.onCompleted: {
    if (!passive) {
      mkdirProcess.running = true
      Qt.callLater(function() {
        if (statusFile) statusFile.reload()
        root.discover()
      })
    }
  }

  Component.onDestruction: {
    daemonWanted = false
    if (daemon.running) daemon.running = false
    if (discoverProcess.running) discoverProcess.running = false
    Quickshell.execDetached(["python3", root.helperPath, "cleanup"])
  }
}
