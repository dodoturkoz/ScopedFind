import XCTest
@testable import ScopedFind

final class FindCommandBuilderTests: XCTestCase {
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

    func testCaseInsensitiveCommandUsesInameAndPrint0() throws {
        let command = try FindCommandBuilder().makeCommand(
            folder: temporaryFolder,
            query: "report",
            extensions: "",
            caseSensitive: false,
            includeHidden: true,
            target: .all
        )

        XCTAssertEqual(command.executableURL.path, "/usr/bin/find")
        XCTAssertEqual(command.arguments, [temporaryFolder.path, "-iname", "*report*", "-print0"])
    }

    func testCaseSensitiveCommandUsesName() throws {
        let command = try FindCommandBuilder().makeCommand(
            folder: temporaryFolder,
            query: "Report",
            extensions: "",
            caseSensitive: true,
            includeHidden: true,
            target: .all
        )

        XCTAssertEqual(command.arguments, [temporaryFolder.path, "-name", "*Report*", "-print0"])
    }

    func testHiddenFilesArePrunedByDefault() throws {
        let command = try FindCommandBuilder().makeCommand(
            folder: temporaryFolder,
            query: "notes",
            extensions: "",
            caseSensitive: false,
            includeHidden: false,
            target: .all
        )

        XCTAssertEqual(
            command.arguments,
            [temporaryFolder.path, "!", "-path", temporaryFolder.path, "-name", ".*", "-prune", "-o", "-iname", "*notes*", "-print0"]
        )
    }

    func testFilesOnlyCommandUsesFileTypePredicate() throws {
        let command = try FindCommandBuilder().makeCommand(
            folder: temporaryFolder,
            query: "notes",
            extensions: "",
            caseSensitive: false,
            includeHidden: true,
            target: .files
        )

        XCTAssertEqual(command.arguments, [temporaryFolder.path, "-type", "f", "-iname", "*notes*", "-print0"])
    }

    func testDirectoriesOnlyCommandUsesDirectoryTypePredicate() throws {
        let command = try FindCommandBuilder().makeCommand(
            folder: temporaryFolder,
            query: "notes",
            extensions: "",
            caseSensitive: false,
            includeHidden: false,
            target: .directories
        )

        XCTAssertEqual(
            command.arguments,
            [temporaryFolder.path, "!", "-path", temporaryFolder.path, "-name", ".*", "-prune", "-o", "-type", "d", "-iname", "*notes*", "-print0"]
        )
    }

    func testSpacesAndPunctuationRemainInSingleArgument() throws {
        let command = try FindCommandBuilder().makeCommand(
            folder: temporaryFolder,
            query: "budget [final]?*.pdf",
            extensions: "",
            caseSensitive: false,
            includeHidden: true,
            target: .all
        )

        XCTAssertEqual(command.arguments.count, 4)
        XCTAssertEqual(command.arguments[2], "*budget \\[final\\]\\?\\*.pdf*")
    }

    func testExtensionOnlyCommandBuildsGroupedExtensionPredicate() throws {
        let command = try FindCommandBuilder().makeCommand(
            folder: temporaryFolder,
            query: "",
            extensions: "swift, .md txt",
            caseSensitive: false,
            includeHidden: true,
            target: .files
        )

        XCTAssertEqual(
            command.arguments,
            [temporaryFolder.path, "-type", "f", "(", "-iname", "*.swift", "-o", "-iname", "*.md", "-o", "-iname", "*.txt", ")", "-print0"]
        )
    }

    func testExtensionFilterCombinesWithFilenameQuery() throws {
        let command = try FindCommandBuilder().makeCommand(
            folder: temporaryFolder,
            query: "report",
            extensions: "pdf",
            caseSensitive: true,
            includeHidden: true,
            target: .all
        )

        XCTAssertEqual(
            command.arguments,
            [temporaryFolder.path, "-name", "*report*", "(", "-name", "*.pdf", ")", "-print0"]
        )
    }

    func testExtensionPunctuationIsEscaped() throws {
        let command = try FindCommandBuilder().makeCommand(
            folder: temporaryFolder,
            query: "",
            extensions: "weird[?]*",
            caseSensitive: false,
            includeHidden: true,
            target: .all
        )

        XCTAssertEqual(command.arguments, [temporaryFolder.path, "(", "-iname", "*.weird\\[\\?\\]\\*", ")", "-print0"])
    }

    func testEmptyQueryThrows() {
        XCTAssertThrowsError(
            try FindCommandBuilder().makeCommand(
                folder: temporaryFolder,
                query: "   ",
                extensions: "",
                caseSensitive: false,
                includeHidden: true,
                target: .all
            )
        ) { error in
            XCTAssertEqual(error as? FindCommandBuilderError, .emptyQuery)
        }
    }

    func testHiddenComponentDetectionChecksEveryRelativeComponent() {
        let visible = temporaryFolder.appendingPathComponent("docs/report.txt")
        let hiddenFile = temporaryFolder.appendingPathComponent("docs/.report.txt")
        let hiddenFolder = temporaryFolder.appendingPathComponent(".cache/report.txt")

        XCTAssertFalse(FindCommandBuilder.pathContainsHiddenComponent(visible, relativeTo: temporaryFolder))
        XCTAssertTrue(FindCommandBuilder.pathContainsHiddenComponent(hiddenFile, relativeTo: temporaryFolder))
        XCTAssertTrue(FindCommandBuilder.pathContainsHiddenComponent(hiddenFolder, relativeTo: temporaryFolder))
    }
}
