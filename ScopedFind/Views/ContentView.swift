import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var viewModel = SearchViewModel()

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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ScopedFind")
                .font(.title2.weight(.semibold))

            Text("Searches file and folder names only, not file contents.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(selectedFolderText)
                .font(.callout)
                .foregroundStyle(viewModel.selectedFolder == nil ? .secondary : .primary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TextField("Name contains (not file contents)", text: $viewModel.query)
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

                Picker("Result type", selection: $viewModel.searchTarget) {
                    ForEach(SearchTarget.allCases) { target in
                        Text(target.label).tag(target)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 190)
            }
            .toggleStyle(.checkbox)
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
