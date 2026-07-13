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
            fileExtension: "pdf"
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
            fileExtension: "docx"
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
        fileExtension: String
    ) throws -> FindCommand? {
        let normalizedExtensions = Self.normalizedExtensions(from: extensions)
        guard let documentMatchArguments = Self.documentMatchArguments(
            extensions: normalizedExtensions,
            caseSensitive: caseSensitive,
            fileExtension: fileExtension
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

        if !query.isEmpty {
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
        fileExtension: String
    ) -> [String]? {
        if extensions.isEmpty {
            return ["-iname", "*.\(fileExtension)"]
        }

        let matchingExtensions = extensions.filter { extensionValue in
            extensionValue.caseInsensitiveCompare(fileExtension) == .orderedSame
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
