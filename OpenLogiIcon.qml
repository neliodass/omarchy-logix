import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property int iconSize: 18
  property color color: Color.foreground
  property color cutoutColor: Color.background
  property color badgeColor: Color.urgent
  property bool lowBattery: false
  property bool isKeyboard: false

  implicitWidth: iconSize
  implicitHeight: iconSize

  Canvas {
    id: canvas
    anchors.fill: parent
    antialiasing: true

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.clearRect(0, 0, width, height)

      var s = Math.min(width, height)
      var pad = s * 0.1
      var w = s - pad * 2
      var h = s - pad * 2
      var x = pad
      var y = pad

      ctx.strokeStyle = root.color
      ctx.fillStyle = root.color
      ctx.lineWidth = Math.max(1.5, s * 0.08)
      ctx.lineCap = "round"
      ctx.lineJoin = "round"

      if (root.isKeyboard) {
        // Draw keyboard shape
        var r = s * 0.12
        var kw = w
        var kh = h * 0.75
        var ky = y + h * 0.12

        ctx.beginPath()
        ctx.roundRect(x, ky, kw, kh, r)
        ctx.stroke()

        // Key rows / dots
        var dotR = s * 0.04
        ctx.beginPath()
        ctx.arc(x + kw * 0.3, ky + kh * 0.35, dotR, 0, 2 * Math.PI)
        ctx.arc(x + kw * 0.5, ky + kh * 0.35, dotR, 0, 2 * Math.PI)
        ctx.arc(x + kw * 0.7, ky + kh * 0.35, dotR, 0, 2 * Math.PI)
        ctx.arc(x + kw * 0.3, ky + kh * 0.65, dotR, 0, 2 * Math.PI)
        ctx.arc(x + kw * 0.5, ky + kh * 0.65, dotR, 0, 2 * Math.PI)
        ctx.arc(x + kw * 0.7, ky + kh * 0.65, dotR, 0, 2 * Math.PI)
        ctx.fill()
      } else {
        // Draw MX Mouse with Smart Ring / Thumb rest curve
        var mw = w * 0.7
        var mx = x + (w - mw) / 2
        var mr = mw * 0.45

        ctx.beginPath()
        // Top rounded cap
        ctx.arc(mx + mw / 2, y + mr, mr, Math.PI, 0, false)
        // Right body line
        ctx.lineTo(mx + mw, y + h - mr)
        // Bottom curve
        ctx.arc(mx + mw / 2, y + h - mr, mr, 0, Math.PI, false)
        // Left thumb rest / Smart Ring curve
        ctx.bezierCurveTo(mx - w * 0.15, y + h * 0.6, mx - w * 0.15, y + h * 0.4, mx, y + mr)
        ctx.closePath()
        ctx.stroke()

        // Scroll wheel
        var ww = mw * 0.22
        var wh = h * 0.28
        var wx = mx + mw / 2 - ww / 2
        var wy = y + h * 0.18

        ctx.beginPath()
        ctx.roundRect(wx, wy, ww, wh, ww * 0.5)
        ctx.fill()

        // Smart Ring / Thumb button accent arc
        ctx.beginPath()
        ctx.lineWidth = Math.max(1.2, s * 0.06)
        ctx.arc(mx - w * 0.05, y + h * 0.52, s * 0.12, Math.PI * 0.6, Math.PI * 1.4, false)
        ctx.stroke()
      }

      // Low battery indicator badge
      if (root.lowBattery) {
        var badgeR = s * 0.2
        var bx = width - badgeR
        var by = height - badgeR

        // Cutout background
        ctx.fillStyle = root.cutoutColor
        ctx.beginPath()
        ctx.arc(bx, by, badgeR * 1.25, 0, 2 * Math.PI)
        ctx.fill()

        // Red badge
        ctx.fillStyle = root.badgeColor
        ctx.beginPath()
        ctx.arc(bx, by, badgeR, 0, 2 * Math.PI)
        ctx.fill()

        // Exclamation mark
        ctx.fillStyle = "#ffffff"
        ctx.fillRect(bx - 0.75, by - badgeR * 0.55, 1.5, badgeR * 0.65)
        ctx.beginPath()
        ctx.arc(bx, by + badgeR * 0.45, 0.8, 0, 2 * Math.PI)
        ctx.fill()
      }
    }
  }

  onColorChanged: canvas.requestPaint()
  onCutoutColorChanged: canvas.requestPaint()
  onBadgeColorChanged: canvas.requestPaint()
  onLowBatteryChanged: canvas.requestPaint()
  onIsKeyboardChanged: canvas.requestPaint()
  onIconSizeChanged: canvas.requestPaint()
}
