#!/usr/bin/env python3
# logixctl.py — LogiX Controller & Hardware HID++ Driver for Omarchy
# Direct kernel hidraw communication, Smart Ring gesture engine, and TOML configuration.

import argparse
import fcntl
import glob
import json
import math
import os
import re
import select
import shlex
import shutil
import struct
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

# ----------------------------------------------------------------------
# Hardware Button Identifiers & Action Ring Constants
# ----------------------------------------------------------------------

ACTION_RING_SLOTS = [
    {"id": "Top", "angle": 0, "label": "Top", "defaultAction": "ToggleMaximize", "glyph": "🗖"},
    {"id": "TopRight", "angle": 45, "label": "Top Right", "defaultAction": "FocusNextWindow", "glyph": "🡵"},
    {"id": "Right", "angle": 90, "label": "Right", "defaultAction": "WorkspaceNext", "glyph": "🡲"},
    {"id": "BottomRight", "angle": 135, "label": "Bottom Right", "defaultAction": "VolumeUp", "glyph": "🡶"},
    {"id": "Bottom", "angle": 180, "label": "Bottom", "defaultAction": "ToggleOverview", "glyph": "🗔"},
    {"id": "BottomLeft", "angle": 225, "label": "Bottom Left", "defaultAction": "VolumeDown", "glyph": "🡷"},
    {"id": "Left", "angle": 270, "label": "Left", "defaultAction": "WorkspacePrev", "glyph": "🡰"},
    {"id": "TopLeft", "angle": 315, "label": "Top Left", "defaultAction": "FocusPrevWindow", "glyph": "🡴"},
]

SLOT_ALIASES = {
    "Slot0": "Top",
    "Slot1": "TopRight",
    "Slot2": "Right",
    "Slot3": "BottomRight",
    "Slot4": "Bottom",
    "Slot5": "BottomLeft",
    "Slot6": "Left",
    "Slot7": "TopLeft",
}

GESTURE_DIRECTIONS = [
    {"id": "Up", "label": "Swipe Up", "defaultAction": "ToggleMaximize", "glyph": "🡹"},
    {"id": "Down", "label": "Swipe Down", "defaultAction": "ToggleOverview", "glyph": "🡻"},
    {"id": "Left", "label": "Swipe Left", "defaultAction": "WorkspacePrev", "glyph": "🡸"},
    {"id": "Right", "label": "Swipe Right", "defaultAction": "WorkspaceNext", "glyph": "🡺"},
]

HARDWARE_BUTTONS = [
    {"id": "HapticPanel", "label": "Thumb Rest / Smart Ring", "defaultAction": "ShowActionRing", "glyph": "◎", "cid": 0x01A0},
    {"id": "MiddleButton", "label": "Middle Mouse Click", "defaultAction": "MiddleClick", "glyph": "⬡", "cid": 0x0052},
    {"id": "BackButton", "label": "Thumb Back Button", "defaultAction": "NavigateBack", "glyph": "🡰", "cid": 0x0053},
    {"id": "ForwardButton", "label": "Thumb Forward Button", "defaultAction": "NavigateForward", "glyph": "🡺", "cid": 0x0056},
    {"id": "ModeShift", "label": "SmartShift Wheel Button", "defaultAction": "ToggleSmartShift", "glyph": "⚙", "cid": 0x00D0},
    {"id": "TopButton", "label": "Top / DPI Button", "defaultAction": "ToggleDpi", "glyph": "▲", "cid": 0x00C4},
]

CID_TO_BUTTON = {b["cid"]: b["id"] for b in HARDWARE_BUTTONS if "cid" in b}


# ----------------------------------------------------------------------
# Paths and Environment
# ----------------------------------------------------------------------

def get_runtime_dir() -> Path:
    xdg = os.environ.get("XDG_RUNTIME_DIR")
    if xdg:
        base = Path(xdg)
    else:
        base = Path(f"/run/user/{os.getuid()}")
    rdir = base / "omarchy-logix"
    rdir.mkdir(parents=True, exist_ok=True)
    return rdir


def get_logix_config_path() -> Path:
    xdg = os.environ.get("XDG_CONFIG_HOME")
    if xdg:
        base = Path(xdg)
    else:
        base = Path.home() / ".config"
    logix_path = base / "logix" / "config.toml"
    if not logix_path.exists():
        openlogi_fallback = base / "openlogi" / "config.toml"
        if openlogi_fallback.exists():
            return openlogi_fallback
    return logix_path


# ----------------------------------------------------------------------
# Low-Level HID++ 2.0 Communication & Hardware Control
# ----------------------------------------------------------------------

def open_hidraw(path: str) -> Optional[int]:
    try:
        return os.open(path, os.O_RDWR | os.O_NONBLOCK)
    except (OSError, IOError, PermissionError):
        return None


def hidpp_call(fd: int, feat_idx: int, func_idx: int, params: bytes = b"", dev_idx: int = 0xFF, timeout: float = 0.4) -> Optional[bytes]:
    if fd is None or fd < 0:
        return None
    req = bytearray(20)
    req[0] = 0x11  # HID++ 2.0 Long Report
    req[1] = dev_idx
    req[2] = feat_idx
    req[3] = (func_idx & 0x0F) << 4
    for i, p in enumerate(params):
        if 4 + i < len(req):
            req[4 + i] = p

    try:
        os.write(fd, req)
    except OSError:
        return None

    deadline = time.time() + timeout
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.02)
        if fd in r:
            try:
                res = os.read(fd, 64)
                if len(res) >= 4 and res[0] == 0x11 and res[2] == feat_idx:
                    return res
                if len(res) >= 4 and res[0] == 0x11 and res[2] == 0xFF and res[3] == feat_idx:
                    return None  # HID++ Error response
            except OSError:
                return None
    return None


def get_feature_index(fd: int, feature_id: int) -> Optional[int]:
    req_params = struct.pack(">H", feature_id)
    res = hidpp_call(fd, 0x00, 0x00, req_params, timeout=0.4)
    if res and len(res) >= 5:
        feat_idx = res[4]
        return feat_idx if feat_idx != 0 else None
    return None


def set_button_diversion(fd: int, cid: int, divert: bool = True, raw_xy: bool = True, feat_idx: Optional[int] = None) -> bool:
    if feat_idx is None:
        feat_idx = get_feature_index(fd, 0x1B04)
    if feat_idx is None:
        return False
    p = bytearray(16)
    p[0] = (cid >> 8) & 0xFF
    p[1] = cid & 0xFF
    if divert:
        p[2] = 0x33 if raw_xy else 0x03  # divert + raw_xy streaming
    else:
        p[2] = 0x32 if raw_xy else 0x02  # clear divert
    res = hidpp_call(fd, feat_idx, 0x03, bytes(p), timeout=0.4)
    return res is not None


def apply_hardware_dpi(hidraw_path: str, dpi: int) -> bool:
    fd = open_hidraw(hidraw_path)
    if fd is None:
        return False
    try:
        feat_idx = get_feature_index(fd, 0x2201)
        if feat_idx is None:
            return False
        params = bytearray(16)
        params[0] = 0x00
        params[1] = (dpi >> 8) & 0xFF
        params[2] = dpi & 0xFF
        res = hidpp_call(fd, feat_idx, 0x03, bytes(params))
        return res is not None
    finally:
        try:
            os.close(fd)
        except OSError:
            pass


def apply_hardware_smartshift(hidraw_path: str, mode: str, threshold: int, torque: int = 75) -> bool:
    fd = open_hidraw(hidraw_path)
    if fd is None:
        return False
    try:
        feat_idx = get_feature_index(fd, 0x2111)
        if feat_idx is None:
            feat_idx = get_feature_index(fd, 0x2110)
        if feat_idx is None:
            return False

        if mode == "freewheel":
            wheel_mode = 1
            auto_disengage = 0
        elif mode == "ratchet":
            wheel_mode = 2
            auto_disengage = 0
        else:  # auto
            wheel_mode = 2
            auto_disengage = max(1, min(35, threshold))

        torque_pct = max(1, min(100, torque))

        params = bytearray(16)
        params[0] = wheel_mode
        params[1] = auto_disengage
        params[2] = torque_pct

        res = hidpp_call(fd, feat_idx, 0x02, bytes(params))
        return res is not None
    finally:
        try:
            os.close(fd)
        except OSError:
            pass


# ----------------------------------------------------------------------
# TOML Minimal Parser & Serializer
# ----------------------------------------------------------------------

def parse_toml(text: str) -> dict:
    result = {}
    current_section = result
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            sec_name = line[1:-1].strip()
            parts = [p.strip().strip('"').strip("'") for p in sec_name.split(".")]
            curr = result
            for p in parts:
                if p not in curr:
                    curr[p] = {}
                curr = curr[p]
            current_section = curr
            continue
        if "=" in line:
            key, val = line.split("=", 1)
            key = key.strip().strip('"').strip("'")
            val = val.strip()
            if val.startswith('"') and val.endswith('"'):
                val = val[1:-1]
            elif val.startswith("'") and val.endswith("'"):
                val = val[1:-1]
            elif val.lower() == "true":
                val = True
            elif val.lower() == "false":
                val = False
            elif val.isdigit() or (val.startswith("-") and val[1:].isdigit()):
                val = int(val)
            elif re.match(r"^-?\d+\.\d+$", val):
                val = float(val)
            elif val.startswith("[") and val.endswith("]"):
                inner = val[1:-1].strip()
                if inner:
                    items = [x.strip() for x in inner.split(",")]
                    parsed_items = []
                    for item in items:
                        if item.isdigit():
                            parsed_items.append(int(item))
                        elif item.startswith('"') and item.endswith('"'):
                            parsed_items.append(item[1:-1])
                        else:
                            parsed_items.append(item)
                    val = parsed_items
                else:
                    val = []
            current_section[key] = val
    return result


def serialize_toml(data: dict, prefix: str = "") -> str:
    lines = []
    sections = {}
    for k, v in data.items():
        if isinstance(v, dict):
            sections[k] = v
        else:
            if isinstance(v, bool):
                val_str = "true" if v else "false"
            elif isinstance(v, (int, float)):
                val_str = str(v)
            elif isinstance(v, list):
                val_str = json.dumps(v)
            else:
                val_str = f'"{v}"'
            lines.append(f"{k} = {val_str}")

    for k, v in sections.items():
        sec_name = f"{prefix}.{k}" if prefix else k
        if lines and lines[-1] != "":
            lines.append("")
        lines.append(f"[{sec_name}]")
        sub_str = serialize_toml(v, sec_name)
        if sub_str:
            lines.append(sub_str)
    return "\n".join(lines)


def load_logix_config() -> dict:
    cfg_path = get_logix_config_path()
    if not cfg_path.exists():
        return {}
    try:
        return parse_toml(cfg_path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def save_logix_config(data: dict) -> None:
    cfg_path = get_logix_config_path()
    cfg_path.parent.mkdir(parents=True, exist_ok=True)
    txt = serialize_toml(data)
    cfg_path.write_text(txt + "\n", encoding="utf-8")


# ----------------------------------------------------------------------
# System Actions & Dispatch Engine for Omarchy 4.0 / Hyprland
# ----------------------------------------------------------------------

def switch_workspace(direction: str) -> None:
    def _run():
        try:
            cur = json.loads(subprocess.check_output(["hyprctl", "cursorpos", "-j"]))
            cx, cy = cur.get("x"), cur.get("y")
        except Exception:
            cx, cy = None, None

        subprocess.run(["hyprctl", "eval", f'hl.dispatch(hl.dsp.focus({{ workspace = "{direction}" }}))'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if cx is not None and cy is not None:
            time.sleep(0.03)
            subprocess.run(["hyprctl", "eval", f'hl.dispatch(hl.dsp.cursor.move({{ x = {cx}, y = {cy} }}))'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    import threading
    threading.Thread(target=_run, daemon=True).start()


def dispatch_action(action_id: str) -> None:
    if not action_id or action_id == "None":
        return

    if action_id == "ShowActionRing":
        subprocess.Popen(["omarchy-shell", "io.logix.omarchy", "showActionRing"])
    elif action_id in ("ToggleOverview", "Overview", "MissionControl"):
        subprocess.Popen(["omarchy-shell", "overview", "toggle"])
    elif action_id in ("WorkspaceNext", "NextWorkspace"):
        switch_workspace("e+1")
    elif action_id in ("WorkspacePrev", "PrevWorkspace"):
        switch_workspace("e-1")
    elif action_id in ("ToggleScratchpad", "Scratchpad", "ToggleSpecialWorkspace", "SpecialWorkspace"):
        run_hyprctl_eval("hl.dsp.workspace.toggle_special()")
    elif action_id in ("ToggleMaximize", "MaximizeWindow", "Fullscreen"):
        run_hyprctl_eval("hl.dsp.window.fullscreen()")
    elif action_id in ("CloseWindow",):
        run_hyprctl_eval("hl.dsp.window.close()")
    elif action_id in ("FocusNextWindow", "TileRight"):
        run_hyprctl_eval('hl.dsp.focus({ direction = "r" })')
    elif action_id in ("FocusPrevWindow", "TileLeft"):
        run_hyprctl_eval('hl.dsp.focus({ direction = "l" })')
    elif action_id in ("FocusUpWindow", "TileUp"):
        run_hyprctl_eval("hl.dsp.window.fullscreen()")
    elif action_id in ("FocusDownWindow", "TileDown"):
        subprocess.Popen(["omarchy-shell", "overview", "toggle"])
    elif action_id in ("VolumeUp",):
        subprocess.Popen(["omarchy-audio-output-volume", "raise"])
    elif action_id in ("VolumeDown",):
        subprocess.Popen(["omarchy-audio-output-volume", "lower"])
    elif action_id in ("VolumeMute", "Mute"):
        subprocess.Popen(["omarchy-audio-output-volume", "mute-toggle"])
    elif action_id in ("MediaPlayPause", "PlayPause"):
        subprocess.Popen(["omarchy-shell", "media", "playPause"])
    elif action_id in ("MediaNext", "NextTrack"):
        subprocess.Popen(["omarchy-shell", "media", "next"])
    elif action_id in ("MediaPrev", "PrevTrack"):
        subprocess.Popen(["omarchy-shell", "media", "previous"])
    elif action_id in ("Screenshot",):
        subprocess.Popen(["omarchy-screenshot"])
    elif action_id in ("Launcher",):
        subprocess.Popen(["omarchy-menu"])
    elif action_id.startswith("Tile"):
        direction = action_id.replace("Tile", "").lower()
        if direction == "up":
            run_hyprctl_eval("hl.dsp.window.fullscreen()")
        elif direction == "down":
            subprocess.Popen(["omarchy-shell", "overview", "toggle"])
        elif direction == "left":
            run_hyprctl_eval('hl.dsp.focus({ direction = "l" })')
        elif direction == "right":
            run_hyprctl_eval('hl.dsp.focus({ direction = "r" })')


# ----------------------------------------------------------------------
# Hardware Scanning & Sysfs Battery Discovery
# ----------------------------------------------------------------------

def get_battery_sysfs(name_hint: str) -> Optional[dict]:
    pwr_dir = Path("/sys/class/power_supply")
    if not pwr_dir.exists():
        return None

    for dev_dir in pwr_dir.iterdir():
        type_file = dev_dir / "type"
        if not type_file.exists():
            continue
        dev_type = type_file.read_text(encoding="utf-8").strip().lower()
        if dev_type != "battery":
            continue

        cap_file = dev_dir / "capacity"
        status_file = dev_dir / "status"
        model_file = dev_dir / "model_name"

        model = model_file.read_text(encoding="utf-8").strip() if model_file.exists() else dev_dir.name
        if name_hint.lower() in model.lower() or any(w in model.lower() for w in ["mouse", "logitech", "mx"]):
            if cap_file.exists():
                try:
                    level = int(cap_file.read_text(encoding="utf-8").strip())
                    status = status_file.read_text(encoding="utf-8").strip().lower() if status_file.exists() else "discharging"
                    return {"level": level, "status": status, "voltage": None, "text": f"{level}%"}
                except Exception:
                    pass
    return None


def scan_hidraw() -> Tuple[List[dict], List[dict]]:
    devices = []
    adapters = []
    hid_class = Path("/sys/class/hidraw")
    if not hid_class.exists():
        return devices, adapters

    seen_serials = set()

    for item in sorted(hid_class.iterdir()):
        dev_name = item.name
        hidraw_path = f"/dev/{dev_name}"
        uevent_file = item / "device" / "uevent"
        if not uevent_file.exists():
            continue

        uevent = uevent_file.read_text(encoding="utf-8")
        hid_name = ""
        hid_id = ""
        for line in uevent.splitlines():
            if line.startswith("HID_NAME="):
                hid_name = line.split("=", 1)[1].strip()
            elif line.startswith("HID_ID="):
                hid_id = line.split("=", 1)[1].strip()

        if not any(k in hid_name.lower() for k in ["logitech", "mx master", "mx anywhere", "mx keys", "craft", "ergo"]):
            continue

        kind = "mouse" if any(k in hid_name.lower() for k in ["master", "anywhere", "mouse", "ergo"]) else "keyboard"

        serial = ""
        uniq_file = item / "device" / "uniq"
        if uniq_file.exists():
            serial = uniq_file.read_text(encoding="utf-8").strip()

        conn = "bluetooth" if ":" in serial or len(serial) == 17 else "usb"

        parts = hid_id.split(":")
        product_id = parts[2] if len(parts) >= 3 else "B042"

        dev_id = serial if serial else f"{conn}-{product_id}-{dev_name}"
        if dev_id in seen_serials:
            continue
        seen_serials.add(dev_id)

        clean_name = hid_name.replace("Logitech", "").strip()
        if not clean_name:
            clean_name = "MX Master 4"

        battery = get_battery_sysfs(clean_name) or {"level": 90, "status": "discharging", "voltage": None, "text": "90%"}

        has_action_ring = kind == "mouse"
        has_smartshift = kind == "mouse"
        has_hires = kind == "mouse"

        is_rw = os.access(hidraw_path, os.R_OK | os.W_OK)

        devices.append({
            "id": dev_id,
            "name": clean_name,
            "codename": clean_name,
            "kind": kind,
            "online": True,
            "path": hidraw_path,
            "productId": product_id,
            "serial": serial or dev_id,
            "unitId": dev_id,
            "protocol": "HID++ 2.0 / LogiX",
            "connection": conn,
            "accessible": is_rw,
            "battery": battery,
            "capabilities": {
                "action_ring": has_action_ring,
                "gestures": True,
                "smartshift": has_smartshift,
                "hires_scroll": has_hires,
                "thumbwheel": has_action_ring,
                "backlight": kind == "keyboard",
                "fn_swap": kind == "keyboard",
            }
        })

    return devices, adapters


def default_device_config(name: str, kind: str) -> dict:
    if kind == "keyboard":
        return {
            "keyboard": {"fn_swap": False, "backlight_level": 50, "smart_backlight": True, "os_layout": "auto"}
        }

    slots = {}
    for slot in ACTION_RING_SLOTS:
        slots[slot["id"]] = {"action": slot["defaultAction"], "label": slot["label"]}

    gestures = {}
    for g in GESTURE_DIRECTIONS:
        gestures[g["id"]] = {"action": g["defaultAction"], "label": g["label"]}

    buttons = {}
    for btn in HARDWARE_BUTTONS:
        buttons[btn["id"]] = {"action": btn["defaultAction"]}

    return {
        "dpi": 1000,
        "dpi_preset": [800, 1000, 1600, 2400, 4000],
        "gesture_distance": 15,
        "smartshift": {"mode": "auto", "threshold": 10, "torque": 75},
        "scroll": {"invert_y": False, "invert_thumb": False, "hires": True},
        "action_ring": {"enabled": True, "haptics": True, "slots": slots},
        "gestures": gestures,
        "buttons": buttons,
        "keyboard": {},
    }


def find_matching_config(cfg_devices: dict, dev: dict) -> Tuple[Optional[str], dict]:
    for k in [dev.get("id"), dev.get("serial"), dev.get("name")]:
        if k and k in cfg_devices:
            return k, cfg_devices[k]

    dname = dev.get("name", "").lower()
    for ck, cv in cfg_devices.items():
        if ck.lower() in dname or dname in ck.lower() or "master" in ck.lower():
            return ck, cv

    if len(cfg_devices) == 1:
        single_k = list(cfg_devices.keys())[0]
        return single_k, cfg_devices[single_k]

    return None, {}


def action_label(act_id: str) -> str:
    labels = {
        "ToggleMaximize": "Maximize Window",
        "MaximizeWindow": "Maximize Window",
        "Fullscreen": "Maximize Window",
        "ToggleOverview": "Overview / Mission Control",
        "Overview": "Overview / Mission Control",
        "MissionControl": "Overview / Mission Control",
        "CloseWindow": "Close Window",
        "WorkspaceNext": "Next Workspace",
        "NextWorkspace": "Next Workspace",
        "WorkspacePrev": "Previous Workspace",
        "PrevWorkspace": "Previous Workspace",
        "ToggleScratchpad": "Toggle Scratchpad",
        "Scratchpad": "Toggle Scratchpad",
        "ToggleSpecialWorkspace": "Toggle Scratchpad",
        "SpecialWorkspace": "Toggle Scratchpad",
        "FocusNextWindow": "Tile Right",
        "TileRight": "Tile Right",
        "FocusPrevWindow": "Tile Left",
        "TileLeft": "Tile Left",
        "FocusUpWindow": "Tile Up",
        "TileUp": "Tile Up",
        "FocusDownWindow": "Tile Down",
        "TileDown": "Tile Down",
        "VolumeUp": "Volume Up",
        "VolumeDown": "Volume Down",
        "VolumeMute": "Mute / Unmute",
        "MediaPlayPause": "Play / Pause Media",
        "MediaNext": "Next Track",
        "MediaPrev": "Previous Track",
        "Screenshot": "Capture Screenshot",
        "Launcher": "App Launcher / Search",
        "ShowActionRing": "Show Smart Ring",
        "MiddleClick": "Middle Mouse Click",
        "NavigateBack": "Back Button",
        "NavigateForward": "Forward Button",
        "ToggleSmartShift": "SmartShift Mode",
        "ToggleDpi": "Cycle DPI Preset",
    }
    return labels.get(act_id, act_id or "Do Nothing")


def get_full_status() -> dict:
    devices, adapters = scan_hidraw()
    config = load_logix_config()

    cfg_devices = config.get("devices", {})
    for dev in devices:
        matched_key, dev_cfg = find_matching_config(cfg_devices, dev)
        default_cfg = default_device_config(dev.get("name", ""), dev.get("kind", ""))

        # Normalize buttons map
        buttons_map = {}
        raw_buttons = dev_cfg.get("buttons", {}) if isinstance(dev_cfg, dict) else {}
        for btn in HARDWARE_BUTTONS:
            bid = btn["id"]
            if bid in raw_buttons:
                val = raw_buttons[bid]
                act = val if isinstance(val, str) else (val.get("action", btn["defaultAction"]) if isinstance(val, dict) else btn["defaultAction"])
                buttons_map[bid] = {"action": act, "label": action_label(act)}
            else:
                buttons_map[bid] = {"action": btn["defaultAction"], "label": action_label(btn["defaultAction"])}

        # Normalize action ring slots
        ar_cfg = dev_cfg.get("action_ring", default_cfg["action_ring"]) if isinstance(dev_cfg, dict) else default_cfg["action_ring"]
        slots_map = {}
        raw_slots = ar_cfg.get("slots", {}) if isinstance(ar_cfg, dict) else {}
        for slot in ACTION_RING_SLOTS:
            sid = slot["id"]
            val = raw_slots.get(sid)
            if val is None:
                for alias_k, canonical in SLOT_ALIASES.items():
                    if canonical == sid and alias_k in raw_slots:
                        val = raw_slots[alias_k]
                        break
            if val is not None:
                act = val if isinstance(val, str) else (val.get("action", slot["defaultAction"]) if isinstance(val, dict) else slot["defaultAction"])
                lbl = val.get("label", "") if isinstance(val, dict) else str(val)
                if not lbl or lbl == sid or lbl == slot["label"] or "slot" in lbl.lower():
                    lbl = action_label(act)
                slots_map[sid] = {"action": act, "label": lbl}
            else:
                slots_map[sid] = {"action": slot["defaultAction"], "label": action_label(slot["defaultAction"])}
        ar_cfg["slots"] = slots_map

        # Normalize gestures map
        g_cfg = dev_cfg.get("gestures", default_cfg["gestures"]) if isinstance(dev_cfg, dict) else default_cfg["gestures"]
        gestures_map = {}
        raw_gestures = g_cfg if isinstance(g_cfg, dict) else {}
        for g in GESTURE_DIRECTIONS:
            gid = g["id"]
            if gid in raw_gestures:
                val = raw_gestures[gid]
                act = val if isinstance(val, str) else (val.get("action", g["defaultAction"]) if isinstance(val, dict) else g["defaultAction"])
                lbl = val.get("label", "") if isinstance(val, dict) else str(val)
                if not lbl or lbl == gid or lbl == g["label"]:
                    lbl = action_label(act)
                gestures_map[gid] = {"action": act, "label": lbl}
            else:
                gestures_map[gid] = {"action": g["defaultAction"], "label": action_label(g["defaultAction"])}

        dev["config"] = dev_cfg
        dev["dpi"] = dev_cfg.get("dpi", 1000) if isinstance(dev_cfg, dict) else 1000
        dev["gesture_distance"] = dev_cfg.get("gesture_distance", 15) if isinstance(dev_cfg, dict) else 15
        dev["smartshift"] = dev_cfg.get("smartshift", {"mode": "auto", "threshold": 10, "torque": 75}) if isinstance(dev_cfg, dict) else {"mode": "auto", "threshold": 10, "torque": 75}
        dev["scroll"] = dev_cfg.get("scroll", {"invert_y": False, "invert_thumb": False, "hires": True}) if isinstance(dev_cfg, dict) else {"invert_y": False, "invert_thumb": False, "hires": True}
        dev["action_ring"] = ar_cfg
        dev["gestures"] = gestures_map
        dev["buttons"] = buttons_map
        dev["keyboard"] = dev_cfg.get("keyboard", {}) if isinstance(dev_cfg, dict) else {}

    all_accessible = all(d.get("accessible", True) for d in devices) if devices else True

    status = {
        "ok": True,
        "driver": "LogiX Engine",
        "accessible": all_accessible,
        "ts": int(time.time()),
        "devices": devices,
        "adapters": adapters,
        "message": "" if devices else "No Logitech devices connected",
    }
    return status


def apply_device_update(device_id: str, updates: dict) -> dict:
    config = load_logix_config()
    if "devices" not in config:
        config["devices"] = {}

    devices, _ = scan_hidraw()
    target_dev = None
    for dev in devices:
        if dev.get("id") == device_id or dev.get("name") in device_id or device_id in dev.get("name", ""):
            target_dev = dev
            break
    if not target_dev and devices:
        target_dev = devices[0]

    matched_key = None
    if target_dev:
        matched_key, _ = find_matching_config(config["devices"], target_dev)

    if not matched_key:
        matched_key = device_id or (target_dev["id"] if target_dev else "MX Master 4")

    if matched_key not in config["devices"]:
        config["devices"][matched_key] = {}

    target = config["devices"][matched_key]
    for k, v in updates.items():
        if isinstance(v, dict) and isinstance(target.get(k), dict):
            for sub_k, sub_v in v.items():
                if isinstance(sub_v, dict) and isinstance(target[k].get(sub_k), dict):
                    target[k][sub_k].update(sub_v)
                else:
                    target[k][sub_k] = sub_v
        else:
            target[k] = v

    save_logix_config(config)

    # Apply directly to hardware
    if target_dev and target_dev.get("path"):
        hpath = target_dev["path"]
        if "dpi" in updates:
            apply_hardware_dpi(hpath, int(updates["dpi"]))
        if "smartshift" in updates:
            ss = updates["smartshift"]
            mode = ss.get("mode", "auto") if isinstance(ss, dict) else str(ss)
            thresh = int(ss.get("threshold", 10)) if isinstance(ss, dict) else 10
            torque = int(ss.get("torque", 75)) if isinstance(ss, dict) else 75
            apply_hardware_smartshift(hpath, mode, thresh, torque)

    return get_full_status()


def process_command(cmd_file: Path) -> None:
    try:
        data = json.loads(cmd_file.read_text(encoding="utf-8"))
    except Exception:
        try:
            cmd_file.unlink()
        except OSError:
            pass
        return

    cmd_type = data.get("type", "")
    device_id = data.get("deviceId", "")
    payload = data.get("payload", {})

    if cmd_type == "set_dpi":
        dpi_val = int(payload.get("dpi", 1000))
        apply_device_update(device_id, {"dpi": dpi_val})
    elif cmd_type == "set_gesture_distance":
        dist_val = int(payload.get("distance", 15))
        apply_device_update(device_id, {"gesture_distance": dist_val})
    elif cmd_type == "set_smartshift":
        apply_device_update(device_id, {"smartshift": payload})
    elif cmd_type == "set_scroll":
        apply_device_update(device_id, {"scroll": payload})
    elif cmd_type == "set_action_ring":
        apply_device_update(device_id, {"action_ring": payload})
    elif cmd_type == "set_action_ring_slot":
        slot = payload.get("slot")
        action = payload.get("action")
        label = payload.get("label", action)
        if slot:
            slot = SLOT_ALIASES.get(slot, slot)
            cfg = load_logix_config()
            cfg_devices = cfg.get("devices", {})
            target_key = device_id
            for k in cfg_devices.keys():
                if k in device_id or device_id in k:
                    target_key = k
                    break
            dev_cfg = cfg_devices.get(target_key, {})
            ar = dev_cfg.get("action_ring", {})
            slots = ar.get("slots", {})
            slots[slot] = {"action": action, "label": label}
            ar["slots"] = slots
            apply_device_update(target_key, {"action_ring": ar})
    elif cmd_type == "set_gesture":
        direction = payload.get("direction")
        action = payload.get("action")
        label = payload.get("label", action)
        if direction:
            cfg = load_logix_config()
            cfg_devices = cfg.get("devices", {})
            target_key = device_id
            for k in cfg_devices.keys():
                if k in device_id or device_id in k:
                    target_key = k
                    break
            dev_cfg = cfg_devices.get(target_key, {})
            gmap = dev_cfg.get("gestures", {})
            if not isinstance(gmap, dict):
                gmap = {}
            gmap[direction] = {"action": action, "label": label}
            apply_device_update(target_key, {"gestures": gmap})
    elif cmd_type == "set_button":
        btn = payload.get("button")
        action = payload.get("action")
        if btn and action:
            cfg = load_logix_config()
            cfg_devices = cfg.get("devices", {})
            target_key = device_id
            for k in cfg_devices.keys():
                if k in device_id or device_id in k:
                    target_key = k
                    break
            dev_cfg = cfg_devices.get(target_key, {})
            btns = dev_cfg.get("buttons", {})
            btns[btn] = {"action": action}
            apply_device_update(target_key, {"buttons": btns})
    elif cmd_type == "set_keyboard":
        apply_device_update(device_id, {"keyboard": payload})
    elif cmd_type == "dispatch":
        action_id = payload.get("action", "")
        dispatch_action(action_id)

    try:
        cmd_file.unlink()
    except OSError:
        pass


def write_status_file(status: dict) -> None:
    rdir = get_runtime_dir()
    status_path = rdir / "status.json"
    tmp_status = rdir / f"status-{os.getpid()}-{int(time.time() * 1000)}.tmp"
    try:
        tmp_status.write_text(json.dumps(status, ensure_ascii=False, indent=2), encoding="utf-8")
        tmp_status.replace(status_path)
    except Exception:
        pass


def is_daemon_running() -> bool:
    rdir = get_runtime_dir()
    lock_path = rdir / "logixctl.lock"
    if not lock_path.exists():
        return False
    try:
        fd = os.open(str(lock_path), os.O_RDWR | os.O_CREAT, 0o644)
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)
        return False
    except (OSError, IOError):
        return True


def get_active_mouse_path() -> Optional[str]:
    devices, _ = scan_hidraw()
    for d in devices:
        if d.get("kind") == "mouse" and d.get("path") and d.get("accessible"):
            return d["path"]
    for d in devices:
        if d.get("path") and d.get("accessible"):
            return d["path"]
    return None


def serve_daemon() -> None:
    rdir = get_runtime_dir()
    lock_path = rdir / "logixctl.lock"

    try:
        lock_fd = os.open(str(lock_path), os.O_RDWR | os.O_CREAT, 0o644)
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except (OSError, IOError):
        sys.exit(0)

    # Initialize device hardware connection and button diversions
    hid_fd = None
    reprog_idx = None
    dev_path = None

    def connect_device():
        nonlocal hid_fd, reprog_idx, dev_path
        dev_path = get_active_mouse_path()
        if dev_path:
            hid_fd = open_hidraw(dev_path)
            if hid_fd is not None:
                reprog_idx = get_feature_index(hid_fd, 0x1B04)
                if reprog_idx is not None:
                    for cid in [0x01A0, 0x00C3, 0x00C4]:
                        set_button_diversion(hid_fd, cid, divert=True, raw_xy=True, feat_idx=reprog_idx)
                        time.sleep(0.02)

    connect_device()

    # Gesture state
    active_cid: Optional[int] = None
    gesture_start_pos: Optional[Tuple[Optional[int], Optional[int]]] = None
    acc_dx = 0
    acc_dy = 0
    press_time = 0.0
    skip_first_raw = True
    last_reconnect = time.time()

    try:
        status = get_full_status()
        write_status_file(status)

        while True:
            # Check for command spools
            cmd_files = sorted(rdir.glob("cmd-*.json"))
            for cf in cmd_files:
                process_command(cf)
                status = get_full_status()
                write_status_file(status)

            # Reconnection logic if device was closed / not opened
            now = time.time()
            if hid_fd is None and (now - last_reconnect >= 1.5):
                last_reconnect = now
                connect_device()

            # Read live hardware HID++ reports from mouse
            if hid_fd is not None:
                r, _, _ = select.select([hid_fd], [], [], 0.05)
                if hid_fd in r:
                    try:
                        packet = os.read(hid_fd, 64)
                        if not packet:
                            try:
                                os.close(hid_fd)
                            except Exception:
                                pass
                            hid_fd = None
                            reprog_idx = None
                            time.sleep(0.05)
                            continue

                        if len(packet) >= 4 and packet[0] == 0x11:
                            feat = packet[2]
                            func = (packet[3] >> 4) & 0x0F

                            # ReprogControlsV4 event
                            if reprog_idx is not None and feat == reprog_idx:
                                if func == 0:
                                    # Diverted button press / release
                                    cid = struct.unpack(">H", packet[4:6])[0]
                                    if cid != 0:
                                        # Button DOWN
                                        active_cid = cid
                                        acc_dx = 0
                                        acc_dy = 0
                                        skip_first_raw = True
                                        press_time = time.time()
                                    elif active_cid is not None:
                                        # Button UP — process action or gesture
                                        btn_name = CID_TO_BUTTON.get(active_cid, "HapticPanel")
                                        cfg = load_logix_config()
                                        cfg_devices = cfg.get("devices", {})
                                        dev_cfg = {}
                                        if cfg_devices:
                                            for k, v in cfg_devices.items():
                                                if isinstance(v, dict):
                                                    dev_cfg = v
                                                    break
                                        buttons_map = dev_cfg.get("buttons", {}) if isinstance(dev_cfg, dict) else {}
                                        g_thresh = int(dev_cfg.get("gesture_distance", 15)) if isinstance(dev_cfg, dict) else 15

                                        dist = math.sqrt(acc_dx * acc_dx + acc_dy * acc_dy)

                                        if dist < g_thresh:
                                            # Single Click -> ShowActionRing / Toggle
                                            act = buttons_map.get(btn_name, "ShowActionRing" if btn_name in ("HapticPanel", "GestureButton") else "None")
                                            if isinstance(act, dict):
                                                act = act.get("action", "None")
                                            dispatch_action(act)
                                        else:
                                            # Swipe Gesture / Quick flick direction
                                            angle_deg = math.degrees(math.atan2(acc_dy, acc_dx)) % 360
                                            if 45 <= angle_deg < 135:
                                                gdir = "Down"
                                            elif 135 <= angle_deg < 225:
                                                gdir = "Left"
                                            elif 225 <= angle_deg < 315:
                                                gdir = "Up"
                                            else:
                                                gdir = "Right"

                                            gmap = dev_cfg.get("gestures", {}) if isinstance(dev_cfg, dict) else {}
                                            gact = gmap.get(gdir, f"Tile{gdir}")
                                            if isinstance(gact, dict):
                                                gact = gact.get("action", f"Tile{gdir}")
                                            dispatch_action(gact)

                                        active_cid = None
                                elif func == 1 and active_cid is not None:
                                    # Raw XY accumulation while button is held
                                    if skip_first_raw:
                                        skip_first_raw = False
                                    else:
                                        dx = struct.unpack(">h", packet[4:6])[0]
                                        dy = struct.unpack(">h", packet[6:8])[0]
                                        acc_dx += dx
                                        acc_dy += dy
                    except OSError:
                        try:
                            os.close(hid_fd)
                        except Exception:
                            pass
                        hid_fd = None
                        reprog_idx = None
            else:
                time.sleep(0.05)

    finally:
        if hid_fd is not None:
            try:
                os.close(hid_fd)
            except OSError:
                pass


# ----------------------------------------------------------------------
# CLI Entry Point
# ----------------------------------------------------------------------

def emit(data: Any) -> None:
    print(json.dumps(data, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser(description="LogiX Control CLI")
    sub = parser.add_subparsers(dest="subcommand")

    sub.add_parser("discover", help="Discover devices and dump status")
    sub.add_parser("status", help="Get full device and configuration status")
    sub.add_parser("serve", help="Run background daemon")
    sub.add_parser("runtime-dir", help="Print runtime directory")
    sub.add_parser("cleanup", help="Clean up runtime files")
    sub.add_parser("fix-permissions", help="Install udev rule and grant user permissions via pkexec")

    write_cmd = sub.add_parser("write-cmd", help="Write a command to the queue")
    write_cmd.add_argument("type", help="Command type")
    write_cmd.add_argument("device_id", help="Device ID")
    write_cmd.add_argument("payload", nargs="?", default="{}", help="Payload JSON")

    args = parser.parse_args()

    if args.subcommand in ("discover", "status", None):
        status = get_full_status()
        emit(status)
    elif args.subcommand == "runtime-dir":
        print(str(get_runtime_dir()))
    elif args.subcommand == "cleanup":
        rdir = get_runtime_dir()
        for f in rdir.glob("cmd-*.json"):
            try:
                f.unlink()
            except OSError:
                pass
        try:
            (rdir / "logixctl.lock").unlink()
        except OSError:
            pass
        emit({"ok": True})
    elif args.subcommand == "fix-permissions":
        rule = 'KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="046d", MODE="0666", TAG+="uaccess"\nKERNEL=="hidraw*", SUBSYSTEM=="hidraw", KERNELS=="*046D*", MODE="0666", TAG+="uaccess"\n'
        script = f"printf '{rule}' > /etc/udev/rules.d/99-logix-hidpp.rules && udevadm control --reload-rules && udevadm trigger --subsystem-match=hidraw"
        try:
            res = subprocess.run(["pkexec", "sh", "-c", script])
            emit({"ok": res.returncode == 0})
        except Exception as e:
            emit({"ok": False, "error": str(e)})
    elif args.subcommand == "write-cmd":
        rdir = get_runtime_dir()
        try:
            payload = json.loads(args.payload)
        except Exception:
            payload = {}
        cmd_data = {
            "type": args.type,
            "deviceId": args.device_id,
            "payload": payload,
            "ts": time.time(),
        }
        cmd_file = rdir / f"cmd-{int(time.time() * 1000)}-{os.getpid()}.json"
        cmd_file.write_text(json.dumps(cmd_data, ensure_ascii=False), encoding="utf-8")
        if not is_daemon_running():
            process_command(cmd_file)
            status = get_full_status()
            write_status_file(status)
        emit({"ok": True, "file": str(cmd_file)})
    elif args.subcommand == "serve":
        serve_daemon()


if __name__ == "__main__":
    main()
