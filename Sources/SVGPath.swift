import AppKit

enum SVGPath {
    static func fill(_ d: String, viewBox: CGFloat = 24, in rect: CGRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let path = bezier(from: d)
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: rect.width / viewBox, y: -rect.height / viewBox)
        ctx.addPath(path.cgPath)
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()
    }

    static func bezier(from d: String) -> NSBezierPath {
        let path = NSBezierPath()
        path.windingRule = .evenOdd
        var i = d.startIndex
        var command: Character = " "
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastCubic = CGPoint.zero
        var lastQuad = CGPoint.zero

        func peek() -> Character? {
            guard i < d.endIndex else { return nil }
            return d[i]
        }

        func skip() {
            while let c = peek(), c == " " || c == "," || c == "\n" || c == "\t" || c == "\r" {
                i = d.index(after: i)
            }
        }

        func isCommand(_ c: Character) -> Bool {
            "MmLlHhVvCcSsQqTtAaZz".contains(c)
        }

        func readNumber() -> CGFloat? {
            skip()
            guard i < d.endIndex else { return nil }
            let startIndex = i
            if peek() == "+" || peek() == "-" {
                i = d.index(after: i)
            }
            var sawDigit = false
            while let c = peek(), c.isNumber {
                sawDigit = true
                i = d.index(after: i)
            }
            if peek() == "." {
                i = d.index(after: i)
                while let c = peek(), c.isNumber {
                    sawDigit = true
                    i = d.index(after: i)
                }
            }
            if let c = peek(), c == "e" || c == "E" {
                i = d.index(after: i)
                if peek() == "+" || peek() == "-" {
                    i = d.index(after: i)
                }
                while let dgt = peek(), dgt.isNumber {
                    i = d.index(after: i)
                }
            }
            guard sawDigit, let value = Double(d[startIndex..<i]) else {
                i = startIndex
                return nil
            }
            return CGFloat(value)
        }

        func readFlag() -> Bool {
            skip()
            if peek() == "+" || peek() == "-" {
                return (readNumber() ?? 0) != 0
            }
            if let c = peek(), c == "0" || c == "1" {
                i = d.index(after: i)
                return c == "1"
            }
            return (readNumber() ?? 0) != 0
        }

        func readPoint(relative: Bool) -> CGPoint? {
            guard let x = readNumber(), let y = readNumber() else { return nil }
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        while i < d.endIndex {
            skip()
            guard let c = peek() else { break }
            if isCommand(c) {
                command = c
                i = d.index(after: i)
            } else if command == " " {
                break
            }

            let rel = command.isLowercase
            switch command.lowercased() {
            case "m":
                guard let p = readPoint(relative: rel) else { return path }
                current = p
                start = p
                path.move(to: p)
                lastCubic = current
                lastQuad = current
                command = rel ? "l" : "L"
            case "l":
                guard let p = readPoint(relative: rel) else { return path }
                path.line(to: p)
                current = p
                lastCubic = current
                lastQuad = current
            case "h":
                guard let x = readNumber() else { return path }
                current = CGPoint(x: rel ? current.x + x : x, y: current.y)
                path.line(to: current)
                lastCubic = current
                lastQuad = current
            case "v":
                guard let y = readNumber() else { return path }
                current = CGPoint(x: current.x, y: rel ? current.y + y : y)
                path.line(to: current)
                lastCubic = current
                lastQuad = current
            case "c":
                guard let c1 = readPoint(relative: rel),
                      let c2 = readPoint(relative: rel),
                      let p = readPoint(relative: rel) else { return path }
                path.curve(to: p, controlPoint1: c1, controlPoint2: c2)
                lastCubic = c2
                current = p
                lastQuad = current
            case "s":
                let c1 = CGPoint(x: 2 * current.x - lastCubic.x, y: 2 * current.y - lastCubic.y)
                guard let c2 = readPoint(relative: rel),
                      let p = readPoint(relative: rel) else { return path }
                path.curve(to: p, controlPoint1: c1, controlPoint2: c2)
                lastCubic = c2
                current = p
                lastQuad = current
            case "q":
                guard let c1 = readPoint(relative: rel),
                      let p = readPoint(relative: rel) else { return path }
                path.curve(
                    to: p,
                    controlPoint1: CGPoint(x: current.x + 2 / 3 * (c1.x - current.x), y: current.y + 2 / 3 * (c1.y - current.y)),
                    controlPoint2: CGPoint(x: p.x + 2 / 3 * (c1.x - p.x), y: p.y + 2 / 3 * (c1.y - p.y))
                )
                lastQuad = c1
                current = p
                lastCubic = current
            case "t":
                let c1 = CGPoint(x: 2 * current.x - lastQuad.x, y: 2 * current.y - lastQuad.y)
                guard let p = readPoint(relative: rel) else { return path }
                path.curve(
                    to: p,
                    controlPoint1: CGPoint(x: current.x + 2 / 3 * (c1.x - current.x), y: current.y + 2 / 3 * (c1.y - current.y)),
                    controlPoint2: CGPoint(x: p.x + 2 / 3 * (c1.x - p.x), y: p.y + 2 / 3 * (c1.y - p.y))
                )
                lastQuad = c1
                current = p
                lastCubic = current
            case "a":
                guard let rx = readNumber(), let ry = readNumber(), let rot = readNumber() else { return path }
                let large = readFlag()
                let sweep = readFlag()
                guard let dest = readPoint(relative: rel) else { return path }
                addArc(path, from: current, rx: rx, ry: ry, rotation: rot, large: large, sweep: sweep, to: dest)
                current = dest
                lastCubic = current
                lastQuad = current
            case "z":
                path.close()
                current = start
                lastCubic = current
                lastQuad = current
            default:
                return path
            }
        }
        return path
    }

    private static func addArc(
        _ path: NSBezierPath,
        from: CGPoint,
        rx: CGFloat,
        ry: CGFloat,
        rotation: CGFloat,
        large: Bool,
        sweep: Bool,
        to: CGPoint
    ) {
        var rx = abs(rx)
        var ry = abs(ry)
        if rx < 0.0001 || ry < 0.0001 || from == to {
            path.line(to: to)
            return
        }

        let phi = rotation * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let dx = (from.x - to.x) / 2
        let dy = (from.y - to.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        var rx2 = rx * rx
        var ry2 = ry * ry
        let x1p2 = x1p * x1p
        let y1p2 = y1p * y1p
        let lambda = x1p2 / rx2 + y1p2 / ry2
        if lambda > 1 {
            let s = sqrt(lambda)
            rx *= s
            ry *= s
            rx2 = rx * rx
            ry2 = ry * ry
        }

        let sign: CGFloat = large == sweep ? -1 : 1
        let num = max(rx2 * ry2 - rx2 * y1p2 - ry2 * x1p2, 0)
        let den = rx2 * y1p2 + ry2 * x1p2
        let coef = den == 0 ? 0 : sign * sqrt(num / den)
        let cxp = coef * (rx * y1p / ry)
        let cyp = coef * -(ry * x1p / rx)
        let cx = cosPhi * cxp - sinPhi * cyp + (from.x + to.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (from.y + to.y) / 2

        func vectorAngle(_ u: CGPoint, _ v: CGPoint) -> CGFloat {
            let mag = sqrt((u.x * u.x + u.y * u.y) * (v.x * v.x + v.y * v.y))
            if mag == 0 { return 0 }
            var cosine = (u.x * v.x + u.y * v.y) / mag
            cosine = min(max(cosine, -1), 1)
            let ang = acos(cosine)
            return u.x * v.y - u.y * v.x < 0 ? -ang : ang
        }

        let v1 = CGPoint(x: (x1p - cxp) / rx, y: (y1p - cyp) / ry)
        let v2 = CGPoint(x: (-x1p - cxp) / rx, y: (-y1p - cyp) / ry)
        var startAngle = vectorAngle(CGPoint(x: 1, y: 0), v1)
        var delta = vectorAngle(v1, v2)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        let segments = max(Int(ceil(abs(delta) / (.pi / 2))), 1)
        let increment = delta / CGFloat(segments)
        let handle = (4 / 3) * tan(increment / 4)
        var theta = startAngle
        for _ in 0..<segments {
            let theta2 = theta + increment
            let p1 = ellipsePoint(cx, cy, rx, ry, cosPhi, sinPhi, theta)
            let p2 = ellipsePoint(cx, cy, rx, ry, cosPhi, sinPhi, theta2)
            let t1 = ellipseTangent(rx, ry, cosPhi, sinPhi, theta)
            let t2 = ellipseTangent(rx, ry, cosPhi, sinPhi, theta2)
            path.curve(
                to: p2,
                controlPoint1: CGPoint(x: p1.x + handle * t1.x, y: p1.y + handle * t1.y),
                controlPoint2: CGPoint(x: p2.x - handle * t2.x, y: p2.y - handle * t2.y)
            )
            theta = theta2
            _ = p1
            startAngle = theta2
        }
    }

    private static func ellipsePoint(
        _ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat,
        _ cosPhi: CGFloat, _ sinPhi: CGFloat, _ t: CGFloat
    ) -> CGPoint {
        let x = rx * cos(t)
        let y = ry * sin(t)
        return CGPoint(x: cosPhi * x - sinPhi * y + cx, y: sinPhi * x + cosPhi * y + cy)
    }

    private static func ellipseTangent(
        _ rx: CGFloat, _ ry: CGFloat, _ cosPhi: CGFloat, _ sinPhi: CGFloat, _ t: CGFloat
    ) -> CGPoint {
        let x = -rx * sin(t)
        let y = ry * cos(t)
        return CGPoint(x: cosPhi * x - sinPhi * y, y: sinPhi * x + cosPhi * y)
    }
}
