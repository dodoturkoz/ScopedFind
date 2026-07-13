import XCTest
@testable import ScopedFind

@MainActor
final class SearchViewModelTests: XCTestCase {
    func testMissingFolderValidation() {
        let viewModel = SearchViewModel(searchService: MockFindSearchService())
        viewModel.query = "notes"

        viewModel.startSearch()

        XCTAssertEqual(viewModel.status, .failed("Choose a folder before searching."))
    }

    func testEmptyQueryValidation() {
        let viewModel = SearchViewModel(searchService: MockFindSearchService())
        viewModel.selectFolder(URL(fileURLWithPath: "/tmp"))
        viewModel.query = " "

        viewModel.startSearch()

        XCTAssertEqual(viewModel.status, .failed("Enter a search term, extension, date filter, or size filter before starting."))
    }

    func testExtensionOnlySearchIsValid() {
        let viewModel = SearchViewModel(searchService: MockFindSearchService())
        viewModel.selectFolder(URL(fileURLWithPath: "/tmp"))
        viewModel.extensionFilter = "swift"

        viewModel.startSearch()

        XCTAssertEqual(viewModel.status, .searching)
    }

    func testFilterOnlyNameSearchIsValid() async throws {
        let service = MockFindSearchService()
        let viewModel = SearchViewModel(searchService: service)
        viewModel.selectFolder(URL(fileURLWithPath: "/tmp"))
        viewModel.dateFilter = .modifiedLastHour
        viewModel.sizeFilter = .largerThan1MB

        viewModel.startSearch()
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(viewModel.status, .searching)
        XCTAssertEqual(service.lastDateFilter, .modifiedLastHour)
        XCTAssertEqual(service.lastSizeFilter, .largerThan1MB)
    }

    func testCustomSizeSearchPassesByteCount() async throws {
        let service = MockFindSearchService()
        let viewModel = SearchViewModel(searchService: service)
        viewModel.selectFolder(URL(fileURLWithPath: "/tmp"))
        viewModel.sizeFilter = .exactCustom
        viewModel.customSizeValue = "1.5"
        viewModel.customSizeUnit = .megabytes

        viewModel.startSearch()
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(viewModel.status, .searching)
        XCTAssertEqual(service.lastSizeFilter, .exactCustom)
        XCTAssertEqual(service.lastCustomSizeBytes, 1_500_000)
    }

    func testCustomSizeRangeSearchPassesMaximumByteCount() async throws {
        let service = MockFindSearchService()
        let viewModel = SearchViewModel(searchService: service)
        viewModel.selectFolder(URL(fileURLWithPath: "/tmp"))
        viewModel.sizeFilter = .betweenCustom
        viewModel.customSizeValue = "1"
        viewModel.customSizeUnit = .kilobytes
        viewModel.customMaximumSizeValue = "2"
        viewModel.customMaximumSizeUnit = .kilobytes

        viewModel.startSearch()
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(viewModel.status, .searching)
        XCTAssertEqual(service.lastSizeFilter, .betweenCustom)
        XCTAssertEqual(service.lastCustomSizeBytes, 1_000)
        XCTAssertEqual(service.lastCustomMaximumSizeBytes, 2_000)
    }

    func testKilobyteFilterUsesDecimalUnits() {
        let threshold = SearchSizeUnit.kilobytes.byteCount(from: "32")

        XCTAssertEqual(threshold, 32_000)
        XCTAssertTrue(SearchSizeFilter.largerThanCustom.matches(32_500, customByteCount: threshold))
        XCTAssertFalse(SearchSizeFilter.largerThanCustom.matches(32_000, customByteCount: threshold))
    }

    func testContentSearchRequiresQueryEvenWithExtension() {
        let viewModel = SearchViewModel(searchService: MockFindSearchService())
        viewModel.selectFolder(URL(fileURLWithPath: "/tmp"))
        viewModel.searchKind = .contents
        viewModel.extensionFilter = "swift"

        viewModel.startSearch()

        XCTAssertEqual(viewModel.status, .failed("Enter text to search file contents."))
    }

    func testContentSearchWithQueryIsValid() async throws {
        let service = MockFindSearchService()
        let viewModel = SearchViewModel(searchService: service)
        viewModel.selectFolder(URL(fileURLWithPath: "/tmp"))
        viewModel.searchKind = .contents
        viewModel.query = "needle"

        viewModel.startSearch()
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(viewModel.status, .searching)
        XCTAssertEqual(service.lastSearchKind, .contents)
    }

    func testCancellationState() {
        let service = MockFindSearchService()
        let viewModel = SearchViewModel(searchService: service)
        viewModel.selectFolder(URL(fileURLWithPath: "/tmp"))
        viewModel.query = "notes"

        viewModel.startSearch()
        viewModel.cancelSearch()

        XCTAssertTrue(service.didCancel)
        XCTAssertEqual(viewModel.status, .cancelled)
    }

    func testFirstResultAppearsImmediatelyAndLaterResultsFlushOnTimer() async throws {
        let service = StreamingFindSearchService()
        let viewModel = SearchViewModel(
            searchService: service,
            resultBatchSize: 25,
            resultFlushDelayNanoseconds: 5_000_000
        )
        viewModel.selectFolder(URL(fileURLWithPath: "/tmp"))
        viewModel.query = "notes"
        viewModel.startSearch()
        try await waitForStream(service)

        service.send(.result(SearchResult(url: URL(fileURLWithPath: "/tmp/first.txt"))))
        try await Task.sleep(nanoseconds: 5_000_000)
        XCTAssertEqual(viewModel.results.map(\.url.path), ["/tmp/first.txt"])

        service.send(.result(SearchResult(url: URL(fileURLWithPath: "/tmp/second.txt"))))
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(viewModel.results.map(\.url.path), ["/tmp/first.txt", "/tmp/second.txt"])

        viewModel.cancelSearch()
    }

    func testFinishingSearchFlushesPendingResults() async throws {
        let service = StreamingFindSearchService()
        let viewModel = SearchViewModel(
            searchService: service,
            resultBatchSize: 25,
            resultFlushDelayNanoseconds: 1_000_000_000
        )
        viewModel.selectFolder(URL(fileURLWithPath: "/tmp"))
        viewModel.query = "notes"
        viewModel.startSearch()
        try await waitForStream(service)

        service.send(.result(SearchResult(url: URL(fileURLWithPath: "/tmp/first.txt"))))
        service.send(.result(SearchResult(url: URL(fileURLWithPath: "/tmp/second.txt"))))
        service.finish()
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(viewModel.results.map(\.url.path), ["/tmp/first.txt", "/tmp/second.txt"])
        XCTAssertEqual(viewModel.status, .finished(resultCount: 2, warning: nil))
    }

    func testSearchActivityMessageIncludesLiveCountAndElapsedTime() throws {
        let viewModel = SearchViewModel(searchService: MockFindSearchService())
        viewModel.selectFolder(URL(fileURLWithPath: "/tmp"))
        viewModel.query = "notes"
        viewModel.startSearch()

        let start = try XCTUnwrap(viewModel.searchStartedAt)
        XCTAssertEqual(
            viewModel.searchActivityMessage(at: start.addingTimeInterval(65)),
            "Searching... 0 found, 1m 5s elapsed."
        )

        viewModel.cancelSearch()
    }

    func testScheduledAutoSearchStartsAfterDelay() async throws {
        let service = MockFindSearchService()
        let viewModel = SearchViewModel(searchService: service, autoSearchDelayNanoseconds: 1_000_000)
        viewModel.selectFolder(URL(fileURLWithPath: "/tmp"))
        viewModel.query = "notes"

        viewModel.scheduleAutoSearch()
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(service.searchCallCount, 1)
        XCTAssertEqual(viewModel.status, .searching)

        viewModel.cancelSearch()
    }

    func testDisabledAutoSearchDoesNotStart() async throws {
        let service = MockFindSearchService()
        let viewModel = SearchViewModel(searchService: service, autoSearchDelayNanoseconds: 1_000_000)
        viewModel.selectFolder(URL(fileURLWithPath: "/tmp"))
        viewModel.query = "notes"
        viewModel.autoSearchEnabled = false

        viewModel.scheduleAutoSearch()
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(service.searchCallCount, 0)
        XCTAssertEqual(viewModel.status, .idle)
    }

    private func waitForStream(_ service: StreamingFindSearchService) async throws {
        for _ in 0..<50 {
            if service.isReady {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Timed out waiting for the search stream to start.")
    }
}

private final class StreamingFindSearchService: FindSearching {
    private var continuation: AsyncThrowingStream<FindSearchEvent, Error>.Continuation?

    var isReady: Bool {
        continuation != nil
    }

    func search(
        folder: URL,
        query: String,
        extensions: String,
        caseSensitive: Bool,
        includeHidden: Bool,
        target: SearchTarget,
        matchMode: SearchMatchMode,
        dateFilter: SearchDateFilter,
        customDate: Date?,
        customEndDate: Date?,
        sizeFilter: SearchSizeFilter,
        customSizeBytes: UInt64?,
        customMaximumSizeBytes: UInt64?,
        searchKind: SearchKind
    ) -> AsyncThrowingStream<FindSearchEvent, Error> {
        AsyncThrowingStream { continuation in
            self.continuation = continuation
        }
    }

    func send(_ event: FindSearchEvent) {
        continuation?.yield(event)
    }

    func finish() {
        continuation?.finish()
    }

    func cancel() {
        continuation?.finish(throwing: FindSearchServiceError.cancelled)
    }
}

private final class MockFindSearchService: FindSearching {
    private(set) var didCancel = false
    private(set) var searchCallCount = 0
    private(set) var lastSearchKind: SearchKind?
    private(set) var lastDateFilter: SearchDateFilter?
    private(set) var lastSizeFilter: SearchSizeFilter?
    private(set) var lastCustomSizeBytes: UInt64?
    private(set) var lastCustomMaximumSizeBytes: UInt64?

    func search(
        folder: URL,
        query: String,
        extensions: String,
        caseSensitive: Bool,
        includeHidden: Bool,
        target: SearchTarget,
        matchMode: SearchMatchMode,
        dateFilter: SearchDateFilter,
        customDate: Date?,
        customEndDate: Date?,
        sizeFilter: SearchSizeFilter,
        customSizeBytes: UInt64?,
        customMaximumSizeBytes: UInt64?,
        searchKind: SearchKind
    ) -> AsyncThrowingStream<FindSearchEvent, Error> {
        searchCallCount += 1
        lastSearchKind = searchKind
        lastDateFilter = dateFilter
        lastSizeFilter = sizeFilter
        lastCustomSizeBytes = customSizeBytes
        lastCustomMaximumSizeBytes = customMaximumSizeBytes
        return AsyncThrowingStream<FindSearchEvent, Error> { _ in }
    }

    func cancel() {
        didCancel = true
    }
}
