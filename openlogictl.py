#!/usr/bin/env python3
# Copyright (C) 2026 OpenLogi & Omarchy Contributors
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the MIT License.

"""JSON CLI and daemon for Omarchy OpenLogi Control.
Integrates Omarchy 4.0 (Quattro) with OpenLogi for Logitech MX devices,
handling Smart Ring (Action Ring), gestures, DPI, SmartShift, and button remaps.
"""

from __future__ import annotations

import argparse
import errno
import fcntl
import json
import os
import re
import select
import shutil
import socket
import stat
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib  # type: ignore
    except ImportError:
        tomllib = None  # type: ignore

# Standard slots for the Action Ring
ACTION_RING_SLOTS = [
    "Top",
    "TopRight",
    "Right",
    "BottomRight",
    "Bottom",
    "BottomLeft",
    "Left",
    "TopLeft",
]

# Standard directions for gestures
GESTURE_DIRECTIONS = ["Up", "Down", "Left", "Right", "Click"]

# Standard button IDs in OpenLogi
BUTTON_IDS = [
    "LeftClick",
    "RightClick",
    "MiddleClick",
    "Back",
    "Forward",
    "DpiToggle",
    "Thumbwheel",
    "ThumbwheelScrollUp",
    "ThumbwheelScrollDown",
    "GestureButton",
    "HapticPanel",
    "KeySearch",
    "KeyDictation",
    "KeyEmoji",
    "KeyScreenCapture",
    "KeyMicMute",
    "KeyPlayPause",
    "KeyMute",
    "KeyVolumeDown",
    "KeyVolumeUp",
]

FALLBACK_RECEIVER_PIDS = {
    "C517", "C518", "C51A", "C51B", "C521", "C525", "C526", "C52B", "C52E",
    "C52F", "C531", "C532", "C534", "C535", "C537", "C539", "C53A", "C53D",
    "C53F", "C541", "C545", "C547", "C548", "C54D", "6042",
}

MX_NAME_RE = re.compile(
    r"(?:\bmx\b|master|anywhere|vertical|ergo|lift|mechanical|keys mini|mx keys|mx master|craft|signature|g502|g903|superlight|pebble)",
    re.IGNORECASE,
)

POWER_SUPPLY_ROOT = Path("/sys/class/power_supply")
CAPACITY_LEVEL_PERCENT = {
    "full": 100,
    "high": 80,
    "normal": 55,
    "low": 20,
    "critical": 5,
}

IDLE_TIMEOUT_SEC = 30.0
HEARTBEAT_SEC = 30.0


def emit(payload: dict, code: int = 0) -> None:
    json.dump(payload, sys.stdout, ensure_ascii=False, default=str)
    sys.stdout.write("\n")
    sys.stdout.flush()
    raise SystemExit(code)


def fail(message: str, **extra) -> None:
    payload = {"ok": False, "message": plain_hid_text(message), "devices": []}
    payload.update(extra)
    emit(payload, 1)


def plain_hid_text(value: Any) -> str:
    """HID identity is untrusted. Strip markup so QML AutoText cannot fetch URLs."""
    if value is None:
        return ""
    text = str(value)
    if "<" not in text and ">" not in text and "&" not in text:
        return text
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def get_runtime_dir() -> Path:
    xdg_runtime = os.environ.get("XDG_RUNTIME_DIR")
    if xdg_runtime:
        path = Path(xdg_runtime) / "omarchy-openlogi"
    else:
        path = Path(f"/run/user/{os.getuid()}/omarchy-openlogi")
    try:
        path.mkdir(parents=True, exist_ok=True, mode=0o700)
    except OSError:
        pass
    return path


def get_openlogi_config_path() -> Path:
    xdg_config = os.environ.get("XDG_CONFIG_HOME")
    if xdg_config:
        config_dir = Path(xdg_config) / "openlogi"
    else:
        config_dir = Path.home() / ".config" / "openlogi"
    config_dir.mkdir(parents=True, exist_ok=True)
    return config_dir / "config.toml"


def get_openlogi_socket_path() -> Path:
    xdg_config = os.environ.get("XDG_CONFIG_HOME")
    if xdg_config:
        config_dir = Path(xdg_config) / "openlogi"
    else:
        config_dir = Path.home() / ".config" / "openlogi"
    return config_dir / "agent.sock"


def is_openlogi_installed() -> bool:
    if shutil.which("openlogi") or shutil.which("openlogi-agent"):
        return True
    socket_path = get_openlogi_socket_path()
    if socket_path.exists():
        return True
    return False


def is_openlogi_agent_running() -> bool:
    socket_path = get_openlogi_socket_path()
    if not socket_path.exists():
        return False
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.5)
        s.connect(str(socket_path))
        s.close()
        return True
    except (OSError, socket.error):
        return False


def hid_field(text: str, key: str) -> str:
    prefix = key + "="
    for line in text.splitlines():
        if line.startswith(prefix):
            return line.split("=", 1)[1].strip()
    return ""


def hid_id_from_uevent(text: str) -> tuple[str, str]:
    for line in text.splitlines():
        if line.startswith("HID_ID="):
            parts = line.split("=", 1)[1].strip().split(":")
            if len(parts) >= 3:
                return parts[1][-4:].upper(), parts[2][-4:].upper()
    return "", ""


def hid_name_from_uevent(text: str) -> str:
    for line in text.splitlines():
        if line.startswith("HID_NAME="):
            return line.split("=", 1)[1].strip()
    return ""


def bus_from_uevent(text: str) -> str:
    if "0005:" in text:
        return "bluetooth"
    if "0003:" in text or "usb" in text.lower():
        return "usb"
    return "hid"


def receiver_kind_for_pid(product: str) -> str:
    pid = (product or "").upper()
    if pid == "C548":
        return "bolt"
    if pid in {"C52B", "C532"}:
        return "unifying"
    if pid.startswith("C53") or pid in {"C541", "C545", "C547", "C54D"}:
        return "lightspeed"
    if pid.startswith("C5"):
        return "nano"
    return "receiver"


def kind_from_name(name: str) -> str:
    lower = name.lower()
    if any(token in lower for token in ("key", "keyboard", "mechanical", "craft")):
        return "keyboard"
    if any(token in lower for token in ("master", "mouse", "anywhere", "ergo", "vertical", "lift", "trackball", "pebble")):
        return "mouse"
    return "device"


def scan_power_supply() -> list[dict]:
    supplies = []
    if not POWER_SUPPLY_ROOT.is_dir():
        return supplies
    for entry in sorted(POWER_SUPPLY_ROOT.glob("hidpp_battery_*")):
        def read_file(name: str) -> str:
            try:
                return (entry / name).read_text(encoding="utf-8", errors="replace").strip()
            except OSError:
                return ""

        if read_file("online") == "0":
            continue
        level = None
        try:
            level = int(read_file("capacity"))
        except ValueError:
            pass
        capacity_level = read_file("capacity_level").strip().lower()
        if level is None:
            level = CAPACITY_LEVEL_PERCENT.get(capacity_level)
        if level is None:
            continue
        supplies.append(
            {
                "serial": read_file("serial_number"),
                "model": read_file("model_name"),
                "level": max(0, min(100, level)),
                "status": read_file("status").lower(),
            }
        )
    return supplies


def match_battery(supplies: list[dict], serial: str, name: str) -> Optional[dict]:
    want_serial = str(serial or "").strip().lower()
    want_name = str(name or "").strip().lower()
    for item in supplies:
        have_serial = str(item.get("serial") or "").strip().lower()
        have_model = str(item.get("model") or "").strip().lower()
        matched = bool(want_serial and have_serial and want_serial == have_serial)
        if not matched and want_name and have_model:
            matched = want_name in have_model or have_model in want_name
        if not matched:
            continue
        return {
            "level": item["level"],
            "status": item.get("status") or "",
            "voltage": None,
            "text": f"{item['level']}%",
        }
    return None


def scan_hidraw() -> tuple[list[dict], list[dict]]:
    devices = []
    adapters = []
    seen = set()
    supplies = scan_power_supply()
    root = Path("/sys/class/hidraw")
    if not root.is_dir():
        return devices, adapters

    for entry in sorted(root.glob("hidraw*")):
        uevent_path = entry / "device" / "uevent"
        try:
            text = uevent_path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        vendor, product = hid_id_from_uevent(text)
        if vendor != "046D":
            continue
        name = hid_name_from_uevent(text) or f"Logitech {product}"
        if name.lower().startswith("logitech "):
            name = name[9:]
        node = f"/dev/{entry.name}"
        uniq = hid_field(text, "HID_UNIQ")
        bus = bus_from_uevent(text)
        driver = hid_field(text, "DRIVER")

        is_rcv = product in FALLBACK_RECEIVER_PIDS or any(
            t in name.lower() for t in ("receiver", "bolt", "unifying", "lightspeed")
        )
        if is_rcv:
            adapter_id = uniq or product or entry.name
            if adapter_id in seen:
                continue
            seen.add(adapter_id)
            kind = receiver_kind_for_pid(product)
            adapters.append(
                {
                    "id": adapter_id,
                    "name": plain_hid_text(name) or kind.title() + " receiver",
                    "kind": kind,
                    "productId": product,
                    "path": node,
                    "connection": kind if kind != "receiver" else "usb",
                    "accessible": os.access(node, os.R_OK | os.W_OK),
                }
            )
            continue

        if not (MX_NAME_RE.search(name) or driver == "logitech-hidpp-device"):
            continue

        dedupe = uniq or f"{product}:{hid_field(text, 'HID_PHYS')}"
        if dedupe in seen:
            continue
        seen.add(dedupe)

        bat = match_battery(supplies, uniq, name)
        is_mouse = kind_from_name(name) == "mouse"

        # Default capabilities for MX devices
        capabilities = {
            "action_ring": is_mouse,
            "gestures": is_mouse,
            "smartshift": is_mouse and ("master" in name.lower() or "anywhere" in name.lower()),
            "hires_scroll": is_mouse,
            "thumbwheel": is_mouse and "master" in name.lower(),
            "backlight": not is_mouse,
            "fn_swap": not is_mouse,
        }

        devices.append(
            {
                "id": uniq or entry.name,
                "name": plain_hid_text(name),
                "codename": plain_hid_text(name),
                "kind": kind_from_name(name),
                "online": True,
                "path": node,
                "productId": product,
                "serial": uniq,
                "unitId": uniq,
                "protocol": "HID++ 2.0 / OpenLogi",
                "connection": bus,
                "accessible": os.access(node, os.R_OK | os.W_OK),
                "battery": bat,
                "capabilities": capabilities,
            }
        )

    return devices, adapters


# Simple zero-dependency TOML parser / serializer for OpenLogi config.toml
def load_openlogi_config() -> dict:
    path = get_openlogi_config_path()
    if not path.exists():
        return {"devices": {}, "general": {}}

    if tomllib is not None:
        try:
            with open(path, "rb") as f:
                return tomllib.load(f)
        except Exception:
            pass

    # Simple fallback parser if tomllib is missing
    return parse_simple_toml(path.read_text(encoding="utf-8", errors="replace"))


def parse_simple_toml(content: str) -> dict:
    result: dict[str, Any] = {}
    current_section = result
    section_name = ""

    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        if line.startswith("[") and line.endswith("]"):
            header = line[1:-1].strip()
            parts = header.split(".")
            curr = result
            for p in parts:
                p = p.strip('"\'')
                if p not in curr or not isinstance(curr[p], dict):
                    curr[p] = {}
                curr = curr[p]
            current_section = curr
            section_name = header
            continue

        if "=" in line:
            key, val = line.split("=", 1)
            key = key.strip().strip('"\'')
            val = val.strip()
            # Parse basic types
            if val.startswith('"') and val.endswith('"'):
                parsed_val = val[1:-1]
            elif val.startswith("'") and val.endswith("'"):
                parsed_val = val[1:-1]
            elif val.lower() == "true":
                parsed_val = True
            elif val.lower() == "false":
                parsed_val = False
            elif val.startswith("[") and val.endswith("]"):
                # Array of strings or ints
                raw_items = val[1:-1].split(",")
                parsed_val = []
                for it in raw_items:
                    it = it.strip().strip('"\'')
                    if it:
                        try:
                            parsed_val.append(int(it))
                        except ValueError:
                            parsed_val.append(it)
            else:
                try:
                    if "." in val:
                        parsed_val = float(val)
                    else:
                        parsed_val = int(val)
                except ValueError:
                    parsed_val = val
            current_section[key] = parsed_val

    return result


def format_toml_value(val: Any) -> str:
    if isinstance(val, bool):
        return "true" if val else "false"
    if isinstance(val, (int, float)):
        return str(val)
    if isinstance(val, str):
        escaped = val.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'
    if isinstance(val, list):
        items = [format_toml_value(x) for x in val]
        return f"[{', '.join(items)}]"
    if isinstance(val, dict):
        items = [f'"{k}" = {format_toml_value(v)}' for k, v in val.items()]
        return f"{{ {', '.join(items)} }}"
    return f'"{val}"'


def save_openlogi_config(config: dict) -> None:
    path = get_openlogi_config_path()
    lines = [
        "# OpenLogi Configuration (managed by omarchy-openlogi)",
        "# https://github.com/AprilNEA/OpenLogi",
        "",
    ]

    # Write top-level keys
    for k, v in sorted(config.items()):
        if not isinstance(v, dict):
            lines.append(f"{k} = {format_toml_value(v)}")

    # Write sections
    def write_table(prefix: str, table: dict):
        # First write direct scalar values
        scalars = {k: v for k, v in table.items() if not isinstance(v, dict)}
        subtables = {k: v for k, v in table.items() if isinstance(v, dict)}

        if scalars or not subtables:
            lines.append("")
            lines.append(f"[{prefix}]")
            for k, v in sorted(scalars.items()):
                lines.append(f"{k} = {format_toml_value(v)}")

        for subk, subv in sorted(subtables.items()):
            new_prefix = f'{prefix}."{subk}"' if " " in subk or ":" in subk else f"{prefix}.{subk}"
            write_table(new_prefix, subv)

    for k, v in sorted(config.items()):
        if isinstance(v, dict):
            write_table(k, v)

    lines.append("")
    temp_path = path.with_suffix(".tmp")
    temp_path.write_text("\n".join(lines), encoding="utf-8")
    temp_path.replace(path)


def default_device_config(dev_name: str, dev_kind: str) -> dict:
    is_mouse = dev_kind == "mouse"
    conf: dict[str, Any] = {}
    if is_mouse:
        conf["dpi"] = 1000
        conf["dpi_preset"] = [800, 1000, 1600, 2400, 4000]
        conf["smartshift"] = {
            "mode": "auto",
            "threshold": 12,
            "torque": 50,
        }
        conf["scroll"] = {
            "invert_y": False,
            "invert_thumb": False,
            "hires": True,
        }
        conf["action_ring"] = {
            "enabled": True,
            "haptics": True,
            "slots": {
                "Top": {"action": "MissionControl", "label": "Overview"},
                "TopRight": {"action": "NextWorkspace", "label": "Workspace +"},
                "Right": {"action": "VolumeUp", "label": "Vol +"},
                "BottomRight": {"action": "PlayPause", "label": "Play/Pause"},
                "Bottom": {"action": "ShowDesktop", "label": "Desktop"},
                "BottomLeft": {"action": "PrevWorkspace", "label": "Workspace -"},
                "Left": {"action": "VolumeDown", "label": "Vol -"},
                "TopLeft": {"action": "Mute", "label": "Mute"},
            },
        }
        conf["gestures"] = {
            "enabled": True,
            "owner": "GestureButton",
            "Up": {"action": "MaximizeWindow", "label": "Maximize"},
            "Down": {"action": "MinimizeWindow", "label": "Minimize"},
            "Left": {"action": "TileLeft", "label": "Tile Left"},
            "Right": {"action": "TileRight", "label": "Tile Right"},
            "Click": {"action": "ShowActionRing", "label": "Action Ring"},
        }
        conf["buttons"] = {
            "GestureButton": {"action": "Gestures"},
            "HapticPanel": {"action": "ShowActionRing"},
            "DpiToggle": {"action": "DpiCycle"},
            "MiddleClick": {"action": "MiddleClick"},
            "Back": {"action": "Back"},
            "Forward": {"action": "Forward"},
            "Thumbwheel": {"action": "HorizontalScroll"},
        }
    else:
        conf["keyboard"] = {
            "fn_swap": False,
            "backlight_level": 80,
            "backlight_timeout_sec": 30,
            "disable_caps_lock": False,
            "disable_windows_key": False,
            "disable_insert": False,
        }
        conf["buttons"] = {
            "KeySearch": {"action": "Launcher"},
            "KeyDictation": {"action": "Dictation"},
            "KeyEmoji": {"action": "EmojiPicker"},
            "KeyScreenCapture": {"action": "Screenshot"},
            "KeyMicMute": {"action": "MicMute"},
            "KeyPlayPause": {"action": "PlayPause"},
            "KeyMute": {"action": "Mute"},
            "KeyVolumeDown": {"action": "VolumeDown"},
            "KeyVolumeUp": {"action": "VolumeUp"},
        }
    return conf


def get_full_status() -> dict:
    devices, adapters = scan_hidraw()
    config = load_openlogi_config()
    openlogi_inst = is_openlogi_installed()
    openlogi_running = is_openlogi_agent_running()

    # Merge config into devices
    cfg_devices = config.get("devices", {})
    for dev in devices:
        key = dev.get("id") or dev.get("serial") or dev.get("name")
        dev_cfg = cfg_devices.get(key)
        if not dev_cfg:
            # Fallback search by codename/name
            for ck, cv in cfg_devices.items():
                if ck.lower() in dev.get("name", "").lower() or dev.get("name", "").lower() in ck.lower():
                    dev_cfg = cv
                    break

        if not dev_cfg:
            dev_cfg = default_device_config(dev.get("name", ""), dev.get("kind", ""))

        dev["config"] = dev_cfg
        dev["dpi"] = dev_cfg.get("dpi", 1000)
        dev["smartshift"] = dev_cfg.get("smartshift", {"mode": "auto", "threshold": 12, "torque": 50})
        dev["scroll"] = dev_cfg.get("scroll", {"invert_y": False, "invert_thumb": False, "hires": True})
        dev["action_ring"] = dev_cfg.get("action_ring", default_device_config(dev.get("name", ""), "mouse")["action_ring"])
        dev["gestures"] = dev_cfg.get("gestures", default_device_config(dev.get("name", ""), "mouse")["gestures"])
        dev["buttons"] = dev_cfg.get("buttons", {})
        dev["keyboard"] = dev_cfg.get("keyboard", {})

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

    target_key = device_id
    # Match existing key if present
    found = False
    for k in list(config["devices"].keys()):
        if k == device_id or k.lower() in device_id.lower() or device_id.lower() in k.lower():
            target_key = k
            found = True
            break

    if not found:
        config["devices"][target_key] = {}

    target = config["devices"][target_key]

    for k, v in updates.items():
        if isinstance(v, dict) and isinstance(target.get(k), dict):
            target[k].update(v)
        else:
            target[k] = v

    save_openlogi_config(config)
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
            dev_cfg = cfg.get("devices", {}).get(device_id, {})
            ar = dev_cfg.get("action_ring", {})
            slots = ar.get("slots", {})
            slots[slot] = {"action": action, "label": label}
            ar["slots"] = slots
            apply_device_update(device_id, {"action_ring": ar})
    elif cmd_type == "set_gesture":
        apply_device_update(device_id, {"gestures": payload})
    elif cmd_type == "set_button":
        btn = payload.get("button")
        action = payload.get("action")
        if btn and action:
            cfg = load_openlogi_config()
            dev_cfg = cfg.get("devices", {}).get(device_id, {})
            btns = dev_cfg.get("buttons", {})
            btns[btn] = {"action": action}
            apply_device_update(device_id, {"buttons": btns})
    elif cmd_type == "set_keyboard":
        apply_device_update(device_id, {"keyboard": payload})
    elif cmd_type == "refresh":
        pass

    try:
        cmd_file.unlink()
    except OSError:
        pass


def serve_daemon() -> None:
    rdir = get_runtime_dir()
    status_path = rdir / "status.json"
    lock_path = rdir / "openlogictl.lock"

    try:
        lock_fd = open(lock_path, "w")
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except (OSError, IOError):
        # Another instance is already serving
        sys.exit(0)

    try:
        # Initial snapshot
        status = get_full_status()
        tmp_status = status_path.with_suffix(".tmp")
        tmp_status.write_text(json.dumps(status, ensure_ascii=False, indent=2), encoding="utf-8")
        tmp_status.replace(status_path)

        last_heartbeat = time.time()
        while True:
            # Check for command spools
            cmd_files = sorted(rdir.glob("cmd-*.json"))
            for cf in cmd_files:
                process_command(cf)
                status = get_full_status()
                tmp_status.write_text(json.dumps(status, ensure_ascii=False, indent=2), encoding="utf-8")
                tmp_status.replace(status_path)

            now = time.time()
            if now - last_heartbeat >= HEARTBEAT_SEC:
                status = get_full_status()
                tmp_status.write_text(json.dumps(status, ensure_ascii=False, indent=2), encoding="utf-8")
                tmp_status.replace(status_path)
                last_heartbeat = now

            time.sleep(0.5)
    except KeyboardInterrupt:
        pass
    finally:
        try:
            lock_fd.close()
            lock_path.unlink()
        except Exception:
            pass


def main() -> None:
    parser = argparse.ArgumentParser(description="OpenLogi Controller for Omarchy")
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
        emit({"ok": True, "file": str(cmd_file)})
    elif args.subcommand == "serve":
        serve_daemon()


if __name__ == "__main__":
    main()
