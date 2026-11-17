import SwiftUI

enum RateFormat {
    static func label(_ rate: Double) -> String {
        var text = String(format: "%.2f", (rate * 100).rounded() / 100)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text + "\u{00D7}"
    }

    static func listenLine(duration: Double, rate: Double) -> String {
        let total = duration.rounded(.down)
        let listen = (duration / rate).rounded(.down)
        if abs(rate - 1) < 0.001 { return "Listen in \(DurationFormat.clock(total))" }
        if rate > 1 { return "Listen in \(DurationFormat.clock(listen)) · saves \(DurationFormat.clock(total - listen))" }
        return "Listen in \(DurationFormat.clock(listen)) · adds \(DurationFormat.clock(listen - total))"
    }

    static func remaining(_ seconds: Double) -> String {
        "\u{2212}" + DurationFormat.clock(seconds)
    }
}

@Observable
final class PlayerDock {
    var cardHidden = false
    var topInset: CGFloat = 0
}

struct PlayerScrollView<Content: View>: View {
    let player: RecordingPlayer
    var docks = true
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dock = PlayerDock()
    @State private var scroll = ScrollPosition(edge: .top)

    var body: some View {
        ScrollView {
            content
        }
        .scrollPosition($scroll)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentInsets.top } action: { _, top in
            dock.topInset = top
        }
        .environment(dock)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ZStack {
                if showsMini {
                    MiniPlayer(player: player) {
                        withAnimation(reduceMotion ? nil : .smooth) { scroll.scrollTo(edge: .top) }
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.86), value: showsMini)
        }
    }

    private var showsMini: Bool {
        docks && player.source != nil && dock.cardHidden
    }
}

struct PlayerCard: View {
    let player: RecordingPlayer
    let source: RecordingPlayer.Source

    @Environment(PlayerDock.self) private var dock: PlayerDock?
    @State private var scrubLabel: String?
    @State private var showSpeed = false

    var body: some View {
        let top = dock?.topInset ?? 0
        VStack(spacing: 10) {
            WaveformScrubber(player: player, scrubLabel: $scrubLabel)
                .padding(.top, 4)
            HStack(spacing: 8) {
                Text(DurationFormat.clock(player.position))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Elapsed")
                    .accessibilityValue(DurationFormat.clock(player.position))
                SpeedChip(player: player) { showSpeed = true }
                Text(RateFormat.remaining(player.remaining))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("Time left at this speed")
                    .accessibilityValue(DurationFormat.clock(player.remaining))
            }
            .font(.footnote)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            HStack(spacing: 28) {
                SkipButton(player: player, direction: .backward)
                PlayPauseButton(player: player)
                SkipButton(player: player, direction: .forward)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .top) {
            PlayerHUD(player: player, scrubLabel: scrubLabel)
                .offset(y: -20)
        }
        .sheet(isPresented: $showSpeed) { SpeedSheet(player: player) }
        .onAppear { player.load(source) }
        .onChange(of: source) { player.load(source) }
        .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).maxY < top } action: { hidden in
            dock?.cardHidden = hidden
        }
        .onDisappear { dock?.cardHidden = false }
    }
}

struct WaveformScrubber: View {
    let player: RecordingPlayer
    @Binding var scrubLabel: String?

    @GestureState private var touching = false
    @State private var lastX: CGFloat?
    @State private var target: Double = 0

    private static let height: CGFloat = 52
    private static let barWidth: CGFloat = 2.5
    private static let barSpacing: CGFloat = 2
    private static let placeholder: Float = 0.12

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let progress = player.progress
            let levels = Self.levels(player.peaks, width: width)
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let bars = Self.bars(levels, size: size)
                    context.fill(bars, with: .color(Color(.tertiaryLabel)))
                    var played = context
                    played.clip(to: Path(CGRect(x: 0, y: 0, width: size.width * progress, height: size.height)))
                    played.fill(bars, with: .color(Color(.label)))
                }
                Capsule()
                    .fill(Palette.ready)
                    .frame(width: 2, height: Self.height + 8)
                    .overlay(alignment: .top) {
                        Circle().fill(Palette.ready).frame(width: 8, height: 8).offset(y: -4)
                    }
                    .position(x: min(max(progress * width, 1), max(width - 1, 1)), y: Self.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($touching) { _, state, _ in state = true }
                    .onChanged { changed($0, width: width) }
                    .onEnded { _ in finish() }
            )
        }
        .frame(height: Self.height)
        .onChange(of: touching) { _, now in
            if !now { finish() }
        }
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(DurationFormat.clock(player.position)) of \(DurationFormat.clock(player.duration))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: player.skip(by: 15)
            case .decrement: player.skip(by: -15)
            @unknown default: break
            }
        }
    }

    private func changed(_ value: DragGesture.Value, width: CGFloat) {
        let duration = player.duration
        guard duration > 0, width > 0 else { return }
        let x = value.location.x
        if let lastX {
            let speed = Self.speed(below: value.location.y - Self.height)
            target = min(max(target + Double((x - lastX) / width) * duration * speed.factor, 0), duration)
            self.lastX = x
            if scrubLabel != speed.label { scrubLabel = speed.label }
        } else {
            player.beginScrub()
            target = Double(min(max(x / width, 0), 1)) * duration
            lastX = x
        }
        player.scrub(to: target)
    }

    private func finish() {
        guard lastX != nil else { return }
        lastX = nil
        scrubLabel = nil
        player.endScrub(at: target)
    }

    private static func speed(below: CGFloat) -> (factor: Double, label: String) {
        switch below {
        case ..<40: return (1, "Hi-speed scrubbing")
        case ..<90: return (0.5, "Half-speed scrubbing")
        case ..<140: return (0.25, "Quarter-speed scrubbing")
        default: return (0.1, "Fine scrubbing")
        }
    }

    private static func levels(_ peaks: [Float]?, width: CGFloat) -> [Float] {
        let count = max(1, Int((width + barSpacing) / (barWidth + barSpacing)))
        guard let peaks, !peaks.isEmpty else { return Array(repeating: placeholder, count: count) }
        return (0..<count).map { bar in
            let start = bar * peaks.count / count
            let end = max(start + 1, (bar + 1) * peaks.count / count)
            let slice = peaks[start..<min(end, peaks.count)]
            return slice.reduce(0, +) / Float(slice.count)
        }
    }

    private static func bars(_ levels: [Float], size: CGSize) -> Path {
        var path = Path()
        let step = levels.count > 1 ? (size.width - barWidth) / CGFloat(levels.count - 1) : 0
        for (index, level) in levels.enumerated() {
            let height = max(3, CGFloat(level) * size.height)
            let rect = CGRect(x: CGFloat(index) * step, y: (size.height - height) / 2, width: barWidth, height: height)
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2))
        }
        return path
    }
}

struct PlayerHUD: View {
    let player: RecordingPlayer
    var scrubLabel: String?

    var body: some View {
        ZStack {
            if let text {
                HStack(spacing: 6) {
                    if let icon { Image(systemName: icon) }
                    Text(text).contentTransition(.numericText())
                }
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color(.systemBackground))
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Color(.label), in: Capsule())
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                .fixedSize()
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: text)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var icon: String? {
        guard let scan = player.scan else { return nil }
        return scan.direction == .forward ? "forward.fill" : "backward.fill"
    }

    private var text: String? {
        if let scan = player.scan {
            return "\(scan.direction == .forward ? "Fast-forward" : "Rewind") \(RateFormat.label(scan.rate))"
        }
        return scrubLabel
    }
}

struct PlayPauseButton: View {
    let player: RecordingPlayer
    var diameter: CGFloat = 60
    var iconSize: CGFloat = 24

    var body: some View {
        Button {
            player.toggle()
        } label: {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: iconSize, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(Color(.systemBackground))
                .offset(x: player.isPlaying ? 0 : iconSize * 0.07)
                .frame(width: diameter, height: diameter)
                .background(Color(.label), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
    }
}

private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SkipButton: View {
    let player: RecordingPlayer
    let direction: RecordingPlayer.ScanDirection
    var symbolSize: CGFloat = 26
    var hitSize: CGFloat = 48

    @GestureState private var pressing = false
    @State private var down = false
    @State private var travel: CGFloat = 0
    @State private var hold: Task<Void, Never>?
    @State private var scanning = false
    @State private var nudges = 0

    private var isBack: Bool { direction == .backward }

    private var nudge: RotateSymbolEffect {
        isBack ? .rotate.counterClockwise.byLayer : .rotate.clockwise.byLayer
    }

    var body: some View {
        Image(systemName: isBack ? "gobackward.15" : "goforward.30")
            .font(.system(size: symbolSize, weight: .medium))
            .symbolEffect(nudge, options: .speed(1.5), value: nudges)
            .foregroundStyle(.primary)
            .frame(width: hitSize, height: hitSize)
            .contentShape(Rectangle())
            .scaleEffect(pressing ? 0.88 : 1)
            .opacity(pressing ? 0.6 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: pressing)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($pressing) { _, state, _ in state = true }
                    .onChanged { value in
                        if !down {
                            down = true
                            began()
                        }
                        travel = max(travel, hypot(value.translation.width, value.translation.height))
                    }
                    .onEnded { _ in
                        guard down else { return }
                        down = false
                        ended(cancelled: false)
                    }
            )
            .onChange(of: pressing) { _, now in
                guard !now, down else { return }
                down = false
                ended(cancelled: true)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: nudges)
            .accessibilityElement()
            .accessibilityLabel(isBack ? "Back 15 seconds" : "Forward 30 seconds")
            .accessibilityHint(isBack ? "Hold to rewind" : "Hold to fast-forward")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { skip() }
    }

    private func began() {
        travel = 0
        hold?.cancel()
        hold = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, travel < 24 else { return }
            scanning = true
            player.beginScan(direction)
        }
    }

    private func ended(cancelled: Bool) {
        hold?.cancel()
        hold = nil
        if scanning {
            scanning = false
            player.endScan()
        } else if !cancelled, travel < 24 {
            skip()
        }
    }

    private func skip() {
        player.skip(by: isBack ? -RecordingPlayer.backInterval : RecordingPlayer.forwardInterval)
        nudges += 1
    }
}

struct SpeedChip: View {
    let player: RecordingPlayer
    var compact = false
    let open: () -> Void

    @State private var resets = 0

    var body: some View {
        let isDefault = abs(player.rate - 1) < 0.001
        let shape = RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
        Text(RateFormat.label(player.rate))
            .font(compact ? .footnote.weight(.bold) : .subheadline.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(isDefault ? Color(.label) : Color(.systemBackground))
            .padding(.horizontal, compact ? 7 : 10)
            .frame(height: compact ? 24 : 28)
            .background {
                if !isDefault { shape.fill(Color(.label)) }
            }
            .overlay {
                if isDefault { shape.strokeBorder(Color(.label), lineWidth: 1.5) }
            }
            .fixedSize()
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
            .onLongPressGesture(minimumDuration: 0.5) { reset() }
            .sensoryFeedback(.impact(weight: .light), trigger: resets)
            .accessibilityElement()
            .accessibilityLabel("Playback speed")
            .accessibilityValue(RateFormat.label(player.rate))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { open() }
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: player.setRate(player.rate + 0.25)
                case .decrement: player.setRate(player.rate - 0.25)
                @unknown default: break
                }
            }
            .accessibilityAction(named: "Reset to 1×") { reset() }
    }

    private func reset() {
        player.setRate(1)
        resets += 1
    }
}

struct MiniPlayer: View {
    let player: RecordingPlayer
    let showCard: () -> Void

    @State private var showSpeed = false

    private static let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

    var body: some View {
        HStack(spacing: 8) {
            PlayPauseButton(player: player, diameter: 42, iconSize: 17)
            Button(action: showCard) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.source?.title ?? "")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("\(DurationFormat.clock(player.position)) · \(RateFormat.remaining(player.remaining))")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 2)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Scrolls back to the player")
            SkipButton(player: player, direction: .backward, symbolSize: 19, hitSize: 38)
            SkipButton(player: player, direction: .forward, symbolSize: 19, hitSize: 38)
            SpeedChip(player: player, compact: true) { showSpeed = true }
        }
        .padding(.leading, 9)
        .padding(.trailing, 6)
        .frame(height: 60)
        .background(.regularMaterial, in: Self.shape)
        .overlay {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color(.label).opacity(0.08))
                    Rectangle().fill(Palette.ready).frame(width: geo.size.width * player.progress)
                }
                .frame(height: 2.5)
            }
            .clipShape(Self.shape)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .overlay { Self.shape.strokeBorder(Color(.label).opacity(0.1), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.14), radius: 18, y: 6)
        .overlay(alignment: .top) {
            PlayerHUD(player: player)
                .offset(y: -38)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .sheet(isPresented: $showSpeed) { SpeedSheet(player: player) }
    }
}

struct SpeedSheet: View {
    let player: RecordingPlayer

    @Environment(\.dismiss) private var dismiss
    @State private var snaps = 0
    @State private var height: CGFloat = 360

    private static let detents: [Double] = [1, 1.5, 2, 3, 4, 5]
    private static let presets: [Double] = [1, 1.25, 1.5, 2, 3, 5]
    private static let ticks: [Double] = [1, 2, 3, 4, 5]
    private static let range = PlaybackMemory.rateRange
    private static let stepper: CGFloat = 36
    private static let controlFill = Color(UIColor { $0.userInterfaceStyle == .dark ? .tertiarySystemFill : .secondarySystemBackground })
    private static let rowSpacing: CGFloat = 12

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Playback speed").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
            }

            VStack(spacing: 4) {
                Text(RateFormat.label(player.rate))
                    .font(.system(size: 44, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: player.rate))
                    .animation(.snappy, value: player.rate)
                Text(RateFormat.listenLine(duration: player.duration, rate: player.rate))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            VStack(spacing: 6) {
                HStack(spacing: Self.rowSpacing) {
                    stepButton("minus", label: "Slower") { player.setRate(player.rate - 0.1) }
                    Slider(value: sliderValue, in: Self.range)
                        .accessibilityLabel("Playback speed")
                        .accessibilityValue(RateFormat.label(player.rate))
                    stepButton("plus", label: "Faster") { player.setRate(player.rate + 0.1) }
                }
                tickLabels
                    .padding(.horizontal, Self.stepper + Self.rowSpacing)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 8) {
                ForEach(Self.presets, id: \.self) { preset in
                    presetChip(preset)
                }
            }

            Text("Applies to every recording. Pitch stays natural. Above 3× works best for skimming.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 14)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: snaps)
    }

    private var sliderValue: Binding<Double> {
        Binding {
            player.rate
        } set: { raw in
            let stepped = (raw / 0.05).rounded() * 0.05
            let detent = Self.detents.first { abs($0 - stepped) <= 0.08 }
            let value = detent ?? stepped
            guard abs(value - player.rate) > 0.001 else { return }
            if detent != nil { snaps += 1 }
            player.setRate(value)
        }
    }

    private var tickLabels: some View {
        GeometryReader { geo in
            let inset = Self.thumbInset
            let usable = max(geo.size.width - inset * 2, 1)
            ForEach(Self.ticks, id: \.self) { tick in
                Text(RateFormat.label(tick).dropLast())
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .position(
                        x: inset + usable * (tick - Self.range.lowerBound) / (Self.range.upperBound - Self.range.lowerBound),
                        y: geo.size.height / 2
                    )
            }
        }
        .frame(height: 14)
    }

    private static var thumbInset: CGFloat {
        if #available(iOS 26, *) { return 19 }
        return 14
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: Self.stepper, height: Self.stepper)
                .background(Self.controlFill, in: Circle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }

    private func presetChip(_ preset: Double) -> some View {
        let selected = abs(player.rate - preset) < 0.001
        return Button {
            player.setRate(preset)
        } label: {
            Text(RateFormat.label(preset))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(selected ? Color(.systemBackground) : Color(.label))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    selected ? Color(.label) : Self.controlFill,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(RateFormat.label(preset))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
