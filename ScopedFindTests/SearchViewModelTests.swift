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

        XCTAssertEqual(viewModel.status, .failed("Enter a search term or extension before starting."))
    }

    func testExtensionOnlySearchIsValid() {
        let viewModel = SearchViewModel(searchService: MockFindSearchService())
        viewModel.selectFolder(URL(fileURLWithPath: "/tmp"))
        viewModel.extensionFilter = "swift"

        viewModel.startSearch()

        XCTAssertEqual(viewModel.status, .searching)
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

    func search(
        folder: URL,
        query: String,
        extensions: String,
        caseSensitive: Bool,
        includeHidden: Bool,
        target: SearchTarget
    ) -> AsyncThrowingStream<FindSearchEvent, Error> {
        searchCallCount += 1
        return AsyncThrowingStream<FindSearchEvent, Error> { _ in }
    }

    func cancel() {
        didCancel = true
    }
}
