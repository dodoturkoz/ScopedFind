import Foundation
import Combine

enum SearchStatus: Equatable {
    case idle
    case searching
    case finished(resultCount: Int, warning: String?)
    case cancelled
    case failed(String)

    var message: String {
        switch self {
        case .idle:
            return "Choose a folder and search by name or content."
        case .searching:
            return "Searching..."
        case let .finished(resultCount, warning):
            if let warning {
                return "Finished with \(resultCount) result\(resultCount == 1 ? "" : "s"). \(warning)"
            }
            return "Finished with \(resultCount) result\(resultCount == 1 ? "" : "s")."
        case .cancelled:
            return "Search cancelled."
        case let .failed(message):
            return message
        }
    }
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var selectedFolder: URL?
    @Published var query = ""
    @Published var extensionFilter = ""
    @Published var isCaseSensitive = false
    @Published var includeHiddenFiles = false
    @Published var autoSearchEnabled = true
    @Published var searchKind: SearchKind = .names
    @Published var searchTarget: SearchTarget = .all
    @Published var matchMode: SearchMatchMode = .contains
    @Published private(set) var results: [SearchResult] = []
    @Published private(set) var status: SearchStatus = .idle

    private let searchService: FindSearching
    private let autoSearchDelayNanoseconds: UInt64
    private var searchTask: Task<Void, Never>?
    private var autoSearchTask: Task<Void, Never>?
    private var latestWarning: String?

    var canSearch: Bool {
        selectedFolder != nil && hasSearchCriteria && !isSearching
    }

    var isSearching: Bool {
        if case .searching = status {
            return true
        }
        return false
    }

    private var hasSearchCriteria: Bool {
        switch searchKind {
        case .names:
            return !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !FindCommandBuilder.normalizedExtensions(from: extensionFilter).isEmpty
        case .contents:
            return !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    init(
        searchService: FindSearching = FindSearchService(),
        autoSearchDelayNanoseconds: UInt64 = 1_200_000_000
    ) {
        self.searchService = searchService
        self.autoSearchDelayNanoseconds = autoSearchDelayNanoseconds
    }

    func selectFolder(_ folder: URL) {
        selectedFolder = folder
        if case .idle = status {
            status = .idle
        }
    }

    func scheduleAutoSearch() {
        autoSearchTask?.cancel()
        autoSearchTask = nil

        guard autoSearchEnabled, selectedFolder != nil, hasSearchCriteria else {
            return
        }

        let delay = autoSearchDelayNanoseconds
        autoSearchTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }

            self?.startAutomaticSearch()
        }
    }

    func startSearch() {
        startSearch(cancelScheduledAutoSearch: true)
    }

    private func startSearch(cancelScheduledAutoSearch: Bool) {
        if cancelScheduledAutoSearch {
            autoSearchTask?.cancel()
            autoSearchTask = nil
        }

        guard !isSearching else {
            return
        }

        guard let selectedFolder else {
            status = .failed("Choose a folder before searching.")
            return
        }

        guard hasSearchCriteria else {
            status = .failed(emptyCriteriaMessage)
            return
        }

        results.removeAll()
        latestWarning = nil
        status = .searching

        let folder = selectedFolder
        let query = query
        let extensions = extensionFilter
        let caseSensitive = isCaseSensitive
        let includeHidden = includeHiddenFiles
        let searchKind = searchKind
        let target = searchTarget
        let matchMode = matchMode

        searchTask = Task {
            do {
                var pendingResults: [SearchResult] = []

                for try await event in searchService.search(
                    folder: folder,
                    query: query,
                    extensions: extensions,
                    caseSensitive: caseSensitive,
                    includeHidden: includeHidden,
                    target: target,
                    matchMode: matchMode,
                    searchKind: searchKind
                ) {
                    switch event {
                    case let .result(result):
                        pendingResults.append(result)
                        if pendingResults.count >= 100 {
                            results.append(contentsOf: pendingResults)
                            pendingResults.removeAll(keepingCapacity: true)
                        }
                    case let .warning(message):
                        latestWarning = message
                    }
                }

                if !pendingResults.isEmpty {
                    results.append(contentsOf: pendingResults)
                }
                status = .finished(resultCount: results.count, warning: latestWarning)
            } catch is CancellationError {
                status = .cancelled
            } catch let error as FindSearchServiceError where error == .cancelled {
                status = .cancelled
            } catch let error as LocalizedError {
                status = .failed(error.errorDescription ?? "The search failed.")
            } catch {
                status = .failed("The search failed.")
            }

            searchTask = nil
        }
    }

    func cancelSearch() {
        cancelSearch(cancelScheduledAutoSearch: true)
    }

    private func cancelSearch(cancelScheduledAutoSearch: Bool) {
        if cancelScheduledAutoSearch {
            autoSearchTask?.cancel()
            autoSearchTask = nil
        }

        guard isSearching else {
            return
        }

        searchTask?.cancel()
        searchService.cancel()
        status = .cancelled
    }

    private func startAutomaticSearch() {
        guard autoSearchEnabled, selectedFolder != nil, hasSearchCriteria else {
            return
        }

        if isSearching {
            let taskToAwait = searchTask
            cancelSearch(cancelScheduledAutoSearch: false)
            autoSearchTask = Task { [weak self, taskToAwait] in
                await taskToAwait?.value
                guard !Task.isCancelled else {
                    return
                }
                self?.startAutomaticSearch()
            }
            return
        }

        startSearch(cancelScheduledAutoSearch: false)
    }

    private var emptyCriteriaMessage: String {
        switch searchKind {
        case .names:
            return "Enter a search term or extension before starting."
        case .contents:
            return "Enter text to search file contents."
        }
    }
}
