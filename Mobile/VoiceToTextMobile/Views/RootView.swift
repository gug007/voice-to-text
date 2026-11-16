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

    private var library: Library { Library.shared }
    private var importer: Importer { Importer.shared }
    private var remote: MacRemote { MacRemote.shared }

    var body: some View {
        NavigationStack(path: $path) {
            LibraryList(query: query, openSettings: { showSettings = true })
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
                .searchable(text: $query, prompt: "Search transcripts")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Settings", systemImage: "gearshape") { showSettings = true }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Import audio", systemImage: "square.and.arrow.down") { showFilePicker = true }
                            .disabled(importer.isImporting)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { recordBar }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .fullScreenCover(isPresented: $showRecorder) {
            RecordingView(onFinish: finishRecording, onDiscard: { showRecorder = false })
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

    private var recordBar: some View {
        VStack(spacing: 10) {
            MacCards()
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
            Button(action: startRecording) {
                HStack(spacing: 10) {
                    Circle().fill(Palette.live).frame(width: 14, height: 14)
                    Text("Record")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .foregroundStyle(Color(.systemBackground))
                .background(Color(.label), in: Capsule())
            }
            .accessibilityLabel("Start recording")
            .padding(.horizontal, 20)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private func startRecording() {
        Task {
            do {
                try await Recorder.shared.start()
                showRecorder = true
            } catch {
                alert = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func finishRecording() {
        showRecorder = false
        guard let finished = Recorder.shared.stop() else {
            alert = "Nothing was recorded."
            return
        }
        library.addPending(id: finished.id, durationSeconds: finished.duration)
        Transcriber.shared.enqueue(finished.id)
        path = NavigationPath([finished.id])
    }
}

struct LibraryList: View {
    let query: String
    let openSettings: () -> Void

    private var library: Library { Library.shared }

    var body: some View {
        let searching = HistorySearch.isActive(query)
        let shown = searching ? HistorySearch.filter(library.entries, query: query) : library.entries

        List {
            ModelBanner()

            if !searching {
                MacConversationsLinks()
            }

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
