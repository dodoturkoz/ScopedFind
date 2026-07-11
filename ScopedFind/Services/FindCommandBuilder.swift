import Foundation

struct FindCommand: Equatable {
    let executableURL: URL
    let arguments: [String]
}

enum FindCommandBuilderError: LocalizedError, Equatable {
    case emptyQuery
    case folderDoesNotExist
    case selectedPathIsNotFolder

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "Enter a search term or extension before starting."
        case .folderDoesNotExist:
            return "The selected folder is no longer available."
        case .selectedPathIsNotFolder:
            return "The selected path is not a folder."
        }
    }
}

struct FindCommandBuilder {
    static let executableURL = URL(fileURLWithPath: "/usr/bin/find")

    func makeCommand(
        folder: URL,
        query: String,
        extensions: String,
        caseSensitive: Bool,
        includeHidden: Bool,
        target: SearchTarget
    ) throws -> FindCommand {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedExtensions = Self.normalizedExtensions(from: extensions)
        guard !trimmedQuery.isEmpty || !normalizedExtensions.isEmpty else {
            throw FindCommandBuilderError.emptyQuery
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) else {
            throw FindCommandBuilderError.folderDoesNotExist
        }
        guard isDirectory.boolValue else {
            throw FindCommandBuilderError.selectedPathIsNotFolder
        }

        let namePredicate = caseSensitive ? "-name" : "-iname"
        let targetArguments = target.findTypeArgument.map { ["-type", $0] } ?? []
        let matchArguments = Self.matchArguments(
            query: trimmedQuery,
            extensions: normalizedExtensions,
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
        namePredicate: String
    ) -> [String] {
        var arguments: [String] = []

        if !query.isEmpty {
            arguments += [namePredicate, "*\(escapedFindPatternComponent(query))*"]
        }

        if !extensions.isEmpty {
            arguments += extensionMatchArguments(for: extensions, namePredicate: namePredicate)
        }

        return arguments
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
