import Foundation

enum FindOutputParserError: LocalizedError, Equatable {
    case malformedUTF8

    var errorDescription: String? {
        switch self {
        case .malformedUTF8:
            return "The search returned a path that could not be read as text."
        }
    }
}

struct FindOutputParser {
    private var buffer = Data()

    mutating func append(_ data: Data) throws -> [String] {
        guard !data.isEmpty else {
            return []
        }

        buffer.append(data)
        var paths: [String] = []
        var searchStart = buffer.startIndex

        while let terminatorIndex = buffer[searchStart...].firstIndex(of: 0) {
            let pathData = buffer[searchStart..<terminatorIndex]
            if !pathData.isEmpty {
                guard let path = String(data: pathData, encoding: .utf8) else {
                    throw FindOutputParserError.malformedUTF8
                }
                paths.append(path)
            }
            searchStart = buffer.index(after: terminatorIndex)
        }

        if searchStart > buffer.startIndex {
            buffer.removeSubrange(buffer.startIndex..<searchStart)
        }

        return paths
    }

    mutating func finish() throws -> [String] {
        guard !buffer.isEmpty else {
            return []
        }

        defer {
            buffer.removeAll()
        }

        guard let path = String(data: buffer, encoding: .utf8) else {
            throw FindOutputParserError.malformedUTF8
        }

        return path.isEmpty ? [] : [path]
    }
}

