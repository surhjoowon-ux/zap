// zap — 화면 위에 띄우는 반투명 실측 자
// 빌드: ./build.sh

import AppKit
import Carbon.HIToolbox
import ServiceManagement
import QuartzCore
import UniformTypeIdentifiers

// MARK: - 설정

enum LengthUnit: String { case metric, inch }

extension Notification.Name {
    static let jaSettingsChanged = Notification.Name("jaSettingsChanged")
}

final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    var unit: LengthUnit {
        get { LengthUnit(rawValue: d.string(forKey: "unit") ?? "") ?? .metric }
        set { d.set(newValue.rawValue, forKey: "unit"); changed() }
    }
    var opacity: CGFloat {
        get { d.object(forKey: "opacity") == nil ? 0.55 : CGFloat(d.double(forKey: "opacity")) }
        set { d.set(Double(min(0.95, max(0.15, newValue))), forKey: "opacity"); changed() }
    }
    var thickness: CGFloat {
        get { d.object(forKey: "thickness") == nil ? 80 : CGFloat(d.double(forKey: "thickness")) }
        set { d.set(Double(min(160, max(40, newValue))), forKey: "thickness"); changed() }
    }
    var color: NSColor {
        get {
            let a = d.array(forKey: "color") as? [Double] ?? [1, 1, 1]
            return NSColor(srgbRed: a[0], green: a[1], blue: a[2], alpha: 1)
        }
        set {
            let c = newValue.usingColorSpace(.sRGB) ?? .white
            d.set([Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)], forKey: "color"); changed()
        }
    }
    var color2: NSColor {
        get {
            let a = d.array(forKey: "color2") as? [Double] ?? [0.62, 0.78, 1]
            return NSColor(srgbRed: a[0], green: a[1], blue: a[2], alpha: 1)
        }
        set {
            let c = newValue.usingColorSpace(.sRGB) ?? .white
            d.set([Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)], forKey: "color2"); changed()
        }
    }
    var gradient: Bool { get { d.bool(forKey: "gradient") } set { d.set(newValue, forKey: "gradient"); changed() } }
    private func flag(_ k: String) -> Bool { d.object(forKey: k) == nil ? true : d.bool(forKey: k) }
    var showReal: Bool { get { flag("showReal") } set { d.set(newValue, forKey: "showReal"); changed() } }
    var showPx: Bool { get { flag("showPx") } set { d.set(newValue, forKey: "showPx"); changed() } }
    var snap90: Bool { get { flag("snap90") } set { d.set(newValue, forKey: "snap90"); changed() } }
    /// 자에 깔 사진 (앱 지원 폴더에 복사본 보관)
    var imagePath: String? {
        get { d.string(forKey: "imagePath") }
        set { if let v = newValue { d.set(v, forKey: "imagePath") } else { d.removeObject(forKey: "imagePath") }; cachedImage = nil; changed() }
    }
    private var cachedImage: (NSImage, CGFloat)?
    /// 사진과 평균 밝기
    var image: (NSImage, CGFloat)? {
        if let c = cachedImage { return c }
        guard let p = imagePath, let img = NSImage(contentsOfFile: p) else { return nil }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        img.draw(in: NSRect(x: 0, y: 0, width: 1, height: 1))
        NSGraphicsContext.restoreGraphicsState()
        let lum = rep.colorAt(x: 0, y: 0)?.luminance ?? 1
        cachedImage = (img, lum)
        return cachedImage
    }
    func resetLook() {
        imagePath = nil
        for k in ["opacity", "thickness", "color", "color2", "gradient", "showReal", "showPx", "snap90", "unit"] { d.removeObject(forKey: k) }
        changed()
    }
    func changed() { NotificationCenter.default.post(name: .jaSettingsChanged, object: nil) }
}

// MARK: - 화면 물리 크기

enum Display {
    enum Source { case calibrated, auto, guess }

    static func id(_ s: NSScreen) -> CGDirectDisplayID {
        (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }
    static func key(_ s: NSScreen) -> String {
        let i = id(s)
        return "cal-\(CGDisplayVendorNumber(i))-\(CGDisplayModelNumber(i))-\(CGDisplaySerialNumber(i))-\(Int(s.frame.width))x\(Int(s.frame.height))"
    }
    /// 디스플레이가 알려주는 물리 크기(mm) ÷ 논리 해상도(pt)
    static func autoMMPerPt(_ s: NSScreen) -> CGFloat? {
        let size = CGDisplayScreenSize(id(s))
        guard size.width > 50, s.frame.width > 0 else { return nil }
        let v = size.width / s.frame.width
        let ppi = 25.4 / v
        guard ppi > 40, ppi < 400 else { return nil }  // TV·프로젝터의 엉터리 EDID 걸러냄
        return v
    }
    static func mmPerPt(_ screen: NSScreen?) -> CGFloat {
        guard let s = screen ?? NSScreen.main else { return 25.4 / 96 }
        if let v = UserDefaults.standard.object(forKey: key(s)) as? Double, v > 0 { return CGFloat(v) }
        return autoMMPerPt(s) ?? 25.4 / 96
    }
    static func source(_ s: NSScreen) -> Source {
        if UserDefaults.standard.object(forKey: key(s)) != nil { return .calibrated }
        return autoMMPerPt(s) != nil ? .auto : .guess
    }
    static func save(_ mmPerPt: CGFloat, for s: NSScreen) {
        UserDefaults.standard.set(Double(mmPerPt), forKey: key(s))
        Settings.shared.changed()
    }
    static func reset(_ s: NSScreen) {
        UserDefaults.standard.removeObject(forKey: key(s))
        Settings.shared.changed()
    }
    static func name(_ s: NSScreen) -> String {
        if #available(macOS 10.15, *) { return s.localizedName }
        return "Display"
    }
}

// MARK: - 포맷

enum Fmt {
    static func len(_ mm: CGFloat) -> String {
        Settings.shared.unit == .inch ? String(format: "%.2f in", mm / 25.4) : String(format: "%.1f mm", mm)
    }
    static func pair(_ a: CGFloat, _ b: CGFloat) -> String {
        Settings.shared.unit == .inch
            ? String(format: "%.2f × %.2f in", a / 25.4, b / 25.4)
            : String(format: "%.1f × %.1f mm", a, b)
    }
    static func px(_ v: CGFloat) -> String {
        let r = (v * 2).rounded() / 2
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
    }
}

func pixelRound(_ v: CGFloat, _ scale: CGFloat) -> CGFloat { (v * scale).rounded() / scale }

extension NSColor {
    var luminance: CGFloat {
        let c = usingColorSpace(.sRGB) ?? .white
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
    }
}

let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)

func drawLabel(_ s: String, at p: NSPoint, anchor: (CGFloat, CGFloat), attrs: [NSAttributedString.Key: Any]) {
    let str = s as NSString
    let sz = str.size(withAttributes: attrs)
    str.draw(at: NSPoint(x: p.x - sz.width * anchor.0, y: p.y - sz.height * anchor.1), withAttributes: attrs)
}

func pillSize(_ lines: [NSAttributedString]) -> NSSize {
    let sizes = lines.map { $0.size() }
    return NSSize(width: ceil((sizes.map { $0.width }.max() ?? 0) + 16),
                  height: ceil(sizes.reduce(0) { $0 + $1.height } + CGFloat(max(0, lines.count - 1)) + 10))
}

/// 어두운 알약 모양 수치 표시
func drawPill(_ lines: [NSAttributedString], at origin: NSPoint, anchor: (CGFloat, CGFloat), within bounds: NSRect? = nil) -> NSRect {
    let padX: CGFloat = 8, padY: CGFloat = 5, gap: CGFloat = 1
    let sizes = lines.map { $0.size() }
    let w = (sizes.map { $0.width }.max() ?? 0) + padX * 2
    let h = sizes.reduce(0) { $0 + $1.height } + gap * CGFloat(max(0, lines.count - 1)) + padY * 2
    var r = NSRect(x: origin.x - w * anchor.0, y: origin.y - h * anchor.1, width: w, height: h)
    if let b = bounds {
        r.origin.x = min(max(r.origin.x, b.minX + 2), b.maxX - w - 2)
        r.origin.y = min(max(r.origin.y, b.minY + 2), b.maxY - h - 2)
    }
    NSColor(white: 0.08, alpha: 0.88).setFill()
    NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6).fill()
    var y = r.maxY - padY
    for (i, l) in lines.enumerated() {
        y -= sizes[i].height
        l.draw(at: NSPoint(x: r.minX + padX, y: y))
        y -= gap
    }
    return r
}

func pillText(_ s: String, size: CGFloat = 11, weight: NSFont.Weight = .medium, alpha: CGFloat = 1) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(white: 1, alpha: alpha),
    ])
}

// MARK: - 떠 있는 패널

class OverlayPanel: NSPanel {
    init(rect: NSRect, level: NSWindow.Level = .statusBar) {
        super.init(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        self.level = level
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func setFrameSnapped(_ f: NSRect) {
        let s = backingScaleFactor
        setFrame(NSRect(x: pixelRound(f.minX, s), y: pixelRound(f.minY, s),
                        width: pixelRound(f.width, s), height: pixelRound(f.height, s)), display: true)
    }
}

/// 설정이 바뀌거나 화면을 옮기면 다시 그림
class LiveView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(refresh), name: .jaSettingsChanged, object: nil)
        nc.addObserver(self, selector: #selector(refresh), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let w = window else { return }
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(refresh), name: NSWindow.didChangeScreenNotification, object: w)
        nc.addObserver(self, selector: #selector(refresh), name: NSWindow.didChangeBackingPropertiesNotification, object: w)
    }
    @objc func refresh() { needsDisplay = true }

    var currentScreen: NSScreen? { window?.screen ?? NSScreen.main }
    var scale: CGFloat { window?.backingScaleFactor ?? 2 }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        (NSApp.delegate as? AppDelegate)?.fillMenu(m, contextual: true)
        return m
    }
}

// MARK: - 자

/// 자 옆에 붙어 다니는 수치 표시. macOS 26은 리퀴드 글라스, 그 전은 블러. 클릭은 통과.
final class GlassReadout {
    let panel = OverlayPanel(rect: NSRect(x: 0, y: 0, width: 10, height: 10))
    private let label = NSTextField(labelWithString: "")
    private let holder = NSView()
    private var glass: NSView!

    init() {
        panel.ignoresMouseEvents = true
        panel.hasShadow = true
        holder.addSubview(label)
        if #available(macOS 26, *) {
            let g = NSGlassEffectView()
            g.contentView = holder
            glass = g
        } else {
            let v = NSVisualEffectView()
            v.material = .hudWindow; v.state = .active; v.blendingMode = .behindWindow
            v.wantsLayer = true; v.layer?.masksToBounds = true
            v.addSubview(holder)
            glass = v
        }
        panel.contentView = glass
    }

    func update(_ text: NSAttributedString) -> NSSize {
        label.attributedStringValue = text
        let t = label.fittingSize
        let size = NSSize(width: ceil(t.width) + 30, height: ceil(t.height) + 16)
        label.frame = NSRect(x: 15, y: 8, width: ceil(t.width), height: ceil(t.height))
        holder.frame = NSRect(origin: .zero, size: size)
        if #available(macOS 26, *) { (glass as? NSGlassEffectView)?.cornerRadius = size.height / 2 }
        else { glass.layer?.cornerRadius = size.height / 2 }
        return size
    }
}

func glassText(_ s: String, size: CGFloat, weight: NSFont.Weight, secondary: Bool = false) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight),
        .foregroundColor: secondary ? NSColor.secondaryLabelColor : NSColor.labelColor,
    ])
}

/// 자는 화면 좌표의 0점 모서리(origin), 각도(angle), 길이(len)로 정의된다.
/// 창은 돌아간 자를 감싸는 사각형이고, 자 바깥의 투명한 부분은 클릭이 뒤로 통과한다.
/// 로컬 좌표: u = 0점에서 길이 방향, v = 실측(cm) 모서리에서 안쪽 방향
final class RulerView: LiveView {
    var origin = NSPoint.zero
    var angle: CGFloat = 0
    var len: CGFloat = 600
    var T: CGFloat { Settings.shared.thickness }
    var hoverU: CGFloat?
    /// 첫 클릭 = 시작점, 두 번째 클릭 = 끝점 고정, 그다음 클릭 = 새로 시작
    var markU: CGFloat?
    var endU: CGFloat?
    private var beforeClick: (CGFloat?, CGFloat?) = (nil, nil)
    /// 지금 보여 줄 끝 위치: 고정된 끝점, 아니면 재는 중일 때만 마우스
    var liveEnd: CGFloat? { markU == nil ? nil : (endU ?? hoverU) }
    private var rotating = false
    /// 자 밖(다른 앱 포함)을 누르면 잰 것 지우기
    private lazy var outsideMonitor: Any? = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
        self?.clearMark()
    }
    func clearMark() {
        guard markU != nil else { return }
        markU = nil; endU = nil; beforeClick = (nil, nil)
        needsDisplay = true
        updateReadout()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        _ = outsideMonitor
    }
    private enum Drag { case none, pending(NSPoint, NSPoint), move(NSPoint, NSPoint), rotate }
    private var drag = Drag.none
    private let grip: CGFloat = 22
    private lazy var readoutGlass = GlassReadout()
    private var readout: OverlayPanel { readoutGlass.panel }
    /// 자 몸통 뒤에 까는 유리 (자 모양으로 마스크)
    var glass: NSView?

    var ud: NSPoint { NSPoint(x: cos(angle), y: sin(angle)) }
    var vd: NSPoint { NSPoint(x: sin(angle), y: -cos(angle)) }
    var axisAligned: Bool { abs(remainder(angle, .pi / 2)) < 1e-6 }
    var degrees: Int {
        var d = Int((-angle * 180 / .pi).rounded()) % 360  // 시계 방향을 +로
        if d < 0 { d += 360 }
        return d
    }

    func screenPt(_ u: CGFloat, _ v: CGFloat) -> NSPoint {
        NSPoint(x: origin.x + u * ud.x + v * vd.x, y: origin.y + u * ud.y + v * vd.y)
    }
    func local(_ p: NSPoint) -> (u: CGFloat, v: CGFloat) {
        let dx = p.x - origin.x, dy = p.y - origin.y
        return (dx * ud.x + dy * ud.y, dx * vd.x + dy * vd.y)
    }
    func inside(_ l: (u: CGFloat, v: CGFloat)) -> Bool { l.u >= 0 && l.u <= len && l.v >= 0 && l.v <= T }

    func snapPt(_ p: NSPoint) -> NSPoint { NSPoint(x: pixelRound(p.x, scale), y: pixelRound(p.y, scale)) }

    /// 모델이 바뀌면 창 크기를 다시 맞춤
    func layoutWindow() {
        guard let w = window else { return }
        let c = [screenPt(0, 0), screenPt(len, 0), screenPt(0, T), screenPt(len, T)]
        let s = scale
        let minX = floor((c.map { $0.x }.min()! - 2) * s) / s, maxX = ceil((c.map { $0.x }.max()! + 2) * s) / s
        let minY = floor((c.map { $0.y }.min()! - 2) * s) / s, maxY = ceil((c.map { $0.y }.max()! + 2) * s) / s
        let f = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        if f != w.frame { w.setFrame(f, display: false) }
        updateGlass()
        needsDisplay = true
        updateReadout()
    }

    var bodyIsDark: Bool {
        if let (_, lum) = Settings.shared.image { return lum < 0.5 }
        let st = Settings.shared
        let lum = st.gradient ? (st.color.luminance + st.color2.luminance) / 2 : st.color.luminance
        return lum < 0.5
    }
    static let radius: CGFloat = 9

    func bodyPath(in wf: NSRect) -> CGPath {
        let t = CGAffineTransform(translationX: origin.x - wf.minX, y: origin.y - wf.minY).rotated(by: angle)
        let p = CGMutablePath()
        p.addRoundedRect(in: CGRect(x: 0, y: -T, width: len, height: T), cornerWidth: RulerView.radius, cornerHeight: RulerView.radius, transform: t)
        return p
    }

    private func updateGlass() {
        guard let g = glass, let w = window else { return }
        w.appearance = NSAppearance(named: bodyIsDark ? .darkAqua : .aqua)
        g.frame = g.superview?.bounds ?? bounds
        let path = bodyPath(in: w.frame)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if #available(macOS 26, *) {
            g.wantsLayer = true
            let m = (g.layer?.mask as? CAShapeLayer) ?? CAShapeLayer()
            m.frame = g.bounds
            m.path = path
            g.layer?.mask = m
        } else if let v = g as? NSVisualEffectView {
            let size = g.bounds.size
            v.maskImage = NSImage(size: size, flipped: false) { _ in
                NSColor.black.setFill()
                NSGraphicsContext.current?.cgContext.addPath(path)
                NSGraphicsContext.current?.cgContext.fillPath()
                return true
            }
        }
        CATransaction.commit()
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self))
    }

    override func refresh() { layoutWindow() }

    override func draw(_ dirtyRect: NSRect) {
        guard let wf = window?.frame else { return }
        let st = Settings.shared
        let L = len, s = scale
        let mmpp = Display.mmPerPt(currentScreen)
        let inch = st.unit == .inch
        let red = NSColor(calibratedRed: 1, green: 0.18, blue: 0.2, alpha: 1)
        let base = st.color
        let dark = bodyIsDark
        let inkColor = NSColor(white: dark ? 1 : 0, alpha: 0.9)

        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: origin.x - wf.minX, yBy: origin.y - wf.minY)
        t.rotate(byRadians: angle)
        t.concat()

        // 로컬: x = u, y = -v
        let R = RulerView.radius
        let bodyRect = NSRect(x: 0, y: -T, width: L, height: T)
        let body = NSBezierPath(roundedRect: bodyRect, xRadius: R, yRadius: R)
        NSGraphicsContext.saveGraphicsState()
        body.addClip()
        if let (img, _) = st.image, img.size.width > 0, img.size.height > 0 {
            // 한 줄로: 높이 = 자 두께, 길이는 cm 단위로 잘라 반복 (2.4cm → 2cm). 1cm보다 좁으면 1cm에 맞춰 위아래를 자름.
            let cm = 10 / mmpp, iw = img.size.width, ih = img.size.height
            let n = max(1, floor(iw / ih * T / cm + 0.05))
            let w = n * cm
            var src = NSRect(x: 0, y: 0, width: iw, height: ih)
            if iw / ih >= w / T {
                src.size.width = ih * w / T; src.origin.x = (iw - src.width) / 2
            } else {
                src.size.height = iw * T / w; src.origin.y = (ih - src.height) / 2
            }
            var x: CGFloat = 0
            while x < L {
                img.draw(in: NSRect(x: x, y: -T, width: w, height: T), from: src, operation: .sourceOver, fraction: st.opacity)
                x += w
            }
        } else if st.gradient {
            NSGradient(starting: base.withAlphaComponent(st.opacity * 0.6), ending: st.color2.withAlphaComponent(st.opacity * 0.6))!
                .draw(in: bodyRect, angle: 0)
        } else {
            base.withAlphaComponent(st.opacity * 0.6).setFill()
            bodyRect.fill()
        }
        // 유리 광택: 위쪽 반사, 아래쪽 은은한 빛
        NSGradient(colors: [NSColor(white: 1, alpha: dark ? 0.22 : 0.5), NSColor(white: 1, alpha: 0)])!
            .draw(in: NSRect(x: 0, y: -T * 0.45, width: L, height: T * 0.45), angle: -90)
        NSGradient(colors: [NSColor(white: 1, alpha: 0), NSColor(white: 1, alpha: dark ? 0.08 : 0.18)])!
            .draw(in: NSRect(x: 0, y: -T, width: L, height: T * 0.3), angle: -90)
        NSGraphicsContext.restoreGraphicsState()
        // 테두리: 안쪽 밝은 림 + 바깥 얇은 그늘
        let rim = NSBezierPath(roundedRect: bodyRect.insetBy(dx: 0.75, dy: 0.75), xRadius: R - 0.75, yRadius: R - 0.75)
        rim.lineWidth = 1.5
        NSColor(white: 1, alpha: dark ? 0.35 : 0.85).setStroke()
        rim.stroke()
        let edge = NSBezierPath(roundedRect: bodyRect, xRadius: R, yRadius: R)
        edge.lineWidth = 1 / s
        NSColor(white: 0, alpha: dark ? 0.4 : 0.14).setStroke()
        edge.stroke()

        if let a = markU, let b = liveEnd {
            red.withAlphaComponent(0.15).setFill()
            NSRect(x: min(a, b), y: -T, width: abs(b - a), height: T).fill()
        }

        let ticks = NSBezierPath()
        func tick(_ u: CGFloat, _ v0: CGFloat, _ v1: CGFloat) {
            let x = axisAligned ? (floor(u * s) + 0.5) / s : u
            ticks.move(to: NSPoint(x: x, y: -v0)); ticks.line(to: NSPoint(x: x, y: -v1))
        }
        let flip = cos(angle) < -0.01  // 거꾸로 서면 글자만 뒤집음
        func label(_ str: String, _ u: CGFloat, _ vc: CGFloat, _ attrs: [NSAttributedString.Key: Any]) {
            let ns = str as NSString
            let sz = ns.size(withAttributes: attrs)
            NSGraphicsContext.saveGraphicsState()
            let lt = NSAffineTransform()
            lt.translateX(by: u, yBy: -vc)
            if flip { lt.rotate(byDegrees: 180) }
            lt.concat()
            ns.draw(at: NSPoint(x: -sz.width / 2, y: -sz.height / 2), withAttributes: attrs)
            NSGraphicsContext.restoreGraphicsState()
        }
        let ink: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: inkColor]
        let faint: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: inkColor.withAlphaComponent(0.5)]

        // 위 모서리: 실제 길이
        if st.showReal {
            if inch {
                let per = 25.4 / 16 / mmpp
                let n = Int(L / per)
                if n > 0 { for i in 0...n {
                    let h: CGFloat = i % 16 == 0 ? 20 : i % 8 == 0 ? 15 : i % 4 == 0 ? 11 : i % 2 == 0 ? 8 : 5
                    tick(CGFloat(i) * per, 0, h)
                    if i % 16 == 0 && i > 0 { label("\(i / 16)", CGFloat(i) * per, 28, ink) }
                } }
            } else {
                let per = 1 / mmpp
                let n = Int(L / per)
                if n > 0 { for i in 0...n {
                    let h: CGFloat = i % 10 == 0 ? 20 : i % 5 == 0 ? 13 : 7
                    tick(CGFloat(i) * per, 0, h)
                    if i % 10 == 0 && i > 0 { label("\(i / 10)", CGFloat(i) * per, 28, ink) }
                } }
            }
            label(inch ? "in" : "cm", 12, 28, faint)
        }

        // 아래 모서리: 화면 px
        if st.showPx {
            var i = 0
            while i <= Int(L) {
                let h: CGFloat = i % 100 == 0 ? 16 : i % 50 == 0 ? 11 : i % 10 == 0 ? 7 : 4
                tick(CGFloat(i), T, T - h)
                if i % 100 == 0 && i > 0 { label("\(i)", CGFloat(i), T - 23, ink) }
                i += 5
            }
            label("px", 12, T - 23, faint)
        }

        inkColor.setStroke()
        ticks.lineWidth = 1 / s
        ticks.stroke()

        // 끝 손잡이 (드래그 = 돌리기 + 늘이기)
        let g = NSBezierPath(ovalIn: NSRect(x: L - grip / 2 - 5, y: -T / 2 - 5, width: 10, height: 10))
        inkColor.withAlphaComponent(0.35).setStroke()
        g.lineWidth = 1.2
        g.stroke()

        if let a = markU { NSColor(white: dark ? 1 : 0, alpha: 0.95).setFill(); NSRect(x: a, y: -T, width: 1 / s, height: T).fill() }
        if let hu = liveEnd { red.setFill(); NSRect(x: hu, y: -T, width: 1 / s, height: T).fill() }

        NSGraphicsContext.restoreGraphicsState()
    }

    // 수치 표시
    func updateReadout() {
        guard let w = window, w.isVisible else { hideReadout(); return }
        let mmpp = Display.mmPerPt(currentScreen)
        var lines: [NSAttributedString] = []
        var at: CGFloat
        if rotating {
            lines = [glassText("\(degrees)°   \(Fmt.len(len * mmpp))", size: 15, weight: .semibold)]
            at = len
        } else if let a = markU, let hu = liveEnd {
            let d = abs(hu - a)
            let l = NSMutableAttributedString(attributedString: glassText(Fmt.len(d * mmpp), size: 15, weight: .semibold))
            l.append(glassText("   \(Fmt.px(d)) px", size: 12, weight: .medium, secondary: true))
            lines = [l]
            at = hu
        } else { hideReadout(); return }
        let size = readoutGlass.update(lines[0])
        let half = abs(vd.x) * size.width / 2 + abs(vd.y) * size.height / 2 + 10
        var c = screenPt(at, T + half)
        let vf = w.screen?.visibleFrame ?? w.frame
        if !vf.insetBy(dx: size.width / 2, dy: size.height / 2).contains(c) { c = screenPt(at, -half) }
        var o = NSPoint(x: c.x - size.width / 2, y: c.y - size.height / 2)
        o.x = min(max(o.x, vf.minX + 4), vf.maxX - size.width - 4)
        o.y = min(max(o.y, vf.minY + 4), vf.maxY - size.height - 4)
        readout.setFrame(NSRect(origin: o, size: size), display: true)
        if readout.parent == nil { w.addChildWindow(readout, ordered: .above) }
        readout.orderFront(nil)
    }
    func hideReadout() { readout.orderOut(nil) }

    private func track(_ p: NSPoint) {
        let l = local(p)
        hoverU = inside(l) ? pixelRound(l.u, scale) : nil
        if !inside(l) { NSCursor.arrow.set() }
        else if l.u > len - grip { NSCursor.openHand.set() }
        else { NSCursor.crosshair.set() }
        needsDisplay = true
        updateReadout()
    }
    override func cursorUpdate(with event: NSEvent) { track(NSEvent.mouseLocation) }
    override func mouseMoved(with e: NSEvent) { track(NSEvent.mouseLocation) }
    override func mouseExited(with e: NSEvent) { hoverU = nil; needsDisplay = true; updateReadout() }

    override func mouseDown(with e: NSEvent) {
        let m = NSEvent.mouseLocation
        let l = local(m)
        guard inside(l) else { drag = .none; clearMark(); return }
        window?.makeKey()
        window?.makeFirstResponder(self)
        if e.clickCount == 2 {  // 첫 클릭이 찍은 시작점은 되돌림
            (markU, endU) = beforeClick
            drag = .none
            rotate(by: -.pi / 2)
            return
        }
        if l.u > len - grip {
            drag = .rotate
            rotating = true
            NSCursor.closedHand.set()
        } else {
            drag = .pending(m, origin)
        }
    }
    override func mouseDragged(with e: NSEvent) {
        let m = NSEvent.mouseLocation
        if case .pending(let s, let o) = drag {
            guard hypot(m.x - s.x, m.y - s.y) > 3 else { return }
            drag = .move(s, o)
            NSCursor.closedHand.set()
        }
        switch drag {
        case .move(let s, let o):
            origin = snapPt(NSPoint(x: o.x + m.x - s.x, y: o.y + m.y - s.y))
            layoutWindow()
        case .rotate:
            // 0점을 축으로 끝을 마우스에 붙임
            let dx = m.x - origin.x, dy = m.y - origin.y
            var a = atan2(dy, dx)
            let step: CGFloat = e.modifierFlags.contains(.shift) ? .pi / 12 : .pi / 2
            let nearest = (a / step).rounded() * step
            if e.modifierFlags.contains(.shift) || (Settings.shared.snap90 && abs(a - nearest) < 4 * .pi / 180) { a = nearest }
            angle = a
            len = max(120, dx * cos(a) + dy * sin(a) + grip / 2)
            hoverU = nil
            layoutWindow()
        default: break
        }
    }
    override func mouseUp(with e: NSEvent) {
        if case .pending = drag {  // 움직이지 않은 클릭 = 시작점
            beforeClick = (markU, endU)
            let u = pixelRound(local(NSEvent.mouseLocation).u, scale)
            if markU == nil || endU != nil { markU = u; endU = nil } else { endU = u }
        }
        drag = .none
        rotating = false
        track(NSEvent.mouseLocation)
    }

    /// 자 가운데를 축으로 돌림. 90° 배수 근처면 정확히 맞춤.
    func rotate(by d: CGFloat) {
        let c = screenPt(len / 2, T / 2)
        var a = angle + d
        let q = (a / (.pi / 2)).rounded() * (.pi / 2)
        if abs(a - q) < 1e-3 { a = q }
        angle = atan2(sin(a), cos(a))
        origin = snapPt(NSPoint(x: c.x - ud.x * len / 2 - vd.x * T / 2, y: c.y - ud.y * len / 2 - vd.y * T / 2))
        hoverU = nil
        layoutWindow()
    }

    func hide() {
        hideReadout()
        window?.orderOut(nil)
    }

    override func keyDown(with e: NSEvent) {
        let step: CGFloat = (e.modifierFlags.contains(.shift) ? 10 : 1) / scale
        var d = NSPoint.zero
        switch Int(e.keyCode) {
        case kVK_LeftArrow: d.x = -step
        case kVK_RightArrow: d.x = step
        case kVK_DownArrow: d.y = -step
        case kVK_UpArrow: d.y = step
        case kVK_Escape:
            if markU != nil { clearMark() } else { hide() }
            return
        default:
            let deg: CGFloat = (e.modifierFlags.contains(.shift) ? 15 : 1) * .pi / 180
            switch e.charactersIgnoringModifiers?.lowercased() {
            case "r": rotate(by: -.pi / 2)
            case "]", "}": rotate(by: -deg)
            case "[", "{": rotate(by: deg)
            case "u": Settings.shared.unit = Settings.shared.unit == .metric ? .inch : .metric
            case "-": Settings.shared.opacity -= 0.1
            case "=", "+": Settings.shared.opacity += 0.1
            default: super.keyDown(with: e)
            }
            return
        }
        origin = NSPoint(x: origin.x + d.x, y: origin.y + d.y)
        layoutWindow()
    }
}

// MARK: - 자 설정 창

final class SettingsController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var controls: [String: NSControl] = [:]

    func show() {
        if window == nil { build() }
        sync()
        let mouse = NSEvent.mouseLocation
        if let sc = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main, let w = window {
            w.setFrameOrigin(NSPoint(x: sc.visibleFrame.maxX - w.frame.width - 40, y: sc.visibleFrame.maxY - w.frame.height - 40))
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    private func build() {
        let W: CGFloat = 380, rowH: CGFloat = 40
        let rows: [(String, NSView)] = [
            ("Color", { () -> NSView in
                let a = NSColorWell(frame: NSRect(x: 0, y: 0, width: 44, height: 24)); a.target = self; a.action = #selector(colorChanged(_:))
                let b = NSColorWell(frame: NSRect(x: 0, y: 0, width: 44, height: 24)); b.target = self; b.action = #selector(color2Changed(_:))
                let g = NSButton(checkboxWithTitle: "Horizontal gradient", target: self, action: #selector(checkChanged(_:)))
                g.identifier = NSUserInterfaceItemIdentifier("gradient")
                for w in [a, b] { w.widthAnchor.constraint(equalToConstant: 44).isActive = true; w.heightAnchor.constraint(equalToConstant: 24).isActive = true }
                controls["color"] = a; controls["color2"] = b; controls["gradient"] = g
                let st = NSStackView(views: [a, b, g]); st.spacing = 8; return st
            }()),
            ("Photo", { () -> NSView in
                let a = NSButton(title: "Choose Photo…", target: self, action: #selector(pickImage)); a.bezelStyle = .rounded
                let b = NSButton(title: "Remove", target: self, action: #selector(removeImage)); b.bezelStyle = .rounded
                controls["removeImage"] = b
                let st = NSStackView(views: [a, b]); st.spacing = 6; return st
            }()),
            ("Opacity", slider("opacity", 15, 95)),
            ("Thickness", slider("thickness", 40, 160)),
            ("Units", { let s = NSSegmentedControl(labels: ["mm · cm", "inch"], trackingMode: .selectOne, target: self, action: #selector(unitChanged(_:))); controls["unit"] = s; return s }()),
            ("Ticks", { () -> NSView in
                let a = NSButton(checkboxWithTitle: "cm (physical length)", target: self, action: #selector(checkChanged(_:)))
                let b = NSButton(checkboxWithTitle: "px (screen)", target: self, action: #selector(checkChanged(_:)))
                a.identifier = NSUserInterfaceItemIdentifier("showReal"); b.identifier = NSUserInterfaceItemIdentifier("showPx")
                controls["showReal"] = a; controls["showPx"] = b
                let st = NSStackView(views: [a, b]); st.spacing = 14; return st
            }()),
            ("Angle", { () -> NSView in
                let c = NSButton(checkboxWithTitle: "Snap to 90°", target: self, action: #selector(checkChanged(_:)))
                c.identifier = NSUserInterfaceItemIdentifier("snap90"); controls["snap90"] = c; return c
            }()),
        ]
        let H = CGFloat(rows.count) * rowH + 70
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: W, height: H), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Ruler Settings"
        w.level = .floating
        w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]  // 다른 데스크톱에 남아 안 보이는 일 방지
        w.isReleasedWhenClosed = false
        let v = w.contentView!
        for (i, (title, ctl)) in rows.enumerated() {
            let y = H - 30 - CGFloat(i + 1) * rowH + 8
            let l = NSTextField(labelWithString: title)
            l.font = .systemFont(ofSize: 13, weight: .medium)
            l.frame = NSRect(x: 20, y: y + 4, width: 70, height: 20)
            v.addSubview(l)
            let sz = ctl.fittingSize
            ctl.frame = NSRect(x: 96, y: y + (28 - max(sz.height, 22)) / 2, width: ctl is NSSlider ? W - 120 : max(sz.width, 44), height: max(sz.height, 22))
            v.addSubview(ctl)
        }
        let reset = NSButton(title: "Restore Defaults", target: self, action: #selector(resetAll))
        reset.bezelStyle = .rounded
        reset.frame = NSRect(x: W - 150, y: 16, width: 130, height: 30)
        v.addSubview(reset)
        let hint = NSTextField(labelWithString: "Drag end handle to rotate · ⇧ 15°")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 20, y: 22, width: W - 170, height: 16)
        v.addSubview(hint)
        window = w
    }
    private func slider(_ key: String, _ lo: Double, _ hi: Double) -> NSSlider {
        let s = NSSlider(value: lo, minValue: lo, maxValue: hi, target: self, action: #selector(sliderChanged(_:)))
        s.identifier = NSUserInterfaceItemIdentifier(key)
        s.isContinuous = true
        controls[key] = s
        return s
    }
    private func sync() {
        let st = Settings.shared
        (controls["color"] as? NSColorWell)?.color = st.color
        (controls["color2"] as? NSColorWell)?.color = st.color2
        (controls["color2"] as? NSColorWell)?.isEnabled = st.gradient
        (controls["gradient"] as? NSButton)?.state = st.gradient ? .on : .off
        (controls["opacity"] as? NSSlider)?.doubleValue = Double(st.opacity * 100)
        (controls["thickness"] as? NSSlider)?.doubleValue = Double(st.thickness)
        (controls["unit"] as? NSSegmentedControl)?.selectedSegment = st.unit == .inch ? 1 : 0
        (controls["showReal"] as? NSButton)?.state = st.showReal ? .on : .off
        (controls["showPx"] as? NSButton)?.state = st.showPx ? .on : .off
        (controls["snap90"] as? NSButton)?.state = st.snap90 ? .on : .off
        controls["removeImage"]?.isEnabled = st.imagePath != nil
    }
    @objc func pickImage() {
        guard let w = window else { return }
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.message = "Choose a photo for the ruler"
        p.beginSheetModal(for: w) { [weak self] r in
            guard r == .OK, let url = p.url else { return }
            let fm = FileManager.default
            let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("zap")
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if let old = Settings.shared.imagePath { try? fm.removeItem(atPath: old) }
            let dst = dir.appendingPathComponent("ruler-\(Int(Date().timeIntervalSince1970)).\(url.pathExtension)")
            if (try? fm.copyItem(at: url, to: dst)) != nil, NSImage(contentsOf: dst) != nil {
                Settings.shared.imagePath = dst.path
            }
            self?.sync()
        }
    }
    @objc func removeImage() {
        if let old = Settings.shared.imagePath { try? FileManager.default.removeItem(atPath: old) }
        Settings.shared.imagePath = nil
        sync()
    }
    @objc func colorChanged(_ c: NSColorWell) { Settings.shared.color = c.color }
    @objc func color2Changed(_ c: NSColorWell) { Settings.shared.color2 = c.color }
    @objc func sliderChanged(_ s: NSSlider) {
        if s.identifier?.rawValue == "opacity" { Settings.shared.opacity = CGFloat(s.doubleValue / 100) }
        else { Settings.shared.thickness = CGFloat(s.doubleValue.rounded()) }
    }
    @objc func unitChanged(_ s: NSSegmentedControl) { Settings.shared.unit = s.selectedSegment == 1 ? .inch : .metric }
    @objc func checkChanged(_ b: NSButton) {
        let on = b.state == .on
        switch b.identifier?.rawValue {
        case "showReal": Settings.shared.showReal = on
        case "showPx": Settings.shared.showPx = on
        case "gradient": Settings.shared.gradient = on; sync()
        default: Settings.shared.snap90 = on
        }
    }
    @objc func resetAll() { Settings.shared.resetLook(); sync() }
}

// MARK: - 화면에서 재기 (사각형 드래그)

final class MeasureView: LiveView {
    var onClose: (() -> Void)?
    var rect: NSRect?
    var mouse: NSPoint?
    private enum Drag { case none, new(NSPoint), move(NSPoint, NSRect), edges(NSPoint, NSRect, CGFloat, CGFloat, CGFloat, CGFloat) }
    private var drag = Drag.none

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate, .mouseEnteredAndExited], owner: self))
    }
    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }
    override func mouseExited(with event: NSEvent) { mouse = nil; needsDisplay = true }

    func snap(_ p: NSPoint) -> NSPoint { NSPoint(x: pixelRound(p.x, scale), y: pixelRound(p.y, scale)) }

    override func draw(_ dirtyRect: NSRect) {
        let s = scale
        let dim = NSBezierPath(rect: bounds)
        if let r = rect { dim.append(NSBezierPath(rect: r)); dim.windingRule = .evenOdd }
        NSColor(white: 0, alpha: 0.22).setFill()
        dim.fill()

        // 십자선
        if let m = mouse, case .none = drag {
            let x = (floor(m.x * s) + 0.5) / s, y = (floor(m.y * s) + 0.5) / s
            let c = NSBezierPath()
            c.move(to: NSPoint(x: x, y: 0)); c.line(to: NSPoint(x: x, y: bounds.height))
            c.move(to: NSPoint(x: 0, y: y)); c.line(to: NSPoint(x: bounds.width, y: y))
            c.lineWidth = 1 / s
            NSColor(white: 1, alpha: 0.55).setStroke()
            c.stroke()
        }

        if let r = rect, r.width > 0 || r.height > 0 {
            // 바깥쪽에 1px 선 → 안쪽 크기가 곧 측정값
            NSColor.black.setFill()
            NSBezierPath(rect: r.insetBy(dx: -2 / s, dy: -2 / s)).fill()
            NSColor.white.setFill()
            NSBezierPath(rect: r.insetBy(dx: -1 / s, dy: -1 / s)).fill()
            NSColor(white: 0, alpha: 0.01).setFill()  // 완전 투명이면 클릭이 뒤로 빠짐
            r.fill(using: .copy)

            // 모서리 손잡이
            NSColor.white.setFill()
            for c in [NSPoint(x: r.minX, y: r.minY), NSPoint(x: r.maxX, y: r.minY), NSPoint(x: r.minX, y: r.maxY), NSPoint(x: r.maxX, y: r.maxY)] {
                let h = NSBezierPath(ovalIn: NSRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6))
                h.fill(); NSColor.black.setStroke(); h.lineWidth = 1; h.stroke()
            }

            let mm = Display.mmPerPt(currentScreen)
            let lines = [
                pillText(Fmt.pair(r.width * mm, r.height * mm), size: 14, weight: .semibold),
                pillText("\(Fmt.px(r.width)) × \(Fmt.px(r.height)) px   ·   @\(Int(s))x  \(Int((r.width * s).rounded())) × \(Int((r.height * s).rounded()))", size: 10.5, alpha: 0.7),
            ]
            let below = r.minY > 60
            _ = drawPill(lines, at: NSPoint(x: r.minX, y: below ? r.minY - 8 : r.maxY + 8), anchor: (0, below ? 1 : 0), within: bounds)
        }

        let help = "Drag to measure  ·  Drag edges/corners to adjust  ·  ← → ↑ ↓ move 1px (⌥ resize, ⇧ ×10)  ·  ⌘C copy  ·  esc close"
        _ = drawPill([pillText(help, size: 11, alpha: 0.85)], at: NSPoint(x: bounds.midX, y: bounds.maxY - 44), anchor: (0.5, 1))
        if let sc = currentScreen, Display.source(sc) == .guess {
            _ = drawPill([pillText("This display doesn't report its physical size, so mm values are estimates. Menu bar ruler icon → Calibrate Display", size: 11)],
                         at: NSPoint(x: bounds.midX, y: bounds.maxY - 72), anchor: (0.5, 1))
        }
    }

    override func mouseMoved(with e: NSEvent) {
        mouse = convert(e.locationInWindow, from: nil)
        NSCursor.crosshair.set()
        needsDisplay = true
    }

    override func mouseDown(with e: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        let p = convert(e.locationInWindow, from: nil)
        if let r = rect {
            let tol: CGFloat = 6
            let near = r.insetBy(dx: -tol, dy: -tol).contains(p)
            let l: CGFloat = abs(p.x - r.minX) < tol ? 1 : 0
            let rt: CGFloat = abs(p.x - r.maxX) < tol ? 1 : 0
            let b: CGFloat = abs(p.y - r.minY) < tol ? 1 : 0
            let t: CGFloat = abs(p.y - r.maxY) < tol ? 1 : 0
            if near && (l + rt + b + t) > 0 { drag = .edges(p, r, l, rt, b, t); return }
            if r.contains(p) { drag = .move(p, r); return }
        }
        let sp = snap(p)
        drag = .new(sp)
        rect = NSRect(origin: sp, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        switch drag {
        case .new(let a):
            var b = snap(p)
            if e.modifierFlags.contains(.shift) {  // 정사각형
                let side = max(abs(b.x - a.x), abs(b.y - a.y))
                b = NSPoint(x: a.x + (b.x >= a.x ? side : -side), y: a.y + (b.y >= a.y ? side : -side))
            }
            rect = NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        case .move(let a, let r0):
            let d = snap(NSPoint(x: p.x - a.x, y: p.y - a.y))
            rect = r0.offsetBy(dx: d.x, dy: d.y)
        case .edges(let a, let r0, let l, let rt, let b, let t):
            let d = snap(NSPoint(x: p.x - a.x, y: p.y - a.y))
            var minX = r0.minX + d.x * l, maxX = r0.maxX + d.x * rt
            var minY = r0.minY + d.y * b, maxY = r0.maxY + d.y * t
            if minX > maxX { swap(&minX, &maxX) }
            if minY > maxY { swap(&minY, &maxY) }
            rect = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case .none: break
        }
        mouse = p
        needsDisplay = true
    }
    override func mouseUp(with e: NSEvent) { drag = .none; needsDisplay = true }
    override func rightMouseDown(with e: NSEvent) { onClose?() }
    override func menu(for event: NSEvent) -> NSMenu? { nil }

    override func keyDown(with e: NSEvent) {
        if Int(e.keyCode) == kVK_Escape { onClose?(); return }
        if e.modifierFlags.contains(.command), e.charactersIgnoringModifiers == "c", let r = rect {
            let mm = Display.mmPerPt(currentScreen)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("\(Fmt.pair(r.width * mm, r.height * mm)) (\(Fmt.px(r.width)) × \(Fmt.px(r.height)) px)", forType: .string)
            return
        }
        guard var r = rect else { return }
        let step: CGFloat = (e.modifierFlags.contains(.shift) ? 10 : 1) / scale
        let resize = e.modifierFlags.contains(.option)
        switch Int(e.keyCode) {
        case kVK_LeftArrow: if resize { r.size.width = max(0, r.width - step) } else { r.origin.x -= step }
        case kVK_RightArrow: if resize { r.size.width += step } else { r.origin.x += step }
        case kVK_DownArrow: if resize { r.origin.y += min(step, r.height); r.size.height = max(0, r.height - step) } else { r.origin.y -= step }
        case kVK_UpArrow: if resize { r.origin.y -= step; r.size.height += step } else { r.origin.y += step }
        default: super.keyDown(with: e); return
        }
        rect = r
        needsDisplay = true
    }
}

final class MeasureController {
    private var windows: [OverlayPanel] = []
    var isOpen: Bool { !windows.isEmpty }

    func show() {
        close()
        let mouse = NSEvent.mouseLocation
        for sc in NSScreen.screens {
            let w = OverlayPanel(rect: sc.frame, level: .screenSaver)
            let v = MeasureView(frame: NSRect(origin: .zero, size: sc.frame.size))
            v.onClose = { [weak self] in self?.close() }
            w.contentView = v
            w.setFrame(sc.frame, display: false)
            w.orderFrontRegardless()
            windows.append(w)
            if sc.frame.contains(mouse) {
                w.makeKey()
                w.makeFirstResponder(v)
            }
        }
        NSCursor.crosshair.set()
    }
    func close() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
    func toggle() { isOpen ? close() : show() }
}

// MARK: - 화면 보정 (카드 맞추기)

final class CalibrationView: LiveView {
    static let cardMM = NSSize(width: 85.60, height: 53.98)  // ISO/IEC 7810 ID-1 (신용·교통카드)
    var cardWidthPt: CGFloat = 0
    var onSave: ((CGFloat) -> Void)?
    var onReset: (() -> Void)?
    private var dragStart: (CGFloat, CGFloat)?
    private let cardOrigin = NSPoint(x: 40, y: 70)

    func resetFromScreen() {
        cardWidthPt = CalibrationView.cardMM.width / Display.mmPerPt(currentScreen)
        needsDisplay = true
    }
    override func refresh() { super.refresh() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); bounds.fill()
        let w = cardWidthPt
        let h = w * CalibrationView.cardMM.height / CalibrationView.cardMM.width
        let r = NSRect(x: cardOrigin.x, y: cardOrigin.y, width: w, height: h)
        let radius = w * 3.18 / 85.6
        let card = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        NSColor(white: 0.5, alpha: 0.15).setFill(); card.fill()
        NSColor.labelColor.setStroke(); card.lineWidth = 1 / scale; card.stroke()
        // 오른쪽 손잡이
        NSColor(calibratedRed: 1, green: 0.18, blue: 0.2, alpha: 1).setFill()
        NSRect(x: r.maxX - 1.5, y: r.minY, width: 3, height: r.height).fill()

        let title: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.labelColor]
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]
        ("Hold a credit card against the screen and drag the red line to match the card's width." as NSString)
            .draw(at: NSPoint(x: 40, y: bounds.height - 40), withAttributes: title)
        ("← →  adjust 1px · hold ⇧ for 10px · height follows automatically" as NSString)
            .draw(at: NSPoint(x: 40, y: bounds.height - 60), withAttributes: body)
        if let sc = currentScreen {
            let auto = Display.autoMMPerPt(sc)
            let src: String
            switch Display.source(sc) {
            case .calibrated: src = "Using calibrated value"
            case .auto: src = "Using auto-detected value"
            case .guess: src = "No size info from this display, using an estimate (calibration recommended)"
            }
            let ppi = 25.4 / (CalibrationView.cardMM.width / w)
            var info = "\(Display.name(sc)) · \(src) · now \(String(format: "%.1f", ppi)) pt/inch"
            if let a = auto { info += String(format: " · auto-detected screen width %.0f mm", a * sc.frame.width) }
            (info as NSString).draw(at: NSPoint(x: 40, y: 34), withAttributes: body)
        }
    }

    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        dragStart = (NSEvent.mouseLocation.x, cardWidthPt)
    }
    override func mouseDragged(with e: NSEvent) {
        guard let (x0, w0) = dragStart else { return }
        cardWidthPt = max(100, w0 + NSEvent.mouseLocation.x - x0)
        needsDisplay = true
    }
    override func keyDown(with e: NSEvent) {
        let step: CGFloat = (e.modifierFlags.contains(.shift) ? 10 : 1) / scale
        switch Int(e.keyCode) {
        case kVK_LeftArrow: cardWidthPt = max(100, cardWidthPt - step)
        case kVK_RightArrow: cardWidthPt += step
        case kVK_Return: onSave?(cardWidthPt); return
        case kVK_Escape: window?.close(); return
        default: super.keyDown(with: e); return
        }
        needsDisplay = true
    }
    override func menu(for event: NSEvent) -> NSMenu? { nil }
}

final class CalibrationController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        let mouse = NSEvent.mouseLocation
        let sc = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main!
        let size = NSSize(width: min(760, sc.visibleFrame.width - 40), height: 520)
        let w = window ?? NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Calibrate Display"
        w.level = .floating
        w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]  // 다른 데스크톱에 남아 안 보이는 일 방지
        w.isReleasedWhenClosed = false
        w.delegate = self
        let v = CalibrationView(frame: NSRect(origin: .zero, size: size))
        let save = NSButton(title: "Save", target: self, action: #selector(save))
        save.keyEquivalent = "\r"
        save.bezelStyle = .rounded
        let reset = NSButton(title: "Revert to Auto", target: self, action: #selector(reset))
        reset.bezelStyle = .rounded
        save.frame = NSRect(x: size.width - 120, y: 24, width: 90, height: 30)
        reset.frame = NSRect(x: size.width - 300, y: 24, width: 170, height: 30)
        v.addSubview(save); v.addSubview(reset)
        w.contentView = v
        w.setFrameOrigin(NSPoint(x: sc.visibleFrame.midX - size.width / 2, y: sc.visibleFrame.midY - size.height / 2))
        window = w
        v.resetFromScreen()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(v)
    }
    func windowDidChangeScreen(_ n: Notification) { (window?.contentView as? CalibrationView)?.resetFromScreen() }

    @objc func save() {
        guard let w = window, let v = w.contentView as? CalibrationView, let sc = w.screen else { return }
        Display.save(CalibrationView.cardMM.width / v.cardWidthPt, for: sc)
        w.close()
    }
    @objc func reset() {
        guard let w = window, let v = w.contentView as? CalibrationView, let sc = w.screen else { return }
        Display.reset(sc)
        v.resetFromScreen()
    }
}

// MARK: - 전역 단축키

enum HotKeys {
    static var handlers: [UInt32: () -> Void] = [:]
    static var refs: [EventHotKeyRef] = []

    static func install() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let id = hk.id
            DispatchQueue.main.async { HotKeys.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
    static func register(_ id: UInt32, key: Int, _ handler: @escaping () -> Void) {
        handlers[id] = handler
        var ref: EventHotKeyRef?
        let hid = EventHotKeyID(signature: OSType(0x4A615275), id: id)  // 'JaRu'
        if RegisterEventHotKey(UInt32(key), UInt32(controlKey | optionKey), hid, GetApplicationEventTarget(), 0, &ref) == noErr, let r = ref {
            refs.append(r)
        }
    }
}

// MARK: - 앱

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var ruler: OverlayPanel!
    var rulerView: RulerView!
    let measure = MeasureController()
    let calibration = CalibrationController()
    let settings = SettingsController()

    func applicationDidFinishLaunching(_ n: Notification) {
        // 예전 이름(JaRuler) 때 저장한 설정·화면 보정값을 한 번 옮겨 옴
        let ud = UserDefaults.standard
        if !ud.bool(forKey: "migratedFromJaRuler"), let old = ud.persistentDomain(forName: "app.jaruler.JaRuler") {
            for (k, v) in old where ud.object(forKey: k) == nil { ud.set(v, forKey: k) }
        }
        ud.set(true, forKey: "migratedFromJaRuler")
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = statusItem.button {
            let img = NSImage(systemSymbolName: "ruler", accessibilityDescription: "zap")
            img?.isTemplate = true
            b.image = img
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // 자
        let sc = NSScreen.main!
        let len = min(sc.visibleFrame.width - 120, 200 / Display.mmPerPt(sc))
        ruler = OverlayPanel(rect: NSRect(x: 0, y: 0, width: 100, height: 100))
        rulerView = RulerView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        rulerView.autoresizingMask = [.width, .height]
        let container = NSView(frame: rulerView.frame)
        let glass: NSView
        if #available(macOS 26, *) {
            let g = NSGlassEffectView(frame: container.bounds)
            g.style = .clear
            glass = g
        } else {
            let v = NSVisualEffectView(frame: container.bounds)
            v.material = .popover; v.state = .active; v.blendingMode = .behindWindow
            glass = v
        }
        glass.autoresizingMask = [.width, .height]
        container.addSubview(glass)
        container.addSubview(rulerView)
        rulerView.glass = glass
        ruler.contentView = container
        rulerView.len = len
        rulerView.origin = NSPoint(x: (sc.visibleFrame.midX - len / 2).rounded(), y: sc.visibleFrame.midY.rounded())
        rulerView.layoutWindow()

        HotKeys.install()
        HotKeys.register(1, key: kVK_ANSI_R) { [weak self] in self?.toggleRuler() }
        HotKeys.register(2, key: kVK_ANSI_M) { [weak self] in self?.measure.toggle() }

        showRuler()
    }

    func showRuler() {
        // 마우스가 있는 화면에 자가 없으면 그 화면 가운데로 데려옴
        let mouse = NSEvent.mouseLocation
        if let sc = NSScreen.screens.first(where: { $0.frame.contains(mouse) }), !sc.frame.intersects(ruler.frame) {
            rulerView.origin = NSPoint(x: (sc.visibleFrame.midX - rulerView.len / 2).rounded(), y: sc.visibleFrame.midY.rounded())
        }
        ruler.orderFrontRegardless()
        rulerView.layoutWindow()
        ruler.makeKey()
        ruler.makeFirstResponder(rulerView)
    }
    @objc func toggleRuler() { ruler.isVisible ? rulerView.hide() : showRuler() }
    @objc func toggleLoginItem() {
        guard #available(macOS 13, *) else { return }
        let svc = SMAppService.mainApp
        if svc.status == .enabled { try? svc.unregister() } else { try? svc.register() }
    }
    @objc func openMeasure() { measure.show() }
    @objc func rotateRuler() { if !ruler.isVisible { toggleRuler() }; rulerView.rotate(by: -.pi / 2) }
    @objc func openCalibration() { calibration.show() }
    @objc func openSettings() { settings.show() }
    @objc func setUnit(_ i: NSMenuItem) { Settings.shared.unit = (i.representedObject as? String) == "inch" ? .inch : .metric }
    @objc func setOpacity(_ i: NSMenuItem) { Settings.shared.opacity = CGFloat((i.representedObject as? Double) ?? 0.55) }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        fillMenu(menu, contextual: false)
    }

    func fillMenu(_ m: NSMenu, contextual: Bool) {
        @discardableResult func add(_ title: String, _ sel: Selector?, key: String = "", to menu: NSMenu = m) -> NSMenuItem {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            it.target = self
            if !key.isEmpty { it.keyEquivalentModifierMask = [.control, .option] }
            menu.addItem(it)
            return it
        }
        let st = Settings.shared
        add(ruler.isVisible ? "Hide Ruler" : "Show Ruler", #selector(toggleRuler), key: "r")
        add("Rotate Ruler 90°", #selector(rotateRuler))
        add("Measure Screen", #selector(openMeasure), key: "m")
        m.addItem(.separator())

        let unit = NSMenu()
        add("mm · cm", #selector(setUnit(_:)), to: unit).state = st.unit == .metric ? .on : .off
        let inch = add("inch", #selector(setUnit(_:)), to: unit)
        inch.representedObject = "inch"; inch.state = st.unit == .inch ? .on : .off
        add("Units", nil).submenu = unit

        let op = NSMenu()
        for v in [0.3, 0.45, 0.55, 0.7, 0.85] {
            let it = add("\(Int(v * 100))%", #selector(setOpacity(_:)), to: op)
            it.representedObject = v
            it.state = abs(Double(st.opacity) - v) < 0.051 ? .on : .off
        }
        add("Ruler Opacity", nil).submenu = op

        m.addItem(.separator())
        add("Ruler Settings…", #selector(openSettings))
        add("Calibrate Display…", #selector(openCalibration))
        if !contextual {
            m.addItem(.separator())
            if #available(macOS 13, *) {
                add("Open at Login", #selector(toggleLoginItem)).state = SMAppService.mainApp.status == .enabled ? .on : .off
            }
            let help = add("Shortcuts  ⌃⌥R toggle ruler · ⌃⌥M measure screen", nil)
            help.isEnabled = false
            let q = NSMenuItem(title: "Quit zap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            m.addItem(q)
            m.addItem(.separator())
            let credit = NSMenuItem(title: "Standing Studio", action: nil, keyEquivalent: "")
            credit.attributedTitle = NSAttributedString(string: "Standing Studio", attributes: [
                .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.tertiaryLabelColor])
            credit.isEnabled = false
            m.addItem(credit)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
