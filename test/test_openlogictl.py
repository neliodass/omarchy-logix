#!/usr/bin/env python3
# Unit tests for openlogictl.py
# MIT License

import json
import os
import tempfile
import unittest
from pathlib import Path

import openlogictl


class TestOpenLogiCtl(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        os.environ["XDG_CONFIG_HOME"] = self.temp_dir.name
        os.environ["XDG_RUNTIME_DIR"] = self.temp_dir.name

    def test_plain_hid_text(self):
        self.assertEqual(openlogictl.plain_hid_text("MX Master 4"), "MX Master 4")
        self.assertEqual(
            openlogictl.plain_hid_text("<script>alert(1)</script>&"),
            "&lt;script&gt;alert(1)&lt;/script&gt;&amp;",
        )

    def test_toml_parsing_and_formatting(self):
        sample_config = {
            "devices": {
                "d5:68:ea:02:dd:1f": {
                    "dpi": 1600,
                    "action_ring": {
                        "enabled": True,
                        "haptics": True,
                        "slots": {
                            "Top": {"action": "MissionControl", "label": "Overview"},
                            "Right": {"action": "VolumeUp", "label": "Vol +"},
                        },
                    },
                    "smartshift": {
                        "mode": "auto",
                        "threshold": 15,
                    },
                }
            }
        }
        openlogictl.save_openlogi_config(sample_config)
        loaded = openlogictl.load_openlogi_config()
        self.assertIn("devices", loaded)
        dev = loaded["devices"].get("d5:68:ea:02:dd:1f")
        self.assertIsNotNone(dev)
        self.assertEqual(dev["dpi"], 1600)
        self.assertEqual(dev["smartshift"]["mode"], "auto")
        self.assertEqual(dev["smartshift"]["threshold"], 15)
        self.assertEqual(dev["action_ring"]["slots"]["Top"]["action"], "MissionControl")

    def test_default_device_config(self):
        mouse_cfg = openlogictl.default_device_config("MX Master 3S", "mouse")
        self.assertIn("action_ring", mouse_cfg)
        self.assertIn("gestures", mouse_cfg)
        self.assertEqual(len(mouse_cfg["action_ring"]["slots"]), 8)
        for direction in openlogictl.GESTURE_DIRECTIONS:
            self.assertIn(direction, mouse_cfg["gestures"])

        kb_cfg = openlogictl.default_device_config("MX Keys", "keyboard")
        self.assertIn("keyboard", kb_cfg)
        self.assertIn("fn_swap", kb_cfg["keyboard"])

    def test_apply_device_update(self):
        status = openlogictl.apply_device_update("test-dev-01", {"dpi": 2400})
        self.assertTrue(status["ok"])
        cfg = openlogictl.load_openlogi_config()
        self.assertEqual(cfg["devices"]["test-dev-01"]["dpi"], 2400)

    def test_command_spool_processing(self):
        rdir = openlogictl.get_runtime_dir()
        cmd_data = {
            "type": "set_action_ring_slot",
            "deviceId": "test-dev-01",
            "payload": {
                "slot": "Top",
                "action": "NextWorkspace",
                "label": "Next Desktop",
            },
        }
        cmd_file = rdir / "cmd-test-1.json"
        cmd_file.write_text(json.dumps(cmd_data), encoding="utf-8")

        openlogictl.process_command(cmd_file)
        self.assertFalse(cmd_file.exists())

        cfg = openlogictl.load_openlogi_config()
        ar = cfg["devices"]["test-dev-01"]["action_ring"]
        self.assertEqual(ar["slots"]["Top"]["action"], "NextWorkspace")
        self.assertEqual(ar["slots"]["Top"]["label"], "Next Desktop")


if __name__ == "__main__":
    unittest.main()
