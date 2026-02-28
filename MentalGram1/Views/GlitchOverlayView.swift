import SwiftUI
import UIKit

// MARK: - Full-screen cinematic glitch (datamosh / signal-corruption)
//
// Technique: snapshot the live screen → slice into horizontal strips →
// displace them independently → overlay RGB channel separation, neon tint
// bands, CRT scanlines, brightness flicker, white micro-flashes.
//
// The animation runs at a deliberately choppy 18 fps — smooth 60 fps looks
// "animated", while 18 fps feels like real corrupted video data.

struct GlitchOverlayView: View {
    let onComplete: () -> Void

    // Captured assets
    @State private var screenshot: UIImage?
    @State private var imageStrips: [UIImage] = []
    @State private var screenW: CGFloat = 0
    @State private var screenH: CGFloat = 0

    // Animation clock
    @State private var animTimer: Timer?
    @State private var elapsed: Double = 0

    // Per-strip state
    @State private var xOffsets: [CGFloat] = []
    @State private var yJumps: [CGFloat] = []

    // Global effects
    @State private var rgbShift: CGFloat = 0
    @State private var flashOpacity: Double = 0
    @State private var darkFlicker: Double = 0
    @State private var fadeOpacity: Double = 1
    @State private var tintBands: [TintBand] = []

    private let stripCount = 40
    private let totalDuration: Double = 3.0
    private let frameInterval: Double = 1.0 / 18.0

    // MARK: - Body

    var body: some View {
        ZStack {
            if !imageStrips.isEmpty {
                Color.black.ignoresSafeArea()

                // 1 — Displaced horizontal strips (the core effect)
                stripsLayer

                // 2 — RGB chromatic aberration on original screenshot
                rgbSplitLayer

                // 3 — Neon colour-noise bands
                tintBandsLayer

                // 4 — CRT scanlines
                scanlinesLayer

                // 5 — Brightness flicker
                Color.black.opacity(darkFlicker).ignoresSafeArea()

                // 6 — White micro-flash
                Color.white.opacity(flashOpacity).ignoresSafeArea()
            }
        }
        .opacity(fadeOpacity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear(perform: begin)
    }

    // MARK: - Layers

    private var stripsLayer: some View {
        let h = screenH / CGFloat(stripCount)
        return ZStack(alignment: .topLeading) {
            ForEach(0..<imageStrips.count, id: \.self) { i in
                Image(uiImage: imageStrips[i])
                    .resizable()
                    .interpolation(.none)
                    .frame(width: screenW, height: h + 1)
                    .offset(
                        x: i < xOffsets.count ? xOffsets[i] : 0,
                        y: CGFloat(i) * h + (i < yJumps.count ? yJumps[i] : 0)
                    )
            }
        }
        .frame(width: screenW, height: screenH, alignment: .topLeading)
        .clipped()
    }

    private var rgbSplitLayer: some View {
        Group {
            if let screenshot, abs(rgbShift) > 1 {
                Image(uiImage: screenshot)
                    .resizable()
                    .frame(width: screenW, height: screenH)
                    .colorMultiply(Color(red: 1, green: 0, blue: 0))
                    .opacity(0.30)
                    .offset(x: rgbShift)
                    .blendMode(.screen)

                Image(uiImage: screenshot)
                    .resizable()
                    .frame(width: screenW, height: screenH)
                    .colorMultiply(Color(red: 0, green: 0.9, blue: 1))
                    .opacity(0.30)
                    .offset(x: -rgbShift * 0.7)
                    .blendMode(.screen)
            }
        }
    }

    private var tintBandsLayer: some View {
        ForEach(tintBands) { band in
            Rectangle()
                .fill(band.color.opacity(band.opacity))
                .frame(width: screenW + 40, height: band.height)
                .position(x: screenW / 2, y: band.y)
        }
    }

    private var scanlinesLayer: some View {
        Canvas { ctx, size in
            for y in stride(from: CGFloat(0), to: size.height, by: 3) {
                ctx.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                    with: .color(.black.opacity(0.10))
                )
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Engine

    private func begin() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else { onComplete(); return }

        screenW = window.bounds.width
        screenH = window.bounds.height

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let captured = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        screenshot = captured

        guard let cg = captured.cgImage else { onComplete(); return }
        let scale = captured.scale
        let pixelStripH = cg.height / stripCount
        var strips: [UIImage] = []
        for i in 0..<stripCount {
            let py = i * pixelStripH
            let ph = (i == stripCount - 1) ? cg.height - py : pixelStripH
            guard ph > 0,
                  let cropped = cg.cropping(to: CGRect(x: 0, y: py, width: cg.width, height: ph))
            else { continue }
            strips.append(UIImage(cgImage: cropped, scale: scale, orientation: captured.imageOrientation))
        }
        imageStrips = strips
        xOffsets  = Array(repeating: 0, count: strips.count)
        yJumps    = Array(repeating: 0, count: strips.count)

        // Kick-off flash + haptic
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        flashOpacity = 0.92

        animTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { _ in
            tick()
        }
    }

    // MARK: - Per-frame update

    private func tick() {
        elapsed += frameInterval
        if elapsed >= totalDuration {
            animTimer?.invalidate()
            animTimer = nil
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.easeOut(duration: 0.18)) { fadeOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onComplete() }
            return
        }

        let progress = elapsed / totalDuration
        let intensity = computeIntensity(progress)

        // ── Flash ────────────────────────────────────────────────────────
        if elapsed < 0.14 {
            flashOpacity = max(0, 0.92 - elapsed * 7)
        } else {
            flashOpacity = (intensity > 0.5 && Double.random(in: 0...1) < 0.07)
                ? Double.random(in: 0.25...0.60)
                : 0
        }

        // ── Strip X displacement ─────────────────────────────────────────
        // Group adjacent strips with the same offset → organic variable-width slices
        let maxXDisp = screenW * 0.38 * CGFloat(intensity)
        var newX = Array(repeating: CGFloat(0), count: imageStrips.count)
        var idx = 0
        while idx < imageStrips.count {
            let groupSize = Int.random(in: 1...max(1, Int(7.0 * intensity + 1)))
            let displaced = Double.random(in: 0...1) < intensity * 0.65
            let off: CGFloat = displaced ? CGFloat.random(in: -maxXDisp...maxXDisp) : 0
            for j in 0..<min(groupSize, imageStrips.count - idx) {
                newX[idx + j] = off
            }
            idx += groupSize
        }
        xOffsets = newX

        // ── Strip Y jumps (datamosh: data from wrong position) ───────────
        var newY = Array(repeating: CGFloat(0), count: imageStrips.count)
        if intensity > 0.35 {
            let jumpCount = Int(intensity * 5)
            for _ in 0..<jumpCount {
                let i = Int.random(in: 0..<imageStrips.count)
                newY[i] = CGFloat.random(in: -screenH * 0.25...screenH * 0.25)
            }
        }
        yJumps = newY

        // ── RGB split ────────────────────────────────────────────────────
        rgbShift = CGFloat.random(in: -20 * intensity...20 * intensity)

        // ── Brightness flicker ───────────────────────────────────────────
        darkFlicker = Double.random(in: 0...0.28 * intensity)

        // ── Neon tint bands ──────────────────────────────────────────────
        if intensity > 0.25 {
            let n = Int.random(in: 0...Int(5 * intensity))
            let palette: [Color] = [
                .cyan,
                Color(red: 1, green: 0, blue: 0.5),
                .green,
                Color(red: 0.3, green: 0.4, blue: 1),
                Color(red: 1, green: 0.85, blue: 0)
            ]
            tintBands = (0..<n).map { _ in
                TintBand(
                    y: CGFloat.random(in: 0...screenH),
                    height: CGFloat.random(in: 4...25),
                    color: palette.randomElement()!,
                    opacity: Double.random(in: 0.08...0.28)
                )
            }
        } else {
            tintBands = []
        }

        // ── Haptic spikes ────────────────────────────────────────────────
        if intensity > 0.80 && Double.random(in: 0...1) < 0.12 {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
    }

    // MARK: - Intensity curve

    /// Returns 0…1 controlling how chaotic this frame should be.
    private func computeIntensity(_ progress: Double) -> Double {
        if progress < 0.04 {
            // Shock burst (initial flash settles)
            return 1.0
        } else if progress < 0.14 {
            // Build from flash into sustained chaos
            return 0.3 + (progress - 0.04) / 0.10 * 0.55
        } else if progress < 0.73 {
            // Sustained chaos — mostly intense with occasional brief "recovery"
            // frames where the image almost snaps back to normal
            if Double.random(in: 0...1) < 0.06 {
                return Double.random(in: 0.02...0.08) // signal tries to recover
            }
            return Double.random(in: 0.55...1.0)
        } else {
            // Decay — intensity drops, with occasional dying jitters
            let decay = (progress - 0.73) / 0.27
            let base = 0.50 * (1.0 - decay * decay)
            if Double.random(in: 0...1) < 0.18 * (1 - decay) {
                return base + Double.random(in: 0.1...0.3)
            }
            return max(0, base)
        }
    }

    // MARK: - Models

    struct TintBand: Identifiable {
        let id = UUID()
        let y: CGFloat
        let height: CGFloat
        let color: Color
        let opacity: Double
    }
}
