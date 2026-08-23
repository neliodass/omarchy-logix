# LogiX Control for Omarchy 4.0 🖱️⚡

> **Advanced Logitech HID++ Driver, Smart Ring Radial Wheel & Gestures for Omarchy 4.0 & Hyprland**

LogiX Control is a lightweight, zero-overhead Logitech HID++ 2.0 integration designed specifically for **Omarchy 4.0** and **Hyprland**. It bypasses external heavy daemons and communicates directly with your Logitech hardware via direct kernel `hidraw` reports.

---

## ✨ Key Features

- 🌟 **Smart Ring Radial Wheel (Thumb Rest Button):**
  - Instant circular popout menu directly at your cursor position (`hyprctl cursorpos`).
  - 8 customizable radial action slots (Window tiling, workspace navigation, volume control, overview).
  - Dismiss by clicking outside, clicking the center hub, or pressing the thumb button again (Toggle).
- 🖐️ **5-Way Directional Gestures:**
  - Hold thumb button + flick (Up, Down, Left, Right) to trigger actions.
  - Configurable **Swipe Distance (Flick Sensitivity)** slider from `6 px (Ultra Short Flick)` to `45 px`.
- ⚙️ **SmartShift Ratchet Wheel Tuning:**
  - Switch between **Smart Auto-Switch**, **Always Ratchet**, and **Always Free Spin**.
  - **Ratchet Motor Force / Torque slider** (`1% – 100%`).
  - **Auto-Disengage Sensitivity slider** (`1 – 35`).
- ⚡ **Precision Pointer Speed (DPI):**
  - Real-time hardware DPI slider (`200 – 8000 DPI`).
- 🔄 **Scroll Customization:**
  - Invert vertical wheel direction.
  - Invert horizontal thumb wheel direction.
- 🎯 **Full Modal Settings & Bar Popover:**
  - Modern Layer-Shell popup from the topbar.
  - Full-featured modal dialog for button reprogramming, gesture mapping, and device telemetry.
- 🔋 **Live Battery & Connection Monitoring:**
  - Automatic battery percentage discovery and visual indicator on the topbar.

---

## 🚀 Installation & Setup

### 1. Install to Omarchy Plugins
Clone or copy this repository into your Omarchy plugin directory:
```bash
git clone https://github.com/YOUR_USERNAME/omarchy-logix.git ~/.config/omarchy/plugins/io.logix.omarchy
```

### 2. Configure Udev Permissions (One-Time Setup)
To grant user-space read/write permissions for your Logitech devices across all Bluetooth and USB reconnects:
```bash
sudo tee /etc/udev/rules.d/99-logix-hidpp.rules << 'EOF'
KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="046d", MODE="0666", TAG+="uaccess"
KERNEL=="hidraw*", SUBSYSTEM=="hidraw", KERNELS=="*046D*", MODE="0666", TAG+="uaccess"
EOF
sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=hidraw
```
*(Or simply click the **"Fix Permissions"** button in the LogiX bar menu).*

### 3. Restart Omarchy Shell
```bash
omarchy restart shell
```

---

## 🎮 Supported Hardware

- **Logitech MX Master Series:** MX Master 4, MX Master 3S, MX Master 3, MX Master 2S, MX Anywhere 3/3S.
- **Logitech MX Keys & Craft Keyboards.**
- **Logitech Ergo Series:** MX Vertical, Lift, ERGO M575, MX Ergo.

---

## 🛠️ CLI Utilities

The backend driver CLI `logixctl.py` can also be run independently:

```bash
# Discover connected devices and output JSON status
python3 logixctl.py status

# Run background driver daemon
python3 logixctl.py serve

# Trigger action ring via Omarchy IPC
omarchy-shell io.logix.omarchy showActionRing
```

---

## 📄 License
MIT License. Created by Bartek Pieróg for Omarchy 4.0.
