import Foundation

struct SearchExplanation: Identifiable, Equatable {
    let title: String
    let summary: String
    let stages: [SearchExplanationStage]

    var id: String {
        ([title, summary] + stages.map { stage in
            [stage.id, stage.detail, stage.command?.shellFormattedCommand ?? "app-only"].joined(separator: "|")
        }).joined(separator: "\u{1F}")
    }
}

struct SearchExplanationStage: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let command: SearchCommandExplanation?
    let lessons: [SearchArgumentLesson]
}

struct SearchCommandExplanation: Equatable {
    let executablePath: String
    let arguments: [String]

    init(command: FindCommand) {
        executablePath = command.executableURL.path
        arguments = command.arguments
    }

    var shellFormattedCommand: String {
        ([executablePath] + arguments)
            .map(Self.shellEscaped)
            .joined(separator: " ")
    }

    static func shellEscaped(_ value: String) -> String {
        let safeCharacters = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "_@%+=:,./-")
        )

        if !value.isEmpty && value.unicodeScalars.allSatisfy(safeCharacters.contains) {
            return value
        }

        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

struct SearchArgumentLesson: Equatable {
    let term: String
    let explanation: String
}

struct SearchExplanationBuilder {
    func makeExplanation(
        plan: FindSearchExecutionPlan,
        query: String,
        extensions: String,
        caseSensitive: Bool,
        includeHidden: Bool,
        target: SearchTarget,
        matchMode: SearchMatchMode,
        filters: SearchFilters
    ) -> SearchExplanation {
        switch plan.strategy {
        case .namesMatchedByFind, .namesMatchedInProcess:
            return makeNamesExplanation(
                plan: plan,
                query: query.trimmingCharacters(in: .whitespacesAndNewlines),
                extensions: extensions,
                caseSensitive: caseSensitive,
                includeHidden: includeHidden,
                target: target,
                matchMode: matchMode,
                filters: filters
            )
        case .contents:
            return makeContentsExplanation(
                plan: plan,
                query: query.trimmingCharacters(in: .whitespacesAndNewlines),
                extensions: extensions,
                caseSensitive: caseSensitive,
                includeHidden: includeHidden,
                filters: filters
            )
        }
    }

    private func makeNamesExplanation(
        plan: FindSearchExecutionPlan,
        query: String,
        extensions: String,
        caseSensitive: Bool,
        includeHidden: Bool,
        target: SearchTarget,
        matchMode: SearchMatchMode,
        filters: SearchFilters
    ) -> SearchExplanation {
        var stages: [SearchExplanationStage] = []

        switch plan.strategy {
        case .namesMatchedByFind:
            stages.append(commandStage(
                id: "find-name-match",
                title: "Match names with find",
                detail: nameMatchDetail(
                    query: query,
                    extensions: extensions,
                    caseSensitive: caseSensitive,
                    target: target,
                    matchMode: matchMode
                ),
                command: plan.primaryCommand
            ))
        case .namesMatchedInProcess:
            stages.append(commandStage(
                id: "find-name-candidates",
                title: "Enumerate candidate names",
                detail: "find lists \(target.label.lowercased()) that pass the extension and hidden-path controls. The name test itself is performed by ScopedFind.",
                command: plan.primaryCommand
            ))

            if matchMode == .regex && !query.isEmpty {
                stages.append(SearchExplanationStage(
                    id: "swift-name-regex",
                    title: "Apply the name regular expression",
                    detail: "ScopedFind applies the expression to each last path component with Foundation's regular-expression engine. This is app-side name matching, not grep content-regex syntax.",
                    command: nil,
                    lessons: []
                ))
            }
        case .contents:
            break
        }

        if let fallbackCommand = plan.unicodeFallbackCommand {
            stages.append(commandStage(
                id: "find-name-unicode-fallback",
                title: "Check Unicode-aware name matches",
                detail: "find enumerates the eligible names once more so ScopedFind can add case-, diacritic-, and width-insensitive matches that find -iname may miss.",
                command: fallbackCommand
            ))
        }

        if filters.isActive {
            stages.append(filterStage(filters))
        }

        let normalizedExtensions = FindCommandBuilder.normalizedExtensions(from: extensions)
        let caseSummary: String
        if query.isEmpty {
            caseSummary = normalizedExtensions.isEmpty
                ? "no name-query comparison"
                : "\(caseSensitive ? "case-sensitive" : "case-insensitive") extension matching"
        } else if matchMode == .regex {
            caseSummary = caseSensitive
                ? "case-sensitive Foundation regex matching"
                : "case-insensitive Foundation regex matching"
        } else {
            caseSummary = caseSensitive
                ? "case-sensitive matching"
                : "case-insensitive matching with a Unicode-aware fallback"
        }
        let hiddenSummary = includeHidden ? "hidden paths included" : "hidden paths pruned"

        return SearchExplanation(
            title: "How this Names search worked",
            summary: "Names mode only considered file and folder names, with \(caseSummary) and \(hiddenSummary). It did not read file contents.",
            stages: stages
        )
    }

    private func makeContentsExplanation(
        plan: FindSearchExecutionPlan,
        query: String,
        extensions: String,
        caseSensitive: Bool,
        includeHidden: Bool,
        filters: SearchFilters
    ) -> SearchExplanation {
        var stages = [commandStage(
            id: "find-exec-grep",
            title: "Search ordinary file contents",
            detail: "find selects regular files and launches /usr/bin/grep in batches. grep treats \(SearchCommandExplanation.shellEscaped(query)) as literal text, ignores binary files, and returns matching paths.",
            command: plan.primaryCommand
        )]

        if let fallbackCommand = plan.unicodeFallbackCommand {
            stages.append(commandStage(
                id: "find-content-unicode-fallback",
                title: "Check Unicode-aware text matches",
                detail: "Because grep -i does not cover every Unicode and diacritic case, find enumerates eligible files and ScopedFind reads decodable ordinary text with Foundation for a folded comparison. Specialized document formats are handled by their own passes.",
                command: fallbackCommand
            ))
        }

        for documentPass in plan.documentSearchPasses {
            stages.append(documentStage(documentPass))
        }

        if filters.isActive {
            stages.append(filterStage(filters))
        }

        let extensionSummary = FindCommandBuilder.normalizedExtensions(from: extensions).isEmpty
            ? "all eligible extensions"
            : "the selected extensions"
        let caseSummary = caseSensitive ? "literal, case-sensitive matching" : "case-insensitive matching with a Unicode-aware fallback"
        let hiddenSummary = includeHidden ? "including hidden paths" : "with hidden paths pruned"
        let passSummary = formattedList(
            ["ordinary files"] + plan.documentSearchPasses.map(documentSummaryLabel)
        )

        return SearchExplanation(
            title: "How this Contents search worked",
            summary: "Contents mode used separate passes for \(passSummary) across \(extensionSummary), with \(caseSummary) and \(hiddenSummary).",
            stages: stages
        )
    }

    private func documentSummaryLabel(_ pass: DocumentSearchPass) -> String {
        switch pass.kind {
        case .pdf:
            return "PDFs"
        case .word:
            return "Word documents"
        case .spreadsheet:
            return "spreadsheets"
        case .presentation:
            return "presentations"
        }
    }

    private func formattedList(_ values: [String]) -> String {
        guard let lastValue = values.last else {
            return ""
        }
        guard values.count > 1 else {
            return lastValue
        }
        guard values.count > 2 else {
            return "\(values[0]) and \(lastValue)"
        }

        return "\(values.dropLast().joined(separator: ", ")), and \(lastValue)"
    }

    private func documentStage(_ pass: DocumentSearchPass) -> SearchExplanationStage {
        switch pass.kind {
        case .pdf:
            return commandStage(
                id: "find-pdfkit",
                title: "Search text-based PDFs",
                detail: "find enumerates eligible PDF files. PDFKit then extracts page text in the app and ScopedFind looks for the literal query. Image-only PDFs are not OCRed.",
                command: pass.command
            )
        case .word:
            return commandStage(
                id: "find-docx",
                title: "Search Word document text",
                detail: "find enumerates eligible .docx files. ScopedFind then reads document, header, footer, note, and comment ZIP/XML text in process; no Office parser or external command is used.",
                command: pass.command
            )
        case .spreadsheet:
            return commandStage(
                id: "find-xlsx",
                title: "Search Excel workbook text",
                detail: "find enumerates eligible .xlsx and .xlsm files. ScopedFind reads shared and inline cell text, stored formulas and values, and comments from their ZIP/XML parts in process. Display formatting and formula recalculation are not reproduced.",
                command: pass.command
            )
        case .presentation:
            return commandStage(
                id: "find-pptx",
                title: "Search PowerPoint presentation text",
                detail: "find enumerates eligible .pptx and .pptm files. ScopedFind reads slide text, speaker notes, comments, and comment-author text from their ZIP/XML parts in process.",
                command: pass.command
            )
        }
    }

    private func commandStage(
        id: String,
        title: String,
        detail: String,
        command: FindCommand
    ) -> SearchExplanationStage {
        SearchExplanationStage(
            id: id,
            title: title,
            detail: detail,
            command: SearchCommandExplanation(command: command),
            lessons: argumentLessons(for: command)
        )
    }

    private func filterStage(_ filters: SearchFilters) -> SearchExplanationStage {
        let activeDescriptions = [
            dateFilterDescription(filters),
            sizeFilterDescription(filters)
        ].compactMap { $0 }

        return SearchExplanationStage(
            id: "swift-filesystem-filters",
            title: "Apply filesystem filters in ScopedFind",
            detail: "After a path matches, ScopedFind reads its filesystem attributes and keeps only items \(activeDescriptions.joined(separator: " and ")). These checks are Swift code, not find flags.",
            command: nil,
            lessons: []
        )
    }

    private func nameMatchDetail(
        query: String,
        extensions: String,
        caseSensitive: Bool,
        target: SearchTarget,
        matchMode: SearchMatchMode
    ) -> String {
        let normalizedExtensions = FindCommandBuilder.normalizedExtensions(from: extensions)
        let extensionDetail = normalizedExtensions.isEmpty
            ? "with no extension restriction"
            : "with extensions \(normalizedExtensions.map { ".\($0)" }.joined(separator: ", "))"
        let caseDetail = caseSensitive ? "case-sensitive" : "case-insensitive"

        if query.isEmpty {
            return "find selects \(target.label.lowercased()) \(extensionDetail), using \(caseDetail) name predicates."
        }

        switch matchMode {
        case .contains:
            return "find applies a \(caseDetail) shell-style name pattern around the literal query and selects \(target.label.lowercased()) \(extensionDetail)."
        case .fuzzy:
            return "find turns the typed characters into an ordered wildcard pattern, such as *s*f*, and selects \(target.label.lowercased()) \(extensionDetail). This is dependency-free name matching, not fzf."
        case .regex:
            return "ScopedFind applies the regular expression in process after find enumerates candidates."
        }
    }

    private func argumentLessons(for command: FindCommand) -> [SearchArgumentLesson] {
        let arguments = command.arguments
        var lessons = [SearchArgumentLesson(
            term: "first argument",
            explanation: "The selected folder is the root of this recursive search."
        )]

        if arguments.contains("-prune") {
            lessons.append(SearchArgumentLesson(
                term: "! … -prune -o",
                explanation: "Rejects and stops descending into hidden paths, then evaluates the visible-path branch."
            ))
        }
        let typeArguments = zip(arguments, arguments.dropFirst()).compactMap { argument, nextArgument in
            argument == "-type" ? nextArgument : nil
        }
        if typeArguments.contains("f") {
            lessons.append(SearchArgumentLesson(
                term: "-type f",
                explanation: "Keeps regular files."
            ))
        }
        if typeArguments.contains("d") {
            lessons.append(SearchArgumentLesson(
                term: "-type d",
                explanation: "Keeps directories, including .app bundles."
            ))
        }
        if arguments.contains("-iname") {
            lessons.append(SearchArgumentLesson(
                term: "-iname pattern",
                explanation: "Matches a file name with a case-insensitive find pattern."
            ))
        }
        if arguments.contains("-name") {
            lessons.append(SearchArgumentLesson(
                term: "-name pattern",
                explanation: "Matches a file name with a case-sensitive find pattern; it is also used by the hidden-path prune expression."
            ))
        }
        if arguments.contains("(") {
            lessons.append(SearchArgumentLesson(
                term: "( … -o … )",
                explanation: "Groups the extension-pattern branch; -o separates alternatives when there are several."
            ))
        }

        if arguments.contains("-exec") {
            lessons += [
                SearchArgumentLesson(
                    term: "-exec … {} +",
                    explanation: "Runs grep with batches of paths instead of starting one process per file."
                ),
                SearchArgumentLesson(
                    term: "grep -I",
                    explanation: "Skips files grep considers binary."
                ),
                SearchArgumentLesson(
                    term: "grep -l --null",
                    explanation: "Prints only matching paths and separates them with null bytes so unusual filenames remain safe."
                ),
                SearchArgumentLesson(
                    term: "grep -F -e",
                    explanation: "Treats the query as fixed literal text and marks the next argument as the pattern."
                )
            ]
            if arguments.contains("-i") {
                lessons.append(SearchArgumentLesson(
                    term: "grep -i",
                    explanation: "Requests case-insensitive matching; ScopedFind adds its Unicode-aware fallback separately."
                ))
            }
        } else if arguments.contains("-print0") {
            lessons.append(SearchArgumentLesson(
                term: "-print0",
                explanation: "Outputs null-separated paths so spaces, quotes, and newlines in filenames are unambiguous."
            ))
        }

        return lessons
    }

    private func dateFilterDescription(_ filters: SearchFilters) -> String? {
        switch filters.dateFilter {
        case .any:
            return nil
        case .modifiedLast5Minutes:
            return "with modification time at or after the rolling 5-minute cutoff"
        case .modifiedLastHour:
            return "with modification time at or after the rolling 1-hour cutoff"
        case .modifiedToday:
            return "modified on today's local calendar date"
        case .modifiedLast7Days:
            return "with modification time at or after the rolling 7-day cutoff"
        case .modifiedOnDate:
            return "modified on \(formattedDate(filters.customDate))"
        case .modifiedBeforeDate:
            return "modified before \(formattedDate(filters.customDate))"
        case .modifiedSinceDate:
            return "modified on or after \(formattedDate(filters.customDate))"
        case .modifiedBetweenDates:
            return "modified from \(formattedDate(filters.customDate)) through \(formattedDate(filters.customEndDate)), including both dates"
        }
    }

    private func sizeFilterDescription(_ filters: SearchFilters) -> String? {
        switch filters.sizeFilter {
        case .any:
            return nil
        case .smallerThan1MB:
            return "smaller than 1000000 bytes"
        case .largerThan1MB:
            return "larger than 1000000 bytes"
        case .largerThan100MB:
            return "larger than 100000000 bytes"
        case .largerThan1GB:
            return "larger than 1000000000 bytes"
        case .smallerThanCustom:
            return "smaller than \(formattedBytes(filters.customSizeBytes))"
        case .largerThanCustom:
            return "larger than \(formattedBytes(filters.customSizeBytes))"
        case .exactCustom:
            return "exactly \(formattedBytes(filters.customSizeBytes))"
        case .betweenCustom:
            return "between \(formattedBytes(filters.customSizeBytes)) and \(formattedBytes(filters.customMaximumSizeBytes)), including both sizes"
        }
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else {
            return "the chosen date"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = .current
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func formattedBytes(_ byteCount: UInt64?) -> String {
        guard let byteCount else {
            return "the chosen byte count"
        }
        return "\(byteCount) bytes"
    }
}
