#!/usr/bin/env python3
# openlogictl.py — OpenLogi Controller & Hardware Driver for Omarchy
# Direct HID++ 2.0 Hardware Event Interceptor, Smart Ring, Gestures, SmartShift, & DPI
# MIT License

import argparse
import fcntl
import html
import json
import math
import os
import re
import select
import struct
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

HEARTBEAT_SEC = 60

ACTION_RING_SLOTS = [
    {"id": "Top", "label": "Top", "angle": 0, "glyph": "↑", "defaultAction": "MissionControl"},
    {"id": "TopRight", "label": "Top Right", "angle": 45, "glyph": "↗", "defaultAction": "NextWorkspace"},
    {"id": "Right", "label": "Right", "angle": 90, "glyph": "→", "defaultAction": "VolumeUp"},
    {"id": "BottomRight", "label": "Bottom Right", "angle": 135, "glyph": "↘", "defaultAction": "PlayPause"},
    {"id": "Bottom", "label": "Bottom", "angle": 180, "glyph": "↓", "defaultAction": "ShowDesktop"},
    {"id": "BottomLeft", "label": "Bottom Left", "angle": 225, "glyph": "↙", "defaultAction": "PrevWorkspace"},
    {"id": "Left", "label": "Left", "angle": 270, "glyph": "←", "defaultAction": "VolumeDown"},
    {"id": "TopLeft", "label": "Top Left", "angle": 315, "glyph": "↖", "defaultAction": "Mute"},
]

GESTURE_DIRECTIONS = [
    {"id": "Up", "label": "Swipe Up", "glyph": "↑", "defaultAction": "TileUp"},
    {"id": "Down", "label": "Swipe Down", "glyph": "↓", "defaultAction": "TileDown"},
    {"id": "Left", "label": "Swipe Left", "glyph": "←", "defaultAction": "TileLeft"},
    {"id": "Right", "label": "Swipe Right", "glyph": "→", "defaultAction": "TileRight"},
    {"id": "Click", "label": "Single Click", "glyph": "◎", "defaultAction": "ShowActionRing"},
]

HARDWARE_BUTTONS = [
    {"id": "HapticPanel", "label": "Smart Ring / Thumb Rest", "cid": 0x01A0, "defaultAction": "ShowActionRing"},
    {"id": "GestureButton", "label": "Thumb Gesture Button", "cid": 0x00C3, "defaultAction": "Gestures"},
    {"id": "DpiToggle", "label": "Top Mode Button", "cid": 0x00C4, "defaultAction": "DpiCycle"},
    {"id": "MiddleClick", "label": "Scroll Wheel Click", "cid": 0x0052, "defaultAction": "MiddleClick"},
    {"id": "Back", "label": "Side Back Button", "cid": 0x0053, "defaultAction": "Back"},
    {"id": "Forward", "label": "Side Forward Button", "cid": 0x0056, "defaultAction": "Forward"},
    {"id": "Thumbwheel", "label": "Horizontal Thumb Wheel", "cid": 0x00D7, "defaultAction": "HorizontalScroll"},
]

CID_TO_BUTTON = {
    0x01A0: "HapticPanel",
    0x00C3: "GestureButton",
    0x00C4: "DpiToggle",
    0x0052: "MiddleClick",
    0x0053: "Back",
    0x0056: "Forward",
    0x00D7: "Thumbwheel",
}


def plain_hid_text(raw: str) -> str:
    if not raw:
        return ""
    return html.escape(str(raw))


def get_runtime_dir() -> Path:
    xdg_runtime = os.environ.get("XDG_RUNTIME_DIR")
    if xdg_runtime:
        base = Path(xdg_runtime)
    else:
        uid = os.getuid()
        base = Path(f"/run/user/{uid}")
    rdir = base / "omarchy-openlogi"
    rdir.mkdir(parents=True, exist_ok=True)
    return rdir


def get_openlogi_config_path() -> Path:
    xdg_config = os.environ.get("XDG_CONFIG_HOME")
    if xdg_config:
        base = Path(xdg_config)
    else:
        base = Path.home() / ".config"
    return base / "openlogi" / "config.toml"


def is_openlogi_installed() -> bool:
    import shutil
    return shutil.which("openlogi") is not None or shutil.which("openlogi-agent") is not None


def is_openlogi_agent_running() -> bool:
    xdg_config = os.environ.get("XDG_CONFIG_HOME")
    base = Path(xdg_config) if xdg_config else Path.home() / ".config"
    sock = base / "openlogi" / "agent.sock"
    return sock.exists()


# ----------------------------------------------------------------------
# TOML Parsing & Saving (Zero-dependency parser)
# ----------------------------------------------------------------------

def parse_simple_toml(content: str) -> dict:
    data: Dict[str, Any] = {}
    current_dict: Dict[str, Any] = data

    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue

        if line.startswith("[") and line.endswith("]"):
            sec_name = line[1:-1].strip()
            parts = []
            cur = ""
            in_q = False
            for c in sec_name:
                if c == '"':
                    in_q = not in_q
                elif c == '.' and not in_q:
                    parts.append(cur.strip(' "'))
                    cur = ""
                else:
                    cur += c
            if cur:
                parts.append(cur.strip(' "'))

            target = data
            for part in parts:
                if part not in target or not isinstance(target[part], dict):
                    target[part] = {}
                target = target[part]
            current_dict = target
            continue

        if "=" in line:
            key, val = line.split("=", 1)
            key = key.strip().strip('"')
            val = val.strip()

            if val.startswith('"') and val.endswith('"'):
                parsed_val: Any = val[1:-1]
            elif val.lower() == "true":
                parsed_val = True
            elif val.lower() == "false":
                parsed_val = False
            elif re.match(r"^-?\d+$", val):
                parsed_val = int(val)
            elif re.match(r"^-?\d+\.\d+$", val):
                parsed_val = float(val)
            elif val.startswith("[") and val.endswith("]"):
                inner = val[1:-1].strip()
                if not inner:
                    parsed_val = []
                else:
                    items = [x.strip().strip('"') for x in inner.split(",")]
                    parsed_val = []
                    for item in items:
                        if re.match(r"^-?\d+$", item):
                            parsed_val.append(int(item))
                        elif item.lower() == "true":
                            parsed_val.append(True)
                        elif item.lower() == "false":
                            parsed_val.append(False)
                        else:
                            parsed_val.append(item)
            elif val.startswith("{") and val.endswith("}"):
                inner = val[1:-1].strip()
                sub_dict = {}
                for pair in inner.split(","):
                    if "=" in pair:
                        sk, sv = pair.split("=", 1)
                        sk = sk.strip().strip('"')
                        sv = sv.strip().strip('"')
                        sub_dict[sk] = sv
                parsed_val = sub_dict
            else:
                parsed_val = val

            current_dict[key] = parsed_val

    return data


def format_simple_toml(data: dict) -> str:
    lines = []

    def write_section(prefix: str, d: dict):
        scalars = {}
        subsections = {}
        for k, v in d.items():
            if isinstance(v, dict):
                subsections[k] = v
            else:
                scalars[k] = v

        if prefix:
            lines.append(f"[{prefix}]")
        for k, v in scalars.items():
            if isinstance(v, bool):
                sval = "true" if v else "false"
            elif isinstance(v, (int, float)):
                sval = str(v)
            elif isinstance(v, list):
                sval = json.dumps(v)
            else:
                sval = f'"{v}"'
            lines.append(f'{k} = {sval}')
        if prefix and (scalars or not subsections):
            lines.append("")

        for k, v in subsections.items():
            sub_prefix = f'{prefix}."{k}"' if prefix else f'"{k}"'
            write_section(sub_prefix, v)

    write_section("", data)
    return "\n".join(lines).strip() + "\n"


def load_openlogi_config() -> dict:
    cfg_path = get_openlogi_config_path()
    if not cfg_path.exists():
        return {"devices": {}}
    try:
        content = cfg_path.read_text(encoding="utf-8")
        return parse_simple_toml(content)
    except Exception as e:
        print(f"Error loading OpenLogi config: {e}", file=sys.stderr)
        return {"devices": {}}


def save_openlogi_config(data: dict) -> None:
    cfg_path = get_openlogi_config_path()
    cfg_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        content = format_simple_toml(data)
        cfg_path.write_text(content, encoding="utf-8")
    except Exception as e:
        print(f"Error saving OpenLogi config: {e}", file=sys.stderr)


# ----------------------------------------------------------------------
# HID++ 2.0 Low-Level Hardware Communication
# ----------------------------------------------------------------------

def open_hidraw(path: str) -> Optional[int]:
    try:
        return os.open(path, os.O_RDWR | os.O_NONBLOCK)
    except Exception:
        return None


def hidpp_call(fd: int, feat_idx: int, func_idx: int, params: bytes = b"", dev_idx: int = 0xFF, timeout: float = 0.1) -> Optional[bytes]:
    req = bytearray(20)
    req[0] = 0x11
    req[1] = dev_idx
    req[2] = feat_idx
    req[3] = (func_idx & 0x0F) << 4
    for i, p in enumerate(params):
        req[4 + i] = p

    try:
        os.write(fd, req)
    except Exception:
        return None

    deadline = time.time() + timeout
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.02)
        if r:
            try:
                res = os.read(fd, 64)
                if len(res) >= 4 and res[0] == 0x11 and res[2] == feat_idx:
                    return res
            except Exception:
                break
    return None


def get_feature_index(fd: int, feat_id: int) -> Optional[int]:
    res = hidpp_call(fd, 0x00, 0x00, struct.pack(">H", feat_id))
    if res and len(res) >= 5 and res[4] != 0:
        return res[4]
    return None


def apply_hardware_smartshift(hidraw_path: str, mode_str: str, threshold: int = 12, torque: int = 50) -> bool:
    fd = open_hidraw(hidraw_path)
    if fd is None:
        return False
    try:
        # Check 0x2111 (SmartShiftWheelEnhanced on MX Master 3/3S/4)
        feat_idx = get_feature_index(fd, 0x2111)
        if feat_idx is not None:
            # Function 2: set_ratchet_control_mode([wheel_mode, auto_disengage, torque])
            # wheel_mode: 1 = Freespin, 2 = Ratchet
            if mode_str == "freewheel":
                params = bytes([1, 0, max(1, min(100, torque))])
            elif mode_str == "ratchet":
                params = bytes([2, 0, max(1, min(100, torque))])
            else: # auto
                params = bytes([2, max(1, min(255, threshold)), max(1, min(100, torque))])
            res = hidpp_call(fd, feat_idx, 0x02, params)
            return res is not None

        # Fallback to 0x2110
        feat_idx = get_feature_index(fd, 0x2110)
        if feat_idx is not None:
            mode_num = 1 if mode_str == "ratchet" else (2 if mode_str == "freewheel" else 3)
            params = bytes([mode_num, max(1, min(255, threshold)), max(1, min(100, torque))])
            res = hidpp_call(fd, feat_idx, 0x01, params)
            return res is not None
        return False
    finally:
        os.close(fd)


def apply_hardware_dpi(hidraw_path: str, dpi: int) -> bool:
    fd = open_hidraw(hidraw_path)
    if fd is None:
        return False
    try:
        feat_idx = get_feature_index(fd, 0x2201)
        if feat_idx is None:
            return False

        params = b"\x00" + struct.pack(">H", max(200, min(8000, dpi)))
        res = hidpp_call(fd, feat_idx, 0x02, params)
        return res is not None
    finally:
        os.close(fd)


def set_button_diversion(fd: int, cid: int, divert: bool = True, raw_xy: bool = True) -> bool:
    feat_idx = get_feature_index(fd, 0x1B04)
    if feat_idx is None:
        return False
    p = bytearray(16)
    p[0] = (cid >> 8) & 0xFF
    p[1] = cid & 0xFF
    if divert:
        p[2] = 0x33 if raw_xy else 0x03 # divert + raw_xy
    else:
        p[2] = 0x32 if raw_xy else 0x02 # clear divert
    res = hidpp_call(fd, feat_idx, 0x03, bytes(p))
    return res is not None


def dispatch_action(action_id: str) -> None:
    if not action_id or action_id == "None":
        return

    if action_id == "ShowActionRing":
        subprocess.Popen(["omarchy-shell", "io.openlogi.omarchy", "showActionRing"])
    elif action_id == "MissionControl":
        subprocess.Popen(["hyprctl", "dispatch", "overview:toggle"])
    elif action_id == "NextWorkspace":
        subprocess.Popen(["hyprctl", "dispatch", "workspace", "+1"])
    elif action_id == "PrevWorkspace":
        subprocess.Popen(["hyprctl", "dispatch", "workspace", "-1"])
    elif action_id == "MaximizeWindow":
        subprocess.Popen(["hyprctl", "dispatch", "fullscreen", "1"])
    elif action_id == "MinimizeWindow":
        subprocess.Popen(["hyprctl", "dispatch", "movetoworkspacesilent", "special:minimized"])
    elif action_id == "TileLeft":
        subprocess.Popen(["hyprctl", "dispatch", "movefocus", "l"])
    elif action_id == "TileRight":
        subprocess.Popen(["hyprctl", "dispatch", "movefocus", "r"])
    elif action_id == "TileUp":
        subprocess.Popen(["hyprctl", "dispatch", "movefocus", "u"])
    elif action_id == "TileDown":
        subprocess.Popen(["hyprctl", "dispatch", "movefocus", "d"])
    elif action_id == "CloseWindow":
        subprocess.Popen(["hyprctl", "dispatch", "killactive"])
    elif action_id == "ShowDesktop":
        subprocess.Popen(["hyprctl", "dispatch", "togglespecialworkspace"])
    elif action_id == "VolumeUp":
        subprocess.Popen(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%+"])
    elif action_id == "VolumeDown":
        subprocess.Popen(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%-"])
    elif action_id == "Mute":
        subprocess.Popen(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
    elif action_id == "PlayPause":
        subprocess.Popen(["playerctl", "play-pause"])
    elif action_id == "NextTrack":
        subprocess.Popen(["playerctl", "next"])
    elif action_id == "PrevTrack":
        subprocess.Popen(["playerctl", "previous"])
    elif action_id == "Launcher":
        subprocess.Popen(["omarchy-menu"])


# ----------------------------------------------------------------------
# Hardware Discovery (sysfs & HID++)
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
            "protocol": "HID++ 2.0 / OpenLogi",
            "connection": conn,
            "accessible": True,
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
        "smartshift": {"mode": "auto", "threshold": 12, "torque": 50},
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


def get_full_status() -> dict:
    devices, adapters = scan_hidraw()
    config = load_openlogi_config()
    openlogi_inst = is_openlogi_installed()
    openlogi_running = is_openlogi_agent_running()

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
                buttons_map[bid] = {"action": act}
            else:
                buttons_map[bid] = {"action": btn["defaultAction"]}

        # Normalize action ring slots
        ar_cfg = dev_cfg.get("action_ring", default_cfg["action_ring"]) if isinstance(dev_cfg, dict) else default_cfg["action_ring"]
        slots_map = {}
        raw_slots = ar_cfg.get("slots", {}) if isinstance(ar_cfg, dict) else {}
        for slot in ACTION_RING_SLOTS:
            sid = slot["id"]
            if sid in raw_slots:
                val = raw_slots[sid]
                act = val if isinstance(val, str) else (val.get("action", slot["defaultAction"]) if isinstance(val, dict) else slot["defaultAction"])
                lbl = val.get("label", act) if isinstance(val, dict) else act
                slots_map[sid] = {"action": act, "label": lbl}
            else:
                slots_map[sid] = {"action": slot["defaultAction"], "label": slot["label"]}
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
                lbl = val.get("label", act) if isinstance(val, dict) else act
                gestures_map[gid] = {"action": act, "label": lbl}
            else:
                gestures_map[gid] = {"action": g["defaultAction"], "label": g["label"]}

        dev["config"] = dev_cfg
        dev["dpi"] = dev_cfg.get("dpi", 1000) if isinstance(dev_cfg, dict) else 1000
        dev["smartshift"] = dev_cfg.get("smartshift", {"mode": "auto", "threshold": 12, "torque": 50}) if isinstance(dev_cfg, dict) else {"mode": "auto", "threshold": 12, "torque": 50}
        dev["scroll"] = dev_cfg.get("scroll", {"invert_y": False, "invert_thumb": False, "hires": True}) if isinstance(dev_cfg, dict) else {"invert_y": False, "invert_thumb": False, "hires": True}
        dev["action_ring"] = ar_cfg
        dev["gestures"] = gestures_map
        dev["buttons"] = buttons_map
        dev["keyboard"] = dev_cfg.get("keyboard", {}) if isinstance(dev_cfg, dict) else {}

    status = {
        "ok": True,
        "openlogiInstalled": openlogi_inst,
        "openlogiRunning": openlogi_running,
        "accessible": True,
        "ts": int(time.time()),
        "devices": devices,
        "adapters": adapters,
        "message": "" if devices else "No Logitech devices connected",
    }
    return status


def apply_device_update(device_id: str, updates: dict) -> dict:
    config = load_openlogi_config()
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
            target[k].update(v)
        else:
            target[k] = v

    save_openlogi_config(config)

    # Apply directly to hardware
    if target_dev and target_dev.get("path"):
        hpath = target_dev["path"]
        if "dpi" in updates:
            apply_hardware_dpi(hpath, int(updates["dpi"]))
        if "smartshift" in updates:
            ss = updates["smartshift"]
            mode = ss.get("mode", "auto") if isinstance(ss, dict) else str(ss)
            thresh = ss.get("threshold", 12) if isinstance(ss, dict) else 12
            apply_hardware_smartshift(hpath, mode, thresh)

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
            cfg = load_openlogi_config()
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
            cfg = load_openlogi_config()
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
            cfg = load_openlogi_config()
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


def serve_daemon() -> None:
    rdir = get_runtime_dir()
    lock_path = rdir / "openlogictl.lock"

    try:
        lock_fd = open(lock_path, "w")
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except (OSError, IOError):
        sys.exit(0)

    # Initialize device hardware connection and button diversions
    hid_fd = None
    reprog_idx = None
    dev_path = None

    devices, _ = scan_hidraw()
    if devices:
        dev_path = devices[0].get("path")
        if dev_path:
            hid_fd = open_hidraw(dev_path)
            if hid_fd is not None:
                reprog_idx = get_feature_index(hid_fd, 0x1B04)
                # Divert HapticPanel (0x01A0), Gesture Button (0x00C3), Top Mode Button (0x00C4), Side Buttons
                for cid in [0x01A0, 0x00C3, 0x00C4, 0x0053, 0x0056]:
                    set_button_diversion(hid_fd, cid, divert=True, raw_xy=True)

    # Gesture state
    active_cid: Optional[int] = None
    acc_dx = 0
    acc_dy = 0
    press_time = 0.0

    try:
        status = get_full_status()
        write_status_file(status)

        last_heartbeat = time.time()
        while True:
            # Check for command spools
            cmd_files = sorted(rdir.glob("cmd-*.json"))
            for cf in cmd_files:
                process_command(cf)
                status = get_full_status()
                write_status_file(status)

            # Read live hardware HID++ reports from mouse
            read_fds = [hid_fd] if hid_fd is not None else []
            r, _, _ = select.select(read_fds, [], [], 0.05)
            if hid_fd is not None and hid_fd in r:
                try:
                    packet = os.read(hid_fd, 64)
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
                                    press_time = time.time()
                                elif active_cid is not None:
                                    # Button UP — process action or gesture
                                    btn_name = CID_TO_BUTTON.get(active_cid, "HapticPanel")
                                    cfg = load_openlogi_config()
                                    _, dev_cfg = find_matching_config(cfg.get("devices", {}), devices[0] if devices else {})
                                    buttons_map = dev_cfg.get("buttons", {}) if isinstance(dev_cfg, dict) else {}

                                    dist = math.sqrt(acc_dx * acc_dx + acc_dy * acc_dy)
                                    if dist < 20:
                                        # Single Click
                                        act = buttons_map.get(btn_name, "ShowActionRing" if btn_name in ("HapticPanel", "GestureButton") else "None")
                                        if isinstance(act, dict):
                                            act = act.get("action", "None")
                                        dispatch_action(act)
                                    else:
                                        # Swipe Gesture / Action Ring direction
                                        angle_deg = math.degrees(math.atan2(acc_dy, acc_dx)) % 360
                                        # 4-way gesture
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
                                dx = struct.unpack(">h", packet[4:6])[0]
                                dy = struct.unpack(">h", packet[6:8])[0]
                                acc_dx += dx
                                acc_dy += dy
                except Exception:
                    pass

            now = time.time()
            if now - last_heartbeat >= HEARTBEAT_SEC:
                status = get_full_status()
                write_status_file(status)
                last_heartbeat = now
    except KeyboardInterrupt:
        pass
    finally:
        if hid_fd is not None:
            try:
                for cid in [0x01A0, 0x00C3, 0x00C4, 0x0053, 0x0056]:
                    set_button_diversion(hid_fd, cid, divert=False, raw_xy=False)
                os.close(hid_fd)
            except Exception:
                pass
        try:
            lock_fd.close()
            lock_path.unlink()
        except Exception:
            pass


def emit(obj: Any) -> None:
    print(json.dumps(obj, ensure_ascii=False))


def main() -> None:
    parser = argparse.ArgumentParser(description="OpenLogi Controller & Hardware Driver for Omarchy")
    sub = parser.add_subparsers(dest="subcommand")

    sub.add_parser("discover", help="Discover devices and print status JSON")
    sub.add_parser("status", help="Get full status JSON")
    sub.add_parser("serve", help="Run background daemon")
    sub.add_parser("runtime-dir", help="Print runtime directory")
    sub.add_parser("cleanup", help="Clean up runtime files")

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
            (rdir / "openlogictl.lock").unlink()
        except OSError:
            pass
        emit({"ok": True})
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
        process_command(cmd_file)
        status = get_full_status()
        write_status_file(status)
        emit({"ok": True, "file": str(cmd_file)})
    elif args.subcommand == "serve":
        serve_daemon()


if __name__ == "__main__":
    main()
