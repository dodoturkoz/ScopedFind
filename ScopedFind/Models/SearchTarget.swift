import Foundation

enum SearchKind: String, CaseIterable, Identifiable {
    case names
    case contents

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .names:
            return "Names"
        case .contents:
            return "Contents"
        }
    }
}

enum SearchTarget: String, CaseIterable, Identifiable {
    case all
    case files
    case directories

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .all:
            return "Files and folders"
        case .files:
            return "Files only"
        case .directories:
            return "Folders/apps only"
        }
    }

    var findTypeArgument: String? {
        switch self {
        case .all:
            return nil
        case .files:
            return "f"
        case .directories:
            return "d"
        }
    }
}

enum SearchMatchMode: String, CaseIterable, Identifiable {
    case contains
    case fuzzy

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .contains:
            return "Contains"
        case .fuzzy:
            return "Fuzzy"
        }
    }

    var helpText: String {
        switch self {
        case .contains:
            return "Matches names containing the typed text."
        case .fuzzy:
            return "Matches names where typed characters appear in order, such as sf matching ScopedFind."
        }
    }
}
