// Model.js — LogiX Control Data Models & Helpers for Omarchy 4.0
// Pure JS zero-dependency state parsing and configuration mapping

var ACTION_RING_SLOTS = [
  { id: "Top", label: "Top", angle: 0, glyph: "↑", defaultAction: "MissionControl" },
  { id: "TopRight", label: "Top Right", angle: 45, glyph: "↗", defaultAction: "NextWorkspace" },
  { id: "Right", label: "Right", angle: 90, glyph: "→", defaultAction: "VolumeUp" },
  { id: "BottomRight", label: "Bottom Right", angle: 135, glyph: "↘", defaultAction: "PlayPause" },
  { id: "Bottom", label: "Bottom", angle: 180, glyph: "↓", defaultAction: "ShowDesktop" },
  { id: "BottomLeft", label: "Bottom Left", angle: 225, glyph: "↙", defaultAction: "PrevWorkspace" },
  { id: "Left", label: "Left", angle: 270, glyph: "←", defaultAction: "VolumeDown" },
  { id: "TopLeft", label: "Top Left", angle: 315, glyph: "↖", defaultAction: "Mute" }
]

var GESTURE_DIRECTIONS = [
  { id: "Up", label: "Swipe Up", glyph: "↑", defaultAction: "TileUp" },
  { id: "Down", label: "Swipe Down", glyph: "↓", defaultAction: "TileDown" },
  { id: "Left", label: "Swipe Left", glyph: "←", defaultAction: "TileLeft" },
  { id: "Right", label: "Swipe Right", glyph: "→", defaultAction: "TileRight" },
  { id: "Click", label: "Single Click", glyph: "◎", defaultAction: "ShowActionRing" }
]

var HARDWARE_BUTTONS = [
  { id: "HapticPanel", label: "Smart Ring / Thumb Rest", defaultAction: "ShowActionRing" },
  { id: "GestureButton", label: "Thumb Gesture Button", defaultAction: "Gestures" },
  { id: "DpiToggle", label: "Top Mode Button", defaultAction: "DpiCycle" },
  { id: "MiddleClick", label: "Scroll Wheel Click", defaultAction: "MiddleClick" },
  { id: "Back", label: "Side Back Button", defaultAction: "Back" },
  { id: "Forward", label: "Side Forward Button", defaultAction: "Forward" },
  { id: "Thumbwheel", label: "Horizontal Thumb Wheel", defaultAction: "HorizontalScroll" }
]

var AVAILABLE_ACTIONS = [
  { id: "ShowActionRing", label: "Smart Action Ring", category: "LogiX", icon: "donut_large" },
  { id: "Gestures", label: "Directional Gestures", category: "LogiX", icon: "pan_tool" },
  { id: "MissionControl", label: "Overview / Mission Control", category: "Window", icon: "dashboard" },
  { id: "NextWorkspace", label: "Next Workspace", category: "Window", icon: "arrow_forward" },
  { id: "PrevWorkspace", label: "Previous Workspace", category: "Window", icon: "arrow_back" },
  { id: "MaximizeWindow", label: "Maximize Window", category: "Window", icon: "fullscreen" },
  { id: "MinimizeWindow", label: "Minimize Window", category: "Window", icon: "minimize" },
  { id: "CloseWindow", label: "Close Window", category: "Window", icon: "close" },
  { id: "TileLeft", label: "Tile Left / Focus Left", category: "Window", icon: "chevron_left" },
  { id: "TileRight", label: "Tile Right / Focus Right", category: "Window", icon: "chevron_right" },
  { id: "TileUp", label: "Tile Up / Focus Up", category: "Window", icon: "expand_less" },
  { id: "TileDown", label: "Tile Down / Focus Down", category: "Window", icon: "expand_more" },
  { id: "ShowDesktop", label: "Show Desktop / Special", category: "Window", icon: "desktop_windows" },
  { id: "VolumeUp", label: "Volume Up", category: "Media", icon: "volume_up" },
  { id: "VolumeDown", label: "Volume Down", category: "Media", icon: "volume_down" },
  { id: "Mute", label: "Mute Audio", category: "Media", icon: "volume_off" },
  { id: "PlayPause", label: "Play / Pause", category: "Media", icon: "play_arrow" },
  { id: "NextTrack", label: "Next Track", category: "Media", icon: "skip_next" },
  { id: "PrevTrack", label: "Previous Track", category: "Media", icon: "skip_previous" },
  { id: "MicMute", label: "Mute Microphone", category: "Media", icon: "mic_off" },
  { id: "Screenshot", label: "Take Screenshot", category: "System", icon: "screenshot" },
  { id: "Launcher", label: "App Launcher / Search", category: "System", icon: "search" },
  { id: "DpiCycle", label: "Cycle DPI Presets", category: "Hardware", icon: "speed" },
  { id: "SmartShiftToggle", label: "Toggle SmartShift Mode", category: "Hardware", icon: "cached" },
  { id: "MiddleClick", label: "Middle Click", category: "Mouse", icon: "mouse" },
  { id: "Back", label: "Back", category: "Mouse", icon: "arrow_back" },
  { id: "Forward", label: "Forward", category: "Mouse", icon: "arrow_forward" },
  { id: "HorizontalScroll", label: "Horizontal Scroll", category: "Mouse", icon: "swap_horiz" },
  { id: "None", label: "Do Nothing", category: "None", icon: "block" }
]

function actionLabel(actionId) {
  for (var i = 0; i < AVAILABLE_ACTIONS.length; i++) {
    if (AVAILABLE_ACTIONS[i].id === actionId) return AVAILABLE_ACTIONS[i].label
  }
  return actionId || "Do Nothing"
}

function actionIcon(actionId) {
  for (var i = 0; i < AVAILABLE_ACTIONS.length; i++) {
    if (AVAILABLE_ACTIONS[i].id === actionId) return AVAILABLE_ACTIONS[i].icon
  }
  return "extension"
}

function getActionRingSlots(device) {
  var conf = device && device.action_ring && device.action_ring.slots ? device.action_ring.slots : {}
  var result = []
  for (var i = 0; i < ACTION_RING_SLOTS.length; i++) {
    var slotDef = ACTION_RING_SLOTS[i]
    var custom = conf[slotDef.id]
    var actId = (typeof custom === "string") ? custom : (custom && custom.action ? custom.action : slotDef.defaultAction)
    var actLabel = (custom && custom.label) ? custom.label : actionLabel(actId)
    result.push({
      id: slotDef.id,
      label: slotDef.label,
      angle: slotDef.angle,
      glyph: slotDef.glyph,
      action: actId,
      customLabel: actLabel,
      icon: actionIcon(actId)
    })
  }
  return result
}

function getGestures(device) {
  var conf = device && device.gestures ? device.gestures : {}
  var result = []
  for (var i = 0; i < GESTURE_DIRECTIONS.length; i++) {
    var gDef = GESTURE_DIRECTIONS[i]
    var custom = conf[gDef.id]
    var actId = (typeof custom === "string") ? custom : (custom && custom.action ? custom.action : gDef.defaultAction)
    var actLabel = (custom && custom.label) ? custom.label : actionLabel(actId)
    result.push({
      id: gDef.id,
      label: gDef.label,
      glyph: gDef.glyph,
      action: actId,
      customLabel: actLabel,
      icon: actionIcon(actId)
    })
  }
  return result
}

function getButtons(device) {
  var conf = device && device.buttons ? device.buttons : {}
  var result = []
  for (var i = 0; i < HARDWARE_BUTTONS.length; i++) {
    var bDef = HARDWARE_BUTTONS[i]
    var custom = conf[bDef.id]
    var actId = (typeof custom === "string") ? custom : (custom && custom.action ? custom.action : bDef.defaultAction)
    result.push({
      id: bDef.id,
      label: bDef.label,
      action: actId,
      actionLabel: actionLabel(actId),
      icon: actionIcon(actId)
    })
  }
  return result
}

function parseStatus(raw) {
  if (!raw || typeof raw !== "string") {
    return { driver: "LogiX Engine", accessible: false, devices: [], adapters: [], message: "No data" }
  }
  try {
    var obj = JSON.parse(raw.trim())
    return obj
  } catch (e) {
    return { driver: "LogiX Engine", accessible: false, devices: [], adapters: [], message: "Parse error" }
  }
}

function pickDefaultDevice(devices, preferredId, userPicked) {
  if (!devices || !devices.length) return null
  if (preferredId) {
    for (var i = 0; i < devices.length; i++) {
      if (devices[i].id === preferredId || devices[i].serial === preferredId) return devices[i]
    }
  }
  return devices[0]
}

function batteryPercent(device) {
  if (!device || !device.battery || device.battery.level === undefined || device.battery.level === null) return -1
  var lvl = parseInt(String(device.battery.level), 10)
  return isNaN(lvl) ? -1 : lvl
}

function batteryLabel(device) {
  var pct = batteryPercent(device)
  return pct >= 0 ? (pct + "%") : "N/A"
}

function isKeyboard(device) {
  return !!(device && device.kind === "keyboard")
}

function connectionLabel(device) {
  if (!device) return ""
  if (device.connection === "bluetooth") return "Bluetooth"
  if (device.connection === "bolt") return "Bolt Receiver"
  if (device.connection === "unifying") return "Unifying"
  return "USB"
}

function plainHidText(raw) {
  if (!raw) return ""
  return String(raw).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#039;")
}
