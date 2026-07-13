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

struct SearchAutoSearchTrigger: Equatable {
    var selectedFolder: URL?
    var query: String
    var extensionFilter: String
    var isCaseSensitive: Bool
    var includeHiddenFiles: Bool
    var autoSearchEnabled: Bool
    var searchKind: SearchKind
    var searchTarget: SearchTarget
    var matchMode: SearchMatchMode
    var dateFilter: SearchDateFilter
    var customDate: Date
    var customEndDate: Date
    var sizeFilter: SearchSizeFilter
    var customSizeValue: String
    var customSizeUnit: SearchSizeUnit
    var customMaximumSizeValue: String
    var customMaximumSizeUnit: SearchSizeUnit
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
    @Published var dateFilter: SearchDateFilter = .any
    @Published var customDate = Date()
    @Published var customEndDate = Date()
    @Published var sizeFilter: SearchSizeFilter = .any
    @Published var customSizeValue = "1"
    @Published var customSizeUnit: SearchSizeUnit = .megabytes
    @Published var customMaximumSizeValue = "10"
    @Published var customMaximumSizeUnit: SearchSizeUnit = .megabytes
    @Published private(set) var results: [SearchResult] = []
    @Published private(set) var status: SearchStatus = .idle
    @Published private(set) var searchStartedAt: Date?

    private let searchService: FindSearching
    private let autoSearchDelayNanoseconds: UInt64
    private let resultBatchSize: Int
    private let resultFlushDelayNanoseconds: UInt64
    private var searchTask: Task<Void, Never>?
    private var autoSearchTask: Task<Void, Never>?
    private var resultFlushTask: Task<Void, Never>?
    private var pendingResults: [SearchResult] = []
    private var latestWarning: String?

    var canSearch: Bool {
        selectedFolder != nil && hasSearchCriteria && searchFilters.validationMessage == nil && !isSearching
    }

    var isSearching: Bool {
        if case .searching = status {
            return true
        }
        return false
    }

    var autoSearchTrigger: SearchAutoSearchTrigger {
        SearchAutoSearchTrigger(
            selectedFolder: selectedFolder,
            query: query,
            extensionFilter: extensionFilter,
            isCaseSensitive: isCaseSensitive,
            includeHiddenFiles: includeHiddenFiles,
            autoSearchEnabled: autoSearchEnabled,
            searchKind: searchKind,
            searchTarget: searchTarget,
            matchMode: matchMode,
            dateFilter: dateFilter,
            customDate: customDate,
            customEndDate: customEndDate,
            sizeFilter: sizeFilter,
            customSizeValue: customSizeValue,
            customSizeUnit: customSizeUnit,
            customMaximumSizeValue: customMaximumSizeValue,
            customMaximumSizeUnit: customMaximumSizeUnit
        )
    }

    private var hasSearchCriteria: Bool {
        switch searchKind {
        case .names:
            return !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !FindCommandBuilder.normalizedExtensions(from: extensionFilter).isEmpty ||
                searchFilters.isActive
        case .contents:
            return !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var searchFilters: SearchFilters {
        SearchFilters(
            dateFilter: dateFilter,
            customDate: customDate,
            customEndDate: customEndDate,
            sizeFilter: sizeFilter,
            customSizeBytes: customSizeUnit.byteCount(from: customSizeValue),
            customMaximumSizeBytes: customMaximumSizeUnit.byteCount(from: customMaximumSizeValue)
        )
    }

    init(
        searchService: FindSearching = FindSearchService(),
        autoSearchDelayNanoseconds: UInt64 = 1_200_000_000,
        resultBatchSize: Int = 25,
        resultFlushDelayNanoseconds: UInt64 = 150_000_000
    ) {
        self.searchService = searchService
        self.autoSearchDelayNanoseconds = autoSearchDelayNanoseconds
        self.resultBatchSize = max(1, resultBatchSize)
        self.resultFlushDelayNanoseconds = resultFlushDelayNanoseconds
    }

    func searchActivityMessage(at date: Date = Date()) -> String {
        let elapsedSeconds = max(0, Int(date.timeIntervalSince(searchStartedAt ?? date)))
        return "Searching... \(results.count) found, \(Self.elapsedTimeDescription(elapsedSeconds)) elapsed."
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

        guard autoSearchEnabled,
              selectedFolder != nil,
              hasSearchCriteria,
              searchFilters.validationMessage == nil else {
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

        let filters = searchFilters
        if let validationMessage = filters.validationMessage {
            status = .failed(validationMessage)
            return
        }

        discardPendingResults()
        results.removeAll()
        latestWarning = nil
        searchStartedAt = Date()
        status = .searching

        let folder = selectedFolder
        let query = query
        let extensions = extensionFilter
        let caseSensitive = isCaseSensitive
        let includeHidden = includeHiddenFiles
        let searchKind = searchKind
        let target = searchTarget
        let matchMode = matchMode
        let dateFilter = filters.dateFilter
        let customDate = filters.customDate
        let customEndDate = filters.customEndDate
        let sizeFilter = filters.sizeFilter
        let customSizeBytes = filters.customSizeBytes
        let customMaximumSizeBytes = filters.customMaximumSizeBytes

        searchTask = Task {
            do {
                for try await event in searchService.search(
                    folder: folder,
                    query: query,
                    extensions: extensions,
                    caseSensitive: caseSensitive,
                    includeHidden: includeHidden,
                    target: target,
                    matchMode: matchMode,
                    dateFilter: dateFilter,
                    customDate: customDate,
                    customEndDate: customEndDate,
                    sizeFilter: sizeFilter,
                    customSizeBytes: customSizeBytes,
                    customMaximumSizeBytes: customMaximumSizeBytes,
                    searchKind: searchKind
                ) {
                    switch event {
                    case let .result(result):
                        receiveSearchResult(result)
                    case let .warning(message):
                        latestWarning = message
                    }
                }

                flushPendingResults()
                searchStartedAt = nil
                status = .finished(resultCount: results.count, warning: latestWarning)
            } catch is CancellationError {
                flushPendingResults()
                searchStartedAt = nil
                status = .cancelled
            } catch let error as FindSearchServiceError where error == .cancelled {
                flushPendingResults()
                searchStartedAt = nil
                status = .cancelled
            } catch let error as LocalizedError {
                flushPendingResults()
                searchStartedAt = nil
                status = .failed(error.errorDescription ?? "The search failed.")
            } catch {
                flushPendingResults()
                searchStartedAt = nil
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
        flushPendingResults()
        searchStartedAt = nil
        status = .cancelled
    }

    private func receiveSearchResult(_ result: SearchResult) {
        if results.isEmpty && pendingResults.isEmpty {
            results.append(result)
            return
        }

        pendingResults.append(result)
        if pendingResults.count >= resultBatchSize {
            flushPendingResults()
        } else {
            scheduleResultFlush()
        }
    }

    private func scheduleResultFlush() {
        guard resultFlushTask == nil else {
            return
        }

        let delay = resultFlushDelayNanoseconds
        resultFlushTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }

            guard let self else {
                return
            }
            resultFlushTask = nil
            flushPendingResults()
        }
    }

    private func flushPendingResults() {
        resultFlushTask?.cancel()
        resultFlushTask = nil

        guard !pendingResults.isEmpty else {
            return
        }

        results.append(contentsOf: pendingResults)
        pendingResults.removeAll(keepingCapacity: true)
    }

    private func discardPendingResults() {
        resultFlushTask?.cancel()
        resultFlushTask = nil
        pendingResults.removeAll(keepingCapacity: true)
    }

    private func startAutomaticSearch() {
        guard autoSearchEnabled,
              selectedFolder != nil,
              hasSearchCriteria,
              searchFilters.validationMessage == nil else {
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
            return "Enter a search term, extension, date filter, or size filter before starting."
        case .contents:
            return "Enter text to search file contents."
        }
    }

    private static func elapsedTimeDescription(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        }
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}
