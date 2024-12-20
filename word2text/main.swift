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





// MARK: - Constants

let BLOCK_RECORD_UNIT_LENGTH: Int   = 6
let RECORD_HEADER_LENGTH: Int       = 4

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


/**
    @Brief Convert an individual Word file to plain text.
 
    @Parameters
        - filepath: Absolute path of the target Word file.
    
    @Returns ProcessResult containing the text or an error message/code.
*/
func processFile(_ filepath: String) -> ProcessResult {
    
    // Convert
    var data: Data
    var text: String = ""
    var outerText: [String] = ["", ""]
    var styles: [String:PsionWordStyle] = [:]
    var emphases: [String:PsionWordStyle] = [:]
    var byteIndex: Int = 40
    
    // Read in the file if we can
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
            // TODO Report actual file type
            return ProcessResult.init(text: "Not a Psion Series 3 Word file", errorCode: .badPsionFileType)
        }
        
        if doShowInfo {
            writeToStderr("File \(filepath) is a Psion Series 3 Word document")
        }
    }
    
    // Check for encrypted files
    // NOTE We can't handle these yet as the decode algorithm remains unknown
    let encrypted: Bool = (getWordValue(data, 16) == 256)
    if encrypted {
        return ProcessResult.init(text: "Word file is encrypted", errorCode: .badPsionFileType)
    }
    
    // Decode the file's records, one by one
    let RECORD_TYPES = ["FILE INFO", "PRINTER CONFIG", "PRINTER DRIVER INFO", "HEADER TEXT", "FOOTER TEXT", "STYLE DEFINITION", "EMPHASIS DEFINITION", "BODY TEXT", "STYLE APPLICATION"]
    
    // Iterate over the file's bytes to extract the records
    while byteIndex < data.count - RECORD_HEADER_LENGTH {
        let recordType: Int = getWordValue(data, byteIndex)
        let recordDataLength: Int = getWordValue(data, byteIndex + 2)
        
        assert(recordType - 1 <= RECORD_TYPES.count, "UNKNOWN RECORD TYPE (\(recordType) @ \(String.init(format: "0x%04x", arguments: [byteIndex]))")
        if doShowInfo {
            writeToStderr("Record of type \(RECORD_TYPES[recordType - 1]) found at offset \(String.init(format: "0x%04x", arguments: [byteIndex])). Size: \(recordDataLength) bytes")
        }
        
        // File record
        // NOTE We don't require this for text conversion
        if recordType == PsionWordRecordType.fileInfo.rawValue {
            
            if recordDataLength != 10 {
                return ProcessResult(text: "Bad file info record size (\(recordDataLength) not 10 bytes", errorCode: .badRecordLengthFileInfo)
            }
            
            if doShowInfo {
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
        }
        
        // Printer Settings
        // NOTE We don't care about this beyond its size
        if recordType == PsionWordRecordType.printerConfig.rawValue && recordDataLength != 58 {
            return ProcessResult(text: "Bad printer config record size (\(recordDataLength) not 58 bytes", errorCode: .badRecordLengthPrinterConfig)
        }
        
        // Header and footer records
        // Data are NUL-terminated strings
        if recordType == PsionWordRecordType.headerText.rawValue || recordType == PsionWordRecordType.footerText.rawValue {
            let index: Int = recordType - PsionWordRecordType.headerText.rawValue
            
            // Allow for the trailing NUL
            let stringLength = recordDataLength - 1
            let asciiBytes: [UInt8] = [UInt8](data[byteIndex + RECORD_HEADER_LENGTH..<byteIndex + RECORD_HEADER_LENGTH + stringLength])
            outerText[index] = String(bytes: asciiBytes, encoding: .ascii)!
            
            if doShowInfo {
                writeToStderr("  \(index == 0 ? "Header" : "Footer") text length \(outerText[index].count) byte\(outerText[index].count == 1 ? "" : "s")")
            }
        }
        
        // Style Definitions
        if recordType == PsionWordRecordType.styleDefinition.rawValue {
            if recordDataLength != 80 {
                return ProcessResult(text: "Bad style definition record size (\(recordDataLength) not 80 bytes", errorCode: .badRecordLengthStyleDefinition)
            }
            
            let style: PsionWordStyle = getStyle(data, byteIndex, true)
            styles[style.code] = style
        }
        
        // Emphasis Definitions
        if recordType == PsionWordRecordType.emphasisDefinition.rawValue {
            if recordDataLength != 28 {
                return ProcessResult(text: "Bad emphasis definition record size (\(recordDataLength) not 80 bytes", errorCode: .badRecordLengthStyleDefinition)
            }
            
            let emphasis: PsionWordStyle = getStyle(data, byteIndex, false)
            emphases[emphasis.code] = emphasis
        }
        
        // Text data record
        if recordType == PsionWordRecordType.bodyText.rawValue {
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
        if recordType == PsionWordRecordType.blockInfo.rawValue {
            var recordByteCount = 0
            var textByteCount = 0
            while recordByteCount < recordDataLength {
                let blockStartByteIndex = byteIndex + RECORD_HEADER_LENGTH + recordByteCount
                let length: Int = getWordValue(data, blockStartByteIndex)
                let styleCode: String = String(bytes: [UInt8](data[blockStartByteIndex + 2..<blockStartByteIndex + 4]), encoding: .ascii)!
                let emphasisCode: String = String(bytes: [UInt8](data[blockStartByteIndex + 4..<blockStartByteIndex + 6]), encoding: .ascii)!
                
                if let style: PsionWordStyle = styles[styleCode] {
                    if let emphasis: PsionWordStyle = emphases[emphasisCode] {
                        if doShowInfo {
                            writeToStderr("  Text bytes range \(textByteCount)-\(textByteCount + length) has style \(style.name) and emphasis \(emphasis.name)")
                        }
                    }
                } else {
                    if doShowInfo {
                        writeToStderr("  Text bytes range \(textByteCount)-\(textByteCount + length) has style code \(styleCode) and emphasis code \(emphasisCode)")
                    }
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


/**
    @Brief Parse a Psion Word Style or Emphasis record.
 
    @Parameters
        - data:  The word file bytes.
        - index: The particular byte at which to start processing.
        - isStyle: `true` if the record holds a Style; `false` if it is an Emphasis.
    
    @Returns PsionWordStyle containing the record's information.
*/
func getStyle(_ data: Data, _ index: Int, _ isStyle: Bool) -> PsionWordStyle {
    
    let index: Int = index + 4
    var style: PsionWordStyle = PsionWordStyle()
    
    // Code and name
    style.code = String(bytes: [UInt8](data[index..<index + 2]), encoding: .ascii)!
    for i in index + 2..<index + 18 {
        if data[i] == 0 {
            style.name = String(bytes: [UInt8](data[(index + 2)..<i]), encoding: .ascii)!
            break
        }
    }
    
    if style.name.isEmpty {
        style.name = "Unknown"
    }
    
    // Type
    style.isStyle = ((data[index + 18] & 0x01) == 0)
    style.isUndeletable = ((data[index + 18] & 0x02) > 0)
    style.isDefault = ((data[index + 18] & 0x04) > 0)
    
    // Font type and size
    style.fontCode = getWordValue(data, index + 20)
    style.fontSize = getWordValue(data, index + 24)
    
    // Textual properties
    style.underlined = ((data[index + 22] & 0x01) > 0)
    style.bold = ((data[index + 22] & 0x02) > 0)
    style.italic = ((data[index + 22] & 0x04) > 0)
    style.superScript = ((data[index + 22] & 0x08) > 0)
    style.subScript = ((data[index + 22] & 0x10) > 0)
    
    // Property inheritance
    style.inheritUnderline = ((data[index + 26] & 0x01) > 0)
    style.inheritBold = ((data[index + 26] & 0x02) > 0)
    style.inheritItalic = ((data[index + 26] & 0x04) > 0)
    style.inheritSuperScript = ((data[index + 26] & 0x08) > 0)
    style.inheritSubScript = ((data[index + 26] & 0x10) > 0)
    
    // The following properties apply to Styles only so exit if it's an Emphasis
    if !style.isStyle {
        if doShowInfo {
            writeToStderr("  Emphasis code: \(style.code) (\(style.name))")
        }
        
        return style
    }
    
    // Indents
    style.leftIndent = getWordValue(data, index + 28)
    style.rightIndent = getWordValue(data, index + 30)
    style.firstIdent = getWordValue(data, index + 32)
    
    // Text alignment
    let alignValue: Int = getWordValue(data, index + 34)
    switch alignValue {
        case 1:
            style.alignment = .right
        case 2:
            style.alignment = .centered
        case 3:
            style.alignment = .justified
        default:
            style.alignment = .left
    }
    
    // Spacing values
    style.lineSpacing = getWordValue(data, index + 36)
    style.spaceAbovePara = getWordValue(data, index + 38)
    style.spaceBelowPara = getWordValue(data, index + 40)
    
    let spacingValue = data[index + 42]
    if spacingValue & 0x01 > 0 {
        style.spacing = .keepWithNext
    } else if spacingValue & 0x02 > 0 {
        style.spacing = .keepTogether
    } else if spacingValue & 0x04 > 0 {
        style.spacing = .newPage
    } else {
        style.spacing = .none
    }
    
    // Outline level
    style.outlineLevel = getWordValue(data, index + 44)
    
    // Tabs
    let tabCount: Int = getWordValue(data, index + 46)
    if tabCount > 0 {
        var tabIndex: Int = index + 48
        for _ in 0..<tabCount {
            style.tabPostions.append(getWordValue(data, tabIndex))
            
            let tabType: Int = getWordValue(data, tabIndex + 2)
            switch tabType {
                case 1:
                    style.tabTypes.append(.right)
                case 2:
                    style.tabTypes.append(.centered)
                default:
                    style.tabTypes.append(.left)
            }
            
            tabIndex += 4
        }
    }
    
    if doShowInfo {
        writeToStderr("  Style code: \(style.code) (\(style.name))")
    }
    
    return style
}


/**
    @Brief Read a 16-bit little endian value from the Word file byte store.
 
    @Parameters
        - data:  The word file bytes.
        - index: The particular byte holding the LSB.
    
    @Returns The value as an full integer.
*/
func getWordValue(_ data: Data, _ index: Int) -> Int {
    
    //print("\(String.init(format: "0x%02x", arguments: [data[index]])), \(String.init(format: "0x%02x", arguments: [data[index + 1]]))")
    return Int(data[index]) + (Int(data[index + 1]) << 8)
}


/**
    @Brief Generic error display routine that also quits the app.
 
    @Parameters
        - message: The error message text.
        - code:    The error code (and app exit code).
*/
func reportErrorAndExit(_ message: String, _ code: Int32 = EXIT_FAILURE) {

    writeToStderr(RED + BOLD + "ERROR" + RESET + " " + message + " -- exiting")
    dss.cancel()
    exit(code)
}


/**
    @Brief Generic error display routine that does not quit the app.
 
    @Parameters
        - message: The error message text.
*/
func reportError(_ message: String) {

    writeToStderr(RED + BOLD + "ERROR" + RESET + " " + message)
}


/**
    @Brief Generic warning display routine.
 
    @Parameters
        - message: The warning's text.
*/
func reportWarning(_ message: String) {

    writeToStderr(YELLOW + BOLD + "WARNING" + RESET + " " + message)
}


/**
    @Brief Write errors and other messages to `stderr`.
 
    @Parameters
        - message: The text to emit.
*/
func writeToStderr(_ message: String) {

    writeOut(message, STD_ERR)
}


/**
    @Brief Write output and other messages to `stdout`.
 
    @Parameters
        - message: The text to emit.
*/
func writeToStdout(_ message: String) {

    writeOut(message, STD_OUT)
}


/**
    @Brief Write output to any standard file.
 
    @Parameters
        - message:          The text to emit.
        - targetFileHandle: Where to emit the message.
*/
func writeOut(_ message: String, _ targetFileHandle: FileHandle) {

    let messageAsString = message + "\r\n"
    if let messageAsData: Data = messageAsString.data(using: .utf8) {
        targetFileHandle.write(messageAsData)
    }
}


/**
    @Brief Display the help text.
*/
func showHelp() {

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


/**
    @Brief Display the app version.
*/
func showVersion() {

    showHeader()
    writeToStdout("Copyright © 2024, Tony Smith (@smittytone).\r\nSource code available under the MIT licence.")
}


/**
    @Brief Display the app's version number.
*/
func showHeader() {
    
    #if os(macOS) 
    let version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
    let build: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
    let name:String = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as! String
    writeToStdout("\(name) \(version) (\(build))")
    #else
    writeToStdout("word2text 0.0.2 (2)")
    #endif
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
