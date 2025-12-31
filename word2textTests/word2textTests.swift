

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
        switch PsionWord.processFile(bytes[...], "/sample/filepath", ProcessSettings()) {
            case .failure(let error):
                #expect(error.code == .badPsionFileType)
            case .success(_):
                #expect(Bool(false))
        }
    }
    

    @Test func testProcessTextBadDataSizeUnder16Bytes() async throws {
        
        let bytes: [UInt8] = [UInt8](repeating: 0, count: 10)
        switch PsionWord.processFile(bytes[...], "/sample/filepath", ProcessSettings()) {
            case .failure(let error):
                #expect(error.code == .badPsionFileType)
            case .success(_):
                #expect(Bool(false))
        }
    }
    

    @Test func testProcessTextBadDataSizeUnder40Bytes() async throws {
        
        let preamble = "PSIONWPDATAFILE"
        var bytes: [UInt8] = Array(preamble.utf8)
        bytes.append(contentsOf: [0, 0, 1])
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 10))
        switch PsionWord.processFile(bytes[...], "/sample/filepath", ProcessSettings()) {
            case .failure(let error):
                #expect(error.code == .badPsionFileType)
            case .success(_):
                #expect(Bool(false))
        }
    }
    
    
    @Test func testProcessTextGoodPreambleAndSize() async throws {
        
        let preamble = "PSIONWPDATAFILE"
        var bytes: [UInt8] = Array(preamble.utf8)
        bytes.append(contentsOf: [0, 0, 1])
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 100))
        switch PsionWord.processFile(bytes[...], "/sample/filepath", ProcessSettings()) {
            case .failure(let error):
                // This will exit with an 'encrypted' error
                #expect(error.code == .badFileEncrypted)
            case .success(_):
                #expect(Bool(false))
        }
    }
    

    @Test func testProcessTextGoodPreambleBadSize() async throws {
        
        let preamble = "PSIONWPDATAFILE"
        var bytes: [UInt8] = Array(preamble.utf8)
        bytes.append(contentsOf: [0, 0, 0])
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 24))
        switch PsionWord.processFile(bytes[...], "/sample/filepath", ProcessSettings()) {
            case .failure(let error):
                // This will exit with an 'missing records' error
                #expect(error.code == .badFileMissingRecords)
            case .success(_):
                #expect(Bool(false))
        }
    }
    
    
    @Test func testProcessTextBadRecordType() async throws {
        
        var bytes = buildHeader()
        bytes.append(contentsOf: [0, 99, 0, 0, 0, 0, 0, 0, 0])
        switch PsionWord.processFile(bytes[...], "/sample/filepath", ProcessSettings()) {
            case .failure(let error):
                #expect(error.code == .badRecordType)
            case .success(_):
                #expect(Bool(false))
        }
    }
    
    
    @Test func testProcessTextBadRecordWrongSizeFileInfo() async throws {
        
        var bytes = buildHeader()
        bytes.append(contentsOf: [0, 1, 0, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        switch PsionWord.processFile(bytes[...], "/sample/filepath", ProcessSettings()) {
            case .failure(let error):
                #expect(error.code == .badRecordLengthFileInfo)
            case .success(_):
                #expect(Bool(false))
        }
    }
    
    
    @Test func testProcessTextBadRecordWrongSizePrinterConfig() async throws {
        
        // Build record
        var bytes = buildHeader()
        bytes.append(contentsOf: [0, 2, 0, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        switch PsionWord.processFile(bytes[...], "/sample/filepath", ProcessSettings()) {
            case .failure(let error):
                #expect(error.code == .badRecordLengthPrinterConfig)
            case .success(_):
                #expect(Bool(false))
        }
    }
    
    
    @Test func testProcessTextBadRecordWrongSizeStyle() async throws {
        
        // Build record
        var bytes = buildHeader()
        bytes.append(contentsOf: [0, 6, 0, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        switch PsionWord.processFile(bytes[...], "/sample/filepath", ProcessSettings()) {
            case .failure(let error):
                #expect(error.code == .badRecordLengthStyleDefinition)
            case .success(_):
                #expect(Bool(false))
        }
    }
    
    
    @Test func testProcessTextBadRecordWrongSizeEmphasis() async throws {
        
        // Build record
        var bytes = buildHeader()
        bytes.append(contentsOf: [0, 7, 0, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        switch PsionWord.processFile(bytes[...], "/sample/filepath", ProcessSettings()) {
            case .failure(let error):
                #expect(error.code == .badRecordLengthStyleDefinition)
            case .success(_):
                #expect(Bool(false))
        }
    }
    

    // MARK: - GetWordValue()
    
    @Test func testGetWordValueGoodArrayLarge() async throws {
        
        let bytes: [UInt8] = [4, 8]
        #expect(PsionWord.getWordValue(bytes[...]) == 2052)
    }
    
    
    @Test func testGetWordValueGoodArraySmall() async throws {
        
        let bytes: [UInt8] = [8, 0]
        #expect(PsionWord.getWordValue(bytes[...]) == 8)
    }
    
    
    @Test func testGetWordValueBadArrayTooShort() async throws {
        
        let bytes: [UInt8] = [4]
        #expect(PsionWord.getWordValue(bytes[...]) == -1)
    }
    
    
    @Test func testGetWordValueBadArrayEmpty() async throws {
        
        let bytes: [UInt8] = []
        #expect(PsionWord.getWordValue(bytes[...]) == -1)
    }
    
    
    // MARK: - GetOuterText()

    @Test func testGetOuterTextGoodHeaderString() async throws {
        
        let header = "Fintlewoodlewix\0"
        let bytes: [UInt8] = Array(header.utf8)
        let s = PsionWord.getOuterText(bytes[...], true, ProcessSettings())
        #expect(s == "Fintlewoodlewix")
    }


    @Test func testGetOuterTextGoodHeaderStringWithWhitespace() async throws {

        let header = "     Fintlewoodlewix\n  \0"
        let bytes: [UInt8] = Array(header.utf8)
        let s = PsionWord.getOuterText(bytes[...], true, ProcessSettings())
        #expect(s == "Fintlewoodlewix")
    }

    
    @Test func testGetOuterTextGoodHeaderZeroLength() async throws {
        
        let header = ""
        let bytes: [UInt8] = Array(header.utf8)
        #expect(PsionWord.getOuterText(bytes[...], true, ProcessSettings()) == "No header")
    }
    
    
    @Test func testGetOuterTextGoodFooterString() async throws {
        
        let footer = "Fintlewoodlewix\0"
        let bytes: [UInt8] = Array(footer.utf8)
        let s = PsionWord.getOuterText(bytes[...], false, ProcessSettings())
        #expect(s == "Fintlewoodlewix")
    }


    @Test func testGetOuterTextGoodFooterStringWithWhitepace() async throws {

        let footer = "               Fintlewoodlewix\n\n\r\0"
        let bytes: [UInt8] = Array(footer.utf8)
        let s = PsionWord.getOuterText(bytes[...], false, ProcessSettings())
        #expect(s == "Fintlewoodlewix")
    }

    
    @Test func testGetOuterTextGoodFooterZeroLength() async throws {
        
        let header = ""
        let bytes: [UInt8] = Array(header.utf8)
        #expect(PsionWord.getOuterText(bytes[...], false, ProcessSettings()) == "No footer")
    }
    
    
    // MARK: - GetBodyText()
    
    @Test func testGetBodyTextGoodSubstitutions() async throws {
        
        let body = "fintlewoodlewix\042"
        let end = "stuff"
        var bytes: [UInt8] = Array(body.utf8)
        bytes.append(0x07)
        bytes.append(contentsOf: Array(end.utf8))
        let backBytes = PsionWord.getBodyText(bytes[...], ProcessSettings())
        #expect(backBytes[15] == 0x0A && backBytes[18] == 0x2D)
    }
    

    /*
        DEPRECATED: The should be part of `Clicore`.

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
    
    
    // MARK: - getFileContents()

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
    */


    // MARK: - getStyleBlocks()

    @Test func testGetStyleBlocksSimpleBlock() async throws {
        
        var bytes: [UInt8] = []
        bytes.append(contentsOf: [100, 0, 65, 66, 67, 68])
        let blocks = PsionWord.getStyleBlocks(bytes[...], 100, ProcessSettings())
        #expect(blocks.count == 1)
        
        let block = blocks[0]
        #expect(block.startIndex == 0 && block.endIndex == 99)
        #expect(block.styleCode == "AB" && block.emphasisCode == "CD")
    }
    
    
    @Test func testGetStyleBlocksComplexBlock() async throws {
        
        var bytes: [UInt8] = []
        bytes.append(contentsOf: [50, 00, 77, 77, 72, 72])
        bytes.append(contentsOf: [50, 00, 69, 69, 66, 66])
        let blocks = PsionWord.getStyleBlocks(bytes[...], 100, ProcessSettings())
        #expect(blocks.count == 2)
        
        var block = blocks[0]
        #expect(block.startIndex == 0 && block.endIndex == 49)
        #expect(block.styleCode == "MM" && block.emphasisCode == "HH")
        
        block = blocks[1]
        #expect(block.startIndex == 50 && block.endIndex == 99)
        #expect(block.styleCode == "EE" && block.emphasisCode == "BB")
    }


    // MARK: - getStyle()

    @Test func testGetStyleNameEmphasis() async throws {

        var bytes: [UInt8] = []
        bytes.append(contentsOf: [100, 0, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 0, 75, 76, 77])
        bytes.append(contentsOf: Array(repeating: 255, count: 64))
        let style = PsionWord.getStyle(bytes[...], false, ProcessSettings())
        #expect(style.name == "ABCDEFGHIJ")
    }


    @Test func testGetStyleNameStyle() async throws {

        var bytes: [UInt8] = []
        bytes.append(contentsOf: [100, 0, 65, 65, 65, 65, 65, 0, 71, 72, 73, 74, 0, 75, 76, 77])
        bytes.append(contentsOf: Array(repeating: 255, count: 64))
        let style = PsionWord.getStyle(bytes[...], true, ProcessSettings())
        #expect(style.name == "AAAAA")
    }


    func returnTestFile() -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.append(contentsOf: [80, 83, 73, 79, 78, 87, 80, 68, 65, 84, 65, 70, 73, 76, 69, 0, 1, 0, 0, 0, 234, 234, 234, 234, 234, 234, 234, 234, 234, 234, 234, 234, 234, 234, 234, 234, 234, 234, 0, 0, 1, 0, 10, 0, 54, 0, 25, 34, 0, 0, 8, 1, 2, 0, 2, 0, 58, 0, 130, 46, 198, 65, 8, 7, 8, 7, 114, 32, 182, 51, 208, 2, 208, 2, 0, 0, 0, 0, 1, 0, 255, 255, 0, 0, 0, 0, 240, 0, 0, 0, 0, 0, 0, 0, 240, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 240, 0, 0, 0, 0, 0, 0, 0, 3, 0, 13, 0, 0, 82, 79, 77, 58, 58, 66, 74, 46, 87, 68, 82, 0, 4, 0, 1, 0, 0, 5, 0, 3, 0, 37, 80, 0, 6, 0, 80, 0, 66, 84, 66, 111, 100, 121, 32, 116, 101, 120, 116, 0, 32, 32, 32, 32, 32, 0, 6, 0, 24, 0, 0, 0, 240, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 240, 0, 0, 0, 240, 0, 0, 0, 9, 0, 8, 0, 208, 2, 0, 0, 160, 5, 0, 0, 112, 8, 0, 0, 64, 11, 0, 0, 16, 14, 0, 0, 224, 16, 0, 0, 176, 19, 0, 0, 128, 22, 0, 0, 6, 0, 80, 0, 72, 65, 72, 101, 97, 100, 105, 110, 103, 32, 65, 0, 32, 32, 32, 32, 32, 0, 0, 0, 24, 0, 2, 0, 224, 1, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 224, 1, 0, 0, 240, 0, 1, 0, 1, 0, 0, 0, 208, 2, 0, 0, 160, 5, 0, 0, 112, 8, 0, 0, 64, 11, 0, 0, 16, 14, 0, 0, 224, 16, 0, 0, 176, 19, 0, 0, 128, 22, 0, 0, 6, 0, 80, 0, 72, 66, 72, 101, 97, 100, 105, 110, 103, 32, 66, 0, 32, 32, 32, 32, 32, 0, 0, 0, 24, 0, 2, 0, 240, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 240, 0, 0, 0, 120, 0, 1, 0, 2, 0, 0, 0, 208, 2, 0, 0, 160, 5, 0, 0, 112, 8, 0, 0, 64, 11, 0, 0, 16, 14, 0, 0, 224, 16, 0, 0, 176, 19, 0, 0, 128, 22, 0, 0, 6, 0, 80, 0, 66, 76, 66, 117, 108, 108, 101, 116, 101, 100, 32, 108, 105, 115, 116, 0, 32, 0, 0, 0, 255, 255, 0, 0, 240, 0, 0, 0, 208, 2, 0, 0, 104, 1, 3, 0, 240, 0, 0, 0, 240, 0, 0, 0, 9, 0, 1, 0, 208, 2, 0, 0, 160, 5, 0, 0, 112, 8, 0, 0, 64, 11, 0, 0, 16, 14, 0, 0, 224, 16, 0, 0, 176, 19, 0, 0, 128, 22, 0, 0, 7, 0, 28, 0, 78, 78, 78, 111, 114, 109, 97, 108, 0, 32, 32, 32, 32, 32, 32, 32, 32, 0, 7, 0, 255, 255, 0, 0, 0, 0, 7, 0, 7, 0, 28, 0, 85, 85, 85, 110, 100, 101, 114, 108, 105, 110, 101, 0, 32, 32, 32, 32, 32, 0, 1, 0, 255, 255, 1, 0, 0, 0, 6, 0, 7, 0, 28, 0, 66, 66, 66, 111, 108, 100, 0, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 0, 1, 0, 255, 255, 2, 0, 0, 0, 5, 0, 7, 0, 28, 0, 73, 73, 73, 116, 97, 108, 105, 99, 0, 32, 32, 32, 32, 32, 32, 32, 32, 0, 1, 0, 255, 255, 4, 0, 0, 0, 3, 0, 7, 0, 28, 0, 69, 69, 83, 117, 112, 101, 114, 115, 99, 114, 105, 112, 116, 0, 32, 32, 32, 0, 1, 0, 255, 255, 8, 0, 0, 0, 7, 0, 7, 0, 28, 0, 83, 83, 83, 117, 98, 115, 99, 114, 105, 112, 116, 0, 32, 32, 32, 32, 32, 0, 1, 0, 255, 255, 16, 0, 0, 0, 7, 0, 8, 0, 55, 0, 72, 101, 97, 100, 105, 110, 103, 0, 84, 104, 105, 115, 32, 105, 115, 32, 115, 111, 109, 101, 32, 98, 111, 108, 100, 32, 116, 101, 120, 116, 46, 0, 0, 84, 104, 105, 115, 32, 105, 115, 32, 112, 108, 97, 105, 110, 32, 116, 101, 120, 116, 46, 0, 0, 0, 9, 0, 54, 0, 8, 0, 72, 65, 78, 78, 13, 0, 66, 84, 78, 78, 4, 0, 66, 84, 66, 66, 7, 0, 66, 84, 78, 78, 1, 0, 66, 84, 78, 78, 20, 0, 66, 84, 78, 78, 1, 0, 66, 84, 78, 78, 1, 0, 66, 84, 78, 78, 1, 0, 66, 84, 78, 78])
        return bytes
    }
}
