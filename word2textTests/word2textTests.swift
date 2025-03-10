

import Testing
import Foundation


struct word2textTests {
    
    func buildHeader() -> [UInt8] {
        // Build header
        let preamble = "PSIONWPDATAFILE"
        var bytes: [UInt8] = Array(preamble.utf8)
        bytes.append(contentsOf: [0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        return bytes
    }
    
    // MARK: - ProcessText()
    
    @Test func testProcessTextBadPreamble() async throws {
        
        let bytes: [UInt8] = [UInt8](repeating: 0, count: 100)
        let result: ProcessResult = processFile(bytes[...], "/sample/filepath")
        #expect(result.errorCode == .badPsionFileType)
    }
    
    
    @Test func testProcessTextBadDataSizeUnder16Bytes() async throws {
        
        let bytes: [UInt8] = [UInt8](repeating: 0, count: 10)
        let result: ProcessResult = processFile(bytes[...], "/sample/filepath")
        #expect(result.errorCode == .badPsionFileType)
    }
    
    
    @Test func testProcessTextBadDataSizeUnder40Bytes() async throws {
        
        let preamble = "PSIONWPDATAFILE"
        var bytes: [UInt8] = Array(preamble.utf8)
        bytes.append(contentsOf: [0, 0, 1])
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 10))
        let result: ProcessResult = processFile(bytes[...], "/sample/filepath")
        #expect(result.errorCode == .badPsionFileType)
    }
    
    
    @Test func testProcessTextGoodPreambleAndSize() async throws {
        
        let preamble = "PSIONWPDATAFILE"
        var bytes: [UInt8] = Array(preamble.utf8)
        bytes.append(contentsOf: [0, 0, 1])
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 100))
        let result: ProcessResult = processFile(bytes[...], "/sample/filepath")
        
        // This will exit with an 'encrypted' error
        #expect(result.errorCode == .badFileEncrypted)
    }
    
    
    @Test func testProcessTextGoodPreambleBadSize() async throws {
        
        let preamble = "PSIONWPDATAFILE"
        var bytes: [UInt8] = Array(preamble.utf8)
        bytes.append(contentsOf: [0, 0, 0])
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 24))
        let result: ProcessResult = processFile(bytes[...], "/sample/filepath")
        
        // This will exit with an 'encrypted' error
        #expect(result.errorCode == .badFileMissingRecords)
    }
    
    
    @Test func testProcessTextBadRecordType() async throws {
        
        var bytes = buildHeader()
        bytes.append(contentsOf: [0, 99, 0, 0, 0, 0, 0, 0, 0])
        let result: ProcessResult = processFile(bytes[...], "/sample/filepath")
        #expect(result.errorCode == .badRecordType)
    }
    
    
    @Test func testProcessTextBadRecordWrongSizeFileInfo() async throws {
        
        var bytes = buildHeader()
        bytes.append(contentsOf: [0, 1, 0, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        let result: ProcessResult = processFile(bytes[...], "/sample/filepath")
        #expect(result.errorCode == .badRecordLengthFileInfo)
    }
    
    
    @Test func testProcessTextBadRecordWrongSizePrinterConfig() async throws {
        
        // Build record
        var bytes = buildHeader()
        bytes.append(contentsOf: [0, 2, 0, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        let result: ProcessResult = processFile(bytes[...], "/sample/filepath")
        #expect(result.errorCode == .badRecordLengthPrinterConfig)
    }
    
    
    @Test func testProcessTextBadRecordWrongSizeStyle() async throws {
        
        // Build record
        var bytes = buildHeader()
        bytes.append(contentsOf: [0, 6, 0, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        let result: ProcessResult = processFile(bytes[...], "/sample/filepath")
        #expect(result.errorCode == .badRecordLengthStyleDefinition)
    }
    
    
    @Test func testProcessTextBadRecordWrongSizeEmphasis() async throws {
        
        // Build record
        var bytes = buildHeader()
        bytes.append(contentsOf: [0, 7, 0, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        let result: ProcessResult = processFile(bytes[...], "/sample/filepath")
        #expect(result.errorCode == .badRecordLengthStyleDefinition)
    }
    
    
    // MARK: - GetWordValue()
    
    @Test func testGetWordValueGoodArrayLarge() async throws {
        
        let bytes: [UInt8] = [4, 8]
        #expect(getWordValue(bytes[...]) == 2052)
    }
    
    
    @Test func testGetWordValueGoodArraySmall() async throws {
        
        let bytes: [UInt8] = [8, 0]
        #expect(getWordValue(bytes[...]) == 8)
    }
    
    
    @Test func testGetWordValueBadArrayTooShort() async throws {
        
        let bytes: [UInt8] = [4]
        #expect(getWordValue(bytes[...]) == -1)
    }
    
    
    @Test func testGetWordValueBadArrayEmpty() async throws {
        
        let bytes: [UInt8] = []
        #expect(getWordValue(bytes[...]) == -1)
    }
    
    
    // MARK: - GetOuterText()
    
    @Test func testGetOuterTextGoodHeaderString() async throws {
        
        let header = "Fintlewoodlewix\0"
        let bytes: [UInt8] = Array(header.utf8)
        let s = getOuterText(bytes[...], true)
        #expect(s == "Fintlewoodlewix")
    }
    
    
    @Test func testGetOuterTextGoodHeaderZeroLength() async throws {
        
        let header = ""
        let bytes: [UInt8] = Array(header.utf8)
        #expect(getOuterText(bytes[...], true) == "None")
    }
    
    
    @Test func testGetOuterTextGoodFooterString() async throws {
        
        let header = "Fintlewoodlewix\0"
        let bytes: [UInt8] = Array(header.utf8)
        let s = getOuterText(bytes[...], false)
        #expect(s == "Fintlewoodlewix")
    }
    
    
    @Test func testGetOuterTextGoodFooterZeroLength() async throws {
        
        let header = ""
        let bytes: [UInt8] = Array(header.utf8)
        #expect(getOuterText(bytes[...], false) == "None")
    }
    
    
    // MARK: - GetBodyText()
    
    @Test func testGetBodyTextGoodSubstitutions() async throws {
        
        let body = "fintlewoodlewix\042"
        let end = "stuff"
        var bytes: [UInt8] = Array(body.utf8)
        bytes.append(0x07)
        bytes.append(contentsOf: Array(end.utf8))
        let backBytes = getBodyText(bytes[...])
        #expect(backBytes[15] == 0x0A && backBytes[18] == 0x2D)
    }
    
    
    // MARK: - GetFullPath()
    
    @Test func testGetFullPathGoodDots() async throws {
        
        let path = "../example"
        let aPath = getFullPath(path)
        #expect(!aPath.contains(".."))
    }
    
    
    @Test func testGetGoodPathGoodDot() async throws {
        
        let path = "./example/../../test"
        let aPath = getFullPath(path)
        #expect(!aPath.contains(".") && !aPath.contains(".."))
    }
    
    
    // MARK: - ProcessRelativePath()
    
    @Test func testProcessRelativePath() async throws {
        
        let path = "/example/test/folder/../../../"
        let aPath = processRelativePath(path)
        #expect(aPath == "/tmp")
    }
    
    
    // MARK: - DoesPathReferenceDirectory()
    
    @Test func testDoesPathReferenceDirectoryWithDir() async throws {
        
        let path = "/"
        #expect(doesPathReferenceDirectory(path))
    }
    
    
    @Test func testDoesPathReferenceDirectoryWithFile() async throws {
        
        let path = "/tmp/test"
        do {
            try "test".write(toFile: path, atomically: true, encoding: .utf8)
            #expect(!doesPathReferenceDirectory(path))
        } catch {
            #expect(Bool(false))
        }
    }
    
    
    // MARK: - GetFileContents()
    
    @Test func testDoesGetFileContentsValidFile() async throws {
        
        let path = "/tmp/test"
        do {
            try "test".write(toFile: path, atomically: true, encoding: .utf8)
            let readback = getFileContents(path)
            #expect(readback.count == 4)
        } catch {
            #expect(Bool(false))
        }
    }
    
    
    @Test func testDoesGetFileContentsNonexistentFile() async throws {
        
        let path = "/tmp/testz"
        let readback = getFileContents(path)
        #expect(readback.isEmpty)
    }
    
    
    @Test func testDoesGetFileContentsDir() async throws {
        
        let path = "/tmp"
        let readback = getFileContents(path)
        #expect(readback.isEmpty)
    }
    
    
    // MARK: - GetStyleBlocks()
    
    @Test func testGetStyleBlocksSimpleBlock() async throws {
        
        var bytes: [UInt8] = []
        bytes.append(contentsOf: [100, 0, 65, 66, 67, 68])
        let blocks = getStyleBlocks(bytes[...], 100)
        #expect(blocks.count == 1)
        
        let block = blocks[0]
        #expect(block.startIndex == 0 && block.endIndex == 99)
        #expect(block.styleCode == "AB" && block.emphasisCode == "CD")
    }
    
    
    @Test func testGetStyleBlocksComplexBlock() async throws {
        
        var bytes: [UInt8] = []
        bytes.append(contentsOf: [50, 00, 77, 77, 72, 72])
        bytes.append(contentsOf: [50, 00, 69, 69, 66, 66])
        let blocks = getStyleBlocks(bytes[...], 100)
        #expect(blocks.count == 2)
        
        var block = blocks[0]
        #expect(block.startIndex == 0 && block.endIndex == 49)
        #expect(block.styleCode == "MM" && block.emphasisCode == "HH")
        
        block = blocks[1]
        #expect(block.startIndex == 50 && block.endIndex == 99)
        #expect(block.styleCode == "EE" && block.emphasisCode == "BB")
    }
}
