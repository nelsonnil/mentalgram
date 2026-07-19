import SwiftUI
import Combine
import QuartzCore
import UIKit

/// Transparent full-screen layer: only the floating card.
/// Instagram chrome underneath stays visible; hits pass through except on the card.
/// When the card leaves the screen, `onFinished` fires (swap / archive trigger).
struct InstapickOverlayView: View {
    let card: UIImage
    let onFinished: () -> Void

    @StateObject private var scene = InstapickCardScene()

    var body: some View {
        GeometryReader { geo in
            let screen = geo.size
            let drawn = scene.cardPosition == .zero ? scene.spawnCenter(in: screen) : scene.cardPosition
            let cardSize = scene.cardSize(for: screen)
            let corner = cardSize.width * 0.06

            ZStack {
                ZStack {
                    Image(uiImage: card)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)

                    if scene.showsReflection {
                        // Soft paper gloss: highlight drifts with tilt, but the
                        // light axis stays fixed (no compass-needle spin).
                        RadialGradient(
                            colors: [
                                .white.opacity(0.22 * scene.shineStrength),
                                .white.opacity(0.06 * scene.shineStrength),
                                .clear
                            ],
                            center: UnitPoint(
                                x: 0.32 + scene.reflectX * 0.12,
                                y: 0.22 + scene.reflectY * 0.10
                            ),
                            startRadius: 2,
                            endRadius: max(cardSize.width, cardSize.height) * 0.55
                        )
                        .blendMode(.softLight)
                        .allowsHitTesting(false)

                        // Very light top wash — fixed direction, tiny parallax only.
                        LinearGradient(
                            colors: [
                                .white.opacity(0.10 * scene.shineStrength),
                                .clear,
                                .black.opacity(0.06 * scene.shineStrength)
                            ],
                            startPoint: UnitPoint(
                                x: 0.15 + scene.reflectX * 0.06,
                                y: 0.0 + scene.reflectY * 0.04
                            ),
                            endPoint: UnitPoint(
                                x: 0.85 + scene.reflectX * 0.06,
                                y: 1.0
                            )
                        )
                        .blendMode(.softLight)
                        .allowsHitTesting(false)
                    }

                    // Soft depth INSIDE the rounded mask only — no external shadow
                    // (external shadow was the semi-transparent ghost in the cut corners).
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.18)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }
                .frame(width: cardSize.width, height: cardSize.height)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .compositingGroup()
                .rotationEffect(.degrees(Double(scene.cardRotation)))
                .opacity(scene.cardOpacity)
                .position(drawn)
                .gesture(dragGesture())
            }
            .frame(width: screen.width, height: screen.height)
            .coordinateSpace(name: "instapickCanvas")
            .contentShape(.interaction, InstapickCardHitShape(center: drawn, size: cardSize))
            .transaction { $0.animation = nil }
            .onAppear {
                scene.start(in: screen, onFinished: onFinished)
            }
            .onDisappear {
                scene.stop()
            }
            .onChange(of: geo.size) { newSize in
                scene.updateBounds(newSize)
            }
        }
        .ignoresSafeArea()
    }

    private func dragGesture() -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("instapickCanvas"))
            .onChanged { value in
                scene.dragChanged(start: value.startLocation, location: value.location)
            }
            .onEnded { _ in
                scene.dragEnded()
            }
    }
}

/// Owns motion + physics on the main actor so tilt / reflection / volume impulses stay in sync.
@MainActor
final class InstapickCardScene: ObservableObject {
    @Published var cardPosition: CGPoint = .zero
    @Published var cardRotation: CGFloat = 0
    @Published var cardOpacity: Double = 1
    @Published var showsReflection = true
    /// Light direction on the card face (−1…1). Drives the specular streak.
    @Published var reflectX: CGFloat = 0.15
    @Published var reflectY: CGFloat = -0.25
    @Published var shineCenter: CGFloat = 0.45
    @Published var shineStrength: Double = 0.55
    @Published var velocityX: CGFloat = 0
    @Published var velocityY: CGFloat = 0

    private var engine: InstapickCardEngine?
    private var ticker = InstapickFrameTicker()
    private let motion = InstapickMotionTiltService()
    private var dragSamples: [(time: CFTimeInterval, point: CGPoint)] = []
    private var grabOffset: CGSize = .zero
    private var isDragging = false
    private var hasFinished = false
    private var onFinished: (() -> Void)?
    private var widthFraction: CGFloat = 0.42
    private var screenSize: CGSize = .zero
    private var volumeCancellable: AnyCancellable?
    private var lastHandledDownCount = 0
    private var ignoreVolumeUntil: CFTimeInterval = 0

    func cardSize(for screen: CGSize) -> CGSize {
        CGSize(
            width: screen.width * widthFraction,
            height: (screen.width * widthFraction) / (583.0 / 808.0)
        )
    }

    func spawnCenter(in screen: CGSize) -> CGPoint {
        CGPoint(x: screen.width / 2, y: screen.height * 0.42)
    }

    func start(in screen: CGSize, onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
        self.hasFinished = false
        self.screenSize = screen
        let settings = InstapickSettings.shared
        let center = spawnCenter(in: screen)
        let size = cardSize(for: screen)
        showsReflection = settings.tiltStyle.usesReflection
        cardPosition = center
        cardOpacity = 1
        cardRotation = 0
        reflectX = 0.15
        reflectY = -0.25
        shineCenter = 0.45
        shineStrength = settings.tiltStyle == .softFloat ? 0.22 : 0.34
        velocityX = 0
        velocityY = 0
        engine = InstapickCardEngine(
            cardSize: size,
            bounds: CGRect(origin: .zero, size: screen),
            center: center,
            tiltStyle: settings.tiltStyle
        )
        motion.start()
        lastHandledDownCount = VolumeButtonMonitor.shared.downCount
        // Arming press already happened — ignore volume briefly, then allow FX presses.
        ignoreVolumeUntil = CACurrentMediaTime() + 0.45
        volumeCancellable = VolumeButtonMonitor.shared.$downCount
            .receive(on: RunLoop.main)
            .sink { [weak self] count in
                self?.handleVolumeDown(count)
            }
        ticker.onTick = { [weak self] dt in
            self?.step(dt: dt)
        }
        ticker.start()

        // Soft entrance impulse matching the selected volume FX.
        if settings.volumeFx != .none {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.engine?.applyVolumeFx(settings.volumeFx, intensity: 0.72)
            }
        }
        print("🃏 [INSTAPICK] Scene armed — tilt=\(settings.tiltStyle.rawValue) fx=\(settings.volumeFx.rawValue)")
    }

    func stop() {
        ticker.stop()
        motion.stop()
        volumeCancellable?.cancel()
        volumeCancellable = nil
    }

    func updateBounds(_ screen: CGSize) {
        guard screen != screenSize, !hasFinished else { return }
        screenSize = screen
        let size = cardSize(for: screen)
        engine?.updateLayout(cardSize: size, bounds: CGRect(origin: .zero, size: screen))
    }

    func dragChanged(start: CGPoint, location: CGPoint) {
        guard !hasFinished, let engine else { return }
        if !isDragging {
            isDragging = true
            grabOffset = CGSize(
                width: cardPosition.x - start.x,
                height: cardPosition.y - start.y
            )
            let point = CGPoint(x: start.x + grabOffset.width, y: start.y + grabOffset.height)
            dragSamples = [(CACurrentMediaTime(), point)]
            engine.beginDrag(at: point)
            cardPosition = engine.state.position
        }
        let point = CGPoint(x: location.x + grabOffset.width, y: location.y + grabOffset.height)
        let now = CACurrentMediaTime()
        dragSamples.append((now, point))
        if dragSamples.count > 8 { dragSamples.removeFirst(dragSamples.count - 8) }
        engine.drag(to: point, velocity: estimatedVelocity())
        publish(from: engine)
    }

    func dragEnded() {
        guard !hasFinished, let engine else { return }
        isDragging = false
        let mode = engine.endDrag(predictedVelocity: estimatedVelocity())
        dragSamples.removeAll()
        publish(from: engine)
        if mode == .exiting {
            print("🃏 [INSTAPICK] Card exit fling")
        }
    }

    private func handleVolumeDown(_ count: Int) {
        guard !hasFinished, !isDragging, count != lastHandledDownCount else { return }
        lastHandledDownCount = count
        guard CACurrentMediaTime() >= ignoreVolumeUntil else { return }
        let fx = InstapickSettings.shared.volumeFx
        guard fx != .none else { return }
        engine?.applyVolumeFx(fx, intensity: 1.0)
        print("🃏 [INSTAPICK] Volume FX → \(fx.rawValue)")
    }

    private func step(dt: CFTimeInterval) {
        guard !hasFinished, let engine, !isDragging else { return }
        let g = motion.currentGravity
        engine.step(dt: CGFloat(dt), gravityX: g.x, gravityY: g.y)
        publish(from: engine)
        if engine.mode == .exiting, engine.isFullyOffscreen {
            finish()
        } else if engine.mode == .exiting {
            cardOpacity = 0.35
        }
    }

    private func publish(from engine: InstapickCardEngine) {
        cardPosition = engine.state.position
        cardRotation = engine.state.rotationDegrees
        reflectX = engine.state.reflectX
        reflectY = engine.state.reflectY
        shineCenter = engine.state.shineCenter
        shineStrength = Double(engine.state.shineStrength)
        velocityX = engine.state.velocity.dx
        velocityY = engine.state.velocity.dy
        showsReflection = InstapickSettings.shared.tiltStyle.usesReflection
    }

    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        cardOpacity = 0
        stop()
        onFinished?()
    }

    private func estimatedVelocity() -> CGVector {
        guard dragSamples.count >= 2 else { return .zero }
        let newest = dragSamples[dragSamples.count - 1]
        var oldest = dragSamples[0]
        for sample in dragSamples.reversed() where newest.time - sample.time >= 0.04 {
            oldest = sample
            break
        }
        let dt = newest.time - oldest.time
        guard dt > 0.008 else { return .zero }
        return CGVector(
            dx: (newest.point.x - oldest.point.x) / dt,
            dy: (newest.point.y - oldest.point.y) / dt
        )
    }
}

/// Hit region limited to the floating card so Instagram UI below stays tappable.
private struct InstapickCardHitShape: Shape {
    let center: CGPoint
    let size: CGSize

    func path(in rect: CGRect) -> Path {
        let cardRect = CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        return Path(cardRect)
    }
}

// MARK: - Physics (tilt / 3D / air impulses / exit)

final class InstapickCardEngine {
    enum Mode { case table, airborne, dragging, exiting }

    struct State {
        var position: CGPoint
        var velocity: CGVector
        var rotationDegrees: CGFloat
        var angularVelocity: CGFloat
        /// Specular light direction on the flat card (−1…1).
        var reflectX: CGFloat
        var reflectY: CGFloat
        var shineCenter: CGFloat
        var shineStrength: CGFloat
    }

    private struct Config {
        var slideAccel: CGFloat = 3200
        var softSlideAccel: CGFloat = 1600
        var deadZone: CGFloat = 0.03
        var friction: CGFloat = 2.2
        var softFriction: CGFloat = 3.4
        var maxSpeed: CGFloat = 1800
        var restitution: CGFloat = 0.42
        var airRestitution: CGFloat = 0.62
        var wallFriction: CGFloat = 0.72
        var rotationGain: CGFloat = 0.012
        var maxLeanDegrees: CGFloat = 10
        var exitFriction: CGFloat = 0.55
        var minExitSpeed: CGFloat = 900
        var maxExitSpeed: CGFloat = 2400
        var worldGravity: CGFloat = 2400
        var airDrag: CGFloat = 0.35
        var angularDrag: CGFloat = 1.8
        var centering: CGFloat = 420
        /// Below this rebound speed we consider the bounce finished.
        var settleSpeed: CGFloat = 140
    }

    private let config = Config()
    private(set) var state: State
    private(set) var mode: Mode = .table
    private var cardSize: CGSize
    private var bounds: CGRect
    private var tiltStyle: InstapickTiltStyle
    private var preferAirborne = false
    /// Hop+spin: flip on the way up, self-right while falling so it lands straight.
    private var hopSelfRight = false

    init(
        cardSize: CGSize,
        bounds: CGRect,
        center: CGPoint,
        tiltStyle: InstapickTiltStyle
    ) {
        self.cardSize = cardSize
        self.bounds = bounds
        self.tiltStyle = tiltStyle
        self.state = State(
            position: center,
            velocity: .zero,
            rotationDegrees: 0,
            angularVelocity: 0,
            reflectX: 0.15,
            reflectY: -0.25,
            shineCenter: 0.45,
            shineStrength: tiltStyle == .softFloat ? 0.22 : 0.34
        )
    }

    func updateLayout(cardSize: CGSize, bounds: CGRect) {
        self.cardSize = cardSize
        self.bounds = bounds
        if mode == .table { clampInside() }
    }

    func beginDrag(at position: CGPoint) {
        mode = .dragging
        preferAirborne = false
        hopSelfRight = false
        state.position = position
        state.velocity = .zero
        state.angularVelocity = 0
        // Keep current spin angle — do NOT snap to lean (that looked like a full twist).
        normalizeRotationDisplay()
        clampInside()
    }

    func drag(to position: CGPoint, velocity: CGVector) {
        guard mode == .dragging else { return }
        state.position = position
        state.velocity = velocity
        // Freeze Z rotation while dragging so hop/spin angle doesn't jump.
        clampInside()
    }

    @discardableResult
    func endDrag(predictedVelocity: CGVector) -> Mode {
        var v = predictedVelocity
        let speed = hypot(v.dx, v.dy)
        if speed > config.maxExitSpeed {
            let s = config.maxExitSpeed / speed
            v.dx *= s
            v.dy *= s
        }
        state.velocity = v
        if shouldExit(with: v) {
            mode = .exiting
            preferAirborne = false
            hopSelfRight = false
            boostExitIfNeeded()
        } else {
            let ext = rotatedHalfExtents()
            let floorY = bounds.maxY - ext.y
            let aboveFloor = state.position.y < floorY - 6
            // Any release above the floor (or a toss) uses airborne bounce — not only volume FX.
            if aboveFloor || speed > 70 || abs(v.dy) > 35 {
                preferAirborne = true
                hopSelfRight = false
                mode = .airborne
            } else {
                preferAirborne = false
                hopSelfRight = false
                mode = .table
                clampInside()
            }
        }
        easeRotationTowardLean(blend: 0.2)
        return mode
    }

    func applyVolumeFx(_ fx: InstapickVolumeFx, intensity: CGFloat) {
        guard mode != .dragging, mode != .exiting else { return }
        let i = max(0.2, min(1.2, intensity))
        preferAirborne = true
        mode = .airborne
        hopSelfRight = false
        switch fx {
        case .none:
            return
        case .hopSpin:
            state.velocity.dy -= 1450 * i
            state.velocity.dx += CGFloat.random(in: -140...140) * i
            // Punchy flip on the rise; while falling we steer upright (see stepAirborne).
            let dir: CGFloat = Bool.random() ? 1 : -1
            state.angularVelocity = CGFloat.random(in: 420...560) * dir * i
            hopSelfRight = true
        case .blowBounce:
            state.velocity.dy = min(state.velocity.dy, 0) - (1950 * i)
            state.velocity.dx += CGFloat.random(in: -120...120) * i
            state.angularVelocity += CGFloat.random(in: -200...200) * i
        case .tumbleKick:
            let dir: CGFloat = Bool.random() ? 1 : -1
            state.velocity.dx += 1600 * dir * i
            state.velocity.dy -= 900 * i
            state.angularVelocity = 620 * dir * i
        case .pulse:
            state.velocity.dy -= 720 * i
            state.angularVelocity += CGFloat.random(in: -140...140) * i
        }
        let speed = hypot(state.velocity.dx, state.velocity.dy)
        if speed > 2600 {
            let s = 2600 / speed
            state.velocity.dx *= s
            state.velocity.dy *= s
        }
    }

    func step(dt: CGFloat, gravityX: Double, gravityY: Double) {
        guard dt > 0, dt < 0.05 else { return }
        switch mode {
        case .dragging:
            return
        case .table:
            stepTable(dt: dt, gravityX: gravityX, gravityY: gravityY)
        case .airborne:
            stepAirborne(dt: dt, gravityX: gravityX, gravityY: gravityY)
        case .exiting:
            applyFriction(dt: dt, strength: config.exitFriction, maxSpeed: config.maxExitSpeed)
            integrate(dt: dt)
            easeRotationTowardLean(blend: 0.1)
            updateReflection(gravityX: gravityX, gravityY: gravityY, dt: dt)
        }
    }

    var isFullyOffscreen: Bool {
        let ext = rotatedHalfExtents()
        let r = CGRect(
            x: state.position.x - ext.x,
            y: state.position.y - ext.y,
            width: ext.x * 2,
            height: ext.y * 2
        )
        return !r.intersects(bounds.insetBy(dx: -2, dy: -2))
    }

    private func stepTable(dt: CGFloat, gravityX: Double, gravityY: Double) {
        if tiltStyle.usesSlide {
            var gx = CGFloat(gravityX)
            var gy = CGFloat(gravityY)
            if abs(gx) < config.deadZone { gx = 0 }
            if abs(gy) < config.deadZone { gy = 0 }
            let accel = tiltStyle == .softFloat ? config.softSlideAccel : config.slideAccel
            state.velocity.dx += gx * accel * dt
            state.velocity.dy += gy * accel * dt
            let friction = tiltStyle == .softFloat ? config.softFriction : config.friction
            applyFriction(dt: dt, strength: friction, maxSpeed: config.maxSpeed)
            integrate(dt: dt)
            resolveCollisions(air: false)
            // Soft lean while sliding — shortest-path blend, no snap.
            // When nearly still after a hop, ease upright so grab doesn't twist.
            if hypot(state.velocity.dx, state.velocity.dy) < 50 {
                easeRotationToward(0, blend: 0.16)
            } else {
                easeRotationTowardLean(blend: 0.14)
            }
        } else {
            let center = CGPoint(x: bounds.midX, y: bounds.height * 0.42)
            state.velocity.dx += (center.x - state.position.x) * config.centering * 0.002 * dt
            state.velocity.dy += (center.y - state.position.y) * config.centering * 0.002 * dt
            applyFriction(dt: dt, strength: config.softFriction, maxSpeed: 600)
            integrate(dt: dt)
            clampInside()
            easeRotationToward(0, blend: 0.2)
            state.angularVelocity = 0
        }
        updateReflection(gravityX: gravityX, gravityY: gravityY, dt: dt)
    }

    private func stepAirborne(dt: CGFloat, gravityX: Double, gravityY: Double) {
        state.velocity.dy += config.worldGravity * dt
        state.velocity.dx += CGFloat(gravityX) * 380 * dt
        applyFriction(dt: dt, strength: config.airDrag, maxSpeed: 2800)

        if hopSelfRight {
            applyHopSelfRight(dt: dt)
        }

        // Integrate without clamp — clamp kills bounce; walls use resolveCollisions.
        integrate(dt: dt, clampAfter: false)
        resolveCollisions(air: true)

        let ext = rotatedHalfExtents()
        let floorY = bounds.maxY - ext.y
        let nearFloor = state.position.y >= floorY - 1.5
        let speed = hypot(state.velocity.dx, state.velocity.dy)
        // Only settle after the bounce energy is spent (keep floor rebound inertia).
        if nearFloor,
           speed < config.settleSpeed,
           abs(state.velocity.dy) < config.settleSpeed * 0.55,
           state.velocity.dy >= -40 {
            preferAirborne = false
            hopSelfRight = false
            mode = .table
            state.velocity = .zero
            state.angularVelocity = 0
            normalizeRotationDisplay()
            easeRotationToward(0, blend: 0.45)
            clampInside()
        }
        updateReflection(gravityX: gravityX, gravityY: gravityY, dt: dt)
    }

    /// Hop+spin: free flip while rising, then steer toward upright on the way down.
    /// Angle-based (degrees) — independent of screen resolution.
    private func applyHopSelfRight(dt: CGFloat) {
        if state.velocity.dy < -80 {
            // Rising — keep the spin lively, light damp only.
            state.angularVelocity *= max(0, 1 - 0.6 * dt)
            return
        }

        // Apex / falling — spring toward upright along the shortest angle.
        let err = shortestAngleDelta(from: state.rotationDegrees, to: 0)
        let stiffness: CGFloat = 14
        let damping: CGFloat = 4.2
        state.angularVelocity += err * stiffness * dt
        state.angularVelocity *= max(0, 1 - damping * dt)

        // Near the floor, blend the angle itself so it lands clean.
        let ext = rotatedHalfExtents()
        let floorY = bounds.maxY - ext.y
        let dist = max(0, floorY - state.position.y)
        if dist < bounds.height * 0.28 {
            let blend = min(0.22, (1 - dist / (bounds.height * 0.28)) * 0.22)
            easeRotationToward(0, blend: blend)
        }

        // Cap so it can't rewind into a long reverse spin.
        let maxSpin: CGFloat = 720
        if abs(state.angularVelocity) > maxSpin {
            state.angularVelocity = maxSpin * (state.angularVelocity > 0 ? 1 : -1)
        }
    }

    private func integrate(dt: CGFloat, clampAfter: Bool = true) {
        state.position.x += state.velocity.dx * dt
        state.position.y += state.velocity.dy * dt
        state.rotationDegrees += state.angularVelocity * dt
        state.angularVelocity *= max(0, 1 - config.angularDrag * dt)
        if abs(state.angularVelocity) < 2 { state.angularVelocity = 0 }
        normalizeRotationDisplay()
        // Table/drag: soft clamp. Airborne: bounce via resolveCollisions only.
        if clampAfter, mode != .exiting, mode != .airborne {
            clampInside()
        }
    }

    private func normalizeRotationDisplay() {
        while state.rotationDegrees > 180 { state.rotationDegrees -= 360 }
        while state.rotationDegrees < -180 { state.rotationDegrees += 360 }
    }

    private func shortestAngleDelta(from: CGFloat, to: CGFloat) -> CGFloat {
        var d = to - from
        while d > 180 { d -= 360 }
        while d < -180 { d += 360 }
        return d
    }

    private func easeRotationToward(_ target: CGFloat, blend: CGFloat) {
        let b = max(0, min(1, blend))
        state.rotationDegrees += shortestAngleDelta(from: state.rotationDegrees, to: target) * b
        normalizeRotationDisplay()
    }

    private func easeRotationTowardLean(blend: CGFloat) {
        guard abs(state.angularVelocity) < 30 else { return }
        let lean = state.velocity.dx * config.rotationGain
        let leanClamped = max(-config.maxLeanDegrees, min(config.maxLeanDegrees, lean))
        easeRotationToward(leanClamped, blend: blend)
    }

    private func updateReflection(gravityX: Double, gravityY: Double, dt: CGFloat) {
        guard tiltStyle.usesReflection else {
            state.shineStrength += (0 - state.shineStrength) * min(1, 8 * dt)
            return
        }
        // Mild tracking — enough for a drifting highlight, not a spinning sheen.
        let targetX = CGFloat(max(-1, min(1, gravityX * 0.85)))
        let targetY = CGFloat(max(-1, min(1, gravityY * 0.85)))
        let blend = min(1, 10 * dt)
        state.reflectX += (targetX - state.reflectX) * blend
        state.reflectY += (targetY - state.reflectY) * blend
        let targetCenter = 0.5 + state.reflectX * 0.12 - state.reflectY * 0.08
        state.shineCenter += (max(0.28, min(0.72, targetCenter)) - state.shineCenter) * blend
        let base: CGFloat = tiltStyle == .softFloat ? 0.22 : 0.34
        let boost = hypot(state.reflectX, state.reflectY) * 0.10
        let targetStrength = base + boost
        state.shineStrength += (targetStrength - state.shineStrength) * blend
    }

    private func shouldExit(with v: CGVector) -> Bool {
        let ext = rotatedHalfExtents()
        let p = state.position
        let past =
            p.x < bounds.minX + ext.x - 8 ||
            p.x > bounds.maxX - ext.x + 8 ||
            p.y < bounds.minY + ext.y - 8 ||
            p.y > bounds.maxY - ext.y + 8
        let band: CGFloat = 56
        let fling =
            (p.x < bounds.minX + ext.x + band && v.dx < -220) ||
            (p.x > bounds.maxX - ext.x - band && v.dx > 220) ||
            (p.y < bounds.minY + ext.y + band && v.dy < -220) ||
            (p.y > bounds.maxY - ext.y - band && v.dy > 220)
        return past || fling
    }

    private func boostExitIfNeeded() {
        let ext = rotatedHalfExtents()
        let p = state.position
        let distLeft = (p.x + ext.x) - bounds.minX
        let distRight = bounds.maxX - (p.x - ext.x)
        let distTop = (p.y + ext.y) - bounds.minY
        let distBottom = bounds.maxY - (p.y - ext.y)
        var dir = CGVector(dx: 0, dy: 1)
        let minDist = min(distLeft, distRight, distTop, distBottom)
        if minDist == distLeft { dir = CGVector(dx: -1, dy: 0) }
        else if minDist == distRight { dir = CGVector(dx: 1, dy: 0) }
        else if minDist == distTop { dir = CGVector(dx: 0, dy: -1) }
        let projected = state.velocity.dx * dir.dx + state.velocity.dy * dir.dy
        if projected < config.minExitSpeed {
            let boost = config.minExitSpeed - max(0, projected)
            state.velocity.dx += dir.dx * boost
            state.velocity.dy += dir.dy * boost
        }
    }

    private func applyFriction(dt: CGFloat, strength: CGFloat, maxSpeed: CGFloat) {
        let speed = hypot(state.velocity.dx, state.velocity.dy)
        if speed > 0.5 {
            let factor = max(0, 1 - strength * dt)
            state.velocity.dx *= factor
            state.velocity.dy *= factor
        } else {
            state.velocity = .zero
        }
        let newSpeed = hypot(state.velocity.dx, state.velocity.dy)
        if newSpeed > maxSpeed {
            let s = maxSpeed / newSpeed
            state.velocity.dx *= s
            state.velocity.dy *= s
        }
    }

    /// Half-size of the AABB covering the *rounded* card silhouette at current spin.
    /// Using sharp-rect corners left a transparent ghost in the cut-off round corners
    /// (shadow / gap against the screen edge).
    private func rotatedHalfExtents() -> CGPoint {
        let rad = state.rotationDegrees * .pi / 180
        let cosR = cos(rad)
        let sinR = sin(rad)
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        for p in roundedSilhouetteLocals() {
            let x = abs(p.x * cosR - p.y * sinR)
            let y = abs(p.x * sinR + p.y * cosR)
            if x > maxX { maxX = x }
            if y > maxY { maxY = y }
        }
        return CGPoint(x: maxX, y: maxY)
    }

    /// Same radius fraction as the SwiftUI `clipShape` (width * 0.06),
    /// bumped slightly so continuous corners (squircle) stay fully opaque in collisions.
    private func cardCornerRadius() -> CGFloat {
        min(cardSize.width * 0.085, cardSize.width / 2, cardSize.height / 2)
    }

    /// Sample points on the visible rounded-rect outline (edges + corner arcs).
    private func roundedSilhouetteLocals() -> [CGPoint] {
        let halfW = cardSize.width / 2
        let halfH = cardSize.height / 2
        let r = cardCornerRadius()
        let ix = max(0, halfW - r)
        let iy = max(0, halfH - r)

        var pts: [CGPoint] = [
            CGPoint(x: halfW, y: 0),
            CGPoint(x: -halfW, y: 0),
            CGPoint(x: 0, y: halfH),
            CGPoint(x: 0, y: -halfH)
        ]

        // Continuous corners are a bit fuller than circular; sample the arcs densely.
        let angles: [CGFloat] = [0, .pi / 10, .pi / 5, .pi / 3.3, .pi / 2]
        for a in angles {
            let ca = cos(a)
            let sa = sin(a)
            pts.append(CGPoint(x: ix + r * ca, y: iy + r * sa))       // top-right
            pts.append(CGPoint(x: -ix - r * ca, y: iy + r * sa))      // top-left
            pts.append(CGPoint(x: -ix - r * ca, y: -iy - r * sa))     // bottom-left
            pts.append(CGPoint(x: ix + r * ca, y: -iy - r * sa))      // bottom-right
        }
        return pts
    }

    /// Rectangular walls using the rounded rotated footprint.
    private func resolveCollisions(air: Bool) {
        let ext = rotatedHalfExtents()
        let minX = bounds.minX + ext.x
        let maxX = bounds.maxX - ext.x
        let minY = bounds.minY + ext.y
        let maxY = bounds.maxY - ext.y
        // Degenerate if spun card is larger than the screen — keep centered.
        guard minX <= maxX, minY <= maxY else {
            state.position = CGPoint(x: bounds.midX, y: bounds.midY)
            state.velocity = .zero
            return
        }
        let rest = air ? config.airRestitution : config.restitution

        if state.position.x < minX {
            state.position.x = minX
            state.velocity.dx = abs(state.velocity.dx) * rest
            state.velocity.dy *= config.wallFriction
            state.angularVelocity *= -0.35
        } else if state.position.x > maxX {
            state.position.x = maxX
            state.velocity.dx = -abs(state.velocity.dx) * rest
            state.velocity.dy *= config.wallFriction
            state.angularVelocity *= -0.35
        }
        if state.position.y < minY {
            state.position.y = minY
            state.velocity.dy = abs(state.velocity.dy) * rest
            state.velocity.dx *= config.wallFriction
        } else if state.position.y > maxY {
            state.position.y = maxY
            // Preserve downward impact → upward rebound (don't zero early).
            if state.velocity.dy > 0 {
                state.velocity.dy = -abs(state.velocity.dy) * rest
            } else {
                state.velocity.dy = -abs(state.velocity.dy) * rest
            }
            state.velocity.dx *= config.wallFriction
            // Tiny impacts stop bouncing; bigger ones keep inertia.
            if air, abs(state.velocity.dy) < 90 {
                state.velocity.dy = 0
            }
        }
    }

    private func clampInside() {
        let ext = rotatedHalfExtents()
        let minX = bounds.minX + ext.x
        let maxX = bounds.maxX - ext.x
        let minY = bounds.minY + ext.y
        let maxY = bounds.maxY - ext.y
        guard minX <= maxX, minY <= maxY else {
            state.position = CGPoint(x: bounds.midX, y: bounds.midY)
            return
        }
        state.position.x = min(max(state.position.x, minX), maxX)
        state.position.y = min(max(state.position.y, minY), maxY)
    }
}

@MainActor
final class InstapickFrameTicker: NSObject {
    private var link: CADisplayLink?
    var onTick: ((CFTimeInterval) -> Void)?

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        onTick = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        onTick?(link.duration > 0 ? link.duration : 1.0 / 60.0)
    }
}
