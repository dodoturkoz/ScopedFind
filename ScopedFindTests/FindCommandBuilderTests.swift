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

    func testFuzzyCommandUsesOrderedCharacterPattern() throws {
        let command = try FindCommandBuilder().makeCommand(
            folder: temporaryFolder,
            query: "sf",
            extensions: "",
            caseSensitive: false,
            includeHidden: true,
            target: .all,
            matchMode: .fuzzy
        )

        XCTAssertEqual(command.arguments, [temporaryFolder.path, "-iname", "*s*f*", "-print0"])
    }

    func testFuzzyCommandIgnoresQueryWhitespace() throws {
        let command = try FindCommandBuilder().makeCommand(
            folder: temporaryFolder,
            query: "s f",
            extensions: "",
            caseSensitive: false,
            includeHidden: true,
            target: .all,
            matchMode: .fuzzy
        )

        XCTAssertEqual(command.arguments, [temporaryFolder.path, "-iname", "*s*f*", "-print0"])
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

    func testFuzzyFilenameQueryCombinesWithExtensionFilter() throws {
        let command = try FindCommandBuilder().makeCommand(
            folder: temporaryFolder,
            query: "sf",
            extensions: "swift",
            caseSensitive: false,
            includeHidden: true,
            target: .files,
            matchMode: .fuzzy
        )

        XCTAssertEqual(
            command.arguments,
            [temporaryFolder.path, "-type", "f", "-iname", "*s*f*", "(", "-iname", "*.swift", ")", "-print0"]
        )
    }

    func testRegexNameCommandEnumeratesCandidatesForInProcessMatching() throws {
        let command = try FindCommandBuilder().makeCommand(
            folder: temporaryFolder,
            query: "report-[0-9]+",
            extensions: "txt",
            caseSensitive: false,
            includeHidden: true,
            target: .files,
            matchMode: .regex
        )

        XCTAssertEqual(
            command.arguments,
            [temporaryFolder.path, "-type", "f", "(", "-iname", "*.txt", ")", "-print0"]
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

    func testContentCommandUsesFindExecGrep() throws {
        let command = try FindCommandBuilder().makeCommand(
            folder: temporaryFolder,
            query: "needle",
            extensions: "",
            caseSensitive: false,
            includeHidden: true,
            target: .all,
            searchKind: .contents
        )

        XCTAssertEqual(command.executableURL.path, "/usr/bin/find")
        XCTAssertEqual(
            command.arguments,
            [temporaryFolder.path, "-type", "f", "-exec", "/usr/bin/grep", "-I", "-l", "--null", "-F", "-i", "-e", "needle", "{}", "+"]
        )
        XCTAssertTrue(command.treatsTerminationStatusAsSuccess(0))
        XCTAssertTrue(command.treatsTerminationStatusAsSuccess(1))
    }

    func testContentCommandCanBeCaseSensitive() throws {
        let command = try FindCommandBuilder().makeCommand(
            folder: temporaryFolder,
            query: "Needle",
            extensions: "",
            caseSensitive: true,
            includeHidden: true,
            target: .all,
            searchKind: .contents
        )

        XCTAssertEqual(
            command.arguments,
            [temporaryFolder.path, "-type", "f", "-exec", "/usr/bin/grep", "-I", "-l", "--null", "-F", "-e", "Needle", "{}", "+"]
        )
    }

    func testContentCommandPrunesHiddenPathsByDefault() throws {
        let command = try FindCommandBuilder().makeCommand(
            folder: temporaryFolder,
            query: "needle",
            extensions: "",
            caseSensitive: false,
            includeHidden: false,
            target: .all,
            searchKind: .contents
        )

        XCTAssertEqual(
            command.arguments,
            [temporaryFolder.path, "!", "-path", temporaryFolder.path, "-name", ".*", "-prune", "-o", "-type", "f", "-exec", "/usr/bin/grep", "-I", "-l", "--null", "-F", "-i", "-e", "needle", "{}", "+"]
        )
    }

    func testContentCommandCombinesWithExtensionFilter() throws {
        let command = try FindCommandBuilder().makeCommand(
            folder: temporaryFolder,
            query: "needle",
            extensions: "swift md",
            caseSensitive: false,
            includeHidden: true,
            target: .directories,
            searchKind: .contents
        )

        XCTAssertEqual(
            command.arguments,
            [temporaryFolder.path, "-type", "f", "(", "-iname", "*.swift", "-o", "-iname", "*.md", ")", "-exec", "/usr/bin/grep", "-I", "-l", "--null", "-F", "-i", "-e", "needle", "{}", "+"]
        )
    }

    func testPDFEnumerationCommandFindsPDFsWhenNoExtensionFilterIsSet() throws {
        let command = try XCTUnwrap(
            FindCommandBuilder().makePDFEnumerationCommand(
                folder: temporaryFolder,
                extensions: "",
                caseSensitive: true,
                includeHidden: true
            )
        )

        XCTAssertEqual(
            command.arguments,
            [temporaryFolder.path, "-type", "f", "-iname", "*.pdf", "-print0"]
        )
    }

    func testPDFEnumerationCommandPrunesHiddenPathsByDefault() throws {
        let command = try XCTUnwrap(
            FindCommandBuilder().makePDFEnumerationCommand(
                folder: temporaryFolder,
                extensions: "",
                caseSensitive: false,
                includeHidden: false
            )
        )

        XCTAssertEqual(
            command.arguments,
            [temporaryFolder.path, "!", "-path", temporaryFolder.path, "-name", ".*", "-prune", "-o", "-type", "f", "-iname", "*.pdf", "-print0"]
        )
    }

    func testPDFEnumerationCommandHonorsPDFExtensionFilter() throws {
        let command = try XCTUnwrap(
            FindCommandBuilder().makePDFEnumerationCommand(
                folder: temporaryFolder,
                extensions: "txt,PDF",
                caseSensitive: true,
                includeHidden: true
            )
        )

        XCTAssertEqual(
            command.arguments,
            [temporaryFolder.path, "-type", "f", "(", "-name", "*.PDF", ")", "-print0"]
        )
    }

    func testPDFEnumerationCommandIsSkippedForNonPDFExtensionFilter() throws {
        let command = try FindCommandBuilder().makePDFEnumerationCommand(
            folder: temporaryFolder,
            extensions: "swift md",
            caseSensitive: false,
            includeHidden: true
        )

        XCTAssertNil(command)
    }

    func testDOCXEnumerationCommandFindsDOCXFilesWhenNoExtensionFilterIsSet() throws {
        let command = try XCTUnwrap(
            FindCommandBuilder().makeDOCXEnumerationCommand(
                folder: temporaryFolder,
                extensions: "",
                caseSensitive: true,
                includeHidden: true
            )
        )

        XCTAssertEqual(
            command.arguments,
            [temporaryFolder.path, "-type", "f", "-iname", "*.docx", "-print0"]
        )
    }

    func testDOCXEnumerationCommandHonorsDOCXExtensionFilter() throws {
        let command = try XCTUnwrap(
            FindCommandBuilder().makeDOCXEnumerationCommand(
                folder: temporaryFolder,
                extensions: "txt,DOCX",
                caseSensitive: true,
                includeHidden: true
            )
        )

        XCTAssertEqual(
            command.arguments,
            [temporaryFolder.path, "-type", "f", "(", "-name", "*.DOCX", ")", "-print0"]
        )
    }

    func testDOCXEnumerationCommandIsSkippedForNonDOCXExtensionFilter() throws {
        let command = try FindCommandBuilder().makeDOCXEnumerationCommand(
            folder: temporaryFolder,
            extensions: "pdf md",
            caseSensitive: false,
            includeHidden: true
        )

        XCTAssertNil(command)
    }

    func testSpreadsheetEnumerationCommandIncludesXLSXAndXLSM() throws {
        let command = try XCTUnwrap(
            FindCommandBuilder().makeSpreadsheetEnumerationCommand(
                folder: temporaryFolder,
                extensions: "",
                caseSensitive: true,
                includeHidden: true
            )
        )

        XCTAssertEqual(
            command.arguments,
            [
                temporaryFolder.path,
                "-type", "f",
                "(", "-iname", "*.xlsx", "-o", "-iname", "*.xlsm", ")",
                "-print0"
            ]
        )
    }

    func testSpreadsheetEnumerationCommandHonorsMatchingExtensionFilter() throws {
        let command = try XCTUnwrap(
            FindCommandBuilder().makeSpreadsheetEnumerationCommand(
                folder: temporaryFolder,
                extensions: "txt,XLSM",
                caseSensitive: true,
                includeHidden: true
            )
        )

        XCTAssertEqual(
            command.arguments,
            [temporaryFolder.path, "-type", "f", "(", "-name", "*.XLSM", ")", "-print0"]
        )
    }

    func testPresentationEnumerationCommandIncludesPPTXAndPPTM() throws {
        let command = try XCTUnwrap(
            FindCommandBuilder().makePresentationEnumerationCommand(
                folder: temporaryFolder,
                extensions: "",
                caseSensitive: false,
                includeHidden: false
            )
        )

        XCTAssertEqual(
            command.arguments,
            [
                temporaryFolder.path,
                "!", "-path", temporaryFolder.path, "-name", ".*", "-prune", "-o",
                "-type", "f",
                "(", "-iname", "*.pptx", "-o", "-iname", "*.pptm", ")",
                "-print0"
            ]
        )
    }

    func testDocumentSearchPassesFollowExecutionOrderAndExtensionFilter() throws {
        let passes = try FindCommandBuilder().makeDocumentSearchPasses(
            folder: temporaryFolder,
            extensions: "xlsx,pptm",
            caseSensitive: false,
            includeHidden: true
        )

        XCTAssertEqual(passes.map(\.kind), [.spreadsheet, .presentation])
        XCTAssertEqual(
            passes[0].command.arguments,
            [temporaryFolder.path, "-type", "f", "(", "-iname", "*.xlsx", ")", "-print0"]
        )
        XCTAssertEqual(
            passes[1].command.arguments,
            [temporaryFolder.path, "-type", "f", "(", "-iname", "*.pptm", ")", "-print0"]
        )
    }

    func testNameEnumerationCommandCanListExtensionFilteredCandidates() throws {
        let command = try FindCommandBuilder().makeNameEnumerationCommand(
            folder: temporaryFolder,
            extensions: "txt md",
            caseSensitive: false,
            includeHidden: true,
            target: .files
        )

        XCTAssertEqual(
            command.arguments,
            [temporaryFolder.path, "-type", "f", "(", "-iname", "*.txt", "-o", "-iname", "*.md", ")", "-print0"]
        )
    }

    func testContentEnumerationCommandCanListExtensionFilteredFiles() throws {
        let command = try FindCommandBuilder().makeContentEnumerationCommand(
            folder: temporaryFolder,
            extensions: "txt md",
            caseSensitive: false,
            includeHidden: false
        )

        XCTAssertEqual(
            command.arguments,
            [temporaryFolder.path, "!", "-path", temporaryFolder.path, "-name", ".*", "-prune", "-o", "-type", "f", "(", "-iname", "*.txt", "-o", "-iname", "*.md", ")", "-print0"]
        )
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

    func testContentSearchRequiresQueryEvenWithExtensions() {
        XCTAssertThrowsError(
            try FindCommandBuilder().makeCommand(
                folder: temporaryFolder,
                query: "   ",
                extensions: "swift",
                caseSensitive: false,
                includeHidden: true,
                target: .all,
                searchKind: .contents
            )
        ) { error in
            XCTAssertEqual(error as? FindCommandBuilderError, .emptyContentQuery)
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
