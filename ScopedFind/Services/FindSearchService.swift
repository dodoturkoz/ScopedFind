import Foundation
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
                    continuation.yield(.result(SearchResult(url: url)))
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

        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        for pageIndex in 0..<document.pageCount {
            if isCancellationRequested() {
                return false
            }
            guard let text = document.page(at: pageIndex)?.string else {
                continue
            }
            if text.range(of: query, options: options) != nil {
                return true
            }
        }
        return false
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
