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
