

import Testing


/*
let PSION_WORD_BLOCK_UNIT_LENGTH: Int       = 6
let PSION_WORD_RECORD_HEADER_LENGTH: Int    = 4
let PSION_WORD_RECORD_TYPES: [String]       = [
    "FILE INFO", "PRINTER CONFIG", "PRINTER DRIVER INFO", "HEADER TEXT", "FOOTER TEXT",
    "STYLE DEFINITION", "EMPHASIS DEFINITION", "BODY TEXT", "STYLE APPLICATION"
]
*/

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
        #expect(result.errorCode == .badFileEncrypted)
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
    
    
    @Test func testGetWordValueBadArray() async throws {
        
        let bytes: [UInt8] = [4]
        #expect(getWordValue(bytes[...]) == -1)
    }
    
    
    @Test func testGetOuterTextGoodHeaderString() async throws {
        
        let header = "Fintlewoodlewix\0"
        let bytes: [UInt8] = Array(header.utf8)
        let s = getOuterText(bytes[...], bytes.count, true)
        #expect(s == "Fintlewoodlewix")
    }
    
    
    @Test func testGetOuterTextGoodHeaderZeroLength() async throws {
        
        let header = "\0"
        let bytes: [UInt8] = Array(header.utf8)
        #expect(getOuterText(bytes[...], bytes.count, true) == "None")
    }
    
    
    @Test func testGetOuterTextGoodFooterString() async throws {
        
        let header = "Fintlewoodlewix\0"
        let bytes: [UInt8] = Array(header.utf8)
        let s = getOuterText(bytes[...], bytes.count, false)
        #expect(s == "Fintlewoodlewix")
    }
    
    
    @Test func testGetOuterTextGoodFooterZeroLength() async throws {
        
        let header = "\0"
        let bytes: [UInt8] = Array(header.utf8)
        #expect(getOuterText(bytes[...], bytes.count, false) == "None")
    }
}
