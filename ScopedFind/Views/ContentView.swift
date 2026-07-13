import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var viewModel = SearchViewModel()

    var body: some View {
        mainLayout
            .onChange(of: viewModel.autoSearchTrigger) {
                viewModel.scheduleAutoSearch()
            }
    }

    private var mainLayout: some View {
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

            Text("Searches file names or file contents inside the chosen folder.")
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

            searchModeControls
            filterControls
        }
    }

    private var searchModeControls: some View {
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
                .frame(width: 250)

                Picker("Name match", selection: $viewModel.matchMode) {
                    ForEach(SearchMatchMode.allCases) { matchMode in
                        Text(matchMode.label).tag(matchMode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 220)
                .help(viewModel.matchMode.helpText)
            }
        }
    }

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            modifiedFilterControls
            sizeFilterControls
        }
    }

    private var modifiedFilterControls: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Picker("Modified", selection: $viewModel.dateFilter) {
                    ForEach(SearchDateFilter.allCases) { dateFilter in
                        Text(dateFilter.label).tag(dateFilter)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 240)

                customDateControls
            }

            if viewModel.dateFilter.usesCustomDate {
                Text("Date format: day / month / year.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var customDateControls: some View {
        if viewModel.dateFilter.usesCustomDate {
            if viewModel.dateFilter.usesCustomEndDate {
                Text("From")
                    .foregroundStyle(.secondary)

                NativeDatePicker(
                    selection: $viewModel.customDate,
                    accessibilityLabel: "Start date"
                )
                .frame(width: 96, height: 22)

                Text("through")
                    .foregroundStyle(.secondary)

                NativeDatePicker(
                    selection: $viewModel.customEndDate,
                    accessibilityLabel: "End date"
                )
                .frame(width: 96, height: 22)
            } else {
                NativeDatePicker(
                    selection: $viewModel.customDate,
                    accessibilityLabel: "Date"
                )
                .frame(width: 96, height: 22)
            }
        }
    }

    private var sizeFilterControls: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Picker("Size", selection: $viewModel.sizeFilter) {
                    ForEach(SearchSizeFilter.allCases) { sizeFilter in
                        Text(sizeFilter.label).tag(sizeFilter)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 220)

                customSizeControls
            }

            Text("Decimal units: 1 KB = 1,000 bytes; MB and GB are decimal too.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var customSizeControls: some View {
        if viewModel.sizeFilter.usesCustomSize {
            if viewModel.sizeFilter.usesCustomMaximumSize {
                Text("Min incl.")
                    .foregroundStyle(.secondary)

                customSizeField("Min", text: $viewModel.customSizeValue)

                sizeUnitPicker("Min unit", selection: $viewModel.customSizeUnit)

                Text("Max incl.")
                    .foregroundStyle(.secondary)

                customSizeField("Max", text: $viewModel.customMaximumSizeValue)

                sizeUnitPicker("Max unit", selection: $viewModel.customMaximumSizeUnit)
            } else {
                customSizeField("Size", text: $viewModel.customSizeValue)
                sizeUnitPicker("Unit", selection: $viewModel.customSizeUnit)
            }
        }
    }

    private func customSizeField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .frame(width: 80)
            .onSubmit {
                viewModel.startSearch()
            }
    }

    private func sizeUnitPicker(_ label: String, selection: Binding<SearchSizeUnit>) -> some View {
        Picker(label, selection: selection) {
            ForEach(SearchSizeUnit.allCases) { unit in
                Text(unit.label).tag(unit)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .accessibilityLabel(label)
        .frame(width: 72)
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
            switch viewModel.matchMode {
            case .contains:
                return "Name contains"
            case .regex:
                return "Name regex"
            case .fuzzy:
                return "Fuzzy name"
            }
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

private struct NativeDatePicker: NSViewRepresentable {
    @Binding var selection: Date
    let accessibilityLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSDatePicker {
        let datePicker = NSDatePicker()
        datePicker.datePickerStyle = .textFieldAndStepper
        datePicker.datePickerElements = .yearMonthDay
        datePicker.locale = Locale(identifier: "en_GB")
        datePicker.dateValue = selection
        datePicker.target = context.coordinator
        datePicker.action = #selector(Coordinator.dateChanged(_:))
        datePicker.setContentHuggingPriority(.defaultLow, for: .horizontal)
        datePicker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        datePicker.setAccessibilityLabel(accessibilityLabel)
        return datePicker
    }

    func updateNSView(_ datePicker: NSDatePicker, context: Context) {
        context.coordinator.selection = $selection
        datePicker.locale = Locale(identifier: "en_GB")
        if datePicker.dateValue != selection {
            datePicker.dateValue = selection
        }
        datePicker.setAccessibilityLabel(accessibilityLabel)
    }

    final class Coordinator: NSObject {
        var selection: Binding<Date>

        init(selection: Binding<Date>) {
            self.selection = selection
        }

        @objc func dateChanged(_ sender: NSDatePicker) {
            selection.wrappedValue = sender.dateValue
        }
    }
}
