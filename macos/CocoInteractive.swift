import Cocoa
import QuartzCore

struct PetAnimation {
    let row: Int
    let frames: Int
    let fps: Double
    let firstFrame: Int

    init(row: Int, frames: Int, fps: Double, firstFrame: Int = 0) {
        self.row = row
        self.frames = frames
        self.fps = fps
        self.firstFrame = firstFrame
    }
}

struct OnlineConfig {
    let serverURL: String
    let room: String
    let actorName: String
    let petName: String
    let petKind: String
    let gitCommit: String
    let updateAPIURL: String
    let updatePageURL: String

    var roomLink: String {
        room.isEmpty ? serverURL : "\(serverURL)/?room=\(room)"
    }

    static func load() -> OnlineConfig {
        let fallback = OnlineConfig(
            serverURL: "http://127.0.0.1:8787",
            room: "",
            actorName: "卷毛",
            petName: "卷毛",
            petKind: "cockapoo",
            gitCommit: "",
            updateAPIURL: "https://api.github.com/repos/0xtoward/juanmao-pet/commits/main",
            updatePageURL: "https://github.com/0xtoward/juanmao-pet"
        )
        let object: [String: Any]
        if let url = Bundle.main.resourceURL?.appendingPathComponent("online-config.json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            object = decoded
        } else {
            object = [:]
        }

        func string(_ key: String, _ defaultValue: String) -> String {
            guard let value = object[key] as? String else { return defaultValue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? defaultValue : trimmed
        }

        let defaults = UserDefaults.standard
        let bundledServerURL = normalizeServerURL(string("serverURL", fallback.serverURL))
        let bundledRoom = string("room", fallback.room)
        let previousBundledServerURL = defaults.string(forKey: "juanmao.online.lastBundledServerURL").map(normalizeServerURL)
        let savedServerURL = defaults.string(forKey: "juanmao.online.serverURL").map(normalizeServerURL)
        let savedRoom = defaults.string(forKey: "juanmao.online.room")
        let shouldPreferBundledConnection = savedServerURL.map {
            previousBundledServerURL != bundledServerURL
                && $0 != bundledServerURL
                && isDisposableTunnelURL($0)
        } ?? false
        let serverURL = shouldPreferBundledConnection ? bundledServerURL : (savedServerURL ?? bundledServerURL)
        let room = shouldPreferBundledConnection ? bundledRoom : (savedRoom ?? bundledRoom)
        if shouldPreferBundledConnection {
            defaults.set(bundledServerURL, forKey: "juanmao.online.serverURL")
            defaults.set(bundledRoom, forKey: "juanmao.online.room")
        }
        defaults.set(bundledServerURL, forKey: "juanmao.online.lastBundledServerURL")

        return OnlineConfig(
            serverURL: serverURL,
            room: room.trimmingCharacters(in: .whitespacesAndNewlines),
            actorName: string("actorName", fallback.actorName),
            petName: string("petName", fallback.petName),
            petKind: string("petKind", fallback.petKind),
            gitCommit: string("gitCommit", fallback.gitCommit),
            updateAPIURL: string("updateAPIURL", fallback.updateAPIURL),
            updatePageURL: string("updatePageURL", fallback.updatePageURL)
        )
    }

    static func from(input: String, current: OnlineConfig) -> OnlineConfig? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return current }

        let pattern = #"https?://[^\s]+"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        let detectedURL = regex?.firstMatch(in: trimmed, range: range).flatMap { match -> String? in
            guard let matchRange = Range(match.range, in: trimmed) else { return nil }
            return String(trimmed[matchRange])
        }

        var serverURL = detectedURL ?? trimmed
        var room = current.room
        if URLComponents(string: serverURL)?.scheme == nil,
           !serverURL.contains(" "),
           serverURL.contains(".") {
            serverURL = "https://\(serverURL)"
        }

        if let components = URLComponents(string: serverURL),
           let scheme = components.scheme,
           let host = components.host {
            let port = components.port.map { ":\($0)" } ?? ""
            serverURL = "\(scheme)://\(host)\(port)"
            if let roomValue = components.queryItems?.first(where: { $0.name == "room" })?.value,
               !roomValue.isEmpty {
                room = roomValue
            }
        }

        let normalized = normalizeServerURL(serverURL)

        return OnlineConfig(
            serverURL: normalized,
            room: room,
            actorName: current.actorName,
            petName: current.petName,
            petKind: current.petKind,
            gitCommit: current.gitCommit,
            updateAPIURL: current.updateAPIURL,
            updatePageURL: current.updatePageURL
        )
    }

    func saveConnection() {
        let defaults = UserDefaults.standard
        defaults.set(serverURL, forKey: "juanmao.online.serverURL")
        defaults.set(room, forKey: "juanmao.online.room")
    }

    private static func normalizeServerURL(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }

    private static func isDisposableTunnelURL(_ value: String) -> Bool {
        guard let host = URLComponents(string: value)?.host?.lowercased() else { return false }
        return host == "trycloudflare.com" || host.hasSuffix(".trycloudflare.com")
    }
}

struct PetHistoryEntry: Codable {
    let id: Int
    let at: TimeInterval
    let action: String
    let actor: String
    let petName: String
    let petKind: String
    let text: String
    let incoming: Bool
}

final class CocoPetView: NSView {
    weak var petWindow: NSWindow?

    private let spriteSheet: NSImage
    private let dachshundSpriteSheet: NSImage?
    private var onlineConfig = OnlineConfig.load()
    private let cellWidth: CGFloat = 192
    private let cellHeight: CGFloat = 208
    private var petScale: CGFloat
    private let petAnimations: [String: PetAnimation] = [
        "idle": PetAnimation(row: 0, frames: 6, fps: 3),
        "runRight": PetAnimation(row: 1, frames: 8, fps: 11),
        "runLeft": PetAnimation(row: 2, frames: 8, fps: 11),
        "wave": PetAnimation(row: 3, frames: 4, fps: 4),
        "jump": PetAnimation(row: 4, frames: 5, fps: 7),
        "failed": PetAnimation(row: 5, frames: 8, fps: 5),
        "sleep": PetAnimation(row: 5, frames: 1, fps: 1, firstFrame: 5),
        "waiting": PetAnimation(row: 6, frames: 6, fps: 3),
        "running": PetAnimation(row: 7, frames: 6, fps: 10)
    ]

    private var activeAnimation = "idle"
    private var frameIndex = 0
    private var lastFrameDate = Date()
    private var frameTimer: Timer?
    private var resetTimer: Timer?
    private var speechTimer: Timer?
    private var tongueTimer: Timer?
    private var walkTimer: Timer?
    private var syncTimer: Timer?
    private var guestTimer: Timer?
    private var guestWaveTimer: Timer?
    private var awayVisitTimer: Timer?
    private var speech: String?
    private var guestSpeech: String?
    private var guestName: String?
    private var guestKind: String?
    private var awayVisitSpeech: String?
    private var tongueVisible = false
    private var tongueStartedAt: Date?
    private var heartsStartedAt: Date?
    private var guestStartedAt: Date?
    private var awayVisitStartedAt: Date?
    private var awayVisitUntil: Date?
    private var stickySpeechEventID: Int?
    private var hovering = false
    private var controlsRevealUntil: Date?
    private var pressedAction: String?
    private var dragStartPoint: NSPoint?
    private var dragStartFrame: NSRect?
    private weak var scaleSliderValueLabel: NSTextField?
    private var didDrag = false
    private var handledMouseDownAction = false
    private var isWalking = false
    private var guestVisible = false
    private var guestAnimation = "runRight"
    private var guestFrameIndex = 0
    private var guestLastFrameDate = Date()
    private var awayVisitAnimation = "runRight"
    private var awayVisitFrameIndex = 0
    private var awayVisitLastFrameDate = Date()
    private var walkDirection: CGFloat = -1
    private let syncClientID = CocoPetView.loadSyncClientID()
    private var lastSyncEventID = 0
    private var syncRequestInFlight = false
    private let feedOptions = ["小饼干", "水", "肉干"]

    private var love: Int
    private var fullness: Int
    private var energy: Int

    override var isFlipped: Bool { false }

    private static func loadSyncClientID() -> String {
        let key = "juanmao.native.syncClientID"
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: key), saved.hasPrefix("desktop-") {
            return saved
        }
        let created = "desktop-\(UUID().uuidString)"
        defaults.set(created, forKey: key)
        return created
    }

    init(frame: NSRect, spriteSheet: NSImage, dachshundSpriteSheet: NSImage?) {
        self.spriteSheet = spriteSheet
        self.dachshundSpriteSheet = dachshundSpriteSheet
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "juanmao.native.love") == nil {
            self.love = 62
            self.fullness = 72
            self.energy = 76
        } else {
            self.love = defaults.integer(forKey: "juanmao.native.love")
            self.fullness = defaults.integer(forKey: "juanmao.native.fullness")
            self.energy = defaults.integer(forKey: "juanmao.native.energy")
        }
        let savedScale = defaults.double(forKey: "juanmao.native.petScale")
        self.petScale = savedScale > 0 ? min(0.68, max(0.28, CGFloat(savedScale))) : 0.41
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        startTimer()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleExternalCommand),
            name: Notification.Name("local.juanmao.command"),
            object: nil
        )
        startOnlineSync()
        checkForGitUpdate()
        say("\(onlineConfig.petName)在。")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        frameTimer?.invalidate()
        resetTimer?.invalidate()
        speechTimer?.invalidate()
        tongueTimer?.invalidate()
        walkTimer?.invalidate()
        syncTimer?.invalidate()
        guestTimer?.invalidate()
        guestWaveTimer?.invalidate()
        awayVisitTimer?.invalidate()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        updateControlHover(at: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        controlsRevealUntil = nil
        pressedAction = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        updateControlHover(at: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        handledMouseDownAction = false
        let point = convert(event.locationInWindow, from: nil)

        if event.modifierFlags.contains(.control), isMainPetHit(at: point) {
            showContextMenu(for: event)
            handledMouseDownAction = true
            return
        }

        if let action = action(at: point) {
            pressedAction = action
            needsDisplay = true
            return
        }

        guard isMainPetHit(at: point) else {
            return
        }

        if event.clickCount >= 2 {
            showFeedPicker()
            handledMouseDownAction = true
            return
        }

        dragStartPoint = NSEvent.mouseLocation
        dragStartFrame = petWindow?.frame
        didDrag = false
        setAnimation("waiting")
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startPoint = dragStartPoint,
              let startFrame = dragStartFrame,
              let window = petWindow else {
            return
        }

        let current = NSEvent.mouseLocation
        let dx = current.x - startPoint.x
        let dy = current.y - startPoint.y
        if hypot(dx, dy) > 3 {
            didDrag = true
        }
        window.setFrameOrigin(NSPoint(x: startFrame.origin.x + dx, y: startFrame.origin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            pressedAction = nil
            dragStartPoint = nil
            dragStartFrame = nil
            needsDisplay = true
        }

        if let action = pressedAction {
            perform(action)
            return
        }

        if handledMouseDownAction {
            return
        }

        if didDrag {
            say("换个地方。")
            setAnimation("idle")
        } else {
            perform("pat")
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard isMainPetHit(at: point) else { return }
        showContextMenu(for: event)
    }

    private func showContextMenu(for event: NSEvent) {
        let menu = NSMenu()
        addMenuItem("摸摸", #selector(menuPat), to: menu)
        addMenuItem("投喂", #selector(menuFeed), to: menu)
        addMenuItem("遛弯", #selector(menuWalk), to: menu)
        addMenuItem("想你", #selector(menuMiss), to: menu)
        addMenuItem("休息", #selector(menuNap), to: menu)
        addMenuItem("去串门", #selector(menuVisit), to: menu)
        addMenuItem("提醒喝水", #selector(menuRemind), to: menu)
        menu.addItem(.separator())
        addMenuItem("发送文字...", #selector(menuSendText), to: menu)
        addMenuItem("浏览对话历史", #selector(menuHistory), to: menu)
        menu.addItem(.separator())
        addMenuItem("调整大小...", #selector(menuScale), to: menu)
        menu.addItem(.separator())
        addMenuItem("设置联机网址...", #selector(menuConnectionSettings), to: menu)
        menu.addItem(.separator())
        addMenuItem("关闭 \(onlineConfig.petName)", #selector(menuClose), to: menu)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        drawGuestPet()
        drawGuestSpeech()
        drawSpeech()
        drawMainPet()
        drawAwayVisitEffect()
        drawTongue()
        drawSleepAccents()
        drawHearts()
        drawControls()
    }

    private var petRect: NSRect {
        let width = cellWidth * petScale
        let height = cellHeight * petScale
        let centerX = guestVisible ? bounds.width * 0.66 : bounds.width / 2
        return NSRect(x: centerX - width / 2, y: 70, width: width, height: height)
    }

    private var guestPetRect: NSRect? {
        guard guestVisible else { return nil }
        let width = cellWidth * petScale
        let height = cellHeight * petScale
        let targetX = bounds.width * 0.34 - width / 2
        let elapsed = Date().timeIntervalSince(guestStartedAt ?? Date())
        let enterProgress = min(1, max(0, CGFloat(elapsed / 0.9)))
        let leaveProgress = min(1, max(0, CGFloat((elapsed - 19.0) / 1.0)))
        let easedEnter = 1 - pow(1 - enterProgress, 3)
        let easedLeave = leaveProgress * leaveProgress
        let startX = -width - 16
        let endX = bounds.width + 16
        let x = targetX * easedEnter + startX * (1 - easedEnter)
        let leavingX = x * (1 - easedLeave) + endX * easedLeave
        return NSRect(x: leavingX, y: 70, width: width, height: height)
    }

    private var isAwayVisiting: Bool {
        guard let awayVisitUntil else { return false }
        return awayVisitUntil > Date()
    }

    private var awayVisitPetRect: NSRect? {
        guard isAwayVisiting else { return nil }
        let width = cellWidth * petScale * 0.54
        let height = cellHeight * petScale * 0.54
        let elapsed = Date().timeIntervalSince(awayVisitStartedAt ?? Date())
        let bob = CGFloat(sin(elapsed * 4.0)) * 5
        let x = min(bounds.width - width - 12, max(12, bounds.width - width - 24))
        let y = max(12, bounds.height - height - 56 + bob)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private var controlRects: [(action: String, title: String, rect: NSRect)] {
        let items = [
            ("pat", "摸摸"),
            ("feed", "投喂"),
            ("walk", "遛弯"),
            ("miss", "想你"),
            ("nap", "休息"),
            ("visit", "串门"),
            ("remind", "提醒"),
            ("close", "关闭")
        ]
        let buttonWidth: CGFloat = 42
        let buttonHeight: CGFloat = 24
        let gap: CGFloat = 6
        let rowGap: CGFloat = 5
        let bottomY: CGFloat = 8

        return items.enumerated().map { index, item in
            let isTopRow = index < 4
            let rowCount = 4
            let localIndex = isTopRow ? index : index - 4
            let totalWidth = CGFloat(rowCount) * buttonWidth + CGFloat(rowCount - 1) * gap
            let startX = (bounds.width - totalWidth) / 2
            let y = bottomY + (isTopRow ? buttonHeight + rowGap : 0)
            let x = startX + CGFloat(localIndex) * (buttonWidth + gap)
            return (item.0, item.1, NSRect(x: x, y: y, width: buttonWidth, height: buttonHeight))
        }
    }

    private func drawMainPet() {
        if isAwayVisiting {
            drawHomeHouse(in: petRect)
            return
        }
        drawSprite(
            sheet: spriteSheet(for: onlineConfig.petKind),
            animationName: activeAnimation,
            frame: frameIndex,
            in: petRect,
            fraction: 1
        )
    }

    private func drawHomeHouse(in rect: NSRect) {
        let scale = rect.width / cellWidth
        let houseWidth = min(rect.width * 0.62, 118 * scale)
        let houseHeight = min(rect.height * 0.42, 92 * scale)
        let base = NSRect(
            x: rect.midX - houseWidth / 2,
            y: rect.minY + rect.height * 0.18,
            width: houseWidth,
            height: houseHeight * 0.62
        )
        let roofPeak = NSPoint(x: base.midX, y: base.maxY + houseHeight * 0.42)
        let roofInset = houseWidth * 0.12

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowBlurRadius = 6
        shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.16)
        shadow.set()

        let roof = NSBezierPath()
        roof.move(to: NSPoint(x: base.minX - roofInset, y: base.maxY - 2 * scale))
        roof.line(to: roofPeak)
        roof.line(to: NSPoint(x: base.maxX + roofInset, y: base.maxY - 2 * scale))
        roof.close()
        NSColor(calibratedRed: 0.93, green: 0.36, blue: 0.42, alpha: 0.96).setFill()
        roof.fill()
        NSColor(calibratedRed: 0.54, green: 0.18, blue: 0.24, alpha: 0.24).setStroke()
        roof.lineWidth = 1.2
        roof.stroke()

        let body = NSBezierPath(roundedRect: base, xRadius: 10 * scale, yRadius: 10 * scale)
        NSColor(calibratedRed: 1.0, green: 0.93, blue: 0.79, alpha: 0.98).setFill()
        body.fill()
        NSColor(calibratedRed: 0.64, green: 0.42, blue: 0.24, alpha: 0.22).setStroke()
        body.lineWidth = 1.2
        body.stroke()

        let door = NSBezierPath(roundedRect: NSRect(
            x: base.midX - 13 * scale,
            y: base.minY,
            width: 26 * scale,
            height: 38 * scale
        ), xRadius: 7 * scale, yRadius: 7 * scale)
        NSColor(calibratedRed: 0.56, green: 0.34, blue: 0.22, alpha: 0.95).setFill()
        door.fill()

        NSColor(calibratedRed: 0.99, green: 0.80, blue: 0.38, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: base.midX + 6 * scale, y: base.minY + 18 * scale, width: 4 * scale, height: 4 * scale)).fill()

        let window = NSBezierPath(roundedRect: NSRect(
            x: base.minX + 14 * scale,
            y: base.minY + 29 * scale,
            width: 22 * scale,
            height: 18 * scale
        ), xRadius: 5 * scale, yRadius: 5 * scale)
        NSColor(calibratedRed: 0.64, green: 0.83, blue: 1.0, alpha: 0.9).setFill()
        window.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawGuestPet() {
        guard let rect = guestPetRect else { return }
        drawSprite(
            sheet: spriteSheet(for: guestKind),
            animationName: guestAnimation,
            frame: guestFrameIndex,
            in: rect,
            fraction: 0.98
        )
    }

    private func drawAwayVisitEffect() {
        guard let rect = awayVisitPetRect else { return }

        let path = NSBezierPath()
        path.move(to: NSPoint(x: petRect.midX, y: petRect.maxY - 12))
        path.curve(
            to: NSPoint(x: rect.midX, y: rect.midY),
            controlPoint1: NSPoint(x: petRect.maxX + 18, y: min(bounds.height - 20, petRect.maxY + 34)),
            controlPoint2: NSPoint(x: rect.minX - 36, y: rect.maxY - 8)
        )
        var dash: [CGFloat] = [4, 5]
        path.setLineDash(&dash, count: dash.count, phase: 0)
        path.lineWidth = 1.4
        NSColor(calibratedRed: 0.44, green: 0.52, blue: 0.85, alpha: 0.42).setStroke()
        path.stroke()

        drawSprite(
            sheet: spriteSheet(for: onlineConfig.petKind),
            animationName: awayVisitAnimation,
            frame: awayVisitFrameIndex,
            in: rect,
            fraction: 0.9
        )

        guard let awayVisitSpeech, !awayVisitSpeech.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.42, alpha: 1),
            .paragraphStyle: paragraph
        ]
        let rawSize = (awayVisitSpeech as NSString).size(withAttributes: attributes)
        let bubbleWidth = min(max(rawSize.width + 18, 88), 150)
        let bubbleHeight: CGFloat = 28
        let bubble = NSRect(
            x: min(bounds.width - bubbleWidth - 8, max(8, rect.midX - bubbleWidth / 2)),
            y: min(bounds.height - bubbleHeight - 10, rect.maxY + 4),
            width: bubbleWidth,
            height: bubbleHeight
        )

        NSColor(calibratedRed: 0.92, green: 0.96, blue: 1.0, alpha: 0.96).setFill()
        NSColor(calibratedRed: 0.30, green: 0.42, blue: 0.82, alpha: 0.24).setStroke()
        let bubblePath = NSBezierPath(roundedRect: bubble, xRadius: 8, yRadius: 8)
        bubblePath.lineWidth = 1
        bubblePath.fill()
        bubblePath.stroke()
        (awayVisitSpeech as NSString).draw(in: bubble.insetBy(dx: 8, dy: 7), withAttributes: attributes)
    }

    private func spriteSheet(for kind: String?) -> NSImage {
        if kind == "dachshund" || kind == "dash" {
            return dachshundSpriteSheet ?? spriteSheet
        }
        return spriteSheet
    }

    private func drawSprite(sheet: NSImage, animationName: String, frame: Int, in rect: NSRect, fraction: CGFloat) {
        guard let animation = petAnimations[animationName] else { return }
        let sourceY = sheet.size.height - CGFloat(animation.row + 1) * cellHeight
        let source = NSRect(
            x: CGFloat(animation.firstFrame + frame) * cellWidth,
            y: sourceY,
            width: cellWidth,
            height: cellHeight
        )

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = .none
        sheet.draw(in: rect, from: source, operation: .sourceOver, fraction: fraction)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawDachshund(animationName: String, frame: Int, in rect: NSRect, fraction: CGFloat) {
        let scale = rect.width / cellWidth
        let facingLeft = animationName == "runLeft"
        let sleep = animationName == "sleep"
        let wave = animationName == "wave"
        let jump = animationName == "jump"
        let run = animationName == "runLeft" || animationName == "runRight" || animationName == "running"
        let phase = CGFloat(frame % 8)
        let bob = sleep ? 0 : (run ? sin(phase * .pi / 2) * 2.4 * scale : sin(phase * .pi / 3) * 1.2 * scale)
        let jumpOffsets: [CGFloat] = [0, 9, 18, 9, 0]
        let jumpOffset: CGFloat = jump ? jumpOffsets[min(frame, 4)] * scale : 0
        let baseY = rect.minY + bob + jumpOffset

        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext.current?.cgContext {
            context.setAlpha(fraction)
        }
        if facingLeft {
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX, yBy: 0)
            transform.scaleX(by: -1, yBy: 1)
            transform.translateX(by: -rect.midX, yBy: 0)
            transform.concat()
        }

        let outline = NSColor(calibratedRed: 0.20, green: 0.12, blue: 0.08, alpha: 1)
        let coat = NSColor(calibratedRed: 0.58, green: 0.31, blue: 0.15, alpha: 1)
        let coatDark = NSColor(calibratedRed: 0.36, green: 0.18, blue: 0.09, alpha: 1)
        let tan = NSColor(calibratedRed: 0.86, green: 0.59, blue: 0.34, alpha: 1)
        let highlight = NSColor(calibratedRed: 0.74, green: 0.43, blue: 0.22, alpha: 1)

        func fillStroke(_ path: NSBezierPath, fill: NSColor, width: CGFloat = 1.6) {
            fill.setFill()
            outline.setStroke()
            path.lineWidth = width * scale
            path.fill()
            path.stroke()
        }

        if sleep {
            let body = NSBezierPath(roundedRect: NSRect(x: rect.minX + 34 * scale, y: baseY + 22 * scale, width: 112 * scale, height: 33 * scale), xRadius: 16 * scale, yRadius: 16 * scale)
            fillStroke(body, fill: coat)
            let head = NSBezierPath(ovalIn: NSRect(x: rect.minX + 128 * scale, y: baseY + 18 * scale, width: 36 * scale, height: 32 * scale))
            fillStroke(head, fill: coat)
            let ear = NSBezierPath(roundedRect: NSRect(x: rect.minX + 119 * scale, y: baseY + 12 * scale, width: 22 * scale, height: 42 * scale), xRadius: 11 * scale, yRadius: 14 * scale)
            fillStroke(ear, fill: coatDark)
            fillStroke(NSBezierPath(ovalIn: NSRect(x: rect.minX + 151 * scale, y: baseY + 27 * scale, width: 12 * scale, height: 9 * scale)), fill: tan, width: 1.2)
            outline.setStroke()
            let eye = NSBezierPath()
            eye.move(to: NSPoint(x: rect.minX + 144 * scale, y: baseY + 39 * scale))
            eye.curve(to: NSPoint(x: rect.minX + 153 * scale, y: baseY + 39 * scale), controlPoint1: NSPoint(x: rect.minX + 147 * scale, y: baseY + 36 * scale), controlPoint2: NSPoint(x: rect.minX + 150 * scale, y: baseY + 36 * scale))
            eye.lineWidth = 1.4 * scale
            eye.stroke()
            NSGraphicsContext.restoreGraphicsState()
            return
        }

        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: rect.minX + 38 * scale, y: baseY + 62 * scale))
        tail.curve(to: NSPoint(x: rect.minX + 18 * scale, y: baseY + 81 * scale), controlPoint1: NSPoint(x: rect.minX + 25 * scale, y: baseY + 74 * scale), controlPoint2: NSPoint(x: rect.minX + 19 * scale, y: baseY + 78 * scale))
        tail.lineWidth = 7 * scale
        coatDark.setStroke()
        tail.stroke()
        tail.lineWidth = 2 * scale
        outline.setStroke()
        tail.stroke()

        let body = NSBezierPath(roundedRect: NSRect(x: rect.minX + 33 * scale, y: baseY + 38 * scale, width: 113 * scale, height: 43 * scale), xRadius: 22 * scale, yRadius: 18 * scale)
        fillStroke(body, fill: coat)

        let chest = NSBezierPath()
        chest.move(to: NSPoint(x: rect.minX + 126 * scale, y: baseY + 42 * scale))
        chest.curve(to: NSPoint(x: rect.minX + 139 * scale, y: baseY + 66 * scale), controlPoint1: NSPoint(x: rect.minX + 132 * scale, y: baseY + 46 * scale), controlPoint2: NSPoint(x: rect.minX + 139 * scale, y: baseY + 54 * scale))
        chest.line(to: NSPoint(x: rect.minX + 117 * scale, y: baseY + 59 * scale))
        chest.close()
        fillStroke(chest, fill: tan, width: 1.2)

        let legLift = run ? sin(phase * .pi) * 3 * scale : 0
        let frontRaised = wave ? (8 + 5 * sin(phase * .pi / 2)) * scale : 0
        let legs: [(CGFloat, CGFloat, CGFloat)] = [
            (52, 0, 0),
            (78, -legLift, 0),
            (118, legLift, frontRaised),
            (137, -legLift, 0)
        ]
        for (x, y, lift) in legs {
            let legHeight = (lift > 0 ? 18 : 29) * scale
            let legRect = NSRect(x: rect.minX + x * scale, y: baseY + 15 * scale + y + lift, width: 12 * scale, height: legHeight)
            fillStroke(NSBezierPath(roundedRect: legRect, xRadius: 5 * scale, yRadius: 5 * scale), fill: x > 110 ? tan : coatDark, width: 1.2)
            if lift == 0 {
                fillStroke(NSBezierPath(ovalIn: NSRect(x: legRect.minX - 2 * scale, y: baseY + 12 * scale + y, width: 18 * scale, height: 9 * scale)), fill: tan, width: 1.0)
            }
        }

        let head = NSBezierPath(ovalIn: NSRect(x: rect.minX + 126 * scale, y: baseY + 58 * scale, width: 43 * scale, height: 42 * scale))
        fillStroke(head, fill: coat)
        let snout = NSBezierPath(roundedRect: NSRect(x: rect.minX + 151 * scale, y: baseY + 67 * scale, width: 28 * scale, height: 18 * scale), xRadius: 10 * scale, yRadius: 9 * scale)
        fillStroke(snout, fill: tan, width: 1.2)
        let ear = NSBezierPath(roundedRect: NSRect(x: rect.minX + 119 * scale, y: baseY + 47 * scale, width: 25 * scale, height: 53 * scale), xRadius: 12 * scale, yRadius: 18 * scale)
        fillStroke(ear, fill: coatDark)

        let hair = NSBezierPath()
        hair.move(to: NSPoint(x: rect.minX + 134 * scale, y: baseY + 95 * scale))
        hair.line(to: NSPoint(x: rect.minX + 127 * scale, y: baseY + 107 * scale))
        hair.line(to: NSPoint(x: rect.minX + 143 * scale, y: baseY + 100 * scale))
        hair.line(to: NSPoint(x: rect.minX + 150 * scale, y: baseY + 109 * scale))
        hair.line(to: NSPoint(x: rect.minX + 153 * scale, y: baseY + 96 * scale))
        hair.close()
        fillStroke(hair, fill: highlight, width: 1.1)

        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.minX + 148 * scale, y: baseY + 81 * scale, width: 4.8 * scale, height: 5.5 * scale)).fill()
        NSBezierPath(ovalIn: NSRect(x: rect.minX + 172 * scale, y: baseY + 73 * scale, width: 7 * scale, height: 6 * scale)).fill()

        outline.setStroke()
        let smile = NSBezierPath()
        smile.move(to: NSPoint(x: rect.minX + 160 * scale, y: baseY + 70 * scale))
        smile.curve(to: NSPoint(x: rect.minX + 168 * scale, y: baseY + 69 * scale), controlPoint1: NSPoint(x: rect.minX + 163 * scale, y: baseY + 66 * scale), controlPoint2: NSPoint(x: rect.minX + 166 * scale, y: baseY + 66 * scale))
        smile.lineWidth = 1.2 * scale
        smile.stroke()

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawTongue() {
        guard tongueVisible else { return }
        if onlineConfig.petKind == "dachshund" {
            return
        }

        let elapsed = Date().timeIntervalSince(tongueStartedAt ?? Date())
        let wiggle = sin(elapsed * 18)
        let bounce = sin(elapsed * 24)
        let extend = 0.76 + 0.24 * abs(sin(elapsed * 9))
        let mouthCenter = pointInPet(sourceX: 92, sourceYFromTop: 99)
        let tongueTop = pointInPet(sourceX: 92, sourceYFromTop: 103)
        let mouthWidth = max(10, 25 * petScale)
        let mouthHeight = max(4, 10 * petScale)
        let tongueWidth = max(9, 22 * petScale)
        let tongueHeight = max(12, 30 * petScale) * extend
        let tongue = NSRect(
            x: tongueTop.x - tongueWidth / 2 + CGFloat(wiggle) * 2.2,
            y: tongueTop.y - tongueHeight - CGFloat(bounce) * 1.5,
            width: tongueWidth,
            height: tongueHeight
        )

        NSColor(calibratedRed: 0.62, green: 0.08, blue: 0.14, alpha: 0.32).setStroke()
        NSColor(calibratedRed: 0.98, green: 0.34, blue: 0.46, alpha: 0.96).setFill()
        let tonguePath = NSBezierPath(roundedRect: tongue, xRadius: tongueWidth / 2, yRadius: tongueWidth / 2)
        tonguePath.lineWidth = 0.8
        tonguePath.fill()
        tonguePath.stroke()

        NSColor(calibratedRed: 0.76, green: 0.12, blue: 0.25, alpha: 0.72).setStroke()
        let centerLine = NSBezierPath()
        centerLine.move(to: NSPoint(x: tongue.midX, y: tongue.minY + 2.5))
        centerLine.line(to: NSPoint(x: tongue.midX, y: tongue.maxY - 3))
        centerLine.lineWidth = 0.8
        centerLine.stroke()

        let mouth = NSRect(
            x: mouthCenter.x - mouthWidth / 2,
            y: mouthCenter.y - mouthHeight / 2,
            width: mouthWidth,
            height: mouthHeight
        )
        NSColor(calibratedWhite: 0.04, alpha: 0.94).setFill()
        NSBezierPath(ovalIn: mouth).fill()
    }

    private func drawDachshundTongue() {
        let elapsed = Date().timeIntervalSince(tongueStartedAt ?? Date())
        let wiggle = sin(elapsed * 18)
        let extend = 0.74 + 0.22 * abs(sin(elapsed * 10))
        let scale = petRect.width / cellWidth
        let facingLeft = activeAnimation == "runLeft"
        let mouthX = facingLeft ? petRect.minX + 33 * scale : petRect.minX + 166 * scale
        let mouthY = petRect.minY + 69 * scale
        let tongueWidth = max(9, 21 * scale)
        let tongueHeight = max(11, 27 * scale) * extend
        let tongue = NSRect(
            x: mouthX - tongueWidth / 2 + CGFloat(wiggle) * 2.0,
            y: mouthY - tongueHeight,
            width: tongueWidth,
            height: tongueHeight
        )

        NSColor(calibratedRed: 0.62, green: 0.08, blue: 0.14, alpha: 0.30).setStroke()
        NSColor(calibratedRed: 0.98, green: 0.36, blue: 0.48, alpha: 0.96).setFill()
        let path = NSBezierPath(roundedRect: tongue, xRadius: tongueWidth / 2, yRadius: tongueWidth / 2)
        path.lineWidth = 0.8
        path.fill()
        path.stroke()
    }

    private func drawHearts() {
        guard let startedAt = heartsStartedAt else { return }

        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed > 1.9 {
            heartsStartedAt = nil
            return
        }

        let progress = CGFloat(elapsed / 1.9)
        let specs: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (-34, 10, 13, 0.00),
            (-12, 30, 10, 0.10),
            (14, 18, 12, 0.18),
            (34, 38, 9, 0.28),
            (2, 50, 14, 0.36)
        ]

        for spec in specs {
            let localProgress = min(1, max(0, (progress - spec.3) / 0.72))
            let alpha = max(0, 1 - localProgress)
            guard alpha > 0 else { continue }

            let center = NSPoint(
                x: petRect.midX + spec.0,
                y: petRect.maxY - 8 + spec.1 + localProgress * 32
            )
            drawHeart(center: center, size: spec.2 * (0.86 + localProgress * 0.18), alpha: alpha)
        }
    }

    private func drawHeart(center: NSPoint, size: CGFloat, alpha: CGFloat) {
        let scale = size / 32
        let path = NSBezierPath()
        path.move(to: NSPoint(x: center.x, y: center.y - 10 * scale))
        path.curve(
            to: NSPoint(x: center.x - 16 * scale, y: center.y + 5 * scale),
            controlPoint1: NSPoint(x: center.x - 14 * scale, y: center.y - 1 * scale),
            controlPoint2: NSPoint(x: center.x - 18 * scale, y: center.y + 8 * scale)
        )
        path.curve(
            to: NSPoint(x: center.x, y: center.y + 14 * scale),
            controlPoint1: NSPoint(x: center.x - 14 * scale, y: center.y + 18 * scale),
            controlPoint2: NSPoint(x: center.x - 4 * scale, y: center.y + 19 * scale)
        )
        path.curve(
            to: NSPoint(x: center.x + 16 * scale, y: center.y + 5 * scale),
            controlPoint1: NSPoint(x: center.x + 4 * scale, y: center.y + 19 * scale),
            controlPoint2: NSPoint(x: center.x + 14 * scale, y: center.y + 18 * scale)
        )
        path.curve(
            to: NSPoint(x: center.x, y: center.y - 10 * scale),
            controlPoint1: NSPoint(x: center.x + 18 * scale, y: center.y + 8 * scale),
            controlPoint2: NSPoint(x: center.x + 14 * scale, y: center.y - 1 * scale)
        )
        path.close()

        NSColor(calibratedRed: 1.0, green: 0.28, blue: 0.56, alpha: alpha * 0.92).setFill()
        NSColor(calibratedRed: 0.92, green: 0.1, blue: 0.38, alpha: alpha * 0.44).setStroke()
        path.lineWidth = 0.8
        path.fill()
        path.stroke()
    }

    private func drawSleepAccents() {
        guard activeAnimation == "sleep" else { return }

        let zzz = "Zzz"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .bold),
            .foregroundColor: NSColor(calibratedRed: 0.42, green: 0.55, blue: 0.86, alpha: 0.82)
        ]
        let textPoint = NSPoint(x: petRect.maxX - 12, y: petRect.maxY - 4)
        (zzz as NSString).draw(at: textPoint, withAttributes: attributes)

        guard onlineConfig.petKind != "dachshund" else { return }

        let cheekColor = NSColor(calibratedRed: 1, green: 0.48, blue: 0.62, alpha: 0.35)
        cheekColor.setFill()
        let leftCheek = pointInPet(sourceX: 70, sourceYFromTop: 112)
        let rightCheek = pointInPet(sourceX: 122, sourceYFromTop: 112)
        NSBezierPath(ovalIn: NSRect(x: leftCheek.x - 4, y: leftCheek.y - 2, width: 8, height: 4)).fill()
        NSBezierPath(ovalIn: NSRect(x: rightCheek.x - 4, y: rightCheek.y - 2, width: 8, height: 4)).fill()
    }

    private func pointInPet(sourceX: CGFloat, sourceYFromTop: CGFloat) -> NSPoint {
        NSPoint(
            x: petRect.minX + sourceX * petScale,
            y: petRect.minY + (cellHeight - sourceYFromTop) * petScale
        )
    }

    private func drawGuestSpeech() {
        guard let rect = guestPetRect,
              let guestSpeech,
              !guestSpeech.isEmpty else {
            return
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor(calibratedWhite: 0.22, alpha: 1),
            .paragraphStyle: paragraph
        ]
        let rawSize = (guestSpeech as NSString).size(withAttributes: attributes)
        let bubbleWidth = min(max(rawSize.width + 18, 84), 142)
        let bubbleHeight: CGFloat = 28
        let bubble = NSRect(
            x: min(bounds.width - bubbleWidth - 8, max(8, rect.midX - bubbleWidth / 2)),
            y: min(bounds.height - bubbleHeight - 14, rect.maxY + 6),
            width: bubbleWidth,
            height: bubbleHeight
        )

        NSColor(calibratedRed: 1, green: 0.95, blue: 0.99, alpha: 0.96).setFill()
        NSColor(calibratedRed: 0.95, green: 0.33, blue: 0.58, alpha: 0.22).setStroke()
        let path = NSBezierPath(roundedRect: bubble, xRadius: 8, yRadius: 8)
        path.lineWidth = 1
        path.fill()
        path.stroke()

        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: bubble.midX - 6, y: bubble.minY + 1))
        arrow.line(to: NSPoint(x: bubble.midX, y: bubble.minY - 7))
        arrow.line(to: NSPoint(x: bubble.midX + 6, y: bubble.minY + 1))
        arrow.close()
        NSColor(calibratedRed: 1, green: 0.95, blue: 0.99, alpha: 0.96).setFill()
        arrow.fill()

        (guestSpeech as NSString).draw(in: bubble.insetBy(dx: 8, dy: 7), withAttributes: attributes)
    }

    private func drawSpeech() {
        guard let speech, !speech.isEmpty else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor(calibratedWhite: 0.18, alpha: 1),
            .paragraphStyle: paragraph
        ]
        let rawSize = (speech as NSString).size(withAttributes: attributes)
        let bubbleWidth = min(max(rawSize.width + 22, 78), guestVisible ? 142 : bounds.width - 24)
        let bubbleHeight: CGFloat = 30
        let bubble = NSRect(
            x: min(bounds.width - bubbleWidth - 8, max(8, petRect.midX - bubbleWidth / 2)),
            y: min(bounds.height - bubbleHeight - 12, petRect.maxY + 8),
            width: bubbleWidth,
            height: bubbleHeight
        )

        NSColor.white.withAlphaComponent(0.96).setFill()
        NSColor(calibratedWhite: 0.1, alpha: 0.14).setStroke()
        let path = NSBezierPath(roundedRect: bubble, xRadius: 8, yRadius: 8)
        path.lineWidth = 1
        path.fill()
        path.stroke()

        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: bubble.midX - 7, y: bubble.minY + 1))
        arrow.line(to: NSPoint(x: bubble.midX, y: bubble.minY - 8))
        arrow.line(to: NSPoint(x: bubble.midX + 7, y: bubble.minY + 1))
        arrow.close()
        NSColor.white.withAlphaComponent(0.96).setFill()
        arrow.fill()

        let textRect = bubble.insetBy(dx: 10, dy: 7)
        (speech as NSString).draw(in: textRect, withAttributes: attributes)
    }

    private func drawControls() {
        guard controlsVisible else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor(calibratedWhite: 0.18, alpha: 1),
            .paragraphStyle: paragraph
        ]

        for item in controlRects {
            let isPressed = item.action == pressedAction
            let fill = isPressed
                ? NSColor(calibratedRed: 0.87, green: 0.94, blue: 0.98, alpha: 0.96)
                : NSColor.white.withAlphaComponent(0.88)
            fill.setFill()
            NSColor(calibratedWhite: 0.1, alpha: 0.14).setStroke()
            let path = NSBezierPath(roundedRect: item.rect, xRadius: 12, yRadius: 12)
            path.lineWidth = 1
            path.fill()
            path.stroke()

            let textRect = item.rect.insetBy(dx: 3, dy: 6)
            (item.title as NSString).draw(in: textRect, withAttributes: attributes)
        }
    }

    private func action(at point: NSPoint) -> String? {
        guard controlsVisible else { return nil }
        return controlRects.first { $0.rect.insetBy(dx: -5, dy: -5).contains(point) }?.action
    }

    private func isMainPetHit(at point: NSPoint) -> Bool {
        guard petRect.contains(point) else { return false }
        let x = (point.x - petRect.minX) / petScale
        let yFromTop = cellHeight - (point.y - petRect.minY) / petScale

        func ellipse(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat) -> Bool {
            let dx = (x - cx) / rx
            let dy = (yFromTop - cy) / ry
            return dx * dx + dy * dy <= 1
        }

        if onlineConfig.petKind == "dachshund" {
            return ellipse(cx: 92, cy: 132, rx: 76, ry: 40)
                || ellipse(cx: 148, cy: 92, rx: 34, ry: 38)
                || ellipse(cx: 34, cy: 106, rx: 24, ry: 28)
        }

        return ellipse(cx: 96, cy: 118, rx: 58, ry: 66)
            || ellipse(cx: 96, cy: 70, rx: 44, ry: 42)
            || ellipse(cx: 62, cy: 102, rx: 28, ry: 46)
            || ellipse(cx: 132, cy: 102, rx: 28, ry: 46)
    }

    private var controlsVisible: Bool {
        if pressedAction != nil { return true }
        if hovering { return true }
        if let controlsRevealUntil, controlsRevealUntil > Date() { return true }
        return false
    }

    private func updateControlHover(at point: NSPoint) {
        let onMainPet = isMainPetHit(at: point)
        let onGuestPet = guestPetRect?.insetBy(dx: -10, dy: -10).contains(point) ?? false
        hovering = onMainPet || onGuestPet
        if onMainPet || onGuestPet {
            controlsRevealUntil = Date().addingTimeInterval(1.2)
        }
    }

    private func startTimer() {
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.advanceFrameIfNeeded()
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    private func advanceFrameIfNeeded() {
        let now = Date()
        clearAwayVisitIfExpired()
        var shouldRedraw = tongueVisible || heartsStartedAt != nil || guestVisible || isAwayVisiting

        if let animation = petAnimations[activeAnimation],
           now.timeIntervalSince(lastFrameDate) >= 1.0 / animation.fps {
            frameIndex = (frameIndex + 1) % animation.frames
            lastFrameDate = now
            shouldRedraw = true
        }

        if guestVisible,
           let animation = petAnimations[guestAnimation],
           now.timeIntervalSince(guestLastFrameDate) >= 1.0 / animation.fps {
            guestFrameIndex = (guestFrameIndex + 1) % animation.frames
            guestLastFrameDate = now
            shouldRedraw = true
        }

        if isAwayVisiting,
           let animation = petAnimations[awayVisitAnimation],
           now.timeIntervalSince(awayVisitLastFrameDate) >= 1.0 / animation.fps {
            awayVisitFrameIndex = (awayVisitFrameIndex + 1) % animation.frames
            awayVisitLastFrameDate = now
            shouldRedraw = true
        }

        if shouldRedraw {
            needsDisplay = true
        }
    }

    private func setAnimation(_ name: String, duration: TimeInterval? = nil, next: String = "idle") {
        guard petAnimations[name] != nil else { return }
        activeAnimation = name
        frameIndex = 0
        lastFrameDate = Date()
        resetTimer?.invalidate()
        if let duration {
            resetTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                self?.setAnimation(next)
            }
        }
        needsDisplay = true
    }

    private func say(_ text: String, sticky: Bool = false, eventID: Int? = nil) {
        speech = text
        speechTimer?.invalidate()
        stickySpeechEventID = sticky ? eventID : nil
        if !sticky {
            speechTimer = Timer.scheduledTimer(withTimeInterval: 2.4, repeats: false) { [weak self] _ in
                self?.speech = nil
                self?.stickySpeechEventID = nil
                self?.needsDisplay = true
            }
        }
        needsDisplay = true
    }

    private func nudge(love loveDelta: Int = 0, fullness fullnessDelta: Int = 0, energy energyDelta: Int = 0) {
        love = min(100, max(0, love + loveDelta))
        fullness = min(100, max(0, fullness + fullnessDelta))
        energy = min(100, max(0, energy + energyDelta))
        let defaults = UserDefaults.standard
        defaults.set(love, forKey: "juanmao.native.love")
        defaults.set(fullness, forKey: "juanmao.native.fullness")
        defaults.set(energy, forKey: "juanmao.native.energy")
    }

    private func perform(_ action: String, broadcast: Bool = true) {
        if action == "feed", broadcast {
            showFeedPicker()
            return
        }
        if broadcast, isAwayVisiting, action == "pat" || action == "miss" {
            sendAwayInteraction(action)
            return
        }

        if broadcast, action != "close", action != "pat", action != "miss" {
            broadcastOnlineAction(action)
        }

        switch action {
        case "pat": pat()
        case "feed": feed()
        case "walk": walk()
        case "miss": missYou()
        case "nap": nap()
        case "visit": visit()
        case "remind": remind()
        case "close": NSApp.terminate(nil)
        default: break
        }
    }

    private func pat() {
        say(["好舒服。", "再摸一下。", "\(onlineConfig.petName)开心。"].randomElement() ?? "好舒服。")
        nudge(love: 8, energy: 1)
        showTongue()
        setAnimation("wave", duration: 1.35)
    }

    private func feed(food: String? = nil) {
        let clipped = food?.trimmingCharacters(in: .whitespacesAndNewlines)
        let options: [String]
        if let clipped, !clipped.isEmpty {
            options = [
                "\(onlineConfig.petName)吃到\(clipped)啦，好开心呀。",
                "\(clipped)好好吃呀。",
                "谢谢你的\(clipped)。",
                "\(onlineConfig.petName)最喜欢\(clipped)了。"
            ]
        } else {
            options = [
                "\(onlineConfig.petName)好开心呀。",
                "好好吃呀。",
                "\(onlineConfig.petName)吃饱啦。",
                "谢谢投喂。"
            ]
        }
        say(options.randomElement() ?? "好好吃呀。")
        nudge(love: 6, fullness: 18, energy: 2)
        showHearts()
        setAnimation("jump", duration: 1.2)
    }

    private func sendFeed(food: String) {
        let clipped = String(food.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        guard !clipped.isEmpty else { return }
        if isAwayVisiting {
            updateAwayVisit(message: "送\(clipped)过去", animation: "wave")
            say("\(onlineConfig.petName)在对方家送\(clipped)。")
            nudge(love: 3, fullness: -1, energy: -2)
            showHearts()
            broadcastOnlineAction("feed", text: clipped)
        } else {
            feed(food: clipped)
        }
    }

    private func sendAwayInteraction(_ action: String) {
        switch action {
        case "pat":
            updateAwayVisit(message: "摸摸对方", animation: "wave")
            say("\(onlineConfig.petName)在对方家摸摸。")
            nudge(love: 2, fullness: -1, energy: -1)
            showHearts()
            broadcastOnlineAction("pat")
        case "miss":
            updateAwayVisit(message: "说想你", animation: "wave")
            say("\(onlineConfig.petName)在对方家说想你。")
            nudge(love: 4, energy: -1)
            showHearts()
            broadcastOnlineAction("miss")
        default:
            return
        }
    }

    private func nap() {
        say(["安心睡一会儿。", "甜甜小睡。", "\(onlineConfig.petName)睡好啦。"].randomElement() ?? "安心睡一会儿。")
        nudge(fullness: -2, energy: 12)
        setAnimation("sleep")
    }

    private func missYou() {
        say("我也想你")
        nudge(love: 10, energy: 1)
        showHearts()
        setAnimation("wave", duration: 1.8)
    }

    private func visit() {
        say("去串门啦。")
        startAwayVisit(message: "在对方家串门", animation: "runRight")
        nudge(love: 6, fullness: -2, energy: -4)
        showHearts()
        setAnimation("runRight", duration: 1.7)
    }

    private func remind() {
        say("提醒发出啦。")
        showHearts()
        setAnimation("wave", duration: 1.2)
    }

    private func walk(message: String? = nil) {
        guard !isWalking else {
            say("\(onlineConfig.petName)正在散步。")
            return
        }

        say(message ?? (["出门小跑。", "遛弯开始。", "跟着你走。"].randomElement() ?? "遛弯开始。"))
        nudge(love: 5, fullness: -5, energy: -9)
        isWalking = true
        walkDirection = Bool.random() ? 1 : -1
        walkTimer?.invalidate()
        resetTimer?.invalidate()
        walkStep(remaining: 9)
    }

    private func walkStep(remaining: Int) {
        guard remaining > 0, let window = petWindow else {
            isWalking = false
            say("散步回来啦。")
            setAnimation("wave", duration: 1.2)
            return
        }

        let currentFrame = window.frame
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: currentFrame.midX, y: currentFrame.midY)) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? currentFrame
        let maxX = max(visible.minX, visible.maxX - currentFrame.width)
        let maxY = max(visible.minY, visible.maxY - currentFrame.height)
        if currentFrame.origin.x <= visible.minX + 8 {
            walkDirection = 1
        } else if currentFrame.origin.x >= maxX - 8 {
            walkDirection = -1
        } else if Int.random(in: 0...4) == 0 {
            walkDirection *= -1
        }

        let stride = CGFloat.random(in: 82...148)
        let wanderY = CGFloat.random(in: -30...30)
        var targetX = currentFrame.origin.x + stride * walkDirection
        if targetX < visible.minX {
            targetX = visible.minX
            walkDirection = 1
        } else if targetX > maxX {
            targetX = maxX
            walkDirection = -1
        }
        let targetY = min(maxY, max(visible.minY, currentFrame.origin.y + wanderY))
        let target = NSPoint(x: targetX, y: targetY)
        let distance = hypot(target.x - currentFrame.origin.x, target.y - currentFrame.origin.y)

        setAnimation(target.x >= currentFrame.origin.x ? "runRight" : "runLeft")
        moveWindow(from: currentFrame.origin, to: target, duration: min(1.35, max(0.55, TimeInterval(distance / 150)))) { [weak self] in
            self?.walkStep(remaining: remaining - 1)
        }
    }

    private func showTongue() {
        tongueVisible = true
        tongueStartedAt = Date()
        tongueTimer?.invalidate()
        tongueTimer = Timer.scheduledTimer(withTimeInterval: 1.7, repeats: false) { [weak self] _ in
            self?.tongueVisible = false
            self?.tongueStartedAt = nil
            self?.needsDisplay = true
        }
        needsDisplay = true
    }

    private func showHearts() {
        heartsStartedAt = Date()
        needsDisplay = true
    }

    private func showGuestVisit(actor: String, petName: String, petKind: String, speech: String? = nil) {
        guestName = petName
        guestKind = petKind
        guestSpeech = speech ?? "\(petName)来串门"
        guestStartedAt = Date()
        guestAnimation = "runRight"
        guestFrameIndex = 0
        guestLastFrameDate = Date()
        guestVisible = true

        guestWaveTimer?.invalidate()
        guestWaveTimer = Timer.scheduledTimer(withTimeInterval: 1.05, repeats: false) { [weak self] _ in
            self?.guestAnimation = "wave"
            self?.guestFrameIndex = 0
            self?.guestLastFrameDate = Date()
            self?.guestSpeech = speech ?? "嗨，\(self?.onlineConfig.petName ?? "桌宠")"
            self?.needsDisplay = true
        }

        guestTimer?.invalidate()
        guestTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: false) { [weak self] _ in
            self?.guestVisible = false
            self?.guestName = nil
            self?.guestKind = nil
            self?.guestSpeech = nil
            self?.guestStartedAt = nil
            self?.needsDisplay = true
        }
        needsDisplay = true
    }

    private func startAwayVisit(message: String, animation: String = "runRight", duration: TimeInterval = 20.0) {
        awayVisitSpeech = message
        awayVisitStartedAt = Date()
        awayVisitUntil = Date().addingTimeInterval(duration)
        awayVisitAnimation = animation
        awayVisitFrameIndex = 0
        awayVisitLastFrameDate = Date()

        awayVisitTimer?.invalidate()
        awayVisitTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.clearAwayVisitIfExpired()
        }
        needsDisplay = true
    }

    private func updateAwayVisit(message: String, animation: String = "wave") {
        startAwayVisit(message: message, animation: animation, duration: 20.0)
    }

    private func clearAwayVisitIfExpired() {
        guard let awayVisitUntil, awayVisitUntil <= Date() else { return }
        self.awayVisitUntil = nil
        awayVisitStartedAt = nil
        awayVisitSpeech = nil
        needsDisplay = true
    }

    private func startOnlineSync() {
        let timer = Timer(timeInterval: 0.9, repeats: true) { [weak self] _ in
            self?.fetchOnlineEvents()
        }
        RunLoop.main.add(timer, forMode: .common)
        syncTimer = timer
    }

    private func fetchOnlineEvents() {
        guard !syncRequestInFlight else { return }
        guard let url = onlineURL(
            path: "/api/events",
            queryItems: [
                URLQueryItem(name: "since", value: "\(lastSyncEventID)"),
                URLQueryItem(name: "client", value: syncClientID),
                URLQueryItem(name: "actor", value: onlineConfig.actorName),
                URLQueryItem(name: "petName", value: onlineConfig.petName),
                URLQueryItem(name: "petKind", value: onlineConfig.petKind)
            ]
        ) else {
            return
        }
        syncRequestInFlight = true

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.syncRequestInFlight = false
                guard let data,
                      let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let events = payload["events"] as? [[String: Any]] else {
                    return
                }

                for event in events {
                    if let id = event["id"] as? Int {
                        self.lastSyncEventID = max(self.lastSyncEventID, id)
                    }
                    if self.isOwnEchoEvent(event) {
                        continue
                    }
                    guard let action = event["action"] as? String else { continue }
                    self.performRemoteOnlineAction(action, event: event)
                }
            }
        }.resume()
    }

    private func checkForGitUpdate() {
        let currentCommit = onlineConfig.gitCommit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard currentCommit.count >= 7,
              let url = URL(string: onlineConfig.updateAPIURL) else {
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("JuanmaoPet/1.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self,
                  let data,
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let latestCommit = payload["sha"] as? String else {
                return
            }
            let latest = latestCommit.trimmingCharacters(in: .whitespacesAndNewlines)
            guard latest.count >= 7,
                  latest != currentCommit,
                  !latest.hasPrefix(currentCommit),
                  !currentCommit.hasPrefix(latest) else {
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                let short = String(latest.prefix(7))
                self.say("发现新版本 \(short)。")
            }
        }.resume()
    }

    private func onlineURL(path: String, queryItems: [URLQueryItem]) -> URL? {
        guard var components = URLComponents(string: onlineConfig.serverURL) else { return nil }
        components.path = path
        var items = queryItems
        if onlineConfig.room.isEmpty {
            items.append(URLQueryItem(name: "desktop", value: "1"))
        } else {
            items.append(URLQueryItem(name: "room", value: onlineConfig.room))
        }
        components.queryItems = items
        return components.url
    }

    private func performRemoteOnlineAction(_ action: String, event: [String: Any]) {
        guard !isOwnEchoEvent(event) else { return }
        let text = ((event["text"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let remotePetName = displayPetName(petName: event["petName"] as? String, petKind: event["petKind"] as? String)
        let remotePetKind = ((event["petKind"] as? String) ?? "cockapoo").trimmingCharacters(in: .whitespacesAndNewlines)
        recordHistory(event: event, incoming: true)

        switch action {
        case "pat":
            say("\(remotePetName)摸了摸\(onlineConfig.petName)。")
            nudge(love: 8, energy: 1)
            showTongue()
            setAnimation("wave", duration: 1.35)
        case "feed":
            let food = text.isEmpty ? "小饼干" : text
            showGuestVisit(actor: remotePetName, petName: remotePetName, petKind: remotePetKind, speech: "送来\(food)")
            say("\(remotePetName)来投喂：\(food)")
            nudge(love: 4, fullness: 16, energy: 2)
            showHearts()
            setAnimation("jump", duration: 1.2)
        case "walk":
            say("\(remotePetName)带\(onlineConfig.petName)去散步。")
            nudge(love: 5, fullness: -5, energy: -9)
            setAnimation("runRight", duration: 2.2)
        case "miss":
            say("\(remotePetName)说想你。")
            nudge(love: 10, energy: 1)
            showHearts()
            setAnimation("wave", duration: 1.8)
        case "nap":
            say("\(remotePetName)让\(onlineConfig.petName)睡觉。")
            nudge(fullness: -2, energy: 12)
            setAnimation("sleep")
        case "visit":
            showGuestVisit(actor: remotePetName, petName: remotePetName, petKind: remotePetKind)
            say("\(remotePetName)来串门。")
        case "remind":
            showHearts()
            say(text.isEmpty ? "\(remotePetName)提醒：喝水，起来走走。" : "\(remotePetName)：\(text)")
            setAnimation("wave", duration: 1.2)
        case "message":
            say(text.isEmpty ? "\(remotePetName)发来一句话。" : "\(remotePetName)：\(text)")
            showHearts()
            setAnimation("wave", duration: 1.2)
        default:
            break
        }
    }

    private func displayPetName(petName: String?, petKind: String?) -> String {
        let kind = (petKind ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if kind == "dachshund" || kind == "dash" {
            return "叶子"
        }
        if kind == "cockapoo" {
            return "卷毛"
        }
        let name = (petName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "对方小狗" : name
    }

    private func isOwnEchoEvent(_ event: [String: Any]) -> Bool {
        if (event["source"] as? String) == syncClientID {
            return true
        }
        let actor = ((event["actor"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let petName = ((event["petName"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let petKind = ((event["petKind"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return actor == onlineConfig.actorName
            && petName == onlineConfig.petName
            && petKind == onlineConfig.petKind
    }

    private func eventLabel(action: String, event: [String: Any] = [:]) -> String {
        if action == "message" || action == "remind" || action == "feed" {
            let fallbackText = action == "message" ? "文字" : ""
            let text = ((event["text"] as? String) ?? fallbackText).trimmingCharacters(in: .whitespacesAndNewlines)
            if action == "feed" {
                return text.isEmpty ? "投喂" : "投喂\(text)"
            }
            return text.isEmpty ? (action == "remind" ? "提醒" : "文字") : text
        }
        let labels = [
            "pat": "摸摸",
            "feed": "投喂",
            "walk": "遛弯",
            "miss": "想你",
            "nap": "休息",
            "visit": "串门",
            "remind": "提醒"
        ]
        return labels[action] ?? action
    }

    private func broadcastOnlineAction(_ action: String, text: String? = nil) {
        guard let url = onlineURL(path: "/api/action", queryItems: []) else { return }
        var payload: [String: Any] = [
            "action": action,
            "actor": onlineConfig.actorName,
            "petName": onlineConfig.petName,
            "petKind": onlineConfig.petKind,
            "source": syncClientID
        ]
        if let text {
            payload["text"] = text
        } else if action == "remind" {
            payload["text"] = "提醒你喝水，起来走走。"
        }
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        URLSession.shared.dataTask(with: request).resume()
    }

    private func moveWindow(from start: NSPoint, to target: NSPoint, duration: TimeInterval, completion: @escaping () -> Void) {
        guard let window = petWindow else {
            isWalking = false
            return
        }

        let startedAt = Date()
        walkTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self, weak window] timer in
            guard let self, let window else {
                timer.invalidate()
                return
            }

            let elapsed = Date().timeIntervalSince(startedAt)
            let progress = min(1, max(0, elapsed / duration))
            let x = start.x + (target.x - start.x) * progress
            let y = start.y + (target.y - start.y) * progress
            window.setFrameOrigin(NSPoint(x: x, y: y))

            if progress >= 1 {
                timer.invalidate()
                self.walkTimer = nil
                completion()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        walkTimer = timer
    }

    private func addMenuItem(_ title: String, _ selector: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    private func historyText(action: String, event: [String: Any]) -> String {
        let text = ((event["text"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if action == "message" || action == "remind" || action == "feed" {
            return text.isEmpty ? eventLabel(action: action, event: event) : text
        }
        return eventLabel(action: action, event: event)
    }

    private func recordHistory(event: [String: Any], incoming: Bool) {
        guard let action = event["action"] as? String else { return }
        let id = event["id"] as? Int ?? Int(Date().timeIntervalSince1970 * 1000)
        var entries = loadHistory()
        if entries.contains(where: { $0.id == id && $0.incoming == incoming }) {
            return
        }
        let entry = PetHistoryEntry(
            id: id,
            at: ((event["at"] as? Double) ?? Date().timeIntervalSince1970 * 1000) / 1000,
            action: action,
            actor: (event["actor"] as? String) ?? onlineConfig.actorName,
            petName: displayPetName(petName: event["petName"] as? String, petKind: event["petKind"] as? String),
            petKind: (event["petKind"] as? String) ?? onlineConfig.petKind,
            text: historyText(action: action, event: event),
            incoming: incoming
        )
        entries.append(entry)
        entries = entries.sorted { $0.at < $1.at }.suffix(1200)
        if let data = try? JSONEncoder().encode(Array(entries)) {
            UserDefaults.standard.set(data, forKey: "juanmao.native.history")
        }
    }

    private func loadHistory() -> [PetHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: "juanmao.native.history"),
              let entries = try? JSONDecoder().decode([PetHistoryEntry].self, from: data) else {
            return []
        }
        return entries
    }

    private func avatarAttachment(kind: String) -> NSTextAttachment {
        let size = NSSize(width: 20, height: 22)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        let sheet = spriteSheet(for: kind)
        let source = NSRect(x: 0, y: sheet.size.height - cellHeight, width: cellWidth, height: cellHeight)
        sheet.draw(in: NSRect(origin: .zero, size: size), from: source, operation: .sourceOver, fraction: 1)
        image.unlockFocus()

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: -5, width: size.width, height: size.height)
        return attachment
    }

    private func showHistory() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "对话历史"
        alert.informativeText = "按天保存，只显示到日期。"
        alert.addButton(withTitle: "关闭")

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 360))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.windowBackgroundColor
        textView.textContainerInset = NSSize(width: 12, height: 12)

        let output = NSMutableAttributedString()
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "zh_CN")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "zh_CN")
        timeFormatter.dateFormat = "HH:mm"
        var currentDay = ""

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let lineAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]

        let entries = loadHistory().sorted { $0.at < $1.at }
        if entries.isEmpty {
            output.append(NSAttributedString(string: "还没有对话历史。\n", attributes: lineAttrs))
        } else {
            for entry in entries {
                let date = Date(timeIntervalSince1970: entry.at)
                let day = dayFormatter.string(from: date)
                if day != currentDay {
                    currentDay = day
                    output.append(NSAttributedString(string: output.length == 0 ? "\(day)\n" : "\n\(day)\n", attributes: titleAttrs))
                }
                output.append(NSAttributedString(string: "\(timeFormatter.string(from: date)) ", attributes: titleAttrs))
                output.append(NSAttributedString(attachment: avatarAttachment(kind: entry.petKind)))
                let petName = displayPetName(petName: entry.petName, petKind: entry.petKind)
                let arrow = entry.incoming ? "  \(petName): " : "  我 -> \(petName): "
                output.append(NSAttributedString(string: "\(arrow)\(entry.text)\n", attributes: lineAttrs))
            }
        }

        textView.textStorage?.setAttributedString(output)
        scrollView.documentView = textView
        alert.accessoryView = scrollView
        alert.runModal()
    }

    private func showConnectionSettings() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "设置联机网址"
        alert.informativeText = "粘贴新的房间完整链接，或者只填服务器网址。房间码会保存到这台 Mac。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 28))
        field.stringValue = onlineConfig.roomLink
        field.placeholderString = "直接粘贴完整链接、域名、或聊天里的一整段文字"
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let updated = OnlineConfig.from(input: field.stringValue, current: onlineConfig) ?? onlineConfig

        onlineConfig = updated
        onlineConfig.saveConnection()
        lastSyncEventID = 0
        say("联机网址已更新。")
        fetchOnlineEvents()
    }

    private func showTextComposer() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "发送"
        alert.informativeText = "可以发一段文字，也可以直接提醒喝水或让小狗去串门。"
        alert.addButton(withTitle: "发送文字")
        alert.addButton(withTitle: "提醒喝水")
        alert.addButton(withTitle: "去串门")
        alert.addButton(withTitle: "取消")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 28))
        field.placeholderString = "想对对方说什么？"
        alert.accessoryView = field

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            perform("remind")
            return
        }
        if response == .alertThirdButtonReturn {
            perform("visit")
            return
        }
        guard response == .alertFirstButtonReturn else { return }

        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let clipped = String(text.prefix(240))
        say(clipped)
        showHearts()
        setAnimation("wave", duration: 1.2)
        broadcastOnlineAction("message", text: clipped)
    }

    private func showFeedPicker() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "投喂"
        let target = isAwayVisiting ? "对方的小狗" : onlineConfig.petName
        alert.informativeText = "选择一种食物，投喂给\(target)。"
        feedOptions.forEach { alert.addButton(withTitle: $0) }
        alert.addButton(withTitle: "取消")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            sendFeed(food: feedOptions[0])
        case .alertSecondButtonReturn:
            sendFeed(food: feedOptions[1])
        case .alertThirdButtonReturn:
            sendFeed(food: feedOptions[2])
        default:
            return
        }
    }

    private func scalePercentText(_ scale: CGFloat) -> String {
        "\(Int(round(scale / 0.41 * 100)))%"
    }

    private func setPetScale(_ scale: CGFloat, announce: Bool = false) {
        petScale = min(0.68, max(0.28, scale))
        UserDefaults.standard.set(Double(petScale), forKey: "juanmao.native.petScale")
        scaleSliderValueLabel?.stringValue = scalePercentText(petScale)
        if announce {
            say("大小 \(scalePercentText(petScale))")
        }
        needsDisplay = true
    }

    private func showScaleSlider() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "狗狗大小"
        alert.informativeText = "拖动滑条调整大小；可点击范围会同步变化。"
        alert.addButton(withTitle: "完成")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 54))
        let label = NSTextField(labelWithString: scalePercentText(petScale))
        label.alignment = .right
        label.frame = NSRect(x: 292, y: 18, width: 58, height: 20)

        let slider = NSSlider(value: Double(petScale), minValue: 0.28, maxValue: 0.68, target: self, action: #selector(scaleSliderChanged(_:)))
        slider.isContinuous = true
        slider.numberOfTickMarks = 5
        slider.allowsTickMarkValuesOnly = false
        slider.frame = NSRect(x: 8, y: 14, width: 272, height: 28)

        container.addSubview(slider)
        container.addSubview(label)
        scaleSliderValueLabel = label
        alert.accessoryView = container
        alert.runModal()
        scaleSliderValueLabel = nil
        say("大小 \(scalePercentText(petScale))")
    }

    @objc private func scaleSliderChanged(_ sender: NSSlider) {
        setPetScale(CGFloat(sender.doubleValue))
    }

    @objc private func menuPat() { perform("pat") }
    @objc private func menuFeed() { perform("feed") }
    @objc private func menuWalk() { perform("walk") }
    @objc private func menuMiss() { perform("miss") }
    @objc private func menuNap() { perform("nap") }
    @objc private func menuVisit() { perform("visit") }
    @objc private func menuRemind() { perform("remind") }
    @objc private func menuSendText() { showTextComposer() }
    @objc private func menuHistory() { showHistory() }
    @objc private func menuScale() { showScaleSlider() }
    @objc private func menuConnectionSettings() { showConnectionSettings() }
    @objc private func menuClose() { NSApp.terminate(nil) }

    @objc private func handleExternalCommand(_ notification: Notification) {
        guard let action = notification.userInfo?["action"] as? String else { return }
        perform(action, broadcast: false)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        guard let spriteURL = Bundle.main.resourceURL?.appendingPathComponent("assets/coco-spritesheet.png"),
              let spriteSheet = NSImage(contentsOf: spriteURL) else {
            NSApp.terminate(nil)
            return
        }
        let dachshundURL = Bundle.main.resourceURL?.appendingPathComponent("assets/dachshund-spritesheet.png")
        let dachshundSpriteSheet = dachshundURL.flatMap { NSImage(contentsOf: $0) }

        let targetScreen = NSScreen.screens.first { screen in
            screen.frame.minY == 0 && screen.frame.minX >= 0
        } ?? NSScreen.main
        let screenFrame = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let width: CGFloat = 304
        let height: CGFloat = 270
        let frame = NSRect(
            x: screenFrame.maxX - width - 28,
            y: screenFrame.minY + 82,
            width: width,
            height: height
        )

        let view = CocoPetView(
            frame: NSRect(x: 0, y: 0, width: width, height: height),
            spriteSheet: spriteSheet,
            dachshundSpriteSheet: dachshundSpriteSheet
        )
        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.acceptsMouseMovedEvents = true
        window.backgroundColor = .clear
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = view
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.isMovable = false
        window.isOpaque = false
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.sharingType = .readOnly
        view.petWindow = window

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
