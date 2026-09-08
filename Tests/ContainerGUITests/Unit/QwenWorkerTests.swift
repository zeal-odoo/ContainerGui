import Foundation
import XCTest

@testable import ContainerGUI

final class QwenWorkerTests: XCTestCase {
    func testRequestRejectsInvalidLanguageEmptyEvidenceAndOversizedLines() throws {
        let valid = Data(#"{"id":"one","evidence":"connection refused","language":"en"}"#.utf8)
        XCTAssertEqual(try AILogWorker.decodeRequest(valid).id, "one")
        for line in [
            #"{"id":"one","evidence":"failure","language":"xx"}"#,
            #"{"id":"one","evidence":"   ","language":"en"}"#,
            #"{"id":"","evidence":"failure","language":"en"}"#,
            #"{"id":"one","evidence":"failure"}"#
        ] {
            XCTAssertThrowsError(try AILogWorker.decodeRequest(Data(line.utf8)))
        }
        XCTAssertThrowsError(try AILogWorker.decodeRequest(Data(repeating: 65, count: 32_769)))
    }

    func testLineReaderEnforcesBytesAndHandlesEOF() throws {
        let pipe = Pipe()
        try pipe.fileHandleForWriting.write(contentsOf: Data("one\ntwo\nlast".utf8))
        try pipe.fileHandleForWriting.close()
        let reader = AILogWorker.LineReader(handle: pipe.fileHandleForReading, maximumBytes: 4)
        XCTAssertEqual(try reader.next(), Data("one".utf8))
        XCTAssertEqual(try reader.next(), Data("two".utf8))
        XCTAssertEqual(try reader.next(), Data("last".utf8))
        XCTAssertNil(try reader.next())

        let oversized = Pipe()
        try oversized.fileHandleForWriting.write(contentsOf: Data("12345\n".utf8))
        try oversized.fileHandleForWriting.close()
        let bounded = AILogWorker.LineReader(handle: oversized.fileHandleForReading, maximumBytes: 4)
        XCTAssertThrowsError(try bounded.next())
    }

    func testLineReaderReturnsARequestBeforeTheWriterCloses() throws {
        let pipe = Pipe()
        let writer = pipe.fileHandleForWriting
        try writer.write(contentsOf: Data("request\n".utf8))
        // Delayed EOF prevents a broken reader from hanging the test indefinitely.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { try? writer.close() }
        let reader = AILogWorker.LineReader(handle: pipe.fileHandleForReading)
        let started = Date()
        XCTAssertEqual(try reader.next(), Data("request".utf8))
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.4)
    }

    func testCausalMaskHasNoFutureAttentionAndRejectsContextOverflow() throws {
        let mask = try QwenLogModel.causalMask(position: 2, count: 2)
        XCTAssertEqual(mask.shape.map(\.intValue), [1, 1, 2, 2048])
        XCTAssertEqual(mask[2].floatValue, 0)
        XCTAssertEqual(mask[3].floatValue, -.infinity)
        XCTAssertEqual(mask[2048 + 3].floatValue, 0)
        XCTAssertEqual(mask[2048 + 4].floatValue, -.infinity)
        XCTAssertThrowsError(try QwenLogModel.causalMask(position: 2048, count: 1))
        XCTAssertThrowsError(try QwenLogModel.causalMask(position: -1, count: 1))
        XCTAssertThrowsError(try QwenLogModel.causalMask(position: 2047, count: 2))
    }

    func testMissingModelFailsWithoutStartingInference() {
        XCTAssertThrowsError(try QwenLogModel(directory: URL(fileURLWithPath: "/nonexistent-qwen-model")))
    }
}
