/*
    word2text
    main.swift

    Copyright © 2024 Tony Smith. All rights reserved.

    MIT License
    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
*/

import Foundation


/*
    Structure to hold the outcome of a single file processing operation.
 
    The `text` property will either be the file's textual content or an error message.
    
    The `errorCode` value will be zero on a successful process, or an error code if processing
    failed. This can be used as an exit code and to determine what kind of content `text`
    contains.
*/
struct ProcessResult {
    var text: String
    var errorCode: ProcessError
}


/*
    Enumeration of processing error codes.
*/
enum ProcessError: Int {
    case none = 0
    case badFile = 1
    case badPsionFileType = 2
}


// MARK: - Constants

let BLOCK_RECORD_UNIT_LENGTH: Int   = 6
let RECORD_HEADER_LENGTH: Int       = 4
let RECORD_TYPE_FILE_INFO: Int      = 1
let RECORD_TYPE_HEADER_TEXT: Int    = 4
let RECORD_TYPE_FOOTER_TEXT: Int    = 5
let RECORD_TYPE_TEXT: Int           = 8
let RECORD_TYPE_BLOCKS: Int         = 9

// Use stderr, stdout for output
let STD_ERR: FileHandle = FileHandle.standardError
let STD_OUT: FileHandle = FileHandle.standardOutput

// TTY formatting
let RED: String             = "\u{001B}[0;31m"
let YELLOW: String          = "\u{001B}[0;33m"
let RESET: String           = "\u{001B}[0m"
let BOLD: String            = "\u{001B}[1m"
let ITALIC: String          = "\u{001B}[3m"
let BSP: String             = String(UnicodeScalar(8))
let EXIT_CTRL_C_CODE: Int32 = 130
let CTRL_C_MSG: String      = "\(BSP)\(BSP)\rword2text interrupted -- halting"


// MARK: - Global Variables

// CLI argument management
var argIsAValue: Bool       = false
var argType: Int            = -1
var argCount: Int           = 0
var prevArg: String         = ""
var doShowInfo: Bool        = false
var haltOnFirstError: Bool  = false
var doIncludeHeader: Bool   = false
var files: [String]         = []


// MARK: - Functions

func processPaths() {
    
    
}

func processFile(_ filepath: String) -> ProcessResult {
    
    var data: Data
    var text: String = ""
    
    let fileURL: URL = URL.init(fileURLWithPath: filepath)
    do {
       data  = try Data(contentsOf: fileURL)
    } catch {
        return ProcessResult.init(text: "Could not locate file", errorCode: .badFile)
    }
    
    // Check the data preamble
    let preamble: String? = String.init(data: data.prefix(15), encoding: .ascii)
    if let p: String = preamble {
        if p != "PSIONWPDATAFILE" {
            return ProcessResult.init(text: "Not a Psion Series 3 Word file", errorCode: .badPsionFileType)
        }
        
        if doShowInfo {
            writeToStderr("File \(filepath) is a Psion Series 3 Word document")
        }
    }
    
    // Decode the file's records, one by one
    let RECORD_TYPES = ["FILE INFO", "PRINTER CONFIG", "PRINTER DRIVER INFO", "HEADER TEXT", "FOOTER TEXT", "STYLE DEFINITION", "EMPHASIS DEFINITION", "BODY TEXT", "STYLE APPLICATION"]
    
    var outerText: [String] = ["", ""]
    var byteIndex: Int = 39
    
    while byteIndex < data.count - RECORD_HEADER_LENGTH {
        let recordType: Int = getWordValue(data, byteIndex)
        let recordDataLength: Int = getWordValue(data, byteIndex + 2)
        
        assert(recordType - 1 <= RECORD_TYPES.count, "UNKNOWN RECORD TYPE")
        if doShowInfo {
            writeToStderr("Record of type \(RECORD_TYPES[recordType - 1]) found at offset \(String.init(format: "0x%04x", arguments: [byteIndex])) (\(byteIndex)). Size: \(recordDataLength) bytes")
        }
        
        // File record
        // NOTE We don't require this for text conversion
        if recordType == RECORD_TYPE_FILE_INFO && doShowInfo {
            let recordByteIndex: Int = byteIndex + RECORD_HEADER_LENGTH
            let cursorLocation: Int = getWordValue(data, recordByteIndex)
            let shownSymbols: UInt8 = data[recordByteIndex + 2]
            let statusWindow: UInt8 = data[recordByteIndex + 3]
            let showStyleBar: UInt8 = data[recordByteIndex + 4]
            let fileType: UInt8 = data[recordByteIndex + 5]
            let outlineLevel: UInt8 = data[recordByteIndex + 6]
            
            writeToStderr("  Cursor location: \(cursorLocation), outline level: \(outlineLevel)")
            writeToStderr("  Show style bar: \(showStyleBar == 1 ? "yes" : "no"), File type: \(fileType == 1 ? "line" : "paragraph")")
            
            var symbolsShown: [String] = []
            var symbolText: String = ""
            if shownSymbols & 0x01 > 0 { symbolsShown.append("tabs") }
            if shownSymbols & 0x02 > 0 { symbolsShown.append("spaces") }
            if shownSymbols & 0x04 > 0 { symbolsShown.append("newlines") }
            if shownSymbols & 0x08 > 0 { symbolsShown.append("soft hyphens") }
            if shownSymbols & 0x10 > 0 { symbolsShown.append("forced line breaks") }
            
            if symbolsShown.count >  0 {
                for symbol in symbolsShown {
                    symbolText += "\(symbol), "
                }
            } else {
                symbolText = "none"
            }
            
            writeToStderr("  Symbols shown: \(symbolText)")
            
            var windowState: UInt8 = statusWindow & 0x03
            var windowText: String
            switch windowState {
                case 1:
                    windowText = "narrow"
                case 2:
                    windowText = "wide"
                default:
                    windowText = "none"
            }
            
            writeToStderr("  Status window: \(windowText)")
            
            windowState = (statusWindow & 0x30) >> 4
            writeToStderr("  Zoom level: \(windowState + 1)x")
        }
        
        // Header and footer records
        if recordType == RECORD_TYPE_HEADER_TEXT || recordType == RECORD_TYPE_FOOTER_TEXT {
            let index: Int = recordType - RECORD_TYPE_HEADER_TEXT
            let asciiBytes: [UInt8] = [UInt8](data[byteIndex + RECORD_HEADER_LENGTH..<byteIndex + RECORD_HEADER_LENGTH + recordDataLength])
            outerText[index] = String(bytes: asciiBytes, encoding: .ascii)!
            
            if doShowInfo {
                writeToStderr("  \(index == 0 ? "Header" : "Footer") text length \(outerText[index].count) byte\(outerText[index].count == 1 ? "" : "s")")
            }
        }
        
        // Text data record
        if recordType == RECORD_TYPE_TEXT {
            // Process the text record
            for i in 0..<recordDataLength {
                let currentByte = byteIndex + RECORD_HEADER_LENGTH + i
                let character: UInt8 = UInt8(data[currentByte])
                switch character {
                    case 0:
                        // 0 = paragraph separator
                        text += "\n"
                    case 7:
                        // 7 = unbreakable hyphen
                        text += "-"
                    case 14:
                        // 14 = soft hyphen (displayed only if used to break line)
                        continue
                    case 15:
                        // 15 = unbreakable space
                        text += " "
                    default:
                        let asciiBytes: [UInt8] = [character]
                        text += String(bytes: asciiBytes, encoding: .ascii)!
                }
            }
            
            if doShowInfo {
                writeToStderr("  Text length \(text.count) byte\(text.count == 1 ? "" : "s")")
            }
        }
        
        // Style application record
        if recordType == RECORD_TYPE_BLOCKS {
            var recordByteCount = 0
            var textByteCount = 0
            while recordByteCount < recordDataLength {
                let blockStartByteIndex = byteIndex + RECORD_HEADER_LENGTH + recordByteCount
                let length: Int = getWordValue(data, blockStartByteIndex)
                let style: Int = getWordValue(data, blockStartByteIndex + 2)
                let emphasis: Int = getWordValue(data, blockStartByteIndex + 4)
                
                if doShowInfo {
                    writeToStderr("  Text bytes range \(textByteCount)-\(textByteCount + length) has style code \(style) and emphasis code \(emphasis)")
                }
                
                textByteCount += length
                recordByteCount += BLOCK_RECORD_UNIT_LENGTH
                
                if textByteCount >= text.count {
                    break
                }
            }
        }
        
        byteIndex += (RECORD_HEADER_LENGTH + recordDataLength)
    }
    
    // Add the header and foot if requested
    if doIncludeHeader {
        text = "HEADER: \(outerText[0])\nBODY: \(text)\nFOOTER: \(outerText[1])"
    }
    
    return ProcessResult(text: text, errorCode: .none)
}


func getWordValue(_ data: Data, _ index: Int) -> Int {
    
    return Int(data[index]) * 0xFF + Int(data[index + 1])
}


func reportErrorAndExit(_ message: String, _ code: Int32 = EXIT_FAILURE) {

    // Generic error display routine that also quits the app

    writeToStderr(RED + BOLD + "ERROR" + RESET + " " + message + " -- exiting")
    dss.cancel()
    exit(code)
}


func reportError(_ message: String) {

    // Generic error display routine

    writeToStderr(RED + BOLD + "ERROR" + RESET + " " + message)
}


func reportWarning(_ message: String) {

    // Generic warning display routine

    writeToStderr(YELLOW + BOLD + "WARNING" + RESET + " " + message)
}


func writeToStderr(_ message: String) {

    // Write errors and other messages to stderr

    writeOut(message, STD_ERR)
}


func writeToStdout(_ message: String) {

    // Write errors and other messages to stderr

    writeOut(message, STD_OUT)
}


func writeOut(_ message: String, _ targetFileHandle: FileHandle) {

    // Write errors and other messages to `target`

    let messageAsString = message + "\r\n"
    if let messageAsData: Data = messageAsString.data(using: .utf8) {
        targetFileHandle.write(messageAsData)
    }
}


func showHelp() {

    // Display the help screen

    showHeader()

    writeToStdout("\nConvert a Psion Series 3 Word document to plain text.")
    writeToStdout(ITALIC + "https://github.com/smittytone/Psion\n" + RESET)
    writeToStdout(BOLD + "USAGE" + RESET + "\n    word2text [-s] [-o] [-v] [-h] file(s)\n")
    writeToStdout(BOLD + "OPTIONS" + RESET)
    writeToStdout("    -s | --stop          Stop on first file that can't be processed. Default: false")
    writeToStdout("    -o | --outer         Include outer text (header and footer) in output.")
    writeToStdout("    -v | --verbose       Show progress information. Otherwise only errors are shown.")
    writeToStdout("    -h | --help          This help screen.")
    writeToStdout("         --version       Show word2text version information.\n")
}


func showVersion() {

    // Display the utility's version

    showHeader()
    writeToStdout("Copyright © 2024, Tony Smith (@smittytone).\r\nSource code available under the MIT licence.")
}


func showHeader() {

    // Display the utility's version number

    let version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
    let build: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
    let name:String = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as! String
    writeToStdout("\(name) \(version) (\(build))")
}


// MARK: - Runtime Start

// Make sure the signal does not terminate the application
signal(SIGINT, SIG_IGN)

// Set up an event source for SIGINT...
let dss: DispatchSourceSignal = DispatchSource.makeSignalSource(signal: SIGINT,
                                                                queue: DispatchQueue.main)
// ...add an event handler (from above)...
dss.setEventHandler {
    writeToStderr(CTRL_C_MSG)
    dss.cancel()
    exit(EXIT_CTRL_C_CODE)
}

// ...and start the event flow
dss.resume()

// No arguments? Show Help
var args = CommandLine.arguments
if args.count == 1 {
    showHelp()
    dss.cancel()
    exit(EXIT_SUCCESS)
}

for argument in args {

    // Ignore the first comand line argument
    if argCount == 0 {
        argCount += 1
        continue
    }

    if argIsAValue {
        // Make sure we're not reading in an option rather than a value
        if argument.prefix(1) == "-" {
            reportErrorAndExit("Missing value for \(prevArg)")
        }

        argIsAValue = false
    } else {
        switch argument {
        case "-v":
            fallthrough
        case "--verbose":
            doShowInfo = true
        case "-s":
            fallthrough
        case "--stop":
            haltOnFirstError = true
        case "-o":
            fallthrough
        case "--outer":
            doIncludeHeader = true
        case "-h":
            fallthrough
        case "--help":
            showHelp()
            exit(EXIT_SUCCESS)
        case "--version":
            showVersion()
            exit(EXIT_SUCCESS)
        default:
            if argument.prefix(1) == "-" {
                reportErrorAndExit("Unknown argument: \(argument)")
            } else {
                files.append(argument)
            }
        }

        prevArg = argument
    }

    argCount += 1

    // Trap commands that come last and therefore have missing args
    if argCount == CommandLine.arguments.count && argIsAValue {
        reportErrorAndExit("Missing value for \(argument)")
    }
}

// Process paths
processPaths()

// Convert the file(s)
for filepath in files {
    let result: ProcessResult = processFile(filepath)
    if result.errorCode != .none {
        if haltOnFirstError {
            reportErrorAndExit("File \(filepath) could not be processed: \(result.text)", Int32(result.errorCode.rawValue))
        } else {
            reportWarning("File \(filepath) could not be processed: \(result.text)")
        }
    } else {
        // Output processed text to STDOUT so it's available for piping or redirection
        writeToStderr("File \(filepath) processed")
        writeToStdout(result.text)
    }
}

dss.cancel()
exit(0)
