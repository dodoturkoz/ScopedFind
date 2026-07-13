import AppKit
import Compression
import CoreText
import XCTest
@testable import ScopedFind

final class FindSearchServiceTests: XCTestCase {
    private var temporaryFolder: URL!

    override func setUpWithError() throws {
        temporaryFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryFolder {
            try? FileManager.default.removeItem(at: temporaryFolder)
        }
    }

    func testServiceFindsVisibleFilesInTemporaryDirectory() async throws {
        let expected = temporaryFolder.appendingPathComponent("notes file.txt")
        try Data("hello".utf8).write(to: expected)

        let results = try await collectResults(
            query: "notes",
            extensions: "",
            includeHidden: false,
            target: .all
        )

        XCTAssertEqual(results.map(\.url.path), [expected.path])
    }

    func testServiceExcludesHiddenPathsByDefault() async throws {
        let hiddenDirectory = temporaryFolder.appendingPathComponent(".hidden", isDirectory: true)
        try FileManager.default.createDirectory(at: hiddenDirectory, withIntermediateDirectories: true)
        try Data().write(to: hiddenDirectory.appendingPathComponent("notes.txt"))
        try Data().write(to: temporaryFolder.appendingPathComponent(".notes.txt"))

        let results = try await collectResults(
            query: "notes",
            extensions: "",
            includeHidden: false,
            target: .all
        )

        XCTAssertEqual(results, [])
    }

    func testServiceIncludesHiddenPathsWhenRequested() async throws {
        let hiddenFile = temporaryFolder.appendingPathComponent(".notes.txt")
        try Data().write(to: hiddenFile)

        let results = try await collectResults(
            query: "notes",
            extensions: "",
            includeHidden: true,
            target: .all
        )

        XCTAssertEqual(results.map(\.url.path), [hiddenFile.path])
    }

    func testServiceCanLimitResultsToFiles() async throws {
        let file = temporaryFolder.appendingPathComponent("notes.txt")
        let directory = temporaryFolder.appendingPathComponent("notes-folder", isDirectory: true)
        try Data().write(to: file)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let results = try await collectResults(
            query: "notes",
            extensions: "",
            includeHidden: true,
            target: .files
        )

        XCTAssertEqual(results.map(\.url.path), [file.path])
    }

    func testServiceCanLimitResultsToDirectories() async throws {
        let file = temporaryFolder.appendingPathComponent("notes.txt")
        let directory = temporaryFolder.appendingPathComponent("notes-folder", isDirectory: true)
        try Data().write(to: file)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let results = try await collectResults(
            query: "notes",
            extensions: "",
            includeHidden: true,
            target: .directories
        )

        XCTAssertEqual(results.map(\.url.path), [directory.path])
    }

    func testServiceCanSearchByExtensionOnly() async throws {
        let swiftFile = temporaryFolder.appendingPathComponent("AppDelegate.swift")
        let textFile = temporaryFolder.appendingPathComponent("notes.txt")
        try Data().write(to: swiftFile)
        try Data().write(to: textFile)

        let results = try await collectResults(
            query: "",
            extensions: "swift",
            includeHidden: true,
            target: .files
        )

        XCTAssertEqual(results.map(\.url.path), [swiftFile.path])
    }

    func testServiceCanSearchMultipleExtensions() async throws {
        let swiftFile = temporaryFolder.appendingPathComponent("AppDelegate.swift")
        let markdownFile = temporaryFolder.appendingPathComponent("README.md")
        let textFile = temporaryFolder.appendingPathComponent("notes.txt")
        try Data().write(to: swiftFile)
        try Data().write(to: markdownFile)
        try Data().write(to: textFile)

        let results = try await collectResults(
            query: "",
            extensions: "swift,md",
            includeHidden: true,
            target: .files
        )

        XCTAssertEqual(Set(results.map(\.url.path)), Set([swiftFile.path, markdownFile.path]))
    }

    func testServiceCanSearchWithFuzzyNameMatching() async throws {
        let expected = temporaryFolder.appendingPathComponent("ScopedFind.txt")
        let nonMatch = temporaryFolder.appendingPathComponent("FindScope.txt")
        try Data().write(to: expected)
        try Data().write(to: nonMatch)

        let results = try await collectResults(
            query: "sf",
            extensions: "",
            includeHidden: true,
            target: .files,
            matchMode: .fuzzy
        )

        XCTAssertEqual(results.map(\.url.path), [expected.path])
    }

    func testNameSearchCanMatchTurkishDiacriticsWhenCaseInsensitive() async throws {
        let expected = temporaryFolder.appendingPathComponent("şevketibostan.txt")
        try Data().write(to: expected)

        let results = try await collectResults(
            query: "sevket",
            extensions: "",
            caseSensitive: false,
            includeHidden: true,
            target: .files
        )

        XCTAssertEqual(Set(results.map(\.url.path)), Set([expected.path]))
    }

    func testNameSearchKeepsTurkishDiacriticsLiteralWhenCaseSensitive() async throws {
        let file = temporaryFolder.appendingPathComponent("şevketibostan.txt")
        try Data().write(to: file)

        let results = try await collectResults(
            query: "sevket",
            extensions: "",
            caseSensitive: true,
            includeHidden: true,
            target: .files
        )

        XCTAssertEqual(results, [])
    }

    func testFuzzyNameSearchCanMatchTurkishDiacriticsWhenCaseInsensitive() async throws {
        let expected = temporaryFolder.appendingPathComponent("şevketibostan.txt")
        try Data().write(to: expected)

        let results = try await collectResults(
            query: "svkt",
            extensions: "",
            caseSensitive: false,
            includeHidden: true,
            target: .files,
            matchMode: .fuzzy
        )

        XCTAssertEqual(Set(results.map(\.url.path)), Set([expected.path]))
    }

    func testServiceCanSearchFileContents() async throws {
        let expected = temporaryFolder.appendingPathComponent("report.txt")
        let nameOnlyMatch = temporaryFolder.appendingPathComponent("needle-name.txt")
        try Data("The project needle is here.".utf8).write(to: expected)
        try Data("plain text".utf8).write(to: nameOnlyMatch)

        let results = try await collectResults(
            query: "needle",
            extensions: "",
            includeHidden: false,
            target: .all,
            searchKind: .contents
        )

        XCTAssertEqual(results.map(\.url.path), [expected.path])
    }

    func testContentSearchCanMatchTurkishDiacriticsInTextFilesWhenCaseInsensitive() async throws {
        let expected = temporaryFolder.appendingPathComponent("report.txt")
        try Data("şevketibostan".utf8).write(to: expected)

        let results = try await collectResults(
            query: "sevket",
            extensions: "",
            caseSensitive: false,
            includeHidden: true,
            target: .all,
            searchKind: .contents
        )

        XCTAssertEqual(Set(results.map(\.url.path)), Set([expected.path]))
    }

    func testContentSearchKeepsTurkishDiacriticsLiteralWhenCaseSensitive() async throws {
        let file = temporaryFolder.appendingPathComponent("report.txt")
        try Data("şevketibostan".utf8).write(to: file)

        let results = try await collectResults(
            query: "sevket",
            extensions: "",
            caseSensitive: true,
            includeHidden: true,
            target: .all,
            searchKind: .contents
        )

        XCTAssertEqual(results, [])
    }

    func testContentSearchIsCaseInsensitiveByDefault() async throws {
        let expected = temporaryFolder.appendingPathComponent("report.txt")
        try Data("Needle".utf8).write(to: expected)

        let results = try await collectResults(
            query: "needle",
            extensions: "",
            includeHidden: true,
            target: .all,
            searchKind: .contents
        )

        XCTAssertEqual(results.map(\.url.path), [expected.path])
    }

    func testContentSearchCanBeCaseSensitive() async throws {
        let upper = temporaryFolder.appendingPathComponent("upper.txt")
        let lower = temporaryFolder.appendingPathComponent("lower.txt")
        try Data("Needle".utf8).write(to: upper)
        try Data("needle".utf8).write(to: lower)

        let results = try await collectResults(
            query: "needle",
            extensions: "",
            caseSensitive: true,
            includeHidden: true,
            target: .all,
            searchKind: .contents
        )

        XCTAssertEqual(results.map(\.url.path), [lower.path])
    }

    func testContentSearchCanBeFilteredByExtension() async throws {
        let swiftFile = temporaryFolder.appendingPathComponent("Search.swift")
        let textFile = temporaryFolder.appendingPathComponent("notes.txt")
        try Data("needle".utf8).write(to: swiftFile)
        try Data("needle".utf8).write(to: textFile)

        let results = try await collectResults(
            query: "needle",
            extensions: "swift",
            includeHidden: true,
            target: .all,
            searchKind: .contents
        )

        XCTAssertEqual(results.map(\.url.path), [swiftFile.path])
    }

    func testContentSearchExcludesHiddenPathsByDefault() async throws {
        let visibleFile = temporaryFolder.appendingPathComponent("visible.txt")
        let hiddenDirectory = temporaryFolder.appendingPathComponent(".hidden", isDirectory: true)
        let hiddenFile = hiddenDirectory.appendingPathComponent("secret.txt")
        try FileManager.default.createDirectory(at: hiddenDirectory, withIntermediateDirectories: true)
        try Data("needle".utf8).write(to: visibleFile)
        try Data("needle".utf8).write(to: hiddenFile)

        let results = try await collectResults(
            query: "needle",
            extensions: "",
            includeHidden: false,
            target: .all,
            searchKind: .contents
        )

        XCTAssertEqual(results.map(\.url.path), [visibleFile.path])
    }

    func testContentSearchNoMatchesFinishesWithEmptyResults() async throws {
        let file = temporaryFolder.appendingPathComponent("report.txt")
        try Data("haystack".utf8).write(to: file)

        let results = try await collectResults(
            query: "needle",
            extensions: "",
            includeHidden: true,
            target: .all,
            searchKind: .contents
        )

        XCTAssertEqual(results, [])
    }

    func testContentSearchCanSearchPDFText() async throws {
        let expected = temporaryFolder.appendingPathComponent("report.pdf")
        let nameOnlyMatch = temporaryFolder.appendingPathComponent("needle-name.pdf")
        try writeSearchablePDF("The project needle is here.", to: expected)
        try writeSearchablePDF("plain text", to: nameOnlyMatch)

        let results = try await collectResults(
            query: "needle",
            extensions: "",
            includeHidden: true,
            target: .all,
            searchKind: .contents
        )

        XCTAssertEqual(Set(results.map(\.url.path)), Set([expected.path]))
    }

    func testPDFContentSearchIsCaseInsensitiveByDefault() async throws {
        let expected = temporaryFolder.appendingPathComponent("report.pdf")
        try writeSearchablePDF("Needle", to: expected)

        let results = try await collectResults(
            query: "needle",
            extensions: "",
            includeHidden: true,
            target: .all,
            searchKind: .contents
        )

        XCTAssertEqual(Set(results.map(\.url.path)), Set([expected.path]))
    }

    func testPDFContentSearchCanBeCaseSensitive() async throws {
        let upper = temporaryFolder.appendingPathComponent("upper.pdf")
        let lower = temporaryFolder.appendingPathComponent("lower.pdf")
        try writeSearchablePDF("Needle", to: upper)
        try writeSearchablePDF("needle", to: lower)

        let results = try await collectResults(
            query: "needle",
            extensions: "",
            caseSensitive: true,
            includeHidden: true,
            target: .all,
            searchKind: .contents
        )

        XCTAssertEqual(Set(results.map(\.url.path)), Set([lower.path]))
    }

    func testPDFContentSearchCanBeFilteredToPDFExtension() async throws {
        let pdfFile = temporaryFolder.appendingPathComponent("report.pdf")
        let textFile = temporaryFolder.appendingPathComponent("report.txt")
        try writeSearchablePDF("needle", to: pdfFile)
        try Data("needle".utf8).write(to: textFile)

        let results = try await collectResults(
            query: "needle",
            extensions: "pdf",
            includeHidden: true,
            target: .all,
            searchKind: .contents
        )

        XCTAssertEqual(Set(results.map(\.url.path)), Set([pdfFile.path]))
    }

    func testPDFContentSearchIsSkippedForNonPDFExtensionFilter() async throws {
        let pdfFile = temporaryFolder.appendingPathComponent("report.pdf")
        let textFile = temporaryFolder.appendingPathComponent("report.txt")
        try writeSearchablePDF("needle", to: pdfFile)
        try Data("needle".utf8).write(to: textFile)

        let results = try await collectResults(
            query: "needle",
            extensions: "txt",
            includeHidden: true,
            target: .all,
            searchKind: .contents
        )

        XCTAssertEqual(results.map(\.url.path), [textFile.path])
    }

    func testPDFContentSearchExcludesHiddenPathsByDefault() async throws {
        let visibleFile = temporaryFolder.appendingPathComponent("visible.pdf")
        let hiddenDirectory = temporaryFolder.appendingPathComponent(".hidden", isDirectory: true)
        let hiddenFile = hiddenDirectory.appendingPathComponent("secret.pdf")
        try FileManager.default.createDirectory(at: hiddenDirectory, withIntermediateDirectories: true)
        try writeSearchablePDF("needle", to: visibleFile)
        try writeSearchablePDF("needle", to: hiddenFile)

        let results = try await collectResults(
            query: "needle",
            extensions: "",
            includeHidden: false,
            target: .all,
            searchKind: .contents
        )

        XCTAssertEqual(Set(results.map(\.url.path)), Set([visibleFile.path]))
    }

    func testPDFContentSearchCanMatchTurkishDiacriticsWhenCaseInsensitive() async throws {
        let expected = temporaryFolder.appendingPathComponent("report.pdf")
        try writeSearchablePDF("şevketibostan", to: expected)

        let results = try await collectResults(
            query: "sevket",
            extensions: "",
            caseSensitive: false,
            includeHidden: true,
            target: .all,
            searchKind: .contents
        )

        XCTAssertEqual(Set(results.map(\.url.path)), Set([expected.path]))
    }

    func testContentSearchCanSearchDOCXText() async throws {
        let expected = temporaryFolder.appendingPathComponent("report.docx")
        let nameOnlyMatch = temporaryFolder.appendingPathComponent("needle-name.docx")
        try writeSearchableDOCX("The project needle is here.", to: expected)
        try writeSearchableDOCX("plain text", to: nameOnlyMatch)

        let results = try await collectResults(
            query: "needle",
            extensions: "",
            includeHidden: true,
            target: .all,
            searchKind: .contents
        )

        XCTAssertEqual(Set(results.map(\.url.path)), Set([expected.path]))
    }

    func testDOCXContentSearchIsCaseInsensitiveByDefault() async throws {
        let expected = temporaryFolder.appendingPathComponent("report.docx")
        try writeSearchableDOCX("Needle", to: expected)

        let results = try await collectResults(
            query: "needle",
            extensions: "",
            includeHidden: true,
            target: .all,
            searchKind: .contents
        )

        XCTAssertEqual(Set(results.map(\.url.path)), Set([expected.path]))
    }

    func testDOCXContentSearchCanBeCaseSensitive() async throws {
        let upper = temporaryFolder.appendingPathComponent("upper.docx")
        let lower = temporaryFolder.appendingPathComponent("lower.docx")
        try writeSearchableDOCX("Needle", to: upper)
        try writeSearchableDOCX("needle", to: lower)

        let results = try await collectResults(
            query: "needle",
            extensions: "",
            caseSensitive: true,
            includeHidden: true,
            target: .all,
            searchKind: .contents
        )

        XCTAssertEqual(Set(results.map(\.url.path)), Set([lower.path]))
    }

    func testDOCXContentSearchCanBeFilteredToDOCXExtension() async throws {
        let docxFile = temporaryFolder.appendingPathComponent("report.docx")
        let textFile = temporaryFolder.appendingPathComponent("report.txt")
        try writeSearchableDOCX("needle", to: docxFile)
        try Data("needle".utf8).write(to: textFile)

        let results = try await collectResults(
            query: "needle",
            extensions: "docx",
            includeHidden: true,
            target: .all,
            searchKind: .contents
        )

        XCTAssertEqual(Set(results.map(\.url.path)), Set([docxFile.path]))
    }

    func testDOCXContentSearchIsSkippedForNonDOCXExtensionFilter() async throws {
        let docxFile = temporaryFolder.appendingPathComponent("report.docx")
        let textFile = temporaryFolder.appendingPathComponent("report.txt")
        try writeSearchableDOCX("needle", to: docxFile)
        try Data("needle".utf8).write(to: textFile)

        let results = try await collectResults(
            query: "needle",
            extensions: "txt",
            includeHidden: true,
            target: .all,
            searchKind: .contents
        )

        XCTAssertEqual(results.map(\.url.path), [textFile.path])
    }

    func testDOCXContentSearchExcludesHiddenPathsByDefault() async throws {
        let visibleFile = temporaryFolder.appendingPathComponent("visible.docx")
        let hiddenDirectory = temporaryFolder.appendingPathComponent(".hidden", isDirectory: true)
        let hiddenFile = hiddenDirectory.appendingPathComponent("secret.docx")
        try FileManager.default.createDirectory(at: hiddenDirectory, withIntermediateDirectories: true)
        try writeSearchableDOCX("needle", to: visibleFile)
        try writeSearchableDOCX("needle", to: hiddenFile)

        let results = try await collectResults(
            query: "needle",
            extensions: "",
            includeHidden: false,
            target: .all,
            searchKind: .contents
        )

        XCTAssertEqual(Set(results.map(\.url.path)), Set([visibleFile.path]))
    }

    func testDOCXContentSearchCanMatchTurkishDiacriticsWhenCaseInsensitive() async throws {
        let expected = temporaryFolder.appendingPathComponent("report.docx")
        try writeSearchableDOCX("şevketibostan", to: expected)

        let results = try await collectResults(
            query: "sevket",
            extensions: "",
            caseSensitive: false,
            includeHidden: true,
            target: .all,
            searchKind: .contents
        )

        XCTAssertEqual(Set(results.map(\.url.path)), Set([expected.path]))
    }

    func testPermissionDeniedSurfacesWarningAndKeepsAccessibleResults() async throws {
        let visibleFile = temporaryFolder.appendingPathComponent("permission-note.txt")
        try Data().write(to: visibleFile)

        let lockedDirectory = temporaryFolder.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: lockedDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: lockedDirectory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: lockedDirectory.path)
        }

        var results: [SearchResult] = []
        var warnings: [String] = []
        let service = FindSearchService()

        for try await event in service.search(
            folder: temporaryFolder,
            query: "permission-note",
            extensions: "",
            caseSensitive: false,
            includeHidden: false,
            target: .all,
            matchMode: .contains,
            searchKind: .names
        ) {
            switch event {
            case let .result(result):
                results.append(result)
            case let .warning(warning):
                warnings.append(warning)
            }
        }

        XCTAssertEqual(results.map(\.url.path), [visibleFile.path])
        XCTAssertTrue(warnings.contains { $0.localizedCaseInsensitiveContains("permission") })
    }

    private func collectResults(
        query: String,
        extensions: String,
        caseSensitive: Bool = false,
        includeHidden: Bool,
        target: SearchTarget,
        matchMode: SearchMatchMode = .contains,
        searchKind: SearchKind = .names
    ) async throws -> [SearchResult] {
        var results: [SearchResult] = []
        let service = FindSearchService()

        for try await event in service.search(
            folder: temporaryFolder,
            query: query,
            extensions: extensions,
            caseSensitive: caseSensitive,
            includeHidden: includeHidden,
            target: target,
            matchMode: matchMode,
            searchKind: searchKind
        ) {
            if case let .result(result) = event {
                results.append(result)
            }
        }

        return results
    }

    private func writeSearchablePDF(_ text: String, to url: URL) throws {
        guard let consumer = CGDataConsumer(url: url as CFURL) else {
            throw TestPDFError.couldNotCreateConsumer
        }

        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw TestPDFError.couldNotCreateContext
        }

        context.beginPDFPage(nil)
        context.translateBy(x: 0, y: mediaBox.height)
        context.scaleBy(x: 1, y: -1)

        let attributedString = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.systemFont(ofSize: 18)]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let textPath = CGMutablePath()
        textPath.addRect(CGRect(x: 72, y: 72, width: 468, height: 648))
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributedString.length),
            textPath,
            nil
        )
        CTFrameDraw(frame, context)

        context.endPDFPage()
        context.closePDF()
    }

    private func writeSearchableDOCX(_ text: String, to url: URL) throws {
        let escapedText = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:r>
                <w:t>\(escapedText)</w:t>
              </w:r>
            </w:p>
          </w:body>
        </w:document>
        """

        try writeZIP(
            entries: [("word/document.xml", Data(documentXML.utf8))],
            to: url
        )
    }

    private func writeZIP(entries: [(name: String, data: Data)], to url: URL) throws {
        var archive = Data()
        var centralDirectory = Data()

        for entry in entries {
            let localHeaderOffset = UInt32(archive.count)
            let fileNameData = Data(entry.name.utf8)
            let compressedData = try deflatedData(from: entry.data)

            archive.appendUInt32LE(0x0403_4b50)
            archive.appendUInt16LE(20)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(8)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt32LE(0)
            archive.appendUInt32LE(UInt32(compressedData.count))
            archive.appendUInt32LE(UInt32(entry.data.count))
            archive.appendUInt16LE(UInt16(fileNameData.count))
            archive.appendUInt16LE(0)
            archive.append(fileNameData)
            archive.append(compressedData)

            centralDirectory.appendUInt32LE(0x0201_4b50)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(8)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt32LE(0)
            centralDirectory.appendUInt32LE(UInt32(compressedData.count))
            centralDirectory.appendUInt32LE(UInt32(entry.data.count))
            centralDirectory.appendUInt16LE(UInt16(fileNameData.count))
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt32LE(0)
            centralDirectory.appendUInt32LE(localHeaderOffset)
            centralDirectory.append(fileNameData)
        }

        let centralDirectoryOffset = UInt32(archive.count)
        archive.append(centralDirectory)
        archive.appendUInt32LE(0x0605_4b50)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(UInt16(entries.count))
        archive.appendUInt16LE(UInt16(entries.count))
        archive.appendUInt32LE(UInt32(centralDirectory.count))
        archive.appendUInt32LE(centralDirectoryOffset)
        archive.appendUInt16LE(0)

        try archive.write(to: url)
    }

    private func deflatedData(from data: Data) throws -> Data {
        guard !data.isEmpty else {
            return Data()
        }

        var destination = Data(count: data.count + 128)
        let destinationCapacity = destination.count
        let encodedCount = data.withUnsafeBytes { sourceBuffer in
            destination.withUnsafeMutableBytes { destinationBuffer in
                guard let sourceBaseAddress = sourceBuffer.bindMemory(to: UInt8.self).baseAddress,
                      let destinationBaseAddress = destinationBuffer.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }

                return compression_encode_buffer(
                    destinationBaseAddress,
                    destinationCapacity,
                    sourceBaseAddress,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard encodedCount > 0 else {
            throw TestDOCXError.couldNotDeflateDocument
        }

        destination.removeSubrange(encodedCount..<destination.count)
        return destination
    }
}

private enum TestPDFError: Error {
    case couldNotCreateConsumer
    case couldNotCreateContext
}

private enum TestDOCXError: Error {
    case couldNotDeflateDocument
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0x00ff))
        append(UInt8((value >> 8) & 0x00ff))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0x0000_00ff))
        append(UInt8((value >> 8) & 0x0000_00ff))
        append(UInt8((value >> 16) & 0x0000_00ff))
        append(UInt8((value >> 24) & 0x0000_00ff))
    }
}
