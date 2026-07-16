import Foundation

struct FindCommand: Equatable {
    let executableURL: URL
    let arguments: [String]
    let successfulTerminationStatuses: Set<Int32>

    init(
        executableURL: URL,
        arguments: [String],
        successfulTerminationStatuses: Set<Int32> = [0]
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.successfulTerminationStatuses = successfulTerminationStatuses
    }

    func treatsTerminationStatusAsSuccess(_ status: Int32) -> Bool {
        successfulTerminationStatuses.contains(status)
    }
}

struct FindSearchExecutionPlan: Equatable {
    enum Strategy: Equatable {
        case namesMatchedByFind
        case namesMatchedInProcess
        case contents
    }

    let strategy: Strategy
    let primaryCommand: FindCommand
    let unicodeFallbackCommand: FindCommand?
    let documentSearchPasses: [DocumentSearchPass]
}

enum ContentDocumentKind: String, CaseIterable, Equatable {
    case pdf
    case word
    case spreadsheet
    case presentation

    var fileExtensions: [String] {
        switch self {
        case .pdf:
            return ["pdf"]
        case .word:
            return ["docx"]
        case .spreadsheet:
            return ["xlsx", "xlsm"]
        case .presentation:
            return ["pptx", "pptm"]
        }
    }
}

struct DocumentSearchPass: Equatable {
    let kind: ContentDocumentKind
    let command: FindCommand
}

enum FindCommandBuilderError: LocalizedError, Equatable {
    case emptyQuery
    case emptyContentQuery
    case folderDoesNotExist
    case selectedPathIsNotFolder

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "Enter a search term or extension before starting."
        case .emptyContentQuery:
            return "Enter text to search file contents."
        case .folderDoesNotExist:
            return "The selected folder is no longer available."
        case .selectedPathIsNotFolder:
            return "The selected path is not a folder."
        }
    }
}

struct FindCommandBuilder {
    static let executableURL = URL(fileURLWithPath: "/usr/bin/find")
    static let grepExecutablePath = "/usr/bin/grep"

    func makeCommand(
        folder: URL,
        query: String,
        extensions: String,
        caseSensitive: Bool,
        includeHidden: Bool,
        target: SearchTarget,
        matchMode: SearchMatchMode = .contains,
        searchKind: SearchKind = .names
    ) throws -> FindCommand {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedExtensions = Self.normalizedExtensions(from: extensions)
        try validateCriteria(
            trimmedQuery: trimmedQuery,
            normalizedExtensions: normalizedExtensions,
            searchKind: searchKind
        )

        try validateFolder(folder)

        switch searchKind {
        case .names:
            return makeNameCommand(
                folder: folder,
                query: trimmedQuery,
                extensions: normalizedExtensions,
                caseSensitive: caseSensitive,
                includeHidden: includeHidden,
                target: target,
                matchMode: matchMode
            )
        case .contents:
            return makeContentCommand(
                folder: folder,
                query: trimmedQuery,
                extensions: normalizedExtensions,
                caseSensitive: caseSensitive,
                includeHidden: includeHidden
            )
        }
    }

    func makeExecutionPlan(
        folder: URL,
        query: String,
        extensions: String,
        caseSensitive: Bool,
        includeHidden: Bool,
        target: SearchTarget,
        matchMode: SearchMatchMode,
        filtersActive: Bool,
        searchKind: SearchKind
    ) throws -> FindSearchExecutionPlan {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedExtensions = Self.normalizedExtensions(from: extensions)

        switch searchKind {
        case .names:
            let matchesNamesInProcess = matchMode == .regex ||
                (trimmedQuery.isEmpty && normalizedExtensions.isEmpty && filtersActive)
            let primaryCommand: FindCommand

            if matchesNamesInProcess {
                primaryCommand = try makeNameEnumerationCommand(
                    folder: folder,
                    extensions: extensions,
                    caseSensitive: caseSensitive,
                    includeHidden: includeHidden,
                    target: target
                )
            } else {
                primaryCommand = try makeCommand(
                    folder: folder,
                    query: query,
                    extensions: extensions,
                    caseSensitive: caseSensitive,
                    includeHidden: includeHidden,
                    target: target,
                    matchMode: matchMode,
                    searchKind: searchKind
                )
            }

            let unicodeFallbackCommand: FindCommand?
            if !matchesNamesInProcess && !caseSensitive && !trimmedQuery.isEmpty {
                unicodeFallbackCommand = try makeNameEnumerationCommand(
                    folder: folder,
                    extensions: extensions,
                    caseSensitive: caseSensitive,
                    includeHidden: includeHidden,
                    target: target
                )
            } else {
                unicodeFallbackCommand = nil
            }

            return FindSearchExecutionPlan(
                strategy: matchesNamesInProcess ? .namesMatchedInProcess : .namesMatchedByFind,
                primaryCommand: primaryCommand,
                unicodeFallbackCommand: unicodeFallbackCommand,
                documentSearchPasses: []
            )
        case .contents:
            let primaryCommand = try makeCommand(
                folder: folder,
                query: query,
                extensions: extensions,
                caseSensitive: caseSensitive,
                includeHidden: includeHidden,
                target: target,
                matchMode: matchMode,
                searchKind: searchKind
            )
            let unicodeFallbackCommand: FindCommand?
            if caseSensitive {
                unicodeFallbackCommand = nil
            } else {
                unicodeFallbackCommand = try makeContentEnumerationCommand(
                    folder: folder,
                    extensions: extensions,
                    caseSensitive: caseSensitive,
                    includeHidden: includeHidden
                )
            }

            return FindSearchExecutionPlan(
                strategy: .contents,
                primaryCommand: primaryCommand,
                unicodeFallbackCommand: unicodeFallbackCommand,
                documentSearchPasses: try makeDocumentSearchPasses(
                    folder: folder,
                    extensions: extensions,
                    caseSensitive: caseSensitive,
                    includeHidden: includeHidden
                )
            )
        }
    }

    func makeDocumentSearchPasses(
        folder: URL,
        extensions: String,
        caseSensitive: Bool,
        includeHidden: Bool
    ) throws -> [DocumentSearchPass] {
        try ContentDocumentKind.allCases.compactMap { kind in
            guard let command = try makeDocumentEnumerationCommand(
                folder: folder,
                extensions: extensions,
                caseSensitive: caseSensitive,
                includeHidden: includeHidden,
                fileExtensions: kind.fileExtensions
            ) else {
                return nil
            }

            return DocumentSearchPass(kind: kind, command: command)
        }
    }

    func makePDFEnumerationCommand(
        folder: URL,
        extensions: String,
        caseSensitive: Bool,
        includeHidden: Bool
    ) throws -> FindCommand? {
        try makeDocumentEnumerationCommand(
            folder: folder,
            extensions: extensions,
            caseSensitive: caseSensitive,
            includeHidden: includeHidden,
            fileExtensions: ContentDocumentKind.pdf.fileExtensions
        )
    }

    func makeDOCXEnumerationCommand(
        folder: URL,
        extensions: String,
        caseSensitive: Bool,
        includeHidden: Bool
    ) throws -> FindCommand? {
        try makeDocumentEnumerationCommand(
            folder: folder,
            extensions: extensions,
            caseSensitive: caseSensitive,
            includeHidden: includeHidden,
            fileExtensions: ContentDocumentKind.word.fileExtensions
        )
    }

    func makeSpreadsheetEnumerationCommand(
        folder: URL,
        extensions: String,
        caseSensitive: Bool,
        includeHidden: Bool
    ) throws -> FindCommand? {
        try makeDocumentEnumerationCommand(
            folder: folder,
            extensions: extensions,
            caseSensitive: caseSensitive,
            includeHidden: includeHidden,
            fileExtensions: ContentDocumentKind.spreadsheet.fileExtensions
        )
    }

    func makePresentationEnumerationCommand(
        folder: URL,
        extensions: String,
        caseSensitive: Bool,
        includeHidden: Bool
    ) throws -> FindCommand? {
        try makeDocumentEnumerationCommand(
            folder: folder,
            extensions: extensions,
            caseSensitive: caseSensitive,
            includeHidden: includeHidden,
            fileExtensions: ContentDocumentKind.presentation.fileExtensions
        )
    }

    func makeNameEnumerationCommand(
        folder: URL,
        extensions: String,
        caseSensitive: Bool,
        includeHidden: Bool,
        target: SearchTarget
    ) throws -> FindCommand {
        let normalizedExtensions = Self.normalizedExtensions(from: extensions)
        try validateFolder(folder)

        let namePredicate = caseSensitive ? "-name" : "-iname"
        let targetArguments = target.findTypeArgument.map { ["-type", $0] } ?? []
        let matchArguments = normalizedExtensions.isEmpty ? [] : Self.extensionMatchArguments(
            for: normalizedExtensions,
            namePredicate: namePredicate
        )

        var arguments = [folder.path]
        if includeHidden {
            arguments += targetArguments + matchArguments + ["-print0"]
        } else {
            arguments += ["!", "-path", folder.path, "-name", ".*", "-prune", "-o"]
            arguments += targetArguments + matchArguments + ["-print0"]
        }

        return FindCommand(executableURL: Self.executableURL, arguments: arguments)
    }

    func makeContentEnumerationCommand(
        folder: URL,
        extensions: String,
        caseSensitive: Bool,
        includeHidden: Bool
    ) throws -> FindCommand {
        let normalizedExtensions = Self.normalizedExtensions(from: extensions)
        try validateFolder(folder)

        let namePredicate = caseSensitive ? "-name" : "-iname"
        let matchArguments = normalizedExtensions.isEmpty ? [] : Self.extensionMatchArguments(
            for: normalizedExtensions,
            namePredicate: namePredicate
        )

        var arguments = [folder.path]
        if includeHidden {
            arguments += ["-type", "f"] + matchArguments + ["-print0"]
        } else {
            arguments += ["!", "-path", folder.path, "-name", ".*", "-prune", "-o"]
            arguments += ["-type", "f"] + matchArguments + ["-print0"]
        }

        return FindCommand(executableURL: Self.executableURL, arguments: arguments)
    }

    private func makeDocumentEnumerationCommand(
        folder: URL,
        extensions: String,
        caseSensitive: Bool,
        includeHidden: Bool,
        fileExtensions: [String]
    ) throws -> FindCommand? {
        let normalizedExtensions = Self.normalizedExtensions(from: extensions)
        guard let documentMatchArguments = Self.documentMatchArguments(
            extensions: normalizedExtensions,
            caseSensitive: caseSensitive,
            fileExtensions: fileExtensions
        ) else {
            return nil
        }

        try validateFolder(folder)

        var arguments = [folder.path]
        if includeHidden {
            arguments += ["-type", "f"] + documentMatchArguments + ["-print0"]
        } else {
            arguments += ["!", "-path", folder.path, "-name", ".*", "-prune", "-o"]
            arguments += ["-type", "f"] + documentMatchArguments + ["-print0"]
        }

        return FindCommand(executableURL: Self.executableURL, arguments: arguments)
    }

    private func validateFolder(_ folder: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) else {
            throw FindCommandBuilderError.folderDoesNotExist
        }
        guard isDirectory.boolValue else {
            throw FindCommandBuilderError.selectedPathIsNotFolder
        }
    }

    private func validateCriteria(
        trimmedQuery: String,
        normalizedExtensions: [String],
        searchKind: SearchKind
    ) throws {
        switch searchKind {
        case .names:
            guard !trimmedQuery.isEmpty || !normalizedExtensions.isEmpty else {
                throw FindCommandBuilderError.emptyQuery
            }
        case .contents:
            guard !trimmedQuery.isEmpty else {
                throw FindCommandBuilderError.emptyContentQuery
            }
        }
    }

    private func makeNameCommand(
        folder: URL,
        query: String,
        extensions: [String],
        caseSensitive: Bool,
        includeHidden: Bool,
        target: SearchTarget,
        matchMode: SearchMatchMode
    ) -> FindCommand {
        let namePredicate = caseSensitive ? "-name" : "-iname"
        let targetArguments = target.findTypeArgument.map { ["-type", $0] } ?? []
        let matchArguments = Self.matchArguments(
            query: query,
            extensions: extensions,
            matchMode: matchMode,
            namePredicate: namePredicate
        )

        var arguments = [folder.path]
        if includeHidden {
            arguments += targetArguments + matchArguments + ["-print0"]
        } else {
            arguments += ["!", "-path", folder.path, "-name", ".*", "-prune", "-o"]
            arguments += targetArguments + matchArguments + ["-print0"]
        }

        return FindCommand(executableURL: Self.executableURL, arguments: arguments)
    }

    private func makeContentCommand(
        folder: URL,
        query: String,
        extensions: [String],
        caseSensitive: Bool,
        includeHidden: Bool
    ) -> FindCommand {
        let namePredicate = caseSensitive ? "-name" : "-iname"
        let matchArguments = extensions.isEmpty ? [] : Self.extensionMatchArguments(
            for: extensions,
            namePredicate: namePredicate
        )

        var grepArguments = [
            Self.grepExecutablePath,
            "-I",
            "-l",
            "--null",
            "-F"
        ]
        if !caseSensitive {
            grepArguments.append("-i")
        }
        grepArguments += ["-e", query, "{}", "+"]

        var arguments = [folder.path]
        if includeHidden {
            arguments += ["-type", "f"] + matchArguments + ["-exec"] + grepArguments
        } else {
            arguments += ["!", "-path", folder.path, "-name", ".*", "-prune", "-o"]
            arguments += ["-type", "f"] + matchArguments + ["-exec"] + grepArguments
        }

        return FindCommand(
            executableURL: Self.executableURL,
            arguments: arguments,
            successfulTerminationStatuses: [0, 1]
        )
    }

    static func normalizedExtensions(from value: String) -> [String] {
        value
            .components(separatedBy: CharacterSet(charactersIn: ",; \n\t"))
            .map { component in
                component.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .map { component in
                var normalized = component
                while normalized.hasPrefix(".") {
                    normalized.removeFirst()
                }
                return normalized
            }
            .filter { !$0.isEmpty }
    }

    private static func matchArguments(
        query: String,
        extensions: [String],
        matchMode: SearchMatchMode,
        namePredicate: String
    ) -> [String] {
        var arguments: [String] = []

        if !query.isEmpty && matchMode != .regex {
            arguments += [namePredicate, namePattern(for: query, matchMode: matchMode)]
        }

        if !extensions.isEmpty {
            arguments += extensionMatchArguments(for: extensions, namePredicate: namePredicate)
        }

        return arguments
    }

    private static func namePattern(for query: String, matchMode: SearchMatchMode) -> String {
        switch matchMode {
        case .contains:
            return "*\(escapedFindPatternComponent(query))*"
        case .regex:
            return "*"
        case .fuzzy:
            return fuzzyFindPatternComponent(query)
        }
    }

    private static func extensionMatchArguments(
        for extensions: [String],
        namePredicate: String
    ) -> [String] {
        var arguments = ["("]

        for (index, pathExtension) in extensions.enumerated() {
            if index > 0 {
                arguments.append("-o")
            }
            arguments += [namePredicate, "*.\(escapedFindPatternComponent(pathExtension))"]
        }

        arguments.append(")")
        return arguments
    }

    private static func documentMatchArguments(
        extensions: [String],
        caseSensitive: Bool,
        fileExtensions: [String]
    ) -> [String]? {
        if extensions.isEmpty {
            if fileExtensions.count == 1, let fileExtension = fileExtensions.first {
                return ["-iname", "*.\(fileExtension)"]
            }

            return extensionMatchArguments(
                for: fileExtensions,
                namePredicate: "-iname"
            )
        }

        let matchingExtensions = extensions.filter { extensionValue in
            fileExtensions.contains { supportedExtension in
                extensionValue.caseInsensitiveCompare(supportedExtension) == .orderedSame
            }
        }
        guard !matchingExtensions.isEmpty else {
            return nil
        }

        return extensionMatchArguments(
            for: matchingExtensions,
            namePredicate: caseSensitive ? "-name" : "-iname"
        )
    }

    static func escapedFindPatternComponent(_ value: String) -> String {
        var result = ""
        for character in value {
            if character == "\\" || character == "*" || character == "?" || character == "[" || character == "]" {
                result.append("\\")
            }
            result.append(character)
        }
        return result
    }

    static func fuzzyFindPatternComponent(_ value: String) -> String {
        var result = "*"
        for character in value where !character.isWhitespaceOrNewline {
            result += escapedFindPatternComponent(String(character))
            result.append("*")
        }
        return result
    }

    static func pathContainsHiddenComponent(_ url: URL, relativeTo rootURL: URL) -> Bool {
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let pathComponents = url.standardizedFileURL.pathComponents
        let relativeComponents: ArraySlice<String>

        if pathComponents.starts(with: rootComponents) {
            relativeComponents = pathComponents.dropFirst(rootComponents.count)
        } else {
            relativeComponents = pathComponents[...]
        }

        return relativeComponents.contains { component in
            component.count > 1 && component.hasPrefix(".")
        }
    }
}

private extension Character {
    var isWhitespaceOrNewline: Bool {
        unicodeScalars.allSatisfy { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
    }
}
