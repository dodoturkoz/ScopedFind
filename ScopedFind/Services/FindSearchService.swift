import Foundation
import Compression
import PDFKit

enum FindSearchEvent: Equatable {
    case result(SearchResult)
    case warning(String)
}

enum FindSearchServiceError: LocalizedError, Equatable {
    case alreadyRunning
    case cancelled
    case failedToStart(String)
    case nonZeroTermination(status: Int32, message: String?)
    case unreadableOutput

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "A search is already running."
        case .cancelled:
            return "The search was cancelled."
        case .failedToStart:
            return "The search command could not be started."
        case let .nonZeroTermination(status, message):
            if let message, !message.isEmpty {
                return "The search command stopped with status \(status): \(message)"
            }
            return "The search command stopped with status \(status)."
        case .unreadableOutput:
            return "The search returned output that could not be read."
        }
    }
}

protocol FindSearching: AnyObject {
    func search(
        folder: URL,
        query: String,
        extensions: String,
        caseSensitive: Bool,
        includeHidden: Bool,
        target: SearchTarget,
        matchMode: SearchMatchMode,
        searchKind: SearchKind
    ) -> AsyncThrowingStream<FindSearchEvent, Error>

    func cancel()
}

final class FindSearchService: FindSearching {
    private let builder: FindCommandBuilder
    private let executionQueue = DispatchQueue(label: "ScopedFind.find.execution", qos: .userInitiated)
    private let stdoutQueue = DispatchQueue(label: "ScopedFind.find.stdout", qos: .userInitiated)
    private let stderrQueue = DispatchQueue(label: "ScopedFind.find.stderr", qos: .userInitiated)
    private let lock = NSLock()

    private var currentProcess: Process?
    private var searchInProgress = false
    private var cancellationRequested = false

    init(builder: FindCommandBuilder = FindCommandBuilder()) {
        self.builder = builder
    }

    func search(
        folder: URL,
        query: String,
        extensions: String,
        caseSensitive: Bool,
        includeHidden: Bool,
        target: SearchTarget,
        matchMode: SearchMatchMode,
        searchKind: SearchKind
    ) -> AsyncThrowingStream<FindSearchEvent, Error> {
        AsyncThrowingStream { continuation in
            executionQueue.async {
                self.runSearch(
                    folder: folder,
                    query: query,
                    extensions: extensions,
                    caseSensitive: caseSensitive,
                    includeHidden: includeHidden,
                    target: target,
                    matchMode: matchMode,
                    searchKind: searchKind,
                    continuation: continuation
                )
            }

            continuation.onTermination = { @Sendable termination in
                if case .cancelled = termination {
                    self.cancel()
                }
            }
        }
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        let process = currentProcess
        lock.unlock()

        if let process, process.isRunning {
            process.terminate()
        }
    }

    private func runSearch(
        folder: URL,
        query: String,
        extensions: String,
        caseSensitive: Bool,
        includeHidden: Bool,
        target: SearchTarget,
        matchMode: SearchMatchMode,
        searchKind: SearchKind,
        continuation: AsyncThrowingStream<FindSearchEvent, Error>.Continuation
    ) {
        do {
            guard beginSearch() else {
                continuation.finish(throwing: FindSearchServiceError.alreadyRunning)
                return
            }
            defer {
                endSearch()
            }

            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

            switch searchKind {
            case .names:
                let deduper = SearchResultDeduper()
                let yieldNameResult: (URL) -> Void = { url in
                    if deduper.shouldYield(url) {
                        continuation.yield(.result(SearchResult(url: url)))
                    }
                }
                let command = try builder.makeCommand(
                    folder: folder,
                    query: query,
                    extensions: extensions,
                    caseSensitive: caseSensitive,
                    includeHidden: includeHidden,
                    target: target,
                    matchMode: matchMode,
                    searchKind: searchKind
                )
                try runPathCommand(
                    command,
                    folder: folder,
                    includeHidden: includeHidden,
                    continuation: continuation
                ) { url in
                    yieldNameResult(url)
                }

                if !caseSensitive && !trimmedQuery.isEmpty {
                    let fallbackCommand = try builder.makeNameEnumerationCommand(
                        folder: folder,
                        extensions: extensions,
                        caseSensitive: caseSensitive,
                        includeHidden: includeHidden,
                        target: target
                    )
                    let candidateURLs = try collectPaths(
                        with: fallbackCommand,
                        folder: folder,
                        includeHidden: includeHidden,
                        continuation: continuation
                    )

                    for candidateURL in candidateURLs {
                        if isCancellationRequested() {
                            throw FindSearchServiceError.cancelled
                        }
                        if UnicodeTextMatcher.fileName(
                            candidateURL.lastPathComponent,
                            matches: trimmedQuery,
                            matchMode: matchMode
                        ) {
                            yieldNameResult(candidateURL)
                        }
                    }
                }
            case .contents:
                let deduper = SearchResultDeduper()
                let yieldContentResult: (URL) -> Void = { url in
                    if deduper.shouldYield(url) {
                        continuation.yield(.result(SearchResult(url: url)))
                    }
                }
                let grepCommand = try builder.makeCommand(
                    folder: folder,
                    query: query,
                    extensions: extensions,
                    caseSensitive: caseSensitive,
                    includeHidden: includeHidden,
                    target: target,
                    matchMode: matchMode,
                    searchKind: searchKind
                )
                try runPathCommand(
                    grepCommand,
                    folder: folder,
                    includeHidden: includeHidden,
                    continuation: continuation,
                    onPath: yieldContentResult
                )

                if isCancellationRequested() {
                    throw FindSearchServiceError.cancelled
                }

                if !caseSensitive {
                    let fallbackCommand = try builder.makeContentEnumerationCommand(
                        folder: folder,
                        extensions: extensions,
                        caseSensitive: caseSensitive,
                        includeHidden: includeHidden
                    )
                    let candidateURLs = try collectPaths(
                        with: fallbackCommand,
                        folder: folder,
                        includeHidden: includeHidden,
                        continuation: continuation
                    )

                    for candidateURL in candidateURLs {
                        if isCancellationRequested() {
                            throw FindSearchServiceError.cancelled
                        }
                        if plainTextDocument(at: candidateURL, contains: trimmedQuery, caseSensitive: caseSensitive) {
                            yieldContentResult(candidateURL)
                        }
                    }
                }

                if let pdfCommand = try builder.makePDFEnumerationCommand(
                    folder: folder,
                    extensions: extensions,
                    caseSensitive: caseSensitive,
                    includeHidden: includeHidden
                ) {
                    let pdfURLs = try collectPaths(
                        with: pdfCommand,
                        folder: folder,
                        includeHidden: includeHidden,
                        continuation: continuation
                    )

                    for pdfURL in pdfURLs {
                        if isCancellationRequested() {
                            throw FindSearchServiceError.cancelled
                        }
                        if pdfDocument(at: pdfURL, contains: trimmedQuery, caseSensitive: caseSensitive) {
                            yieldContentResult(pdfURL)
                        }
                    }
                }

                if let docxCommand = try builder.makeDOCXEnumerationCommand(
                    folder: folder,
                    extensions: extensions,
                    caseSensitive: caseSensitive,
                    includeHidden: includeHidden
                ) {
                    let docxURLs = try collectPaths(
                        with: docxCommand,
                        folder: folder,
                        includeHidden: includeHidden,
                        continuation: continuation
                    )

                    for docxURL in docxURLs {
                        if isCancellationRequested() {
                            throw FindSearchServiceError.cancelled
                        }
                        if docxDocument(at: docxURL, contains: trimmedQuery, caseSensitive: caseSensitive) {
                            yieldContentResult(docxURL)
                        }
                    }
                }
            }

            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private func runPathCommand(
        _ command: FindCommand,
        folder: URL,
        includeHidden: Bool,
        continuation: AsyncThrowingStream<FindSearchEvent, Error>.Continuation,
        onPath: @escaping (URL) -> Void
    ) throws {
        if isCancellationRequested() {
            throw FindSearchServiceError.cancelled
        }

        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        setCurrentProcess(process)
        defer {
            clearCurrentProcess(process)
        }

        do {
            try process.run()
        } catch {
            throw FindSearchServiceError.failedToStart(error.localizedDescription)
        }

        let outputGroup = DispatchGroup()
        let stderrCollector = LockedStringCollector()
        let parserError = LockedErrorCollector()

        outputGroup.enter()
        stdoutQueue.async {
            var parser = FindOutputParser()
            let handle = stdoutPipe.fileHandleForReading

            while true {
                let data = handle.availableData
                if data.isEmpty {
                    break
                }

                do {
                    let paths = try parser.append(data)
                    for path in paths {
                        let url = URL(fileURLWithPath: path)
                        if includeHidden || !FindCommandBuilder.pathContainsHiddenComponent(url, relativeTo: folder) {
                            onPath(url)
                        }
                    }
                } catch {
                    parserError.set(error)
                    process.terminate()
                    break
                }
            }

            do {
                for path in try parser.finish() {
                    let url = URL(fileURLWithPath: path)
                    if includeHidden || !FindCommandBuilder.pathContainsHiddenComponent(url, relativeTo: folder) {
                        onPath(url)
                    }
                }
            } catch {
                parserError.set(error)
                process.terminate()
            }

            outputGroup.leave()
        }

        outputGroup.enter()
        stderrQueue.async {
            let handle = stderrPipe.fileHandleForReading
            while true {
                let data = handle.availableData
                if data.isEmpty {
                    break
                }
                if let message = String(data: data, encoding: .utf8) {
                    stderrCollector.append(message)
                }
            }
            outputGroup.leave()
        }

        process.waitUntilExit()
        outputGroup.wait()

        if isCancellationRequested() {
            throw FindSearchServiceError.cancelled
        }

        if parserError.value != nil {
            throw FindSearchServiceError.unreadableOutput
        }

        let stderr = stderrCollector.value
        if command.treatsTerminationStatusAsSuccess(process.terminationStatus) {
            yieldPermissionWarningIfNeeded(stderr, continuation: continuation)
        } else if stderr.localizedCaseInsensitiveContains("Permission denied") {
            yieldPermissionWarningIfNeeded(stderr, continuation: continuation)
        } else {
            throw FindSearchServiceError.nonZeroTermination(
                status: process.terminationStatus,
                message: conciseProcessMessage(from: stderr)
            )
        }
    }

    private func collectPaths(
        with command: FindCommand,
        folder: URL,
        includeHidden: Bool,
        continuation: AsyncThrowingStream<FindSearchEvent, Error>.Continuation
    ) throws -> [URL] {
        let collector = LockedURLCollector()
        try runPathCommand(
            command,
            folder: folder,
            includeHidden: includeHidden,
            continuation: continuation
        ) { url in
            collector.append(url)
        }
        return collector.values
    }

    private func pdfDocument(
        at url: URL,
        contains query: String,
        caseSensitive: Bool
    ) -> Bool {
        guard !query.isEmpty, let document = PDFDocument(url: url) else {
            return false
        }

        for pageIndex in 0..<document.pageCount {
            if isCancellationRequested() {
                return false
            }
            guard let text = document.page(at: pageIndex)?.string else {
                continue
            }
            if UnicodeTextMatcher.contains(query, in: text, caseSensitive: caseSensitive) {
                return true
            }
        }
        return false
    }

    private func plainTextDocument(
        at url: URL,
        contains query: String,
        caseSensitive: Bool
    ) -> Bool {
        guard !query.isEmpty else {
            return false
        }

        let documentExtension = url.pathExtension.lowercased()
        guard documentExtension != "pdf", documentExtension != "docx" else {
            return false
        }

        guard let data = try? Data(contentsOf: url), !Self.looksBinary(data) else {
            return false
        }

        guard let text = String(data: data, encoding: .utf8) ??
            String(data: data, encoding: .utf16) ??
            String(data: data, encoding: .utf16LittleEndian) ??
            String(data: data, encoding: .utf16BigEndian) else {
            return false
        }

        return UnicodeTextMatcher.contains(query, in: text, caseSensitive: caseSensitive)
    }

    private func docxDocument(
        at url: URL,
        contains query: String,
        caseSensitive: Bool
    ) -> Bool {
        guard !query.isEmpty else {
            return false
        }

        guard let text = try? DOCXTextExtractor.text(from: url) else {
            return false
        }

        return UnicodeTextMatcher.contains(query, in: text, caseSensitive: caseSensitive)
    }

    private static func looksBinary(_ data: Data) -> Bool {
        data.prefix(4_096).contains(0)
    }

    private func beginSearch() -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }

        guard !searchInProgress else {
            return false
        }

        searchInProgress = true
        currentProcess = nil
        cancellationRequested = false
        return true
    }

    private func endSearch() {
        lock.lock()
        currentProcess = nil
        searchInProgress = false
        cancellationRequested = false
        lock.unlock()
    }

    private func setCurrentProcess(_ process: Process) {
        lock.lock()
        currentProcess = process
        lock.unlock()
    }

    private func clearCurrentProcess(_ process: Process) {
        lock.lock()
        if currentProcess === process {
            currentProcess = nil
        }
        lock.unlock()
    }

    private func isCancellationRequested() -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        return cancellationRequested
    }

    private func yieldPermissionWarningIfNeeded(
        _ stderr: String,
        continuation: AsyncThrowingStream<FindSearchEvent, Error>.Continuation
    ) {
        if stderr.localizedCaseInsensitiveContains("Permission denied") {
            continuation.yield(.warning("Some folders could not be searched because macOS denied permission. Accessible results are still shown."))
        }
    }

    private func conciseProcessMessage(from stderr: String) -> String? {
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.localizedCaseInsensitiveContains("Permission denied") {
            return "Some folders could not be searched because macOS denied permission."
        }

        return trimmed.components(separatedBy: .newlines).first
    }
}

private final class LockedStringCollector {
    private let lock = NSLock()
    private var storage = ""

    var value: String {
        lock.lock()
        defer {
            lock.unlock()
        }
        return storage
    }

    func append(_ value: String) {
        lock.lock()
        storage += value
        lock.unlock()
    }
}

private final class LockedErrorCollector {
    private let lock = NSLock()
    private var storage: Error?

    var value: Error? {
        lock.lock()
        defer {
            lock.unlock()
        }
        return storage
    }

    func set(_ error: Error) {
        lock.lock()
        if storage == nil {
            storage = error
        }
        lock.unlock()
    }
}

private final class LockedURLCollector {
    private let lock = NSLock()
    private var storage: [URL] = []

    var values: [URL] {
        lock.lock()
        defer {
            lock.unlock()
        }
        return storage
    }

    func append(_ url: URL) {
        lock.lock()
        storage.append(url)
        lock.unlock()
    }
}

private final class SearchResultDeduper {
    private let lock = NSLock()
    private var yieldedPaths: Set<String> = []

    func shouldYield(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path

        lock.lock()
        defer {
            lock.unlock()
        }
        return yieldedPaths.insert(path).inserted
    }
}

private enum UnicodeTextMatcher {
    private static let insensitiveOptions: String.CompareOptions = [
        .caseInsensitive,
        .diacriticInsensitive,
        .widthInsensitive
    ]

    static func contains(
        _ query: String,
        in text: String,
        caseSensitive: Bool
    ) -> Bool {
        guard !query.isEmpty else {
            return true
        }

        if caseSensitive {
            return text.contains(query)
        }

        return text.range(of: query, options: insensitiveOptions) != nil
    }

    static func fileName(
        _ fileName: String,
        matches query: String,
        matchMode: SearchMatchMode
    ) -> Bool {
        switch matchMode {
        case .contains:
            return contains(query, in: fileName, caseSensitive: false)
        case .fuzzy:
            return fuzzyContains(query, in: fileName)
        }
    }

    private static func fuzzyContains(
        _ query: String,
        in text: String
    ) -> Bool {
        var remainingCharacters = folded(query)
            .filter { !$0.isWhitespaceOrNewline }
            .makeIterator()

        guard var queryCharacter = remainingCharacters.next() else {
            return true
        }

        for textCharacter in folded(text) {
            if textCharacter == queryCharacter {
                guard let nextQueryCharacter = remainingCharacters.next() else {
                    return true
                }
                queryCharacter = nextQueryCharacter
            }
        }

        return false
    }

    private static func folded(_ value: String) -> String {
        value.folding(options: insensitiveOptions, locale: .current)
    }
}

private struct DOCXTextExtractor {
    static func text(from url: URL) throws -> String {
        let archive = try ZIPArchive(data: Data(contentsOf: url))
        var extractedText = ""

        for entryName in archive.entryNames where isWordTextEntry(entryName) {
            guard let xmlData = try archive.data(forEntryNamed: entryName) else {
                continue
            }
            let entryText = WordXMLTextExtractor.text(from: xmlData)
            if !entryText.isEmpty {
                if !extractedText.isEmpty {
                    extractedText.append("\n")
                }
                extractedText.append(entryText)
            }
        }

        return extractedText
    }

    private static func isWordTextEntry(_ entryName: String) -> Bool {
        if entryName == "word/document.xml" ||
            entryName == "word/footnotes.xml" ||
            entryName == "word/endnotes.xml" ||
            entryName == "word/comments.xml" {
            return true
        }

        if entryName.hasPrefix("word/header") && entryName.hasSuffix(".xml") {
            return true
        }

        if entryName.hasPrefix("word/footer") && entryName.hasSuffix(".xml") {
            return true
        }

        return false
    }
}

private final class WordXMLTextExtractor: NSObject, XMLParserDelegate {
    private var extractedText = ""
    private var isInsideTextElement = false

    static func text(from data: Data) -> String {
        let delegate = WordXMLTextExtractor()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            return ""
        }

        return delegate.extractedText
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch localName(from: elementName) {
        case "t":
            isInsideTextElement = true
        case "tab":
            extractedText.append("\t")
        case "br", "cr":
            extractedText.append("\n")
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        foundCharacters string: String
    ) {
        if isInsideTextElement {
            extractedText.append(string)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch localName(from: elementName) {
        case "t":
            isInsideTextElement = false
        case "p":
            extractedText.append("\n")
        default:
            break
        }
    }

    private func localName(from elementName: String) -> String {
        guard let separatorIndex = elementName.lastIndex(of: ":") else {
            return elementName
        }

        return String(elementName[elementName.index(after: separatorIndex)...])
    }
}

private struct ZIPArchive {
    private let data: Data
    private let entriesByName: [String: ZIPEntry]

    var entryNames: [String] {
        Array(entriesByName.keys).sorted()
    }

    init(data: Data) throws {
        self.data = data
        self.entriesByName = try Self.readCentralDirectory(in: data)
    }

    func data(forEntryNamed name: String) throws -> Data? {
        guard let entry = entriesByName[name] else {
            return nil
        }

        let localHeaderOffset = Int(entry.localHeaderOffset)
        guard try data.zipUInt32(at: localHeaderOffset) == ZIPSignature.localFileHeader else {
            throw ZIPArchiveError.invalidLocalFileHeader
        }

        let fileNameLength = Int(try data.zipUInt16(at: localHeaderOffset + 26))
        let extraFieldLength = Int(try data.zipUInt16(at: localHeaderOffset + 28))
        let compressedDataStart = localHeaderOffset + 30 + fileNameLength + extraFieldLength
        let compressedDataEnd = compressedDataStart + Int(entry.compressedSize)
        let compressedData = try data.zipData(in: compressedDataStart..<compressedDataEnd)

        switch entry.compressionMethod {
        case 0:
            return compressedData
        case 8:
            return try Self.inflate(compressedData, uncompressedSize: Int(entry.uncompressedSize))
        default:
            throw ZIPArchiveError.unsupportedCompressionMethod(entry.compressionMethod)
        }
    }

    private static func readCentralDirectory(in data: Data) throws -> [String: ZIPEntry] {
        let endOfCentralDirectoryOffset = try findEndOfCentralDirectory(in: data)
        let entryCount = Int(try data.zipUInt16(at: endOfCentralDirectoryOffset + 10))
        let centralDirectoryOffset = Int(try data.zipUInt32(at: endOfCentralDirectoryOffset + 16))
        var entries: [String: ZIPEntry] = [:]
        var offset = centralDirectoryOffset

        for _ in 0..<entryCount {
            guard try data.zipUInt32(at: offset) == ZIPSignature.centralDirectoryFileHeader else {
                throw ZIPArchiveError.invalidCentralDirectory
            }

            let compressionMethod = try data.zipUInt16(at: offset + 10)
            let compressedSize = try data.zipUInt32(at: offset + 20)
            let uncompressedSize = try data.zipUInt32(at: offset + 24)
            let fileNameLength = Int(try data.zipUInt16(at: offset + 28))
            let extraFieldLength = Int(try data.zipUInt16(at: offset + 30))
            let fileCommentLength = Int(try data.zipUInt16(at: offset + 32))
            let localHeaderOffset = try data.zipUInt32(at: offset + 42)

            let fileNameStart = offset + 46
            let fileNameEnd = fileNameStart + fileNameLength
            let fileNameData = try data.zipData(in: fileNameStart..<fileNameEnd)
            let fileName = String(decoding: fileNameData, as: UTF8.self)

            entries[fileName] = ZIPEntry(
                name: fileName,
                compressionMethod: compressionMethod,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localHeaderOffset
            )

            offset = fileNameEnd + extraFieldLength + fileCommentLength
        }

        return entries
    }

    private static func findEndOfCentralDirectory(in data: Data) throws -> Int {
        let minimumRecordSize = 22
        guard data.count >= minimumRecordSize else {
            throw ZIPArchiveError.missingEndOfCentralDirectory
        }

        let maximumCommentLength = 65_535
        let searchStart = max(0, data.count - minimumRecordSize - maximumCommentLength)
        var offset = data.count - minimumRecordSize

        while offset >= searchStart {
            if try data.zipUInt32(at: offset) == ZIPSignature.endOfCentralDirectory {
                return offset
            }
            offset -= 1
        }

        throw ZIPArchiveError.missingEndOfCentralDirectory
    }

    private static func inflate(_ compressedData: Data, uncompressedSize: Int) throws -> Data {
        guard uncompressedSize > 0 else {
            return Data()
        }

        var destination = Data(count: uncompressedSize)
        let decodedCount = compressedData.withUnsafeBytes { sourceBuffer in
            destination.withUnsafeMutableBytes { destinationBuffer in
                guard let sourceBaseAddress = sourceBuffer.bindMemory(to: UInt8.self).baseAddress,
                      let destinationBaseAddress = destinationBuffer.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }

                return compression_decode_buffer(
                    destinationBaseAddress,
                    uncompressedSize,
                    sourceBaseAddress,
                    compressedData.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard decodedCount > 0 else {
            throw ZIPArchiveError.couldNotDecompressEntry
        }

        if decodedCount < destination.count {
            destination.removeSubrange(decodedCount..<destination.count)
        }

        return destination
    }
}

private struct ZIPEntry {
    let name: String
    let compressionMethod: UInt16
    let compressedSize: UInt32
    let uncompressedSize: UInt32
    let localHeaderOffset: UInt32
}

private enum ZIPArchiveError: Error {
    case missingEndOfCentralDirectory
    case invalidCentralDirectory
    case invalidLocalFileHeader
    case unsupportedCompressionMethod(UInt16)
    case couldNotDecompressEntry
    case outOfBoundsRead
}

private enum ZIPSignature {
    static let localFileHeader: UInt32 = 0x0403_4b50
    static let centralDirectoryFileHeader: UInt32 = 0x0201_4b50
    static let endOfCentralDirectory: UInt32 = 0x0605_4b50
}

private extension Data {
    func zipUInt16(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else {
            throw ZIPArchiveError.outOfBoundsRead
        }

        return UInt16(self[offset]) |
            (UInt16(self[offset + 1]) << 8)
    }

    func zipUInt32(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else {
            throw ZIPArchiveError.outOfBoundsRead
        }

        return UInt32(self[offset]) |
            (UInt32(self[offset + 1]) << 8) |
            (UInt32(self[offset + 2]) << 16) |
            (UInt32(self[offset + 3]) << 24)
    }

    func zipData(in range: Range<Int>) throws -> Data {
        guard range.lowerBound >= 0, range.upperBound <= count else {
            throw ZIPArchiveError.outOfBoundsRead
        }

        return subdata(in: range)
    }
}

private extension Character {
    var isWhitespaceOrNewline: Bool {
        unicodeScalars.allSatisfy { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
    }
}
