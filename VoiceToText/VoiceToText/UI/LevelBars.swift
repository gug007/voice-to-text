import SwiftUI

/// Mirrored capsule bars, oldest → newest, left → right. Each bar springs to its
/// level independently so the strip feels alive even on a steady signal; a small
/// floor keeps silent bars visible as a thin baseline. Shared by the dictation
/// HUD and the Conversations recording card.
///
/// THE SAMPLING FIX. The buffer holds 140 samples and the strip draws 56 bars.
/// It used to nearest-neighbour those: `samples[Int(i * 140/56)]` — bar *i* read
/// one sample and the other ~1.5 in its window were thrown away, so roughly 60%
/// of the captured audio never reached the screen and a short transient landed
/// or vanished depending on where it fell in the stride. Every bar now averages
/// its whole window, so all 140 samples contribute and the trace is a real
/// envelope rather than a subsample of one.
struct LevelBars: View {
    let samples: [Double]
    /// Bar colour. `ink` in both appearances — the old hardcoded white only
    /// worked on the black HUD slab that no longer exists.
    var tint: Color = Palette.ink
    /// Transcribing: the bars keep their last values and desaturate in place
    /// rather than being replaced by unrelated dots.
    var isFrozen: Bool = false
    /// The write head is clipping: the rightmost bars lerp toward `signalLive`.
    var isOverloaded: Bool = false

    @Environment(\.motion) private var motion

    /// Smoothed level above which the overload cue lights.
    static let overloadThreshold: Double = 0.75

    private static let barCount = 56
    private static let barSpacing: CGFloat = 3
    private static let minBarHeight: CGFloat = 3
    /// How many bars at the write head carry the overload cue.
    private static let overloadBars = 6

    var body: some View {
        let pooled = Self.pooled(samples, into: Self.barCount)

        GeometryReader { geo in
            // THE OVERFLOW FIX. Bar width used to be computed here — geometry
            // width minus spacing, over 56 — and handed to each bar as a fixed
            // frame. Two ways that spilled past the card's right inset: the
            // `max(2, …)` floor silently made the row wider than its box on any
            // narrow container, and during the card's width morph each bar's
            // frame was a separate animatable value, so it lagged the shrinking
            // container by a frame and the strip hung outside. Flexible bars
            // make the HStack divide the real width every layout pass, so the
            // row is exactly as wide as its box and both edges sit on the inset.
            HStack(alignment: .center, spacing: Self.barSpacing) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    MeterBar(
                        level: pooled[index],
                        maxHeight: geo.size.height,
                        color: color(at: index),
                        animation: motion.meterBar
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .animation(motion.hover, value: isOverloaded)
        // Routed through `Motion` like everything else on this panel: the
        // desaturation settles over 0.4s normally and snaps under Reduce Motion.
        .animation(freezeAnimation, value: isFrozen)
    }

    // MARK: Colour

    /// The transcribing hand-off: bars hold their last values and desaturate in
    /// place over 0.4s. Slower than any named transition on purpose — it reads
    /// as the meter settling rather than as a state swap.
    private var freezeAnimation: Animation {
        motion.reduceMotion ? Motion.reduced : .smooth(duration: 0.4)
    }

    private func color(at index: Int) -> Color {
        if isFrozen { return Palette.inkFaint.opacity(0.30) }
        let base = tint.opacity(opacity(at: index))
        guard isOverloaded else { return base }
        return base.mix(with: Palette.signalLive, by: overloadAmount(at: index))
    }

    /// Older samples on the left fade out; the rightmost bars sit at the write
    /// head and read as the current input.
    private func opacity(at index: Int) -> Double {
        let t = Double(index) / Double(Self.barCount - 1)
        return 0.20 + 0.65 * t
    }

    /// 0 everywhere but the last `overloadBars`, ramping to 1 at the write head.
    private func overloadAmount(at index: Int) -> Double {
        let first = Self.barCount - Self.overloadBars
        guard index >= first else { return 0 }
        return Double(index - first + 1) / Double(Self.overloadBars)
    }

    // MARK: Pooling

    /// Average-pools `samples` into `count` buckets. Every sample lands in
    /// exactly one bucket, and no bucket is empty as long as there is at least
    /// one sample.
    static func pooled(_ samples: [Double], into count: Int) -> [Double] {
        guard count > 0 else { return [] }
        guard !samples.isEmpty else { return Array(repeating: 0, count: count) }

        let total = samples.count
        var result = [Double](repeating: 0, count: count)
        for bucket in 0..<count {
            let lower = bucket * total / count
            let upper = max(lower + 1, min(total, (bucket + 1) * total / count))
            guard lower < total else {
                result[bucket] = samples[total - 1]
                continue
            }
            var sum = 0.0
            for index in lower..<upper { sum += samples[index] }
            result[bucket] = sum / Double(upper - lower)
        }
        return result
    }
}

/// One bar, isolated so the per-bar spring re-evaluates a leaf rather than the
/// whole strip — 56 springing bars inside one body would spike the view count
/// on every audio tick.
private struct MeterBar: View {
    let level: Double
    let maxHeight: CGFloat
    let color: Color
    /// `nil` under Reduce Motion: the bar snaps instead of springing.
    let animation: Animation?

    private static let minHeight: CGFloat = 3

    var body: some View {
        Capsule()
            .fill(color)
            // Width comes from the HStack's equal split of the container, not
            // from a measurement — that is what keeps the strip inside its box.
            // Only the height is ours, and only the height springs.
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .animation(animation, value: level)
    }

    private var height: CGFloat {
        let clamped = min(1, max(0, level))
        return Self.minHeight + (maxHeight - Self.minHeight) * CGFloat(clamped)
    }
}

#if DEBUG
#Preview("Meter") {
    let samples = (0..<140).map { index in
        0.15 + 0.7 * abs(sin(Double(index) / 9))
    }
    return VStack(spacing: Space.s6) {
        LevelBars(samples: samples).frame(height: 56)
        LevelBars(samples: samples, isOverloaded: true).frame(height: 56)
        LevelBars(samples: samples, isFrozen: true).frame(height: 56)
    }
    .padding(Space.s7)
    .frame(width: 420)
    .background(Palette.canvas)
    .motionEnvironment()
}
#endif
