import QtQuick
import QtQuick.Controls
import qs.Commons

Item {
  id: root

  property int iconSize: Style.bar.iconCanvas
  property color color: Color.foreground
  property color cutoutColor: Color.background
  property bool lowBattery: false
  property bool isKeyboard: false
  property color badgeColor: Color.urgent

  implicitWidth: iconSize
  implicitHeight: iconSize

  Canvas {
    id: canvas
    anchors.fill: parent
    renderTarget: Canvas.Image

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()

      var w = width
      var h = height
      var s = Math.min(w, h)
      var pad = s * 0.1
      var x = pad
      var y = pad
      w -= pad * 2
      h -= pad * 2

      ctx.strokeStyle = root.color
      ctx.fillStyle = root.color
      ctx.lineWidth = Math.max(1.5, s * 0.08)
      ctx.lineCap = "round"
      ctx.lineJoin = "round"

      if (root.isKeyboard) {
        // Draw MX Keyboard outline
        var kw = w
        var kh = h * 0.65
        var ky = y + (h - kh) / 2
        var kr = 3

        ctx.beginPath()
        ctx.rect(x, ky, kw, kh)
        ctx.stroke()

        // Key matrix dots
        var dotR = Math.max(1, s * 0.04)
        ctx.beginPath()
        ctx.arc(x + kw * 0.3, ky + kh * 0.35, dotR, 0, 2 * Math.PI)
        ctx.arc(x + kw * 0.5, ky + kh * 0.35, dotR, 0, 2 * Math.PI)
        ctx.arc(x + kw * 0.7, ky + kh * 0.35, dotR, 0, 2 * Math.PI)
        ctx.arc(x + kw * 0.3, ky + kh * 0.65, dotR, 0, 2 * Math.PI)
        ctx.arc(x + kw * 0.5, ky + kh * 0.65, dotR, 0, 2 * Math.PI)
        ctx.arc(x + kw * 0.7, ky + kh * 0.65, dotR, 0, 2 * Math.PI)
        ctx.fill()
      } else {
        // Draw sleek ergonomic MX Master silhouette with thumb wing & scroll wheel
        var mw = w * 0.78
        var mh = h * 0.95
        var mx = x + (w - mw) / 2
        var my = y + (h - mh) / 2

        ctx.beginPath()
        // Top front curve
        ctx.moveTo(mx + mw * 0.3, my)
        ctx.bezierCurveTo(mx + mw * 0.85, my, mx + mw, my + mh * 0.3, mx + mw, my + mh * 0.65)
        // Right flank curve down to base
        ctx.bezierCurveTo(mx + mw, my + mh * 0.9, mx + mw * 0.8, my + mh, mx + mw * 0.5, my + mh)
        // Base back curve
        ctx.bezierCurveTo(mx + mw * 0.25, my + mh, mx + mw * 0.1, my + mh * 0.88, mx, my + mh * 0.75)
        // Thumb rest / wing flare
        ctx.bezierCurveTo(mx - mw * 0.15, my + mh * 0.65, mx - mw * 0.15, my + mh * 0.45, mx + mw * 0.1, my + mh * 0.3)
        // Left front curve back to top
        ctx.bezierCurveTo(mx + mw * 0.15, my + mh * 0.15, mx + mw * 0.2, my, mx + mw * 0.3, my)
        ctx.stroke()

        // Center scroll wheel
        var ww = mw * 0.18
        var wh = mh * 0.28
        var wx = mx + mw * 0.48 - ww / 2
        var wy = my + mh * 0.15

        ctx.beginPath()
        ctx.rect(wx, wy, ww, wh)
        ctx.stroke()
      }

      // Low battery notification dot
      if (root.lowBattery) {
        var dotRadius = Math.max(2, s * 0.15)
        var dotX = width - dotRadius - 1
        var dotY = height - dotRadius - 1

        ctx.fillStyle = root.badgeColor
        ctx.beginPath()
        ctx.arc(dotX, dotY, dotRadius, 0, 2 * Math.PI)
        ctx.fill()
      }
    }
  }

  onColorChanged: canvas.requestPaint()
  onLowBatteryChanged: canvas.requestPaint()
  onIsKeyboardChanged: canvas.requestPaint()
}
