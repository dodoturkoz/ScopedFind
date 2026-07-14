import SwiftUI
import AppKit

struct SearchExplanationView: View {
    private enum DetailMode: String, CaseIterable, Identifiable {
        case learn = "Learn"
        case exact = "Exact"

        var id: String {
            rawValue
        }
    }

    let explanation: SearchExplanation

    @Environment(\.dismiss) private var dismiss
    @State private var detailMode: DetailMode = .learn
    @State private var copiedStageID: String?
    @State private var expandedArgumentGuideIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(explanation.title)
                    .font(.title2.weight(.semibold))

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            Text(explanation.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Detail", selection: $detailMode) {
                ForEach(DetailMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)

            Divider()

            ScrollViewReader { scrollProxy in
                ScrollView {
                    Group {
                        switch detailMode {
                        case .learn:
                            learnView
                        case .exact:
                            exactView(scrollProxy: scrollProxy)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 680, idealWidth: 760, minHeight: 500, idealHeight: 620)
    }

    private var learnView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("ScopedFind may combine direct system commands with app-side matching. Command stages are shown in launch order; app-side checks can run as each path arrives.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ForEach(Array(explanation.stages.enumerated()), id: \.element.id) { index, stage in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(.tint, in: Circle())
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(stage.title)
                            .font(.headline)

                        Text(stage.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let command = stage.command {
                            Label(
                                "Launches \(URL(fileURLWithPath: command.executablePath).lastPathComponent)",
                                systemImage: "terminal"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else {
                            Label("Runs inside ScopedFind", systemImage: "gearshape")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func exactView(scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(
                "ScopedFind passes these arguments directly to Process. The display is shell-formatted for reading and copying; ScopedFind itself does not launch a shell.",
                systemImage: "info.circle"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Text("If a search is cancelled or fails, it may stop before a later stage is launched.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(explanation.stages) { stage in
                VStack(alignment: .leading, spacing: 8) {
                    Text(stage.title)
                        .font(.headline)

                    Text(stage.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let command = stage.command {
                        HStack(alignment: .top, spacing: 8) {
                            Text(command.shellFormattedCommand)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                copy(command.shellFormattedCommand, stageID: stage.id)
                            } label: {
                                Label(
                                    copiedStageID == stage.id ? "Copied" : "Copy",
                                    systemImage: copiedStageID == stage.id ? "checkmark" : "doc.on.doc"
                                )
                            }
                            .labelStyle(.titleAndIcon)
                        }
                        .padding(12)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))

                        if !stage.lessons.isEmpty {
                            argumentGuide(for: stage, scrollProxy: scrollProxy)
                        }
                    } else {
                        Label("App-side step — no external command", systemImage: "gearshape")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                if stage.id != explanation.stages.last?.id {
                    Divider()
                }
            }
        }
    }

    private func argumentGuide(
        for stage: SearchExplanationStage,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        let isExpanded = expandedArgumentGuideIDs.contains(stage.id)

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                toggleArgumentGuide(stage.id, scrollProxy: scrollProxy)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))

                    Text("Argument guide")
                        .font(.callout.weight(.medium))
                        .underline()

                    Spacer()

                    Text(isExpanded ? "Hide" : "Show")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.tint)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(stage.lessons.enumerated()), id: \.offset) { _, lesson in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(lesson.term)
                                .font(.system(.caption, design: .monospaced).weight(.medium))
                                .frame(width: 125, alignment: .leading)

                            Text(lesson.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 2)
                .id(argumentGuideAnchor(for: stage.id))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func toggleArgumentGuide(_ stageID: String, scrollProxy: ScrollViewProxy) {
        let isExpanding = !expandedArgumentGuideIDs.contains(stageID)

        withAnimation(.easeInOut(duration: 0.2)) {
            if isExpanding {
                expandedArgumentGuideIDs.insert(stageID)
            } else {
                expandedArgumentGuideIDs.remove(stageID)
            }
        }

        guard isExpanding else {
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            withAnimation(.easeInOut(duration: 0.25)) {
                scrollProxy.scrollTo(argumentGuideAnchor(for: stageID), anchor: .bottom)
            }
        }
    }

    private func argumentGuideAnchor(for stageID: String) -> String {
        "argument-guide-\(stageID)"
    }

    private func copy(_ command: String, stageID: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copiedStageID = stageID

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if copiedStageID == stageID {
                copiedStageID = nil
            }
        }
    }
}
