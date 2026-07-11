import XCTest
@testable import ScopedFind

final class FindSearchServiceTests: XCTestCase {
    private var temporaryFolder: URL!

    override func setUpWithError() throws {
        temporaryFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryFolder {
            try? FileManager.default.removeItem(at: temporaryFolder)
        }
    }

    func testServiceFindsVisibleFilesInTemporaryDirectory() async throws {
        let expected = temporaryFolder.appendingPathComponent("notes file.txt")
        try Data("hello".utf8).write(to: expected)

        let results = try await collectResults(
            query: "notes",
            extensions: "",
            includeHidden: false,
            target: .all
        )

        XCTAssertEqual(results.map(\.url.path), [expected.path])
    }

    func testServiceExcludesHiddenPathsByDefault() async throws {
        let hiddenDirectory = temporaryFolder.appendingPathComponent(".hidden", isDirectory: true)
        try FileManager.default.createDirectory(at: hiddenDirectory, withIntermediateDirectories: true)
        try Data().write(to: hiddenDirectory.appendingPathComponent("notes.txt"))
        try Data().write(to: temporaryFolder.appendingPathComponent(".notes.txt"))

        let results = try await collectResults(
            query: "notes",
            extensions: "",
            includeHidden: false,
            target: .all
        )

        XCTAssertEqual(results, [])
    }

    func testServiceIncludesHiddenPathsWhenRequested() async throws {
        let hiddenFile = temporaryFolder.appendingPathComponent(".notes.txt")
        try Data().write(to: hiddenFile)

        let results = try await collectResults(
            query: "notes",
            extensions: "",
            includeHidden: true,
            target: .all
        )

        XCTAssertEqual(results.map(\.url.path), [hiddenFile.path])
    }

    func testServiceCanLimitResultsToFiles() async throws {
        let file = temporaryFolder.appendingPathComponent("notes.txt")
        let directory = temporaryFolder.appendingPathComponent("notes-folder", isDirectory: true)
        try Data().write(to: file)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let results = try await collectResults(
            query: "notes",
            extensions: "",
            includeHidden: true,
            target: .files
        )

        XCTAssertEqual(results.map(\.url.path), [file.path])
    }

    func testServiceCanLimitResultsToDirectories() async throws {
        let file = temporaryFolder.appendingPathComponent("notes.txt")
        let directory = temporaryFolder.appendingPathComponent("notes-folder", isDirectory: true)
        try Data().write(to: file)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let results = try await collectResults(
            query: "notes",
            extensions: "",
            includeHidden: true,
            target: .directories
        )

        XCTAssertEqual(results.map(\.url.path), [directory.path])
    }

    func testServiceCanSearchByExtensionOnly() async throws {
        let swiftFile = temporaryFolder.appendingPathComponent("AppDelegate.swift")
        let textFile = temporaryFolder.appendingPathComponent("notes.txt")
        try Data().write(to: swiftFile)
        try Data().write(to: textFile)

        let results = try await collectResults(
            query: "",
            extensions: "swift",
            includeHidden: true,
            target: .files
        )

        XCTAssertEqual(results.map(\.url.path), [swiftFile.path])
    }

    func testServiceCanSearchMultipleExtensions() async throws {
        let swiftFile = temporaryFolder.appendingPathComponent("AppDelegate.swift")
        let markdownFile = temporaryFolder.appendingPathComponent("README.md")
        let textFile = temporaryFolder.appendingPathComponent("notes.txt")
        try Data().write(to: swiftFile)
        try Data().write(to: markdownFile)
        try Data().write(to: textFile)

        let results = try await collectResults(
            query: "",
            extensions: "swift,md",
            includeHidden: true,
            target: .files
        )

        XCTAssertEqual(Set(results.map(\.url.path)), Set([swiftFile.path, markdownFile.path]))
    }

    func testPermissionDeniedSurfacesWarningAndKeepsAccessibleResults() async throws {
        let visibleFile = temporaryFolder.appendingPathComponent("permission-note.txt")
        try Data().write(to: visibleFile)

        let lockedDirectory = temporaryFolder.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: lockedDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: lockedDirectory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: lockedDirectory.path)
        }

        var results: [SearchResult] = []
        var warnings: [String] = []
        let service = FindSearchService()

        for try await event in service.search(
            folder: temporaryFolder,
            query: "permission-note",
            extensions: "",
            caseSensitive: false,
            includeHidden: false,
            target: .all
        ) {
            switch event {
            case let .result(result):
                results.append(result)
            case let .warning(warning):
                warnings.append(warning)
            }
        }

        XCTAssertEqual(results.map(\.url.path), [visibleFile.path])
        XCTAssertTrue(warnings.contains { $0.localizedCaseInsensitiveContains("permission") })
    }

    private func collectResults(
        query: String,
        extensions: String,
        includeHidden: Bool,
        target: SearchTarget
    ) async throws -> [SearchResult] {
        var results: [SearchResult] = []
        let service = FindSearchService()

        for try await event in service.search(
            folder: temporaryFolder,
            query: query,
            extensions: extensions,
            caseSensitive: false,
            includeHidden: includeHidden,
            target: target
        ) {
            if case let .result(result) = event {
                results.append(result)
            }
        }

        return results
    }
}
