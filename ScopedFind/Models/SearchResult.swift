import Foundation

struct SearchResult: Identifiable, Hashable {
    let url: URL

    var id: String {
        url.path
    }

    var filename: String {
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }

    var parentDirectory: String {
        url.deletingLastPathComponent().path
    }
}

