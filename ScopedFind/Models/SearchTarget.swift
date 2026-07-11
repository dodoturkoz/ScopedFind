import Foundation

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
            return "Folders only"
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

