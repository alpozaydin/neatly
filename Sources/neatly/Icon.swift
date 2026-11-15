import AppKit
import CoreGraphics

/// neatly's mark: a cream page with a folded corner and an "n" cut through it, on a deep forest-green tile.
/// The page is the file, the cut-out is its name. Drawn in code (no image files to ship), so the app icon,
/// the Home window and the menu-bar glyph are always the same shape. Designed on a 1024 grid.
enum Icon {
    /// The full-colour app icon, `px` pixels square.
    static func image(_ px: Int) -> CGImage? {
        render(px: px, design: 1024) { ctx in
            tile(ctx)
            ctx.saveGState(); ctx.addPath(tileShape); ctx.clip()
            mark(ctx, mono: false)
            ctx.restoreGState()
        }
    }

    /// The menu-bar glyph: the same page and n in one colour, as a template image (macOS tints it).
    static func menuBarGlyph(points: CGFloat = 18) -> NSImage {
        let px = Int(points * 2)
        let img = render(px: px, design: CGFloat(px)) { ctx in
            let fit = CGFloat(px) * 0.86
            let k = fit / max(pageRect.width, pageRect.height)
            ctx.translateBy(x: CGFloat(px) / 2, y: CGFloat(px) / 2)
            ctx.scaleBy(x: k, y: k)
            ctx.translateBy(x: -pageRect.midX, y: -pageRect.midY)
            mark(ctx, mono: true)
        }
        let ns = img.map { NSImage(cgImage: $0, size: NSSize(width: points, height: points)) } ?? NSImage()
        ns.isTemplate = true
        ns.accessibilityDescription = "neatly"
        return ns
    }

    static func png(_ px: Int) -> Data? {
        image(px).flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
    }

    // MARK: Drawing

    private static func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: a)
    }

    /// Top-left origin, in design units, rendered at `px`.
    private static func render(px: Int, design: CGFloat, _ draw: (CGContext) -> Void) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        let k = CGFloat(px) / design
        scale = k
        ctx.translateBy(x: 0, y: CGFloat(px)); ctx.scaleBy(x: k, y: -k)
        draw(ctx)
        return ctx.makeImage()
    }
    nonisolated(unsafe) private static var scale: CGFloat = 1   // shadows are in device pixels

    /// Apple's continuous-corner icon shape: a superellipse (n = 5) on the 824 px icon grid.
    nonisolated(unsafe) private static let tileShape: CGPath = {
        let r = CGRect(x: 100, y: 100, width: 824, height: 824), p = CGMutablePath()
        let a = r.width / 2, b = r.height / 2, n: CGFloat = 5
        for i in 0..<720 {
            let t = CGFloat(i) / 720 * 2 * .pi, c = cos(t), s = sin(t)
            let pt = CGPoint(x: r.midX + a * pow(abs(c), 2 / n) * (c < 0 ? -1 : 1), y: r.midY + b * pow(abs(s), 2 / n) * (s < 0 ? -1 : 1))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }()

    private static func linear(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
        guard let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil) else { return }
        ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    /// The green tile: soft drop shadow, top-to-bottom green, a faint sheen and a hairline edge.
    private static func tile(_ ctx: CGContext) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 28 * scale, color: rgb(0x000000, 0.28))
        ctx.addPath(tileShape); ctx.setFillColor(rgb(0x10392A)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState(); ctx.addPath(tileShape); ctx.clip()
        linear(ctx, [rgb(0x22634A), rgb(0x10392A)], from: CGPoint(x: 512, y: 100), to: CGPoint(x: 512, y: 924))
        linear(ctx, [rgb(0xffffff, 0.05), rgb(0xffffff, 0)], from: CGPoint(x: 512, y: 100), to: CGPoint(x: 512, y: 480))
        ctx.restoreGState()
        var t = CGAffineTransform(translationX: 512, y: 512).scaledBy(x: 821 / 824, y: 821 / 824).translatedBy(x: -512, y: -512)
        if let edge = tileShape.copy(using: &t) {
            ctx.saveGState(); ctx.addPath(edge); ctx.setStrokeColor(rgb(0xffffff, 0.08)); ctx.setLineWidth(3); ctx.strokePath(); ctx.restoreGState()
        }
    }

    // The page: portrait 1:1.3, a 132 px dog-ear top-right, corners 44.
    private static let pageRect = CGRect(x: 512 - 206, y: 512 - 268, width: 412, height: 536)
    private static let fold: CGFloat = 132

    private static func page(_ r: CGRect, radius R: CGFloat = 44) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: r.minX + R, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - fold, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + fold))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: R)
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: R)
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: R)
        p.closeSubpath()
        return p
    }

    /// The folded-down flap, with a soft inner corner.
    private static func flap(_ r: CGRect, radius rad: CGFloat = 30) -> CGPath {
        let p = CGMutablePath(), f = fold
        p.move(to: CGPoint(x: r.maxX - f, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - f, y: r.minY + f - rad))
        p.addArc(tangent1End: CGPoint(x: r.maxX - f, y: r.minY + f), tangent2End: CGPoint(x: r.maxX, y: r.minY + f), radius: rad)
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + f))
        p.closeSubpath()
        return p
    }

    /// The n: a crisp lowercase n with a flat top (the notch between stem and shoulder filled) and slightly
    /// rounded corners. Returned as fill paths, placed so its box centre lands on `c`.
    private static func letter(at c: CGPoint) -> [CGPath] {
        let span: CGFloat = 184, strokeW: CGFloat = 89, height: CGFloat = 258, r: CGFloat = 11
        let st = strokeW - 2 * r, h = height - 2 * r
        let top = -h + st / 2, joinY = top + span * 0.5
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 0, y: joinY))
        let a = span / 2, b = joinY - top
        for i in 0...96 {   // the shoulder: half an ellipse from the stem over to the right leg
            let t = CGFloat.pi + CGFloat(i) / 96 * .pi
            p.addLine(to: CGPoint(x: a + a * cos(t), y: joinY + b * sin(t)))
        }
        p.addLine(to: CGPoint(x: span, y: 0))
        p.move(to: CGPoint(x: 0, y: joinY)); p.addLine(to: CGPoint(x: 0, y: top - st / 2))   // the stem's top
        let stroked = p.copy(strokingWithWidth: st, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
        let bridge = CGPath(rect: CGRect(x: -st / 2, y: -h, width: st / 2 + span / 2, height: st), transform: nil)
        let body = CGMutablePath(); body.addPath(stroked); body.addPath(bridge)
        let soft = body.copy(strokingWithWidth: 2 * r, lineCap: .round, lineJoin: .round, miterLimit: 10)
        let box = stroked.boundingBoxOfPath.insetBy(dx: -r, dy: -r)
        var t = CGAffineTransform(translationX: c.x - box.midX, y: c.y - box.midY)
        return [stroked, bridge, soft].compactMap { $0.copy(using: &t) }
    }

    /// The page with its fold and the n cut through. In mono the flap is knocked out with a thin gap, so the
    /// fold still reads in the menu bar.
    private static func mark(_ ctx: CGContext, mono: Bool) {
        let r = pageRect
        ctx.saveGState()
        if !mono { ctx.setShadow(offset: CGSize(width: 0, height: -16 * scale), blur: 36 * scale, color: rgb(0x000000, 0.40)) }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.addPath(page(r))
        if mono { ctx.setFillColor(rgb(0x000000)); ctx.fillPath() } else {
            ctx.saveGState(); ctx.clip()
            linear(ctx, [rgb(0xFBF7EC), rgb(0xEFE7D4)], from: CGPoint(x: r.midX, y: r.minY), to: CGPoint(x: r.midX, y: r.maxY))
            ctx.restoreGState()
        }
        if mono {
            ctx.saveGState(); ctx.setBlendMode(.clear)
            ctx.addPath(flap(r)); ctx.setLineWidth(10); ctx.setStrokeColor(rgb(0, 1)); ctx.addPath(flap(r)); ctx.drawPath(using: .fillStroke)
            ctx.restoreGState()
        } else {
            ctx.addPath(flap(r)); ctx.setFillColor(rgb(0xD6C9AA)); ctx.fillPath()
        }
        ctx.saveGState(); ctx.setBlendMode(.clear)
        for q in letter(at: CGPoint(x: r.midX - 6, y: r.midY + 40)) { ctx.addPath(q); ctx.fillPath() }
        ctx.restoreGState()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
}
