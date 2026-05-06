#!/usr/bin/env bash
# Generate Resources/AppIcon.icns from a Swift-rendered PNG.
#
# Run once (or whenever the source design changes); the output is committed
# alongside the app so build.sh just copies it. Re-run after editing the
# Swift drawing block below.
#
# Requires: macOS (sips, iconutil), Swift toolchain.

set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PNG="$WORK/icon-1024.png"
ICONSET="$WORK/AppIcon.iconset"
OUT="Resources/AppIcon.icns"

echo "==> Rendering 1024x1024 source PNG"
swift - "$PNG" <<'SWIFT'
import AppKit
import CoreGraphics

// Render the master 1024x1024 PNG. Design: dark navy rounded square,
// 240° gauge arc (gap at the bottom), indigo->teal active fill at 70%,
// triangular needle, central hub disc.
//
// Coordinate notes: CGContext bitmap space has y-up and standard math
// angles (0 = +X / right, increasing CCW). `clockwise: true` sweeps in
// the decreasing-angle direction.
let size = 1024
let url = URL(fileURLWithPath: CommandLine.arguments[1])

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fatalError("CGContext") }

let s = CGFloat(size)
let center = CGPoint(x: s / 2, y: s / 2)

// macOS Big Sur+ icon mask: 824/1024 squircle with 185 corner radius.
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
let cornerRadius: CGFloat = 185
let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
ctx.saveGState()
ctx.addPath(path)
ctx.clip()

// Dark navy gradient background.
let gradient = CGGradient(
    colorsSpace: cs,
    colors: [
        CGColor(red: 0.07, green: 0.10, blue: 0.20, alpha: 1) as Any,
        CGColor(red: 0.03, green: 0.05, blue: 0.12, alpha: 1) as Any,
    ] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(gradient,
    start: CGPoint(x: rect.minX, y: rect.maxY),
    end: CGPoint(x: rect.maxX, y: rect.minY),
    options: [])

// Gauge geometry: 240° arc from lower-left (210°) clockwise to lower-right (-30°).
// Gap of 120° centered at the bottom (270°).
let arcStart: CGFloat = .pi + .pi / 6      // 210°, lower-left
let arcEnd: CGFloat = -.pi / 6             // -30°, lower-right
let arcSweep: CGFloat = 4 * .pi / 3        // 240°
let progress: CGFloat = 0.70
let dialRadius: CGFloat = 305
let strokeWidth: CGFloat = 44

// Background dial track.
ctx.setStrokeColor(CGColor(red: 0.30, green: 0.36, blue: 0.55, alpha: 0.55))
ctx.setLineWidth(strokeWidth)
ctx.setLineCap(.round)
ctx.addArc(center: center, radius: dialRadius,
    startAngle: arcStart, endAngle: arcEnd, clockwise: true)
ctx.strokePath()

// Active arc (0% -> 70%) clipped to a stroked path so we can fill with a gradient.
let activeEnd = arcStart - arcSweep * progress
ctx.saveGState()
ctx.setLineWidth(strokeWidth)
ctx.setLineCap(.round)
ctx.addArc(center: center, radius: dialRadius,
    startAngle: arcStart, endAngle: activeEnd, clockwise: true)
ctx.replacePathWithStrokedPath()
ctx.clip()
let activeGrad = CGGradient(
    colorsSpace: cs,
    colors: [
        CGColor(red: 0.40, green: 0.45, blue: 1.00, alpha: 1) as Any, // indigo (start = lower-left)
        CGColor(red: 0.20, green: 0.85, blue: 0.78, alpha: 1) as Any, // teal (end = right side, near top)
    ] as CFArray,
    locations: [0, 1])!
let startPt = CGPoint(
    x: center.x + cos(arcStart) * dialRadius,
    y: center.y + sin(arcStart) * dialRadius)
let endPt = CGPoint(
    x: center.x + cos(activeEnd) * dialRadius,
    y: center.y + sin(activeEnd) * dialRadius)
ctx.drawLinearGradient(activeGrad, start: startPt, end: endPt, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
ctx.restoreGState()

// Tick dots OUTSIDE the dial track, pointing inward.
let tickCount = 9
let tickRadius: CGFloat = dialRadius + strokeWidth / 2 + 38
let tickDotRadius: CGFloat = 12
for i in 0...tickCount {
    let t = CGFloat(i) / CGFloat(tickCount)
    let angle = arcStart - arcSweep * t  // CW sweep matches the dial
    let p = CGPoint(
        x: center.x + cos(angle) * tickRadius,
        y: center.y + sin(angle) * tickRadius)
    ctx.setFillColor(CGColor(red: 0.78, green: 0.83, blue: 0.95, alpha: 0.85))
    let dot = CGRect(x: p.x - tickDotRadius, y: p.y - tickDotRadius,
                     width: tickDotRadius * 2, height: tickDotRadius * 2)
    ctx.fillEllipse(in: dot)
}

// Needle: triangle from center hub pointing at activeEnd.
let needleLen: CGFloat = dialRadius - 50
let baseHalfWidth: CGFloat = 26
let needleTip = CGPoint(
    x: center.x + cos(activeEnd) * needleLen,
    y: center.y + sin(activeEnd) * needleLen)
let perpAngle = activeEnd + .pi / 2
let baseLeft = CGPoint(
    x: center.x + cos(perpAngle) * baseHalfWidth,
    y: center.y + sin(perpAngle) * baseHalfWidth)
let baseRight = CGPoint(
    x: center.x - cos(perpAngle) * baseHalfWidth,
    y: center.y - sin(perpAngle) * baseHalfWidth)
ctx.beginPath()
ctx.move(to: needleTip)
ctx.addLine(to: baseLeft)
ctx.addLine(to: baseRight)
ctx.closePath()
ctx.setFillColor(CGColor(red: 0.96, green: 0.97, blue: 1.0, alpha: 1.0))
ctx.fillPath()

// Hub disc (outer dark ring + inner indigo dot).
let hubOuter = CGRect(x: center.x - 56, y: center.y - 56, width: 112, height: 112)
ctx.setFillColor(CGColor(red: 0.16, green: 0.20, blue: 0.34, alpha: 1.0))
ctx.fillEllipse(in: hubOuter)
let hubInner = CGRect(x: center.x - 26, y: center.y - 26, width: 52, height: 52)
ctx.setFillColor(CGColor(red: 0.42, green: 0.45, blue: 0.95, alpha: 1.0))
ctx.fillEllipse(in: hubInner)

ctx.restoreGState()

guard let cg = ctx.makeImage() else { fatalError("makeImage") }
let bitmap = NSBitmapImageRep(cgImage: cg)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("png encode")
}
try png.write(to: url)
SWIFT

echo "==> Generating .iconset"
mkdir -p "$ICONSET"
# Apple iconset spec: 10 PNGs covering 16/32/128/256/512 @1x and @2x.
for spec in \
    "16 icon_16x16.png" \
    "32 icon_16x16@2x.png" \
    "32 icon_32x32.png" \
    "64 icon_32x32@2x.png" \
    "128 icon_128x128.png" \
    "256 icon_128x128@2x.png" \
    "256 icon_256x256.png" \
    "512 icon_256x256@2x.png" \
    "512 icon_512x512.png" \
    "1024 icon_512x512@2x.png"; do
    set -- $spec
    sips -z "$1" "$1" "$PNG" --out "$ICONSET/$2" >/dev/null
done

echo "==> iconutil -> $OUT"
iconutil -c icns "$ICONSET" -o "$OUT"

ls -lh "$OUT"
