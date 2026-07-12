import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var viewModel = SearchViewModel()
    @State private var isShowingFuzzyHelp = false

    private let fuzzyHelpText = "Fuzzy matches typed characters in order. For example, sf finds ScopedFind."

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            controls
            Divider()
            resultsList
            statusBar
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 520)
        .onChange(of: viewModel.selectedFolder) {
            viewModel.scheduleAutoSearch()
        }
        .onChange(of: viewModel.query) {
            viewModel.scheduleAutoSearch()
        }
        .onChange(of: viewModel.extensionFilter) {
            viewModel.scheduleAutoSearch()
        }
        .onChange(of: viewModel.isCaseSensitive) {
            viewModel.scheduleAutoSearch()
        }
        .onChange(of: viewModel.includeHiddenFiles) {
            viewModel.scheduleAutoSearch()
        }
        .onChange(of: viewModel.autoSearchEnabled) {
            viewModel.scheduleAutoSearch()
        }
        .onChange(of: viewModel.searchKind) {
            viewModel.scheduleAutoSearch()
        }
        .onChange(of: viewModel.searchTarget) {
            viewModel.scheduleAutoSearch()
        }
        .onChange(of: viewModel.matchMode) {
            viewModel.scheduleAutoSearch()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ScopedFind")
                .font(.title2.weight(.semibold))

            Text("Searches file and folder names or file contents inside the chosen folder.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(selectedFolderText)
                .font(.callout)
                .foregroundStyle(viewModel.selectedFolder == nil ? .secondary : .primary)
                .lineLimit(2)
                .textSelection(.enabled)

            if shouldShowApplicationsWarning {
                Label(
                    "Apps are .app bundles, which macOS treats as folders. Use Files and folders or Folders/apps only. Some Apple apps live in /System/Applications.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(2)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TextField(queryPlaceholder, text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        viewModel.startSearch()
                    }

                TextField("Extensions", text: $viewModel.extensionFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                    .onSubmit {
                        viewModel.startSearch()
                    }

                Button("Choose Folder...", action: chooseFolder)

                Button("Search") {
                    viewModel.startSearch()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!viewModel.canSearch)

                Button("Cancel") {
                    viewModel.cancelSearch()
                }
                .disabled(!viewModel.isSearching)
            }

            HStack(spacing: 18) {
                Toggle("Case sensitive", isOn: $viewModel.isCaseSensitive)
                Toggle("Include hidden files", isOn: $viewModel.includeHiddenFiles)
                Toggle("Auto search", isOn: $viewModel.autoSearchEnabled)
                    .help("Runs a search after you stop typing for about one second.")
            }
            .toggleStyle(.checkbox)

            HStack(spacing: 14) {
                Picker("Search", selection: $viewModel.searchKind) {
                    ForEach(SearchKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                if viewModel.searchKind == .names {
                    Picker("Result type", selection: $viewModel.searchTarget) {
                        ForEach(SearchTarget.allCases) { target in
                            Text(target.label).tag(target)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 190)

                    HStack(spacing: 6) {
                        Toggle("Fuzzy name matching", isOn: fuzzyNameMatchingBinding)

                        Button {
                            isShowingFuzzyHelp.toggle()
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .imageScale(.small)
                                .foregroundStyle(.secondary)
                                .padding(3)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { isHovering in
                            isShowingFuzzyHelp = isHovering
                        }
                        .popover(isPresented: $isShowingFuzzyHelp, arrowEdge: .top) {
                            Text(fuzzyHelpText)
                                .font(.callout)
                                .padding(12)
                                .frame(width: 280, alignment: .leading)
                        }
                        .help(fuzzyHelpText)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("Fuzzy name matching help")
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private var resultsList: some View {
        List(viewModel.results) { result in
            SearchResultRow(result: result)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    open(result)
                }
                .contextMenu {
                    Button("Open") {
                        open(result)
                    }

                    Button("Reveal in Finder") {
                        reveal(result)
                    }

                    Button("Copy Path") {
                        copyPath(result)
                    }
                }
        }
        .overlay {
            if viewModel.results.isEmpty {
                ContentUnavailableView("No Results", systemImage: "magnifyingglass")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusBar: some View {
        HStack {
            if viewModel.isSearching {
                ProgressView()
                    .controlSize(.small)
            }

            Text(viewModel.status.message)
                .font(.callout)
                .foregroundStyle(statusColor)
                .lineLimit(2)

            Spacer()

            Text("\(viewModel.results.count) result\(viewModel.results.count == 1 ? "" : "s")")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var selectedFolderText: String {
        viewModel.selectedFolder?.path ?? "No folder selected. Search stays inside the folder you choose."
    }

    private var queryPlaceholder: String {
        switch viewModel.searchKind {
        case .names:
            return "Name contains"
        case .contents:
            return "File contents contain"
        }
    }

    private var shouldShowApplicationsWarning: Bool {
        guard let selectedFolder = viewModel.selectedFolder else {
            return false
        }

        return selectedFolder.standardizedFileURL.lastPathComponent == "Applications"
    }

    private var fuzzyNameMatchingBinding: Binding<Bool> {
        Binding {
            viewModel.matchMode == .fuzzy
        } set: { isEnabled in
            viewModel.matchMode = isEnabled ? .fuzzy : .contains
        }
    }

    private var statusColor: Color {
        switch viewModel.status {
        case .failed:
            return .red
        case .cancelled:
            return .orange
        default:
            return .secondary
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose"

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.selectFolder(url)
        }
    }

    private func open(_ result: SearchResult) {
        NSWorkspace.shared.open(result.url)
    }

    private func reveal(_ result: SearchResult) {
        NSWorkspace.shared.activateFileViewerSelecting([result.url])
    }

    private func copyPath(_ result: SearchResult) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.url.path, forType: .string)
    }
}
