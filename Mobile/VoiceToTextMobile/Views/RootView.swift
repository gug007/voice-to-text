import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var path = NavigationPath()
    @State private var query = ""
    @State private var showSettings = false
    @State private var showFilePicker = false
    @State private var showRecorder = false
    @State private var alert: String?
    @AppStorage("home.recordDestination") private var destinationID = ""

    private var library: Library { Library.shared }
    private var importer: Importer { Importer.shared }
    private var remote: MacRemote { MacRemote.shared }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let destination {
                    MacHomeList(link: destination, query: query)
                } else {
                    LibraryList(query: query)
                }
            }
                .navigationTitle("Recordings")
                .navigationDestination(for: UUID.self) { id in
                    DetailView(id: id, openSettings: { showSettings = true })
                }
                .navigationDestination(for: MacRoute.self) { route in
                    switch route {
                    case .conversations(let macID): MacConversationsView(macID: macID)
                    case .conversation(let macID, let id): MacConversationView(macID: macID, id: id)
                    }
                }
                .searchable(text: $query, prompt: searchPrompt)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Settings", systemImage: "gearshape") { showSettings = true }
                    }
                    ToolbarItem(placement: .principal) { destinationMenu }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Import audio", systemImage: "square.and.arrow.down") { showFilePicker = true }
                            .disabled(importer.isImporting)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { recordBar }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .fullScreenCover(isPresented: $showRecorder) {
            RecordingView(
                onFinish: { finishRecording() },
                onSave: { finishRecording(transcribe: false) },
                onDiscard: { showRecorder = false }
            )
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.audio, .movie]) { result in
            switch result {
            case .success(let url):
                Task { await importer.importFile(url) }
            case .failure(let error):
                alert = error.localizedDescription
            }
        }
        .alert("Something went wrong", isPresented: alertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alert ?? importer.failure ?? "")
        }
        .onChange(of: destination?.id) {
            guard let destination, destination.conversationsLoaded else { return }
            Task { await destination.refreshConversations() }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: remote.setForeground(true)
            case .background: remote.setForeground(false)
            default: break
            }
        }
        .task {
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "debugShowSettings") { showSettings = true }
            if UserDefaults.standard.bool(forKey: "debugRemoteSignIn") { remote.signIn() }
            if let open = UserDefaults.standard.string(forKey: "debugRemoteOpen"), let link = await DebugLaunch.waitForMac() {
                path.append(MacRoute.conversations(link.id))
                if let id = UUID(uuidString: open) {
                    path.append(MacRoute.conversation(link.id, id))
                } else if open == "first" {
                    await link.refreshConversations()
                    if let first = link.conversations.first { path.append(MacRoute.conversation(link.id, first.id)) }
                }
            }
            if DebugLaunch.openFirst, let first = library.entries.first { path = NavigationPath([first.id]) }
            if UserDefaults.standard.bool(forKey: "debugRecord") { startRecording() }
            if let seconds = UserDefaults.standard.object(forKey: "debugStopAfter") as? Double ?? Double(UserDefaults.standard.string(forKey: "debugStopAfter") ?? "") {
                try? await Task.sleep(for: .seconds(seconds))
                finishRecording()
            }
            #endif
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { alert != nil || importer.failure != nil },
            set: { if !$0 { alert = nil; importer.failure = nil } }
        )
    }

    private var destination: MacLink? {
        guard !destinationID.isEmpty else { return nil }
        return remote.homeLinks.first { $0.id == destinationID }
    }

    private var deviceName: String {
        destination?.shortName ?? "This iPhone"
    }

    private var searchPrompt: String {
        remote.homeLinks.isEmpty ? "Search transcripts" : "Search \(deviceName)"
    }

    @ViewBuilder
    private var destinationMenu: some View {
        let links = remote.homeLinks
        if !links.isEmpty {
            Menu {
                Picker("Show and record on", selection: Binding(get: { destination?.id ?? "" }, set: { destinationID = $0 })) {
                    Label("This iPhone", systemImage: "iphone").tag("")
                    ForEach(links) { Label($0.shortName, systemImage: "laptopcomputer").tag($0.id) }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: destination == nil ? "iphone" : "laptopcomputer")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(deviceName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
            }
            .accessibilityLabel("Showing and recording on")
            .accessibilityValue(deviceName)
        }
    }

    private var recordBar: some View {
        VStack(spacing: 10) {
            if let fraction = importer.fraction {
                HStack(spacing: 10) {
                    ProgressView(value: fraction)
                    Text("Importing \(importer.fileName ?? "file")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 20)
            }
            if let destination {
                MacRecordCapsule(link: destination)
            } else {
                RecordCapsule(
                    title: "Record",
                    accessibility: remote.homeLinks.isEmpty ? "Start recording" : "Start recording on this iPhone",
                    action: startRecording
                )
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private func startRecording() {
        Task {
            await remote.stopListening()
            do {
                try await Recorder.shared.start()
                showRecorder = true
            } catch {
                alert = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func finishRecording(transcribe: Bool = true) {
        showRecorder = false
        guard let finished = Recorder.shared.stop() else {
            alert = "Nothing was recorded."
            return
        }
        guard transcribe else {
            library.addPending(id: finished.id, durationSeconds: finished.duration, status: .savedForLater)
            return
        }
        library.addPending(id: finished.id, durationSeconds: finished.duration)
        Transcriber.shared.enqueue(finished.id)
        path = NavigationPath([finished.id])
    }
}

struct RecordCapsule: View {
    let title: String
    var stops = false
    var enabled = true
    let accessibility: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if stops {
                    RoundedRectangle(cornerRadius: 3).fill(.white).frame(width: 13, height: 13)
                } else if enabled {
                    Circle().fill(Palette.live).frame(width: 14, height: 14)
                }
                Text(title)
                    .font(.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(stops ? Color.white : Color(.systemBackground))
            .background(stops ? Palette.live : Color(.label), in: Capsule())
            .opacity(enabled ? 1 : 0.4)
        }
        .disabled(!enabled)
        .accessibilityLabel(accessibility)
        .padding(.horizontal, 20)
    }
}

struct MacRecordCapsule: View {
    let link: MacLink

    var body: some View {
        let name = link.shortName
        switch link.connection {
        case .idle, .connecting:
            RecordCapsule(title: "Connecting to \(name)…", enabled: false, accessibility: "Connecting to \(name)") {}
        case .unreachable:
            RecordCapsule(title: "\(name) isn't reachable", enabled: false, accessibility: "\(name) isn't reachable") {}
        case .connected:
            switch link.status?.state {
            case .recording:
                let canSave = link.canStopAndSave
                VStack(spacing: 10) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let clock = DurationFormat.clock(link.elapsed(at: context.date))
                        RecordCapsule(
                            title: canSave ? "Stop & Transcribe · \(clock)" : "Stop · \(clock)",
                            stops: true,
                            enabled: !link.isSending,
                            accessibility: canSave ? "Stop and transcribe on \(name)" : "Stop recording on \(name)"
                        ) {
                            Task { await link.stopRecording() }
                        }
                    }
                    if canSave {
                        Button {
                            Task { await link.stopRecording(transcribe: false) }
                        } label: {
                            Label("Stop & Save", systemImage: "square.and.arrow.down")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .foregroundStyle(Color.primary)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                                .opacity(link.isSending ? 0.4 : 1)
                        }
                        .buttonStyle(.plain)
                        .disabled(link.isSending)
                        .accessibilityLabel("Stop and save on \(name)")
                        .accessibilityHint("Saves the audio on \(name) without transcribing it")
                        .padding(.horizontal, 20)

                        Text("Stop & Save keeps the audio on \(name) to transcribe later.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                }
            case .transcribing where link.status?.saving == true:
                RecordCapsule(title: "Saving on \(name)…", enabled: false, accessibility: "Saving on \(name)") {}
            case .transcribing, .importing:
                RecordCapsule(title: "Transcribing on \(name)…", enabled: false, accessibility: "Transcribing on \(name)") {}
            case .idle, .error, nil:
                RecordCapsule(
                    title: link.isSending ? "Starting on \(name)…" : "Record on \(name)",
                    enabled: !link.isSending,
                    accessibility: "Start recording a conversation on \(name)"
                ) {
                    Task { await link.startRecording() }
                }
            }
        }
    }
}

struct LibraryList: View {
    let query: String

    private var library: Library { Library.shared }

    var body: some View {
        let searching = HistorySearch.isActive(query)
        let shown = searching ? HistorySearch.filter(library.entries, query: query) : library.entries

        List {
            ModelBanner()

            if library.entries.isEmpty {
                ContentUnavailableView(
                    "No recordings yet",
                    systemImage: "waveform",
                    description: Text("Tap Record at a meeting, a lecture or on the go. The transcript is made on this iPhone.")
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else if searching {
                Section("Results · \(shown.count)") {
                    ForEach(shown) { RecordingRowLink(entry: $0, query: query) }
                        .onDelete { delete($0, from: shown) }
                }
            } else {
                ForEach(HistoryDateGrouping.sections(of: shown)) { section in
                    Section(section.title) {
                        ForEach(section.entries) { RecordingRowLink(entry: $0, query: "") }
                            .onDelete { delete($0, from: section.entries) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func delete(_ offsets: IndexSet, from entries: [RecordingHistoryEntry]) {
        for index in offsets {
            let id = entries[index].id
            Transcriber.shared.forget(id)
            library.delete(id: id)
        }
    }
}

struct RecordingRowLink: View {
    let entry: RecordingHistoryEntry
    let query: String

    var body: some View {
        NavigationLink(value: entry.id) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    if entry.transcriptIsPlaceholder {
                        PendingLabel(entry: entry)
                    } else {
                        Text(HistorySearch.highlighted(entry.transcript, query: query))
                            .font(.body)
                            .lineLimit(2)
                    }
                    HStack(spacing: 6) {
                        Text(RecordingDateFormat.rowLabel(entry.createdAt))
                        Text("·")
                        Text(DurationFormat.clock(entry.durationSeconds))
                        if entry.summary != nil {
                            Image(systemName: "text.alignleft").accessibilityLabel("Has summary")
                        }
                        if let items = entry.actionItems, !items.items.isEmpty {
                            Image(systemName: "checklist").accessibilityLabel("Has action items")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if entry.isSavedForLater, !Transcriber.shared.isWaiting(entry.id) {
                    Button("Transcribe") { Transcriber.shared.enqueue(entry.id) }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(Color.primary)
                        .accessibilityLabel("Transcribe recording from \(RecordingDateFormat.rowLabel(entry.createdAt))")
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct PendingLabel: View {
    let entry: RecordingHistoryEntry

    var body: some View {
        let transcriber = Transcriber.shared
        HStack(spacing: 8) {
            if transcriber.activeID == entry.id {
                ProgressView()
                Text("Transcribing…")
            } else if transcriber.queue.contains(entry.id) {
                Image(systemName: "clock")
                Text(waitingText(transcriber.modelState))
            } else if entry.isSavedForLater {
                Image(systemName: "waveform")
                Text(HistorySearch.notTranscribedYetLabel)
            } else {
                Image(systemName: "exclamationmark.triangle")
                Text(HistorySearch.notTranscribedLabel)
            }
        }
        .font(.body)
        .foregroundStyle(.secondary)
    }

    private func waitingText(_ state: Transcriber.ModelState) -> String {
        switch state {
        case .ready: return "Waiting to be transcribed"
        case .preparing: return "Waiting for the speech model"
        case .missing, .failed: return Transcriber.isModelDownloaded ? "Waiting to be transcribed" : "Needs the speech model"
        }
    }
}

struct ModelBanner: View {
    var body: some View {
        let transcriber = Transcriber.shared
        switch transcriber.modelState {
        case .ready:
            EmptyView()
        case .missing:
            if !Transcriber.isModelDownloaded {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Download the speech model", systemImage: "arrow.down.circle")
                            .font(.headline)
                        Text("About \(Transcriber.approxDownloadMB) MB, once. After that, recordings are transcribed on this iPhone, with no internet and at no cost.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Download") { transcriber.prepareModel() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 6)
                }
            }
        case .preparing(let fraction, let message):
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preparing the speech model")
                        .font(.headline)
                    ProgressView(value: min(max(fraction, 0), 1))
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
        case .failed(let message):
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("The speech model couldn't be prepared", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Try again") { transcriber.prepareModel() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 6)
            }
        }
    }
}
