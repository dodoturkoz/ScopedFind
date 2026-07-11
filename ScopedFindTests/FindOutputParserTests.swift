import XCTest
@testable import ScopedFind

final class FindOutputParserTests: XCTestCase {
    func testEmptyOutput() throws {
        var parser = FindOutputParser()

        XCTAssertEqual(try parser.append(Data()), [])
        XCTAssertEqual(try parser.finish(), [])
    }

    func testParsesNullDelimitedPaths() throws {
        var parser = FindOutputParser()
        let data = Data("/tmp/a.txt\0/tmp/b.txt\0".utf8)

        XCTAssertEqual(try parser.append(data), ["/tmp/a.txt", "/tmp/b.txt"])
        XCTAssertEqual(try parser.finish(), [])
    }

    func testParsesPathSplitAcrossChunks() throws {
        var parser = FindOutputParser()

        XCTAssertEqual(try parser.append(Data("/tmp/long".utf8)), [])
        XCTAssertEqual(try parser.append(Data("-name.txt\0".utf8)), ["/tmp/long-name.txt"])
        XCTAssertEqual(try parser.finish(), [])
    }

    func testParsesMultiplePathsInOneChunkWithNewlineInFilename() throws {
        var parser = FindOutputParser()
        let data = Data("/tmp/line\nbreak.txt\0/tmp/other.txt\0".utf8)

        XCTAssertEqual(try parser.append(data), ["/tmp/line\nbreak.txt", "/tmp/other.txt"])
    }

    func testFinishReturnsBufferedFinalPath() throws {
        var parser = FindOutputParser()

        XCTAssertEqual(try parser.append(Data("/tmp/no-null".utf8)), [])
        XCTAssertEqual(try parser.finish(), ["/tmp/no-null"])
    }

    func testMalformedUTF8Throws() {
        var parser = FindOutputParser()

        XCTAssertThrowsError(try parser.append(Data([0xFF, 0x00]))) { error in
            XCTAssertEqual(error as? FindOutputParserError, .malformedUTF8)
        }
    }
}

