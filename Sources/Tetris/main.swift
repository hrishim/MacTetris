import AppKit

// MARK: - Constants

let kCols = 10
let kRows = 20
let kCell: CGFloat = 28
let kLockDelay: TimeInterval = 0.5
let kMaxLockResets = 15

enum PieceType: Int, CaseIterable {
    case I, O, T, S, Z, J, L
    var color: NSColor {
        switch self {
        case .I: return NSColor(srgbRed: 0.24, green: 0.78, blue: 0.94, alpha: 1)
        case .O: return NSColor(srgbRed: 0.96, green: 0.83, blue: 0.20, alpha: 1)
        case .T: return NSColor(srgbRed: 0.71, green: 0.42, blue: 0.94, alpha: 1)
        case .S: return NSColor(srgbRed: 0.29, green: 0.87, blue: 0.50, alpha: 1)
        case .Z: return NSColor(srgbRed: 0.94, green: 0.35, blue: 0.35, alpha: 1)
        case .J: return NSColor(srgbRed: 0.35, green: 0.48, blue: 0.94, alpha: 1)
        case .L: return NSColor(srgbRed: 0.94, green: 0.57, blue: 0.24, alpha: 1)
        }
    }
}

// MARK: - Shapes: absolute cell coords per piece per SRS rotation state (y-down, 3x3 box, I in 4x4)

let kShapes: [PieceType: [[(Int, Int)]]] = [
    .I: [
        [(0,1),(1,1),(2,1),(3,1)],
        [(2,0),(2,1),(2,2),(2,3)],
        [(0,2),(1,2),(2,2),(3,2)],
        [(1,0),(1,1),(1,2),(1,3)]],
    .O: [
        [(1,0),(2,0),(1,1),(2,1)],
        [(1,0),(2,0),(1,1),(2,1)],
        [(1,0),(2,0),(1,1),(2,1)],
        [(1,0),(2,0),(1,1),(2,1)]],
    .T: [
        [(1,0),(0,1),(1,1),(2,1)],
        [(1,0),(1,1),(2,1),(1,2)],
        [(0,1),(1,1),(2,1),(1,2)],
        [(1,0),(0,1),(1,1),(1,2)]],
    .S: [
        [(1,0),(2,0),(0,1),(1,1)],
        [(1,0),(1,1),(2,1),(2,2)],
        [(1,1),(2,1),(0,2),(1,2)],
        [(0,0),(0,1),(1,1),(1,2)]],
    .Z: [
        [(0,0),(1,0),(1,1),(2,1)],
        [(2,0),(1,1),(2,1),(1,2)],
        [(1,0),(2,0),(0,1),(1,1)],
        [(1,0),(0,1),(1,1),(0,2)]],
    .J: [
        [(0,0),(0,1),(1,1),(2,1)],
        [(1,0),(2,0),(1,1),(1,2)],
        [(0,1),(1,1),(2,1),(2,2)],
        [(1,0),(1,1),(0,2),(1,2)]],
    .L: [
        [(2,0),(0,1),(1,1),(2,1)],
        [(1,0),(1,1),(1,2),(2,2)],
        [(0,1),(1,1),(2,1),(0,2)],
        [(0,0),(0,1),(0,2),(1,2)]],
]

// SRS kick tables, y-up convention (inverted to screen y at use).
// Keyed: from-state -> offsets for clockwise rotation. JLSTZ table.
let kKicksJLSTZ: [[(Int, Int)]] = [
    [(0,0),(-1,0),(-1, 1),(0,-2),(-1,-2)], // 0->R
    [(0,0),( 1,0),( 1,-1),(0, 2),( 1, 2)], // R->2
    [(0,0),( 1,0),( 1,-1),(0, 2),( 1, 2)], // 2->L
    [(0,0),(-1,0),(-1,-1),(0, 2),(-1, 2)], // L->0
]
let kKicksI: [[(Int, Int)]] = [
    [(0,0),(-2,0),( 1,0),(-2,-1),( 1, 2)], // 0->R
    [(0,0),(-1,0),( 2,0),(-1, 2),( 2,-1)], // R->2
    [(0,0),( 2,0),(-1,0),( 2, 1),(-1,-2)], // 2->L
    [(0,0),( 1,0),(-2,0),( 1,-2),(-2, 1)], // L->0
]

func kicks(type: PieceType, from: Int, dir: Int) -> [(Int, Int)] {
    if type == .O { return [(0, 0)] }
    let table = (type == .I) ? kKicksI : kKicksJLSTZ
    if dir == 1 {
        return table[from].map { ($0.0, -$0.1) }
    } else {
        let toState = (from + 3) % 4
        return table[toState].map { (-$0.0, $0.1) }
    }
}

// MARK: - Game model

struct ActivePiece {
    var type: PieceType
    var rot: Int = 0
    var x: Int = 3
    var y: Int = 0
    func cells(rot: Int? = nil, dx: Int = 0, dy: Int = 0) -> [(Int, Int)] {
        let r = rot ?? self.rot
        return kShapes[type]![r].map { ($0.0 + x + dx, $0.1 + y + dy) }
    }
}

enum GameState { case playing, paused, over }
enum GameEvent { case move, rotate, lock, clear(Int), hold, hardDrop, levelUp, gameOver }

final class Game {
    var grid: [[PieceType?]]
    var current = ActivePiece(type: .O)
    var queue: [PieceType] = []
    var bag: [PieceType] = []
    var hold: PieceType?
    var canHold = true
    var score = 0, lines = 0, level = 1
    var combo = -1, b2b = false
    var state: GameState = .playing
    var elapsed: TimeInterval = 0
    private var dropAccum: TimeInterval = 0
    private var lockTimer: TimeInterval = 0
    private var lockResets = 0
    private var lowestY = 0
    var onEvent: (GameEvent) -> Void = { _ in }

    func die() {
        if state != .over { state = .over; onEvent(.gameOver) }
    }

    init() {
        grid = Array(repeating: Array(repeating: nil, count: kCols), count: kRows)
        refill()
        for _ in 0..<4 { queue.append(next()) }
        spawn()
    }

    func refill() {
        if bag.isEmpty {
            bag = PieceType.allCases.shuffled()
        }
    }
    func next() -> PieceType {
        refill()
        return bag.removeLast()
    }

    func collides(_ p: ActivePiece, rot: Int? = nil, dx: Int = 0, dy: Int = 0) -> Bool {
        for (x, y) in p.cells(rot: rot, dx: dx, dy: dy) {
            if x < 0 || x >= kCols || y >= kRows { return true }
            if y >= 0 && grid[y][x] != nil { return true }
        }
        return false
    }

    func spawn() {
        let t = queue.removeFirst()
        queue.append(next())
        let p = ActivePiece(type: t, rot: 0, x: t == .I ? 3 : 3, y: 0)
        current = p
        canHold = true
        lockTimer = 0
        lockResets = 0
        if collides(p) {
            // try one row up (block-out tolerance)
            var q = p
            q.y = -1
            if collides(q) { die(); return }
            current = q
        }
        lowestY = current.y
    }

    func grounded() -> Bool { collides(current, dy: 1) }

    func tryMove(dx: Int) {
        guard state == .playing else { return }
        if !collides(current, dx: dx) {
            current.x += dx
            onEvent(.move)
            resetLockIfGrounded()
        }
    }

    func tryRotate(dir: Int) {
        guard state == .playing else { return }
        let newRot = (current.rot + dir + 4) % 4
        for (kx, ky) in kicks(type: current.type, from: current.rot, dir: dir) {
            if !collides(current, rot: newRot, dx: kx, dy: ky) {
                current.rot = newRot
                current.x += kx
                current.y += ky
                onEvent(.rotate)
                resetLockIfGrounded()
                return
            }
        }
    }

    func trySoftDrop() -> Bool {
        guard state == .playing else { return false }
        if !collides(current, dy: 1) {
            current.y += 1
            score += 1
            if current.y > lowestY { lowestY = current.y; lockTimer = 0; lockResets = 0 }
            return true
        }
        return false
    }

    func hardDrop() {
        guard state == .playing else { return }
        var d = 0
        while !collides(current, dy: 1) { current.y += 1; d += 1 }
        score += 2 * d
        onEvent(.hardDrop)
        lock()
    }

    func doHold() {
        guard state == .playing, canHold else { return }
        onEvent(.hold)
        let cur = current.type
        if let h = hold {
            current = ActivePiece(type: h, rot: 0, x: 3, y: 0)
            if collides(current) { current.y = -1; if collides(current) { die(); return } }
            hold = cur
        } else {
            hold = cur
            spawn()
        }
        canHold = false
        lockTimer = 0
        lockResets = 0
        lowestY = current.y
    }

    func resetLockIfGrounded() {
        if grounded() && lockResets < kMaxLockResets {
            lockTimer = 0
            lockResets += 1
        }
    }

    func gravityInterval() -> TimeInterval {
        let l = Double(level)
        let t = pow(0.8 - (l - 1) * 0.007, l - 1)
        return max(t, 1.0 / 60.0)
    }

    func update(dt: TimeInterval) {
        guard state == .playing else { return }
        elapsed += dt
        if grounded() {
            lockTimer += dt
            if lockTimer >= kLockDelay { lock() }
        } else {
            lockTimer = 0
            dropAccum += dt
            while dropAccum >= gravityInterval() {
                dropAccum -= gravityInterval()
                if !collides(current, dy: 1) {
                    current.y += 1
                    if current.y > lowestY { lowestY = current.y; lockResets = 0 }
                    if grounded() { break }
                } else { break }
            }
        }
    }

    func lock() {
        let prevLevel = level
        for (x, y) in current.cells() {
            if y < 0 { die(); return }
            grid[y][x] = current.type
        }
        // clear lines
        var cleared = 0
        var r = kRows - 1
        while r >= 0 {
            if grid[r].allSatisfy({ $0 != nil }) {
                grid.remove(at: r)
                grid.insert(Array(repeating: nil, count: kCols), at: 0)
                cleared += 1
            } else { r -= 1 }
        }
        if cleared > 0 {
            var pts = [0, 100, 300, 500, 800][cleared] * level
            let difficult = cleared == 4
            if b2b && difficult { pts = pts * 3 / 2 }
            b2b = difficult
            combo += 1
            if combo > 0 { pts += 50 * combo * level }
            let perfect = grid.allSatisfy { row in row.allSatisfy { $0 == nil } }
            if perfect && cleared < 4 { pts += 1000 * level }
            score += pts
            lines += cleared
            level = 1 + lines / 10
        } else {
            combo = -1
        }
        onEvent(cleared > 0 ? .clear(cleared) : .lock)
        if level > prevLevel { onEvent(.levelUp) }
        spawn()
    }
}

// MARK: - View

final class TetrisView: NSView {
    var game = Game()
    var timer: Timer?
    var lastTime: TimeInterval = 0
    let panelW: CGFloat = 190
    private var recorded = false
    private var newBest = false
    private var soundMsg: String = ""
    private var soundMsgUntil: TimeInterval = 0
    private var swipeAccX: CGFloat = 0
    private var swipeAccY: CGFloat = 0
    private var dropFired = false

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        wire()
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        lastTime = CACurrentMediaTime()

        // Trackpad: horizontal swipe = move, swipe up = rotate, hard downward flick = drop
        NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] ev in
            guard let self, self.game.state == .playing else { return ev }
            if ev.phase == .began { self.swipeAccX = 0; self.swipeAccY = 0; self.dropFired = false }
            let dx = ev.scrollingDeltaX, dy = ev.scrollingDeltaY
            if abs(dy) > abs(dx) {
                self.swipeAccY += dy
                if !self.dropFired && self.swipeAccY <= -70 {
                    self.dropFired = true
                    self.game.hardDrop()
                }
                while self.swipeAccY >= 35 { self.swipeAccY -= 35; self.game.tryRotate(dir: 1) }
                while self.swipeAccY <= -20 && !self.dropFired { self.swipeAccY += 20; self.game.trySoftDrop() }
            } else {
                self.swipeAccX += dx
                while self.swipeAccX >= 16 { self.swipeAccX -= 16; self.game.tryMove(dx: 1) }
                while self.swipeAccX <= -16 { self.swipeAccX += 16; self.game.tryMove(dx: -1) }
            }
            self.needsDisplay = true
            return nil  // consume so the window does not scroll
        }
    }

    func wire() {
        game.onEvent = { [weak self] e in
            guard let self else { return }
            switch e {
            case .move:     SoundEngine.shared.play("move")
            case .rotate:   SoundEngine.shared.play("rotate")
            case .lock:     SoundEngine.shared.play("lock")
            case .hold:     SoundEngine.shared.play("hold")
            case .hardDrop: SoundEngine.shared.play("drop")
            case .levelUp:  SoundEngine.shared.play("level")
            case .gameOver: SoundEngine.shared.play("over")
            case .clear(let n):
                SoundEngine.shared.play(n == 4 ? "tetris" : "clear\(min(n,3))")
            }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTime, 0.1)
        lastTime = now
        game.update(dt: dt)
        if game.state == .over && !recorded {
            recorded = true
            newBest = HighScores.record(score: game.score, lines: game.lines)
        }
        needsDisplay = true
    }

    func restart() {
        game = Game()
        wire()
        recorded = false
        newBest = false
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 15 && (event.modifierFlags.contains(.command)) {
            restart(); return
        }
        switch event.keyCode {
        case 123: game.tryMove(dx: -1)       // left
        case 124: game.tryMove(dx: 1)        // right
        case 126, 7: game.tryRotate(dir: 1)  // up / x
        case 8: game.tryRotate(dir: -1)      // z
        case 125: game.trySoftDrop()         // down
        case 49: game.hardDrop()             // space
        case 11, 16: game.doHold()           // c / shift
        case 35: if game.state == .playing { game.state = .paused }
                 else if game.state == .paused { game.state = .playing }  // p
        case 15: restart()                   // r
        case 53: game.state = (game.state == .paused) ? .playing : .paused // esc
        case 46:                                             // m mute toggle
            soundMsg = SoundEngine.shared.toggleMute() ? "sound: off" : "sound: on"
            soundMsgUntil = CACurrentMediaTime() + 1.5
        default: super.keyDown(with: event); return
        }
        needsDisplay = true
    }

    // MARK: drawing

    func drawCell(_ ctx: CGContext, px: CGFloat, py: CGFloat, size: CGFloat, color: NSColor, ghost: Bool = false) {
        let inset: CGFloat = 1
        let rect = CGRect(x: px + inset, y: py + inset, width: size - 2*inset, height: size - 2*inset)
        if ghost {
            color.withAlphaComponent(0.28).setFill()
            ctx.fill(rect)
            color.setStroke()
            ctx.setLineWidth(1.5)
            ctx.stroke(rect.insetBy(dx: 1, dy: 1))
        } else {
            color.setFill()
            ctx.fill(rect)
            NSColor.white.withAlphaComponent(0.30).setFill()
            ctx.fill(CGRect(x: rect.minX, y: rect.maxY - 3, width: rect.width, height: 3))
            NSColor.black.withAlphaComponent(0.25).setFill()
            ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 2))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let W = bounds.width, H = bounds.height
        NSColor(srgbRed: 0.04, green: 0.05, blue: 0.08, alpha: 1).setFill()
        ctx.fill(bounds)

        let boardX: CGFloat = 16
        let boardY: CGFloat = H - 16 - CGFloat(kRows) * kCell

        // board background + grid
        NSColor(srgbRed: 0.02, green: 0.03, blue: 0.05, alpha: 1).setFill()
        ctx.fill(CGRect(x: boardX, y: boardY, width: CGFloat(kCols)*kCell, height: CGFloat(kRows)*kCell))
        NSColor.white.withAlphaComponent(0.05).setStroke()
        ctx.setLineWidth(0.5)
        for c in 0...kCols {
            ctx.move(to: CGPoint(x: boardX + CGFloat(c)*kCell, y: boardY))
            ctx.addLine(to: CGPoint(x: boardX + CGFloat(c)*kCell, y: boardY + CGFloat(kRows)*kCell))
        }
        for r in 0...kRows {
            ctx.move(to: CGPoint(x: boardX, y: boardY + CGFloat(r)*kCell))
            ctx.addLine(to: CGPoint(x: boardX + CGFloat(kCols)*kCell, y: boardY + CGFloat(kRows)*kCell))
        }
        ctx.strokePath()

        // locked cells
        for r in 0..<kRows {
            for c in 0..<kCols {
                if let t = game.grid[r][c] {
                    let px = boardX + CGFloat(c)*kCell
                    let py = boardY + CGFloat(kRows - 1 - r)*kCell
                    drawCell(ctx, px: px, py: py, size: kCell, color: t.color)
                }
            }
        }

        if game.state != .over {
            // ghost
            var gy = 0
            while !game.collides(game.current, dy: gy + 1) { gy += 1 }
            for (x, y) in game.current.cells(dy: gy) {
                if y >= 0 {
                    drawCell(ctx, px: boardX + CGFloat(x)*kCell, py: boardY + CGFloat(kRows - 1 - y)*kCell,
                             size: kCell, color: game.current.type.color, ghost: true)
                }
            }
            // current piece
            for (x, y) in game.current.cells() where y >= 0 {
                drawCell(ctx, px: boardX + CGFloat(x)*kCell, py: boardY + CGFloat(kRows - 1 - y)*kCell,
                         size: kCell, color: game.current.type.color)
            }
        }

        // board border
        NSColor(srgbRed: 0.35, green: 0.4, blue: 0.5, alpha: 1).setStroke()
        ctx.setLineWidth(2)
        ctx.stroke(CGRect(x: boardX, y: boardY, width: CGFloat(kCols)*kCell, height: CGFloat(kRows)*kCell))

        // panel
        let px = boardX + CGFloat(kCols)*kCell + 20
        let pw = panelW
        func label(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 11, color: NSColor = .lightGray, bold: Bool = false) {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: bold ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: .bold)
                            : NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular),
                .foregroundColor: color,
            ]
            NSAttributedString(string: s, attributes: attrs).draw(at: CGPoint(x: x, y: y))
        }
        func miniBox(_ title: String, at y: CGFloat, type: PieceType?) {
            label(title, px, y + 46, size: 10)
            NSColor(white: 1, alpha: 0.06).setFill()
            ctx.fill(CGRect(x: px, y: y, width: pw, height: 42))
            if let t = type {
                let cells = kShapes[t]![0]
                let mini: CGFloat = 12
                let minX = cells.map { $0.0 }.min()!, maxX = cells.map { $0.0 }.max()!
                let minY = cells.map { $0.1 }.min()!, maxY = cells.map { $0.1 }.max()!
                let gw = CGFloat(maxX - minX + 1) * mini, gh = CGFloat(maxY - minY + 1) * mini
                let ox = px + (pw - gw)/2 - CGFloat(minX)*mini
                let oy = y + (42 - gh)/2 - CGFloat(minY)*mini + mini
                for (cx, cy) in cells {
                    let r = CGRect(x: ox + CGFloat(cx)*mini, y: oy + CGFloat(maxY - cy)*mini, width: mini-1, height: mini-1)
                    t.color.setFill(); ctx.fill(r)
                }
            }
        }
        miniBox("HOLD", at: H - 58, type: game.hold)
        label("NEXT", px, H - 96, size: 10)
        for i in 0..<3 {
            let t = game.queue[i]
            let y = H - 140 - CGFloat(i) * 50
            NSColor(white: 1, alpha: 0.05).setFill()
            ctx.fill(CGRect(x: px, y: y, width: pw, height: 44))
            let cells = kShapes[t]![0]
            let mini: CGFloat = 11
            let minX = cells.map { $0.0 }.min()!, maxX = cells.map { $0.0 }.max()!
            let minY = cells.map { $0.1 }.min()!, maxY = cells.map { $0.1 }.max()!
            let gw = CGFloat(maxX - minX + 1) * mini, gh = CGFloat(maxY - minY + 1) * mini
            let ox = px + (pw - gw)/2 - CGFloat(minX)*mini
            let oy = y + (44 - gh)/2 - CGFloat(minY)*mini + mini
            for (cx, cy) in cells {
                let r = CGRect(x: ox + CGFloat(cx)*mini, y: oy + CGFloat(maxY - cy)*mini, width: mini-1, height: mini-1)
                t.color.setFill(); ctx.fill(r)
            }
        }

        label("SCORE", px, H - 320, size: 10)
        label("\(game.score)", px, H - 342, size: 20, color: .white, bold: true)
        label("LINES", px, H - 372, size: 10)
        label("\(game.lines)", px, H - 394, size: 16, color: .white, bold: true)
        label("LEVEL", px, H - 422, size: 10)
        label("\(game.level)", px, H - 444, size: 16, color: .white, bold: true)
        label("TIME", px, H - 472, size: 10)
        let m = Int(game.elapsed) / 60, s = Int(game.elapsed) % 60
        label(String(format: "%d:%02d", m, s), px, H - 494, size: 16, color: .white, bold: true)
        label("HIGH SCORES", px, H - 524, size: 10, color: NSColor(srgbRed: 0.96, green: 0.83, blue: 0.35, alpha: 1))
        let entries = HighScores.top(3)
        if entries.isEmpty {
            label("—", px, H - 542, size: 11)
        } else {
            for (i, e) in entries.enumerated() {
                let gold = (i == 0 && newBest)
                label("\(i+1). \(e.score)", px, H - 542 - CGFloat(i) * 16, size: 12,
                      color: gold ? NSColor(srgbRed: 1, green: 0.84, blue: 0.3, alpha: 1) : .white, bold: gold)
            }
        }
        if CACurrentMediaTime() < soundMsgUntil { label(soundMsg, px, H - 596, size: 10, color: .white) }
        label("\u{2190}\u{2192} move  \u{2191}/Z rotate", px, 60, size: 10)
        label("\u{2193} soft  SP hard  M mute", px, 44, size: 10)
        label("C hold  P pause  R restart", px, 28, size: 10)
        label("swipe: \u{2190}\u{2192} move \u{2191} rot \u{2193} drop", px, 12, size: 10)

        // overlays
        func overlay(_ text: String, _ sub: String) {
            NSColor(white: 0, alpha: 0.55).setFill()
            ctx.fill(CGRect(x: boardX, y: boardY, width: CGFloat(kCols)*kCell, height: CGFloat(kRows)*kCell))
            let a: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 22, weight: .heavy),
                .foregroundColor: NSColor.white,
            ]
            let str = NSAttributedString(string: text, attributes: a)
            let sz = str.size()
            str.draw(at: CGPoint(x: boardX + (CGFloat(kCols)*kCell - sz.width)/2,
                                y: boardY + CGFloat(kRows)*kCell/2))
            let a2: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor(white: 0.8, alpha: 1),
            ]
            let str2 = NSAttributedString(string: sub, attributes: a2)
            let sz2 = str2.size()
            str2.draw(at: CGPoint(x: boardX + (CGFloat(kCols)*kCell - sz2.width)/2,
                                 y: boardY + CGFloat(kRows)*kCell/2 - 26))
        }
        if game.state == .paused { overlay("PAUSED", "press P to resume") }
        if game.state == .over { overlay(newBest ? "NEW BEST!" : "GAME OVER", "press R to restart") }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var view: TetrisView!

    func applicationDidFinishLaunching(_ note: Notification) {
        let w = 16 + CGFloat(kCols)*kCell + 20 + 190 + 16
        let h = 16 + CGFloat(kRows)*kCell + 76
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "Tetris"
        window.center()
        window.backgroundColor = NSColor(srgbRed: 0.04, green: 0.05, blue: 0.08, alpha: 1)
        view = TetrisView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        window.contentView = view
        window.makeFirstResponder(view)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let mainMenu = NSMenu()
        let item = mainMenu.addItem(withTitle: "Tetris", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.addItem(withTitle: "Restart", action: #selector(AppDelegate.restartAction),
                    keyEquivalent: "r")
        sub.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)),
                    keyEquivalent: "q")
        item.submenu = sub
        NSApp.mainMenu = mainMenu
    }

    @objc func restartAction() { view.restart() }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

// MARK: - Touch Bar (no-op on Macs without one)

private let tbItemLeft  = NSTouchBarItem.Identifier("tetris.left")
private let tbItemRight = NSTouchBarItem.Identifier("tetris.right")
private let tbItemRot   = NSTouchBarItem.Identifier("tetris.rotate")
private let tbItemDrop  = NSTouchBarItem.Identifier("tetris.drop")

extension TetrisView {
    override func makeTouchBar() -> NSTouchBar? {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [.flexibleSpace, tbItemLeft, tbItemRot, tbItemDrop, tbItemRight, .flexibleSpace]
        return bar
    }

    @objc func tbLeft()  { game.tryMove(dx: -1); needsDisplay = true }
    @objc func tbRight() { game.tryMove(dx: 1);  needsDisplay = true }
    @objc func tbRot()   { game.tryRotate(dir: 1); needsDisplay = true }
    @objc func tbDrop()  { game.hardDrop();      needsDisplay = true }
}

extension TetrisView: NSTouchBarDelegate {
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let specs: [NSTouchBarItem.Identifier: (String, Selector)] = [
            tbItemLeft:  ("\u{25C0}", #selector(tbLeft)),
            tbItemRight: ("\u{25B6}", #selector(tbRight)),
            tbItemRot:   ("\u{21BB}", #selector(tbRot)),
            tbItemDrop:  ("\u{2913}", #selector(tbDrop)),
        ]
        guard let (title, sel) = specs[identifier] else { return nil }
        let b = NSButton(title: title, target: self, action: sel)
        b.bezelColor = NSColor(white: 0.2, alpha: 1)
        item.view = b
        return item
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
