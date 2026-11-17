import SafariServices
import SwiftUI

enum MacRoute: Hashable {
    case conversations(String)
    case conversation(String, UUID)
}

struct MacHomeList: View {
    let link: MacLink
    let query: String

    var body: some View {
        let searching = HistorySearch.isActive(query)
        List {
            if !searching {
                Section { MacStatusRow(link: link) }
            }
            if link.conversations.isEmpty {
                if link.conversationsLoaded || link.connection != .unreachable {
                    MacConversationsEmpty(link: link)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            } else if searching {
                results
            } else {
                if let error = link.conversationsError {
                    MacConversationsErrorLabel(error: error)
                }
                let sections = MacConversationGrouping.sections(of: link.conversations)
                ForEach(sections) { section in
                    Section {
                        ForEach(section.rows) { MacConversationRow(macID: link.id, row: $0) }
                    } header: {
                        Text(section.title)
                    } footer: {
                        if section.id == sections.last?.id { MacConversationsFooter(link: link) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await link.refreshConversations() }
    }

    private var results: some View {
        let shown = MacConversationGrouping.filter(link.conversations, query: query)
        return Section {
            if shown.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(shown) { MacConversationRow(macID: link.id, row: $0, query: query) }
            }
        } header: {
            Text("Results · \(shown.count)")
        } footer: {
            Text("Searches the opening lines of each conversation on \(link.macName).")
        }
    }
}

struct MacConversationSection: Identifiable {
    let id: String
    let title: String
    let rows: [RemoteConversationRow]
}

enum MacConversationGrouping {
    static func sections(of rows: [RemoteConversationRow], now: Date = Date(), calendar: Calendar = .current) -> [MacConversationSection] {
        var order: [(id: String, title: String)] = []
        var buckets: [String: [RemoteConversationRow]] = [:]
        for row in rows.sorted(by: { $0.createdAt > $1.createdAt }) {
            let bucket = HistoryDateGrouping.bucket(for: row.createdAt, now: now, calendar: calendar)
            if buckets[bucket.id] == nil { order.append(bucket) }
            buckets[bucket.id, default: []].append(row)
        }
        return order.map { MacConversationSection(id: $0.id, title: $0.title, rows: buckets[$0.id] ?? []) }
    }

    static func filter(_ rows: [RemoteConversationRow], query: String) -> [RemoteConversationRow] {
        let terms = HistorySearch.terms(in: query)
        return rows
            .filter { row in terms.allSatisfy { row.preview.range(of: $0, options: HistorySearch.options) != nil } }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

struct MacStatusRow: View {
    let link: MacLink

    var body: some View {
        HStack(spacing: 12) {
            status
                .font(.subheadline)
                .lineLimit(3)
                .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            action
        }
        .frame(minHeight: 44)
        .padding(.vertical, 2)
    }

    private var listening: LiveListener.State {
        MacRemote.shared.listenState(for: link)
    }

    private var listeningWord: String? {
        switch listening {
        case .listening: return "listening"
        case .connecting: return "connecting…"
        case .reconnecting: return "reconnecting…"
        case .off, .failed: return nil
        }
    }

    @ViewBuilder
    private func recordingLine(_ clock: String) -> some View {
        if let word = listeningWord {
            ViewThatFits(in: .horizontal) {
                StatusLine(text: "Recording · \(clock) · \(word)", dot: Palette.live, emphasized: true)
                StatusLine(text: "\(clock) · \(word)", dot: Palette.live, emphasized: true)
                StatusLine(text: word, dot: Palette.live, emphasized: true)
                    .lineLimit(1)
            }
            .monospacedDigit()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Recording · \(clock) · \(word)")
        } else {
            ViewThatFits(in: .horizontal) {
                StatusLine(text: "Recording · \(clock)", dot: Palette.live, emphasized: true)
                StatusLine(text: clock, dot: Palette.live, emphasized: true)
                    .lineLimit(1)
            }
            .monospacedDigit()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Recording · \(clock)")
        }
    }

    private var readyText: String {
        guard link.conversationsLoaded, link.conversationsError == nil else { return "Ready" }
        switch link.conversations.count {
        case 0: return "Ready · no conversations yet"
        case 1: return "Ready · 1 conversation"
        case let count: return "Ready · \(count) conversations"
        }
    }

    @ViewBuilder
    private var status: some View {
        if let error = link.commandError {
            StatusLine(text: error, dot: Palette.live, alert: true)
        } else {
            switch link.connection {
            case .idle, .connecting:
                StatusLine(text: "Connecting…", dot: Color(.systemGray3))
            case .unreachable:
                StatusLine(text: "Asleep or not reachable", dot: Color(.systemGray3))
            case .connected:
                switch link.status?.state {
                case .recording:
                    if case .failed(let message) = listening {
                        StatusLine(text: message, dot: Palette.live, alert: true)
                    } else {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            recordingLine(DurationFormat.clock(link.elapsed(at: context.date)))
                        }
                    }
                case .transcribing, .importing:
                    StatusLine(text: "Transcribing on Mac…", dot: Color(.systemGray3))
                case .error:
                    StatusLine(text: link.status?.message ?? "The Mac couldn't record.", dot: Palette.live, alert: true)
                case .idle, nil:
                    StatusLine(text: readyText, dot: Palette.ready)
                }
            }
        }
    }

    @ViewBuilder
    private var action: some View {
        switch link.connection {
        case .idle, .connecting:
            ProgressView().accessibilityLabel("Connecting to \(link.shortName)")
        case .unreachable:
            Button { link.retry() } label: {
                RowPill(title: "Retry", fill: Color(.tertiarySystemFill), ink: Color(.label))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Retry connecting to \(link.shortName)")
        case .connected:
            switch link.status?.state {
            case .recording:
                if link.status?.liveListen == true {
                    ListenButton(link: link, state: listening)
                }
            case .transcribing, .importing:
                ProgressView().accessibilityLabel("Transcribing on \(link.shortName)")
            case .idle, .error, nil:
                EmptyView()
            }
        }
    }
}

private struct RowPill: View {
    let title: String
    var systemImage: String?
    let fill: Color
    let ink: Color

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).font(.caption.weight(.bold)) }
            Text(title)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(ink)
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(fill, in: Capsule())
        .fixedSize()
    }
}

private struct StatusLine: View {
    let text: String
    let dot: Color
    var alert = false
    var emphasized = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle()
                .fill(dot)
                .frame(width: 7, height: 7)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
            Text(text)
                .fontWeight(emphasized ? .semibold : nil)
                .foregroundStyle(alert ? Palette.live : emphasized ? Color.primary : Color.secondary)
        }
    }
}

struct ListenButton: View {
    let link: MacLink
    let state: LiveListener.State

    var body: some View {
        let on = state == .listening
        let busy = state == .connecting || state == .reconnecting
        Button {
            MacRemote.shared.toggleListening(link)
        } label: {
            HStack(spacing: 6) {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "headphones")
                        .font(.caption.weight(.bold))
                }
                Text(on ? "Listening" : "Listen")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(on ? Color(.systemBackground) : Color(.label))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(on ? Color(.label) : Color(.tertiarySystemFill), in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .fixedSize()
        }
        .buttonStyle(.plain)
        .disabled(Recorder.shared.isActive)
        .accessibilityLabel(on || busy ? "Stop listening to \(link.macName)" : "Listen live to \(link.macName)")
    }
}

struct MacUnavailableView: View {
    var body: some View {
        ContentUnavailableView(
            "This Mac isn't available",
            systemImage: "laptopcomputer.slash",
            description: Text("It's no longer on your Tailscale account, or this iPhone is signed out. Check Settings → Mac.")
        )
    }
}

struct MacConversationsView: View {
    let macID: String

    var body: some View {
        if let link = MacRemote.shared.link(id: macID) {
            MacConversationsList(link: link)
        } else {
            MacUnavailableView()
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct MacConversationsList: View {
    let link: MacLink

    var body: some View {
        List {
            if link.conversations.isEmpty {
                MacConversationsEmpty(link: link)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                if let error = link.conversationsError {
                    MacConversationsErrorLabel(error: error)
                }
                Section {
                    ForEach(link.conversations) { MacConversationRow(macID: link.id, row: $0) }
                } footer: {
                    MacConversationsFooter(link: link)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(link.macName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await link.refreshConversations() }
        .task(id: ObjectIdentifier(link)) { await link.refreshConversations() }
    }
}

struct MacConversationsFooter: View {
    let link: MacLink

    var body: some View {
        Text("These stay on \(link.macName). Audio you play is downloaded to this iPhone.")
    }
}

struct MacConversationsErrorLabel: View {
    let error: String

    var body: some View {
        Label(error, systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(Palette.live)
    }
}

struct MacConversationsEmpty: View {
    let link: MacLink

    var body: some View {
        if !link.conversationsLoaded {
            HStack {
                Spacer()
                ProgressView("Loading conversations")
                Spacer()
            }
            .padding(.vertical, 40)
        } else if let error = link.conversationsError {
            ContentUnavailableView {
                Label("Couldn't load conversations", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Try again") { Task { await link.refreshConversations() } }
                    .buttonStyle(.bordered)
            }
        } else {
            ContentUnavailableView(
                "No conversations on this Mac",
                systemImage: "person.2.wave.2",
                description: Text("Record one with Record on Mac, or on the Mac itself. It appears here once it's transcribed.")
            )
        }
    }
}

struct MacConversationRow: View {
    let macID: String
    let row: RemoteConversationRow
    var query = ""

    var body: some View {
        NavigationLink(value: MacRoute.conversation(macID, row.id)) {
            VStack(alignment: .leading, spacing: 6) {
                if row.isUntranscribed {
                    Label(HistorySearch.notTranscribedLabel, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                } else {
                    Text(row.preview.isEmpty ? AttributedString("No speech") : HistorySearch.highlighted(row.preview, query: query))
                        .font(.body)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(RecordingDateFormat.rowLabel(row.createdAt))
                    Text("·")
                    Text(DurationFormat.clock(row.durationSeconds))
                    if row.hasSummary {
                        Image(systemName: "text.alignleft").accessibilityLabel("Has summary")
                    }
                    if row.hasActionItems {
                        Image(systemName: "checklist").accessibilityLabel("Has action items")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
}

struct MacConversationView: View {
    let macID: String
    let id: UUID

    @State private var entry: RecordingHistoryEntry?
    @State private var failure: String?
    @State private var tab: DetailTab = .transcript
    @State private var player = RecordingPlayer()

    private var remote: MacRemote { MacRemote.shared }
    private var link: MacLink? { remote.link(id: macID) }

    var body: some View {
        Group {
            if let entry {
                content(entry)
            } else if link == nil {
                MacUnavailableView()
            } else if let failure {
                ContentUnavailableView {
                    Label("Couldn't open this conversation", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failure)
                } actions: {
                    Button("Try again") { Task { await load() } }.buttonStyle(.bordered)
                }
            } else {
                ProgressView("Loading")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if entry == nil { entry = link?.cachedDetail(id) }
            await load()
            #if DEBUG
            if let raw = DebugLaunch.tab, let wanted = DetailTab(rawValue: raw), tabs.contains(wanted) { tab = wanted }
            if UserDefaults.standard.bool(forKey: "debugRemotePlay"), entry != nil, let link {
                await link.downloadAudio(id)
                if remote.hasAudio(id), let entry {
                    player.load(.init(entry, url: remote.audioURL(id)))
                    player.play()
                }
            }
            #endif
        }
        .onDisappear { player.stop() }
    }

    private func load() async {
        guard let link else { return }
        do {
            entry = try await link.detail(id)
            failure = nil
        } catch {
            if entry == nil { failure = error.localizedDescription }
        }
    }

    private var tabs: [DetailTab] {
        guard let entry else { return [.transcript] }
        var tabs: [DetailTab] = [.transcript]
        if entry.summary != nil { tabs.append(.summary) }
        if entry.actionItems != nil { tabs.append(.actionItems) }
        return tabs
    }

    private func content(_ entry: RecordingHistoryEntry) -> some View {
        PlayerScrollView(player: player, docks: remote.hasAudio(id)) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(RecordingDateFormat.rowLabel(entry.createdAt))
                        .font(.title3.weight(.semibold))
                    Text(subtitle(entry))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                audio(entry)

                if tabs.count > 1 {
                    Picker("Section", selection: $tab) {
                        ForEach(tabs) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                switch tab {
                case .transcript:
                    transcript(entry)
                case .summary:
                    if let summary = entry.summary { SummaryText(text: summary.text) }
                case .actionItems:
                    if let items = entry.actionItems { actionItems(items) }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .refreshable { await load() }
        .toolbar {
            if !entry.transcriptIsPlaceholder {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: entry.transcript) { Label("Share transcript", systemImage: "square.and.arrow.up") }
                }
            }
        }
    }

    private func subtitle(_ entry: RecordingHistoryEntry) -> String {
        var parts = [DurationFormat.clock(entry.durationSeconds)]
        if let model = entry.modelName { parts.append(model) }
        if let link { parts.append("on \(link.macName)") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func audio(_ entry: RecordingHistoryEntry) -> some View {
        if remote.hasAudio(id) {
            PlayerCard(player: player, source: .init(entry, url: remote.audioURL(id)))
        } else if let progress = link?.downloadProgress[id] {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress)
                    .accessibilityLabel("Downloading audio")
                Text(progress > 0 ? "Downloading audio · \(Int(progress * 100))%" : "Preparing audio on the Mac…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    Task { await link?.downloadAudio(id) }
                } label: {
                    Label("Play audio", systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
                .disabled(link == nil)
                .accessibilityHint("Downloads the recording from the Mac, then you can play it")
                if link == nil {
                    Text("Reconnect to this Mac to play its audio.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if let error = link?.downloadErrors[id] {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Palette.live)
                }
            }
        }
    }

    @ViewBuilder
    private func transcript(_ entry: RecordingHistoryEntry) -> some View {
        if entry.transcriptIsPlaceholder {
            VStack(alignment: .leading, spacing: 8) {
                Text(HistorySearch.notTranscribedLabel).font(.headline)
                Text(entry.status?.message ?? HistorySearch.savedWithoutTranscriptReason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Transcribe it on the Mac, from History.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        } else {
            Text(entry.transcript)
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func actionItems(_ actionItems: TranscriptActionItems) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if actionItems.items.isEmpty {
                Text("No action items came out of this conversation.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            ForEach(actionItems.items) { item in
                ActionItemRow(item: item)
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(item.text), \(item.isDone ? "done" : "not done")")
                Divider()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MacSettingsSection: View {
    private var remote: MacRemote { MacRemote.shared }

    var body: some View {
        Section {
            if remote.isLoopback {
                LabeledContent("Mode", value: "Debug loopback")
                macRows
            } else {
                switch remote.tailnet.state {
                case .off, .signedOut:
                    Button("Sign in with Tailscale") { remote.signIn() }
                case .starting, .connecting:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Connecting to Tailscale…").foregroundStyle(.secondary)
                    }
                case .needsLogin:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Waiting for you to sign in…").foregroundStyle(.secondary)
                    }
                case .failed(let message):
                    Text(message).font(.footnote).foregroundStyle(Palette.live)
                    Button("Try again") { remote.signIn() }
                case .running(let account):
                    LabeledContent("Account", value: account)
                    macRows
                    Button("Sign out", role: .destructive) { Task { await remote.signOut() } }
                }
            }
        } header: {
            Text(remote.links.count > 1 ? "Macs" : "Mac")
        } footer: {
            Text("Control conversation recording on each of your Macs and play back their conversations. Each Mac must be signed in to the same Tailscale account, with Control from iPhone turned on (Mac app → iPhone).")
        }
    }

    @ViewBuilder
    private var macRows: some View {
        let links = remote.links
        if links.isEmpty {
            Text("No Mac found on this account yet. In the Mac app, open iPhone in the sidebar, turn on Control from iPhone and sign in there.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            ForEach(links) { link in
                LabeledContent {
                    Text(connectionText(link))
                } label: {
                    Label(link.macName, systemImage: "laptopcomputer")
                        .lineLimit(1)
                }
            }
        }
    }

    private func connectionText(_ link: MacLink) -> String {
        switch link.connection {
        case .connected: return "Connected"
        case _ where !link.mac.isOnline: return "Offline"
        case .idle, .connecting: return "Connecting"
        case .unreachable: return "Not reachable"
        }
    }
}

struct LoginPage: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.delegate = context.coordinator
        controller.dismissButtonStyle = .cancel
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onFinish()
        }
    }
}
