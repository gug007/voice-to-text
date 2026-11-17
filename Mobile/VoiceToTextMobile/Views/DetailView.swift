import SwiftUI

enum DetailTab: String, CaseIterable, Identifiable {
    case transcript = "Transcript"
    case summary = "Summary"
    case actionItems = "Action Items"
    var id: String { rawValue }
}

struct DetailView: View {
    let id: UUID
    let openSettings: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tab: DetailTab = .transcript
    @State private var confirmDelete = false
    @State private var player = RecordingPlayer()

    private var library: Library { Library.shared }

    var body: some View {
        if let entry = library.entry(id: id) {
            content(entry)
        } else {
            Color.clear.onAppear { dismiss() }
        }
    }

    private func content(_ entry: RecordingHistoryEntry) -> some View {
        PlayerScrollView(player: player) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(RecordingDateFormat.rowLabel(entry.createdAt))
                        .font(.title3.weight(.semibold))
                    Text(subtitle(entry))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                PlayerCard(player: player, source: .init(entry, url: library.audioURL(for: entry)))

                Picker("Section", selection: $tab) {
                    ForEach(DetailTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch tab {
                case .transcript: TranscriptPane(entry: entry)
                case .summary: SummaryPane(entry: entry, openSettings: openSettings)
                case .actionItems: ActionItemsPane(entry: entry, openSettings: openSettings)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let text = shareText(entry) {
                    ShareLink(item: text) { Label("Share", systemImage: "square.and.arrow.up") }
                }
                Menu {
                    if let text = shareText(entry) {
                        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
                    }
                    ShareLink(item: library.audioURL(for: entry)) { Label("Share audio", systemImage: "waveform") }
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Delete this recording?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete recording", role: .destructive) {
                player.stop()
                PlaybackMemory.forget(id)
                Transcriber.shared.forget(id)
                library.delete(id: id)
            }
        } message: {
            Text("The audio and its transcript will be removed from this iPhone.")
        }
        .onDisappear { player.stop() }
        .task {
            #if DEBUG
            if let raw = DebugLaunch.tab, let wanted = DetailTab(rawValue: raw) { tab = wanted }
            #endif
        }
    }

    private func subtitle(_ entry: RecordingHistoryEntry) -> String {
        var parts = [DurationFormat.clock(entry.durationSeconds)]
        if let model = entry.modelName { parts.append("\(model) · on this iPhone") }
        return parts.joined(separator: " · ")
    }

    private func shareText(_ entry: RecordingHistoryEntry) -> String? {
        switch tab {
        case .transcript:
            return entry.transcriptIsPlaceholder ? nil : entry.transcript
        case .summary:
            return entry.summary?.text
        case .actionItems:
            guard let items = entry.actionItems?.items, !items.isEmpty else { return nil }
            return items.map { item in
                var line = "\(item.isDone ? "☑" : "☐") \(item.text)"
                let meta = [item.owner, item.due].compactMap { $0 }.joined(separator: ", ")
                if !meta.isEmpty { line += " (\(meta))" }
                return line
            }.joined(separator: "\n")
        }
    }
}

struct TranscriptPane: View {
    let entry: RecordingHistoryEntry

    var body: some View {
        if entry.transcriptIsPlaceholder {
            pending
        } else {
            Text(entry.transcript)
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var pending: some View {
        let transcriber = Transcriber.shared
        VStack(alignment: .leading, spacing: 12) {
            if transcriber.activeID == entry.id {
                Text("Transcribing on this iPhone…").font(.headline)
                if let progress = transcriber.progress, progress.total > 1 {
                    ProgressView(value: progress.fraction)
                    Text("Part \(min(progress.done + 1, progress.total)) of \(progress.total)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            } else if transcriber.queue.contains(entry.id) {
                switch transcriber.modelState {
                case .preparing(let fraction, let message):
                    Text("Preparing the speech model").font(.headline)
                    ProgressView(value: min(max(fraction, 0), 1))
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                case .failed(let message):
                    Text("The speech model couldn't be prepared").font(.headline)
                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                    Button("Try again") { transcriber.prepareModel() }.buttonStyle(.borderedProminent)
                case .missing where !Transcriber.isModelDownloaded:
                    Text("This recording is saved").font(.headline)
                    Text("Download the speech model (about \(Transcriber.approxDownloadMB) MB) to transcribe it on this iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Download") { transcriber.prepareModel() }.buttonStyle(.borderedProminent)
                default:
                    Text("Waiting to be transcribed").font(.headline)
                    ProgressView()
                }
            } else {
                Text(HistorySearch.notTranscribedLabel).font(.headline)
                Text(entry.status?.message ?? HistorySearch.savedWithoutTranscriptReason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Transcribe") { transcriber.enqueue(entry.id) }.buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct InsightGate: View {
    let entry: RecordingHistoryEntry
    let kind: InsightKind
    let title: String
    let explanation: String
    let action: String
    let openSettings: () -> Void

    var body: some View {
        let insights = Insights.shared
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            if insights.isRunning(entry.id, kind) {
                HStack(spacing: 10) {
                    ProgressView()
                    if let progress = insights.progress(entry.id, kind) {
                        Text("Part \(min(progress.done + 1, progress.total)) of \(progress.total)")
                    } else {
                        Text("Asking OpenAI…")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else if entry.transcriptIsPlaceholder {
                Text("Available once this recording has a transcript.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if !OpenAIKeyStore.shared.hasKey {
                Text("\(explanation) It uses your own OpenAI API key and sends the transcript text, not the audio.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Add OpenAI key", action: openSettings).buttonStyle(.borderedProminent)
            } else {
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(action) {
                    Task { await insights.generate(entryID: entry.id, kind: kind) }
                }
                .buttonStyle(.borderedProminent)
            }
            if let failure = insights.failure(entry.id, kind) {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Palette.live)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct InsightFooter: View {
    let entry: RecordingHistoryEntry
    let kind: InsightKind

    var body: some View {
        let insights = Insights.shared
        VStack(alignment: .leading, spacing: 8) {
            if entry.isStale(kind) {
                Text("The transcript changed after this was written.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let failure = insights.failure(entry.id, kind) {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Palette.live)
            }
            if insights.isRunning(entry.id, kind) {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Asking OpenAI…").font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                Button("Regenerate", systemImage: "arrow.clockwise") {
                    Task { await insights.generate(entryID: entry.id, kind: kind) }
                }
                .font(.footnote)
                .buttonStyle(.bordered)
            }
        }
        .padding(.top, 8)
    }
}

struct SummaryPane: View {
    let entry: RecordingHistoryEntry
    let openSettings: () -> Void

    var body: some View {
        if let summary = entry.summary {
            VStack(alignment: .leading, spacing: 10) {
                SummaryText(text: summary.text)
                InsightFooter(entry: entry, kind: .summary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            InsightGate(
                entry: entry,
                kind: .summary,
                title: "Summary",
                explanation: "A short summary of what was said.",
                action: "Summarize",
                openSettings: openSettings
            )
        }
    }
}

struct ActionItemsPane: View {
    let entry: RecordingHistoryEntry
    let openSettings: () -> Void

    var body: some View {
        if let actionItems = entry.actionItems {
            VStack(alignment: .leading, spacing: 0) {
                if actionItems.items.isEmpty {
                    Text("No action items came out of this recording.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
                ForEach(actionItems.items) { item in
                    Button {
                        Library.shared.update(id: entry.id) {
                            $0.updatingActionItems($0.actionItems?.toggling(itemID: item.id))
                        }
                    } label: {
                        ActionItemRow(item: item)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.text), \(item.isDone ? "done" : "not done")")
                    Divider()
                }
                InsightFooter(entry: entry, kind: .actionItems)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            InsightGate(
                entry: entry,
                kind: .actionItems,
                title: "Action Items",
                explanation: "A checklist of the tasks people agreed to.",
                action: "Find action items",
                openSettings: openSettings
            )
        }
    }
}

struct SummaryText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(SummaryLayout.blocks(of: text)) { block in
                switch block.shape {
                case .heading:
                    Text(block.text).font(.headline).padding(.top, 4)
                case .bullet:
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                        Text(block.text)
                    }
                case .paragraph:
                    Text(block.text)
                }
            }
        }
        .font(.body)
        .lineSpacing(4)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ActionItemRow: View {
    let item: ActionItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(item.isDone ? Palette.ready : Color.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.text)
                    .strikethrough(item.isDone)
                    .foregroundStyle(item.isDone ? Color.secondary : Color.primary)
                    .multilineTextAlignment(.leading)
                let meta = [item.owner, item.due].compactMap { $0 }.joined(separator: " · ")
                if !meta.isEmpty {
                    Text(meta).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
