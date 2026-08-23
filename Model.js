// Copyright (C) 2026 OpenLogi & Omarchy Contributors
// MIT License

var HID_AMP_RE = /&/g
var HID_LT_RE = /</g
var HID_GT_RE = />/g

function plainHidText(value) {
  if (value === undefined || value === null) return ""
  var text = String(value)
  if (text.indexOf("&") === -1 && text.indexOf("<") === -1 && text.indexOf(">") === -1)
    return text
  return text.replace(HID_AMP_RE, "&amp;").replace(HID_LT_RE, "&lt;").replace(HID_GT_RE, "&gt;")
}

function emptyStatus(message) {
  return {
    ok: false,
    openlogiInstalled: false,
    openlogiRunning: false,
    accessible: false,
    ts: 0,
    message: message || "",
    devices: [],
    adapters: []
  }
}

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return emptyStatus("No response from openlogictl")
  try {
    var data = JSON.parse(text)
    return {
      ok: data.ok !== false,
      openlogiInstalled: data.openlogiInstalled === true,
      openlogiRunning: data.openlogiRunning === true,
      accessible: data.accessible !== false,
      ts: isFinite(Number(data.ts)) ? Number(data.ts) : 0,
      message: plainHidText(data.message || ""),
      devices: Array.isArray(data.devices) ? data.devices : [],
      adapters: Array.isArray(data.adapters) ? data.adapters : []
    }
  } catch (e) {
    return emptyStatus("Failed to parse device status")
  }
}

function isMouse(device) {
  if (!device) return false
  var kind = String(device.kind || "").toLowerCase()
  if (kind === "mouse" || kind === "trackball" || kind === "touchpad") return true
  return /master|mouse|anywhere|vertical|lift|ergo|trackball|pebble/.test(String(device.name || "").toLowerCase())
}

function isKeyboard(device) {
  if (!device) return false
  var kind = String(device.kind || "").toLowerCase()
  if (kind.indexOf("key") !== -1 || kind === "keyboard") return true
  return /key|mechanical|craft|signature/.test(String(device.name || "").toLowerCase())
}

function deviceMatches(device, needle) {
  if (!device || needle === undefined || needle === null || String(needle) === "") return false
  var want = String(needle).toLowerCase()
  var keys = [device.id, device.unitId, device.serial, device.path, device.name, device.codename]
  for (var i = 0; i < keys.length; i++) {
    if (keys[i] !== undefined && keys[i] !== null && String(keys[i]).toLowerCase() === want) return true
  }
  if (device.path && String(device.path).split("/").pop().toLowerCase() === want) return true
  return false
}

function pickDefaultDevice(devices, preferredId, userPicked) {
  var list = Array.isArray(devices) ? devices : []
  if (preferredId) {
    for (var i = 0; i < list.length; i++) {
      if (deviceMatches(list[i], preferredId)) {
        if (userPicked === true || !isKeyboard(list[i])) return list[i]
        break
      }
    }
  }
  for (var j = 0; j < list.length; j++) if (isMouse(list[j]) && list[j].online !== false) return list[j]
  for (var k = 0; k < list.length; k++) if (list[k].online !== false) return list[k]
  return list.length > 0 ? list[0] : null
}

function batteryPercent(device) {
  if (!device) return -1
  var battery = device.battery
  if (battery && typeof battery.level === "number" && isFinite(battery.level)) return Math.round(battery.level)
  return -1
}

function batteryLabel(device) {
  var p = batteryPercent(device)
  if (p < 0) return ""
  var status = device && device.battery && device.battery.status ? String(device.battery.status).toLowerCase() : ""
  var charging = status === "charging" || status === "full"
  return String(p) + "%" + (charging ? " ⚡" : "")
}

function connectionLabel(device) {
  if (!device) return ""
  var conn = String(device.connection || "").toLowerCase()
  if (conn === "bluetooth" || conn === "bt") return "Bluetooth"
  if (conn === "bolt") return "Bolt"
  if (conn === "unifying") return "Unifying"
  if (conn === "lightspeed") return "Lightspeed"
  if (conn === "usb") return "USB"
  return conn ? conn.toUpperCase() : ""
}

// Action Ring slot definitions & angles (8 slots)
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

// Gestures direction definitions (5 directions)
var GESTURE_DIRECTIONS = [
  { id: "Up", label: "Swipe Up", glyph: "↑", defaultAction: "MaximizeWindow" },
  { id: "Down", label: "Swipe Down", glyph: "↓", defaultAction: "MinimizeWindow" },
  { id: "Left", label: "Swipe Left", glyph: "←", defaultAction: "TileLeft" },
  { id: "Right", label: "Swipe Right", glyph: "→", defaultAction: "TileRight" },
  { id: "Click", label: "Single Click", glyph: "·", defaultAction: "ShowActionRing" }
]

// Available action library for Smart Ring & buttons
var AVAILABLE_ACTIONS = [
  { id: "ShowActionRing", label: "Smart Action Ring", category: "OpenLogi", icon: "gesture" },
  { id: "Gestures", label: "Directional Gestures", category: "OpenLogi", icon: "gesture" },
  { id: "MissionControl", label: "Overview / Workspaces", category: "Window Manager", icon: "view_compact" },
  { id: "ShowDesktop", label: "Show Desktop", category: "Window Manager", icon: "desktop_windows" },
  { id: "NextWorkspace", label: "Next Workspace", category: "Window Manager", icon: "arrow_forward" },
  { id: "PrevWorkspace", label: "Previous Workspace", category: "Window Manager", icon: "arrow_back" },
  { id: "MaximizeWindow", label: "Maximize / Toggle Fullscreen", category: "Window Manager", icon: "fullscreen" },
  { id: "MinimizeWindow", label: "Minimize Window", category: "Window Manager", icon: "minimize" },
  { id: "TileLeft", label: "Tile Left", category: "Window Manager", icon: "dock_to_left" },
  { id: "TileRight", label: "Tile Right", category: "Window Manager", icon: "dock_to_right" },
  { id: "CloseWindow", label: "Close Window", category: "Window Manager", icon: "close" },
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
    var custom = conf[slotDef.id] || {}
    result.push({
      id: slotDef.id,
      label: slotDef.label,
      angle: slotDef.angle,
      glyph: slotDef.glyph,
      action: custom.action || slotDef.defaultAction,
      customLabel: custom.label || actionLabel(custom.action || slotDef.defaultAction),
      icon: actionIcon(custom.action || slotDef.defaultAction)
    })
  }
  return result
}

function getGestures(device) {
  var conf = device && device.gestures ? device.gestures : {}
  var result = []
  for (var i = 0; i < GESTURE_DIRECTIONS.length; i++) {
    var gDef = GESTURE_DIRECTIONS[i]
    var custom = conf[gDef.id] || {}
    result.push({
      id: gDef.id,
      label: gDef.label,
      glyph: gDef.glyph,
      action: custom.action || gDef.defaultAction,
      customLabel: custom.label || actionLabel(custom.action || gDef.defaultAction),
      icon: actionIcon(custom.action || gDef.defaultAction)
    })
  }
  return result
}
