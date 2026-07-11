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
}

private final class MockFindSearchService: FindSearching {
    private(set) var didCancel = false

    func search(
        folder: URL,
        query: String,
        extensions: String,
        caseSensitive: Bool,
        includeHidden: Bool,
        target: SearchTarget
    ) -> AsyncThrowingStream<FindSearchEvent, Error> {
        AsyncThrowingStream { _ in }
    }

    func cancel() {
        didCancel = true
    }
}
