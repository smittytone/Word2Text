

import Testing


struct word2textTests {
    
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
        
        let preamble = "PSIONWPDATAFILE"
        var bytes: [UInt8] = Array(preamble.utf8)
        bytes.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0,
                                  0, 0, 0, 0, 0, 0, 0, 0, 0, 99, 0, 0, 0, 0, 0, 0, 0])
        let result: ProcessResult = processFile(bytes[...], "/sample/filepath")
        #expect(result.errorCode == .badRecordType)
    }
    
    
    @Test func testGetWordValueGoodArray() async throws {
        
        let bytes: [UInt8] = [4, 8]
        #expect(getWordValue(bytes[...]) == 2052)
    }
    
    
    @Test func testGetWordValueBadArrayTooShort() async throws {
        
        let bytes: [UInt8] = [4]
        #expect(getWordValue(bytes[...]) == -1)
    }
    
    
    @Test func testGetWordValueBadArrayEmpty() async throws {
        
        let bytes: [UInt8] = []
        #expect(getWordValue(bytes[...]) == -1)
    }
    
    
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
    
    
    @Test func testGetBodyTextGoodSubstitutions() async throws {
        
        let body = "fintlewoodlewix\042"
        let end = "stuff"
        var bytes: [UInt8] = Array(body.utf8)
        bytes.append(0x07)
        bytes.append(contentsOf: Array(end.utf8))
        let backBytes = getBodyText(bytes[...])
        #expect(backBytes[15] == 0x0A && backBytes[18] == 0x2D)
    }
    
    
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
    
    
    @Test func testProcessRelativePath() async throws {
        
        let path = "/example/test/folder/../../../"
        let aPath = processRelativePath(path)
        #expect(aPath == "/tmp")
    }
    
}
