import SwiftUI

// MARK: - Motion
//
// Every animation in the app is a spring keyed to causality: `.snappy` when the
// user did something, `.smooth` when layout reflows, `.bouncy` reserved solely
// for the HUD's state morph. Six named transitions cover the whole app; there
// are no timing curves and no ad-hoc `easeInOut` tweens.
//
// All six collapse to a single 0.15s smooth fade under Reduce Motion.

nonisolated enum Motion {

    /// What every named transition becomes when Reduce Motion is on.
    static let reduced = Animation.smooth(duration: 0.15)

    /// Plate fill/stroke lift, HUD control fill lift, icon-button reveal,
    /// dropdown row highlight.
    static func hover(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : .smooth(duration: 0.12)
    }

    /// Press feedback — scale 0.985 for plates, 0.97 for HUD controls.
    static func press(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : .snappy(duration: 0.16, extraBounce: 0)
    }

    /// Sidebar selection capsule, segmented controls, model-row accent adoption,
    /// filter pills.
    static func select(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : .snappy(duration: 0.24, extraBounce: 0.05)
    }

    /// Pane swap, list mutation, expansion, permission-strip collapse.
    static func layout(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : .smooth(duration: 0.28)
    }

    /// THE signature: recording → transcribing → review, one continuous morph.
    static func hudMorph(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : .bouncy(duration: 0.38, extraBounce: 0.06)
    }

    /// HUD presentation — scale 0.92→1, opacity 0→1, y +8→0.
    /// Under Reduce Motion this becomes a pure opacity fade at full scale.
    static func hudEnter(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : .bouncy(duration: 0.34, extraBounce: 0.08)
    }

    /// HUD dismissal — scale 1→0.96, opacity → 0.
    static func hudExit(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : .smooth(duration: 0.20)
    }

    /// Per-bar spring for the level meter. Retuned from 0.18/0.75.
    /// Under Reduce Motion the meter snaps — pass `nil` instead of this.
    static let meterBar = Animation.spring(response: 0.16, dampingFraction: 0.72)

    /// The meter spring, or `nil` (snap) under Reduce Motion.
    static func meterBar(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : meterBar
    }

    /// Gate for the five `repeatForever` loops: the recording dot's phase
    /// animator, the three shimmers, and the menu-bar variable-colour effect.
    /// When this is `false` each one must render a static resting frame
    /// (dot at 0.85 opacity, shimmer flat).
    static func repeatsAllowed(reduceMotion: Bool) -> Bool { !reduceMotion }
}

// MARK: - Environment plumbing

/// The resolved motion vocabulary for the current accessibility settings.
///
/// Views read `@Environment(\.motion)` once and use `motion.select`,
/// `motion.layout` … rather than each one re-reading
/// `accessibilityReduceMotion` and re-deriving the spring.
nonisolated struct MotionValues: Equatable, Sendable {
    var reduceMotion: Bool = false

    var hover: Animation { Motion.hover(reduceMotion: reduceMotion) }
    var press: Animation { Motion.press(reduceMotion: reduceMotion) }
    var select: Animation { Motion.select(reduceMotion: reduceMotion) }
    var layout: Animation { Motion.layout(reduceMotion: reduceMotion) }
    var hudMorph: Animation { Motion.hudMorph(reduceMotion: reduceMotion) }
    var hudEnter: Animation { Motion.hudEnter(reduceMotion: reduceMotion) }
    var hudExit: Animation { Motion.hudExit(reduceMotion: reduceMotion) }
    var meterBar: Animation? { Motion.meterBar(reduceMotion: reduceMotion) }
    var repeatsAllowed: Bool { Motion.repeatsAllowed(reduceMotion: reduceMotion) }
}

nonisolated struct MotionValuesKey: EnvironmentKey {
    static let defaultValue = MotionValues()
}

extension EnvironmentValues {
    /// The resolved springs for this subtree. Injected by `.motionEnvironment()`
    /// at each root (the settings scene and each HUD panel); the default value
    /// is the non-reduced vocabulary, so a view that misses the injection still
    /// animates correctly — it just won't honour Reduce Motion.
    nonisolated var motion: MotionValues {
        get { self[MotionValuesKey.self] }
        set { self[MotionValuesKey.self] = newValue }
    }
}

private struct MotionEnvironmentModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    nonisolated init() {}

    func body(content: Content) -> some View {
        content.environment(\.motion, MotionValues(reduceMotion: reduceMotion))
    }
}

extension View {
    /// Resolves `accessibilityReduceMotion` once and publishes the whole motion
    /// vocabulary downward. Apply at every hosting root.
    nonisolated func motionEnvironment() -> some View {
        modifier(MotionEnvironmentModifier())
    }
}
