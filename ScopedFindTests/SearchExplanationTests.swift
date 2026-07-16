import XCTest
@testable import ScopedFind

final class SearchExplanationTests: XCTestCase {
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

    func testShellFormattedCommandQuotesEachUnsafeArgument() {
        let command = FindCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/find"),
            arguments: ["/tmp/Client Files", "-iname", "*O'Brien*", "-print0"]
        )

        XCTAssertEqual(
            SearchCommandExplanation(command: command).shellFormattedCommand,
            "/usr/bin/find '/tmp/Client Files' -iname '*O'\\''Brien*' -print0"
        )
    }

    func testCaseInsensitiveNamePlanIncludesExactUnicodeFallbackCommand() throws {
        let plan = try FindCommandBuilder().makeExecutionPlan(
            folder: temporaryFolder,
            query: "report",
            extensions: "txt",
            caseSensitive: false,
            includeHidden: true,
            target: .files,
            matchMode: .contains,
            filtersActive: false,
            searchKind: .names
        )

        XCTAssertEqual(plan.strategy, .namesMatchedByFind)
        XCTAssertEqual(
            plan.primaryCommand.arguments,
            [temporaryFolder.path, "-type", "f", "-iname", "*report*", "(", "-iname", "*.txt", ")", "-print0"]
        )
        XCTAssertEqual(
            plan.unicodeFallbackCommand?.arguments,
            [temporaryFolder.path, "-type", "f", "(", "-iname", "*.txt", ")", "-print0"]
        )
    }

    func testRegexNamePlanExplainsInProcessMatchingWithoutInventingGrep() throws {
        let plan = try FindCommandBuilder().makeExecutionPlan(
            folder: temporaryFolder,
            query: "report-[0-9]+",
            extensions: "txt",
            caseSensitive: false,
            includeHidden: false,
            target: .files,
            matchMode: .regex,
            filtersActive: false,
            searchKind: .names
        )
        let explanation = SearchExplanationBuilder().makeExplanation(
            plan: plan,
            query: "report-[0-9]+",
            extensions: "txt",
            caseSensitive: false,
            includeHidden: false,
            target: .files,
            matchMode: .regex,
            filters: SearchFilters()
        )

        XCTAssertEqual(plan.strategy, .namesMatchedInProcess)
        XCTAssertNil(plan.unicodeFallbackCommand)
        XCTAssertEqual(explanation.stages.map(\.id), ["find-name-candidates", "swift-name-regex"])
        XCTAssertFalse(explanation.summary.contains("Unicode-aware fallback"))
        XCTAssertNotNil(explanation.stages[0].command)
        XCTAssertNil(explanation.stages[1].command)
        XCTAssertFalse(explanation.stages.compactMap(\.command).contains { command in
            command.arguments.contains("/usr/bin/grep")
        })
    }

    func testContentsExplanationShowsEverySpecializedDocumentPass() throws {
        let plan = try FindCommandBuilder().makeExecutionPlan(
            folder: temporaryFolder,
            query: "needle",
            extensions: "",
            caseSensitive: false,
            includeHidden: true,
            target: .all,
            matchMode: .contains,
            filtersActive: false,
            searchKind: .contents
        )
        let explanation = SearchExplanationBuilder().makeExplanation(
            plan: plan,
            query: "needle",
            extensions: "",
            caseSensitive: false,
            includeHidden: true,
            target: .all,
            matchMode: .contains,
            filters: SearchFilters()
        )

        XCTAssertEqual(
            explanation.stages.map(\.id),
            [
                "find-exec-grep",
                "find-content-unicode-fallback",
                "find-pdfkit",
                "find-docx",
                "find-xlsx",
                "find-pptx"
            ]
        )
        XCTAssertTrue(explanation.stages[0].command?.arguments.contains("/usr/bin/grep") == true)
        XCTAssertTrue(explanation.stages[2].detail.contains("not OCRed"))
        XCTAssertTrue(explanation.stages[3].detail.contains("ZIP/XML"))
        XCTAssertTrue(explanation.stages[4].detail.contains("stored formulas and values"))
        XCTAssertTrue(explanation.stages[5].detail.contains("speaker notes"))
        XCTAssertTrue(explanation.summary.contains("spreadsheets"))
        XCTAssertTrue(explanation.summary.contains("presentations"))
    }

    func testContentsExplanationOnlyIncludesSelectedOfficeFormatPasses() throws {
        let plan = try FindCommandBuilder().makeExecutionPlan(
            folder: temporaryFolder,
            query: "needle",
            extensions: "xlsx,pptm",
            caseSensitive: false,
            includeHidden: true,
            target: .all,
            matchMode: .contains,
            filtersActive: false,
            searchKind: .contents
        )
        let explanation = SearchExplanationBuilder().makeExplanation(
            plan: plan,
            query: "needle",
            extensions: "xlsx,pptm",
            caseSensitive: false,
            includeHidden: true,
            target: .all,
            matchMode: .contains,
            filters: SearchFilters()
        )

        XCTAssertEqual(
            explanation.stages.map(\.id),
            ["find-exec-grep", "find-content-unicode-fallback", "find-xlsx", "find-pptx"]
        )
        XCTAssertTrue(explanation.summary.contains("ordinary files, spreadsheets, and presentations"))
        XCTAssertFalse(explanation.summary.contains("PDFs"))
        XCTAssertFalse(explanation.summary.contains("Word documents"))
    }

    func testActiveFiltersAreDescribedAsAppSideExactByteChecks() throws {
        let plan = try FindCommandBuilder().makeExecutionPlan(
            folder: temporaryFolder,
            query: "report",
            extensions: "",
            caseSensitive: true,
            includeHidden: true,
            target: .all,
            matchMode: .contains,
            filtersActive: true,
            searchKind: .names
        )
        let explanation = SearchExplanationBuilder().makeExplanation(
            plan: plan,
            query: "report",
            extensions: "",
            caseSensitive: true,
            includeHidden: true,
            target: .all,
            matchMode: .contains,
            filters: SearchFilters(sizeFilter: .exactCustom, customSizeBytes: 1_500_000)
        )

        let filterStage = try XCTUnwrap(explanation.stages.last)
        XCTAssertEqual(filterStage.id, "swift-filesystem-filters")
        XCTAssertNil(filterStage.command)
        XCTAssertTrue(filterStage.detail.contains("exactly 1500000 bytes"))
        XCTAssertTrue(filterStage.detail.contains("not find flags"))
    }

    func testSearchServicePublishesThePlanUsedForExecution() async throws {
        var receivedExplanation: SearchExplanation?
        let service = FindSearchService()

        for try await event in service.search(
            folder: temporaryFolder,
            query: "report",
            extensions: "",
            caseSensitive: true,
            includeHidden: true,
            target: .all,
            matchMode: .contains,
            dateFilter: .any,
            customDate: nil,
            customEndDate: nil,
            sizeFilter: .any,
            customSizeBytes: nil,
            customMaximumSizeBytes: nil,
            searchKind: .names
        ) {
            if case let .explanation(explanation) = event {
                receivedExplanation = explanation
            }
        }

        let command = try XCTUnwrap(receivedExplanation?.stages.first?.command)
        XCTAssertEqual(
            command.arguments,
            [temporaryFolder.path, "-name", "*report*", "-print0"]
        )
    }
}
