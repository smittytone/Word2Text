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

// Use stderr, stdout for output
let STD_ERR: FileHandle                     = FileHandle.standardError
let STD_OUT: FileHandle                     = FileHandle.standardOutput

// TTY formatting
let RED: String                             = "\u{001B}[0;31m"
let YELLOW: String                          = "\u{001B}[0;33m"
let RESET: String                           = "\u{001B}[0m"
let BOLD: String                            = "\u{001B}[1m"
let ITALIC: String                          = "\u{001B}[3m"
let BSP: String                             = String(UnicodeScalar(8))
let EXIT_CTRL_C_CODE: Int32                 = 130
let CTRL_C_MSG: String                      = "\(BSP)\(BSP)\rword2text interrupted -- halting"

// Psion
let PSION_WORD_BLOCK_UNIT_LENGTH: Int       = 6
let PSION_WORD_RECORD_HEADER_LENGTH: Int    = 4
let PSION_WORD_RECORD_TYPES: [String]       = [
    "FILE INFO", "PRINTER CONFIG", "PRINTER DRIVER INFO", "HEADER TEXT", "FOOTER TEXT",
    "STYLE DEFINITION", "EMPHASIS DEFINITION", "BODY TEXT", "STYLE APPLICATION"
]


// MARK: - Global Variables

// CLI argument management
var argIsAValue: Bool       = false
var argType: Int            = -1
var argCount: Int           = 0
var prevArg: String         = ""
var doShowInfo: Bool        = false
var doIncludeHeader: Bool   = false
var doReturnMarkdown: Bool  = false
var haltOnFirstError: Bool  = false
var files: [String]         = []


// MARK: - Functions

/// Convert an individual Word file to plain text.
///
/// - Parameter data:     Data object containing the file bytes.
///                       May be better to just pass a byte array.
/// - Parameter filepath: Absolute path of the target Word file.
///
/// - Returns: A ProcessResult containing the text or an error code.

func processFile(_ data: [UInt8], _ filepath: String) -> ProcessResult {
    
    var textBytes: [UInt8] = []
    var bodyText: String = ""
    var outerText: [String] = ["", ""]
    var styles: [String:PsionWordStyle] = [:]
    var emphases: [String:PsionWordStyle] = [:]
    var blocks: [PsionWordFormatBlock] = []
    var byteIndex: Int = 40
    
    // Check the data preamble (C String of up to 15 chars plus `NUL`)
    let preamble = String.init(cString: data)
    if preamble != "PSIONWPDATAFILE" {
        // TODO Report actual file type
        return ProcessResult.init(text: "Not a Psion Series 3 Word file", errorCode: .badPsionFileType)
    }
    
    if doShowInfo {
        writeToStderr("File \(filepath) is a Psion Series 3 Word document")
    }
    
    // Check for encrypted files
    // NOTE We can't handle these yet as the decode algorithm remains unknown
    if getWordValue(data, 16) == 256 {
        return ProcessResult.init(text: "Word file is encrypted", errorCode: .badFileEncrypted)
    }
    
    // Iterate over the file's bytes to extract the records
    while byteIndex < data.count - PSION_WORD_RECORD_HEADER_LENGTH {
        let recordType: Int = getWordValue(data, byteIndex)
        let recordDataLength: Int = getWordValue(data, byteIndex + 2)
        
        // Won't be included in release builds
        assert(recordType - 1 <= PSION_WORD_RECORD_TYPES.count, "UNKNOWN RECORD TYPE (\(recordType) @ \(String.init(format: "0x%04x", arguments: [byteIndex]))")
        
        if doShowInfo {
            writeToStderr("Record of type \(PSION_WORD_RECORD_TYPES[recordType - 1]) found at offset \(String.init(format: "0x%04x", arguments: [byteIndex])). Size: \(recordDataLength) bytes")
        }
        
        // File record
        // NOTE We don't require this for text conversion
        if recordType == PsionWordRecordType.fileInfo.rawValue && recordDataLength != 10 {
            return ProcessResult(text: "Bad file info record size (\(recordDataLength) not 10 bytes", errorCode: .badRecordLengthFileInfo)
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
            let asciiBytes: [UInt8] = [UInt8](data[byteIndex + PSION_WORD_RECORD_HEADER_LENGTH..<byteIndex + PSION_WORD_RECORD_HEADER_LENGTH + stringLength])
            outerText[index] = String(bytes: asciiBytes, encoding: .ascii) ?? "None"
            
            if doShowInfo {
                writeToStderr("  \(index == 0 ? "Header" : "Footer") text length \(outerText[index].count) byte\(outerText[index].count == 1 ? "" : "s")")
            }

            // Set default on empty string
            if outerText[index].isEmpty {
                outerText[index] = "None"
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
                // Process Psion's special character values
                let characterByte = data[byteIndex + PSION_WORD_RECORD_HEADER_LENGTH + i]
                switch characterByte {
                    case 0:
                        // 0 = paragraph separator
                        textBytes.append(0x0A)
                    case 7:
                        // 7 = unbreakable hyphen
                        textBytes.append(0x2D)
                    case 14:
                        // 14 = soft hyphen (displayed only if used to break line)
                        // NOTE This may be problematic: removing a character may invalidate
                        //      the range values provided in the block format records below.
                        continue
                    case 15:
                        // 15 = unbreakable space
                        textBytes.append(0x20)
                    default:
                        textBytes.append(characterByte)
                }
            }
            
            if doShowInfo {
                writeToStderr("  Processed text length \(textBytes.count) characters\(textBytes.count == 1 ? "" : "s")")
            }
        }
        
        // Style application record
        if recordType == PsionWordRecordType.blockInfo.rawValue {
            var recordByteCount = 0
            var textByteCount = 0
            while recordByteCount < recordDataLength {
                let blockStartByteIndex = byteIndex + PSION_WORD_RECORD_HEADER_LENGTH + recordByteCount
                let length: Int = getWordValue(data, blockStartByteIndex)
                let styleCode: String = String(bytes: [UInt8](data[blockStartByteIndex + 2..<blockStartByteIndex + 4]), encoding: .ascii) ?? ""
                let emphasisCode: String = String(bytes: [UInt8](data[blockStartByteIndex + 4..<blockStartByteIndex + 6]), encoding: .ascii) ?? ""
                
                var block: PsionWordFormatBlock = PsionWordFormatBlock()
                block.styleCode = styleCode
                block.emphasisCode = emphasisCode
                blocks.append(block)
                block.startIndex = textByteCount
                block.endIndex = textByteCount + length
                if block.endIndex > textBytes.count {
                    block.endIndex = textBytes.count
                }
                
                if doShowInfo {
                    if let style: PsionWordStyle = styles[styleCode], let emphasis: PsionWordStyle = emphases[emphasisCode] {
                        writeToStderr("  Text bytes range \(block.startIndex)-\(block.endIndex) has style \(style.name) and emphasis \(emphasis.name)")
                    } else {
                        writeToStderr("  Text bytes range \(block.startIndex)-\(block.endIndex) has style code \(styleCode) and emphasis code \(emphasisCode)")
                    }
                }
                
                textByteCount += length
                recordByteCount += PSION_WORD_BLOCK_UNIT_LENGTH
                
                if textByteCount >= textBytes.count {
                    break
                }
            }
        }
        
        byteIndex += (PSION_WORD_RECORD_HEADER_LENGTH + recordDataLength)
    }
    
    // Process to Markdown if that's required
    if doReturnMarkdown {
        bodyText = convertToMarkdown(textBytes, blocks, styles, emphases)
    } else {
        bodyText = String(bytes: textBytes, encoding: .ascii) ?? "None"
    }
    
    // Add the header and foot if requested
    if doIncludeHeader {
        bodyText = "\(outerText[0])\n\(String(repeating: "-", count: outerText[0].count))\n\(bodyText)\n\(String(repeating: "-", count: outerText[1].count))\n\(outerText[1])"
    }
    
    return ProcessResult(text: bodyText, errorCode: .none)
}


/// Parse a Psion Word Style or Emphasis record.
///
/// - Parameter data:     The word file bytes.
/// - Parameter index:    Index of the record in the data.
/// - Parameter isStyle: `true` if the record holds a Style; `false` if it is an Emphasis.
///
/// - Returns: A PsionWordStyle containing the record's information.

func getStyle(_ data: [UInt8], _ baseIndex: Int, _ isStyle: Bool) -> PsionWordStyle {
    
    let index: Int = baseIndex + 4
    var style: PsionWordStyle = PsionWordStyle()
    
    // Code and name
    style.code = String.init(bytes: data[index..<index + 2], encoding: .ascii) ?? ""
    style.name = String.init(cString: [UInt8](data[index + 2..<index + 18]))
    
    if style.name.isEmpty {
        style.name = "Unknown"
    }
    
    // NOTE Many of these properties are irrelevant to text or even Markdown output, so
    //      I may remove unneeded properties at a later time. Do not rely on their presence!
    
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
            style.tabPositions.append(getWordValue(data, tabIndex))
            
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


/// Read a 16-bit little endian value from the Word file byte store.
///
/// - Parameter data:   The word file bytes.
/// - Parameter index:  The particular byte holding the LSB.
///
/// - Returns: The value as an full integer.

func getWordValue(_ data: [UInt8], _ index: Int) -> Int {
    
    return Int(data[index]) + (Int(data[index + 1]) << 8)
}


/// Convert plain text to Markdown by parsing the block formatting data in
/// conjunction with the document's stored Style and Emphasis data.
///
/// - Parameter rawText:  The basic Ascii text.
/// - Parameter blocks:   The block formatting data extracted from the document.
/// - Parameter styles:   The styles extracted from the document.
/// - Parameter emphases: The emphases extracted from the document.
///
/// - Returns: A Markdown-formatted version of the base text.

func convertToMarkdown(_ rawText: [UInt8], _ blocks: [PsionWordFormatBlock], _ styles: [String:PsionWordStyle], _ emphases: [String:PsionWordStyle]) -> String {
    
    // The raw text is a series of paragraphs separated by NEWLINE.
    // A block will contain a style AND an emphasis over a range of characters, in sequence.
    // Emphasis can be anywhere (ie. character level); styles are paragraph level.
    // Initially we will support STANDARD Styles and Emphases. Only a subset of each require
    // tagging with Markdown (eg. `HA` -> `#`, `BB` -> `**`.
    
    // NOTE This all assumes that the doc only contains standard styles, but what if it has, say,
    //      a headline set to bold text, ie. a custom style? A bold headline in Markdown would be
    //      `# **headline**, but this would not comprise separate blocks. So we need to set the `#`
    //      on the paragraph start and (separately) the `**` at the start and end of the actual text.
    
    var markdown: String = ""
    var paraStyleSet: Bool = false
    var textEndTag: String = ""
    
    // Blocks are in stored in sequence, so we just need to iterate over them
    for block in blocks {
        // Create Range values for the section of the raw text that we are formatting
        //let startIndex = rawText.index(rawText.startIndex, offsetBy: block.startIndex)
        //let endIndex = rawText.index(rawText.startIndex, offsetBy: block.endIndex)
        
        // The
        var tag: String = ""
        var isEmphasisTag: Bool = false
        
        if !paraStyleSet {
            // Starting a new para, so the Style should not change
            paraStyleSet = true
            
            // Look for
            switch block.styleCode {
                case "HA":
                    tag = "# "
                case "HB":
                    tag = "### "
                case "BL":
                    // Bullet list
                    tag = "- "
                default:
                    if block.styleCode != "NN" {
                        if let style: PsionWordStyle = styles[block.styleCode] {
                            if style.bold {
                                tag += "**"
                                textEndTag = "**"
                            } else if style.italic {
                                textEndTag = "*"
                            }
                        }
                    }
            }
        }
        
        // Look for in-paragraph tags.
        // NOTE BB (Bold) and II (Italic) are the only ones relevant to Markdown
        if tag == "" {
            switch block.emphasisCode {
                case "BB":
                    tag = "**"
                    isEmphasisTag = true
                case "II":
                    tag = "*"
                    isEmphasisTag = true
                default:
                    tag = ""
            }
        }
        
        // Add the tagged text to the string store. We only duplicate the tag at the end
        // of the block if it is a character-level tag, ie. an Emphasis
        let addition = String(bytes: rawText[block.startIndex..<block.endIndex], encoding: .ascii) ?? ""
        markdown += (tag + addition + (isEmphasisTag ? tag :""))
        
        // Check if we've come to the end of a paragraph. If so, reset the flag
        if addition.hasSuffix("\n") {
            paraStyleSet = false
            
            // NOTE This tag should really come BEFORE the NEWLINE...
            if !textEndTag.isEmpty {
                markdown += textEndTag
                textEndTag = ""
            }
        }
    }
    
    return markdown
}


/// Convert a user-supplied possibly partial path to an absolute path.
///
/// - Parameter relativePath: A possible relative path.
///
/// - Returns: The absolute path.

func getFullPath(_ relativePath: String) -> String {

    // Standardise the path as best as we can (this covers most cases)
    var absolutePath: String = (relativePath as NSString).standardizingPath

    // Check for a unresolved relative path -- and if it is one, resolve it
    // NOTE This includes raw filenames
    if (absolutePath as NSString).contains("..") || !(absolutePath as NSString).hasPrefix("/") {
        absolutePath = processRelativePath(absolutePath)
    }

    // Return the absolute path
    return absolutePath
}


/// Convert a relative path to an absolute path.
///
/// - Parameter relativePath: A relative path.
///
/// - Returns: The absolute path.

func processRelativePath(_ relativePath: String) -> String {

    // Add the basepath (the current working directory of the call) to the
    // supplied relative path - and then resolve it
    let absolutePath = FileManager.default.currentDirectoryPath + "/" + relativePath
    return (absolutePath as NSString).standardizingPath
}


/// Convert a relative path to an absolute path.
///
/// - Parameter absolutePath: An absolute path to a file or directory.
///
/// - Returns: `true` of the path references an existing directory, otherwise `false`.

func doesPathReferenceDirectory(_ absolutePath: String) -> Bool {
    
    let fileURL = URL.init(fileURLWithPath: absolutePath)
    guard let value = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]) else { return false }
    return value.isDirectory!
}


/// Load a named file's contents into Data.
///
/// - Parameter filePath: An absolute path to a file.
///
/// - Returns: The file data, or an empty array on error.

func getFileContents(_ filepath: String) -> [UInt8] {
    
    let fileURL: URL = URL.init(fileURLWithPath: filepath)
    guard let data = try? Data(contentsOf: fileURL) else { return [] }
    return data.bytes
}


/// Generic error display routine that also quits the app.
///
/// - Parameter message: The error message text.
/// - Parameter code:    The error code (and app exit code).

func reportErrorAndExit(_ message: String, _ code: Int32 = EXIT_FAILURE) {

    writeToStderr(RED + BOLD + "ERROR" + RESET + " " + message + " -- exiting")
    dss.cancel()
    exit(code)
}


/// Generic error display routine that does not quit the app.
///
/// - Parameter message: The error message text.

func reportError(_ message: String) {

    writeToStderr(RED + BOLD + "ERROR" + RESET + " " + message)
}


/// Generic warning display routine.
///
/// - Parameter message: The warning's text.

func reportWarning(_ message: String) {

    writeToStderr(YELLOW + BOLD + "WARNING" + RESET + " " + message)
}


/// Write errors and other messages to `stderr`.
///
/// - Parameter message: The text to emit.

func writeToStderr(_ message: String) {

    writeOut(message, STD_ERR)
}


/// Write output and other messages to `stdout`.
///
/// - Parameter message: The text to emit.

func writeToStdout(_ message: String) {

    writeOut(message, STD_OUT)
}


/// Write output to any standard file.
///
/// - Parameter message:          The text to emit.
/// - Parameter targetFileHandle: Where to emit the message

func writeOut(_ message: String, _ targetFileHandle: FileHandle) {

    let messageAsString = message + "\r\n"
    if let messageAsData: Data = messageAsString.data(using: .utf8) {
        targetFileHandle.write(messageAsData)
    }
}


/// Display the help text.

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


/// Display the app version.

func showVersion() {

    showHeader()
    writeToStdout("Copyright © 2024, Tony Smith (@smittytone).\r\nSource code available under the MIT licence.")
}


/// Display the app's version number.

func showHeader() {
    
#if os(macOS)
    let version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
    let build: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
    let name:String = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as! String
    writeToStdout("\(name) \(version) (\(build))")
#else
    // Linux output
    // TODO Automate based on build settings
    writeToStdout("word2text \(LINUX_VERSION) (\(LINUX_BUILD))")
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

    // Ignore the first command line argument
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
        case "-m":
            fallthrough
        case "--markdown":
            doReturnMarkdown = true
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

// Pre-process the file list looking for directories.
// We also take the time to rationalise the paths of passed files
var finalFiles: [String] = []
for filepath in files {
    let absolutePath: String = getFullPath(filepath)
    if doesPathReferenceDirectory(absolutePath) {
        // References a directory so get the file list
        let directoryContentsEnumerator = FileManager.default.enumerator(atPath: absolutePath)
        while let file = directoryContentsEnumerator?.nextObject() as? String {
            if file.hasSuffix(".WRD") {
                finalFiles.append(absolutePath + "/" + file)
            }
        }
    } else {
        finalFiles.append(absolutePath)
    }
}

// Convert the file(s) to text
let outputToFiles: Bool = (finalFiles.count > 1)
for filepath in finalFiles {
    let data: [UInt8] = getFileContents(filepath)
    let result: ProcessResult = !data.isEmpty 
        ? processFile(data, filepath) 
        : ProcessResult.init(text: "file not found", errorCode: .badFile)
    
    // Handle the outcome of processing
    if result.errorCode != .none {
        // Report the error and, if required, bail
        if haltOnFirstError {
            reportErrorAndExit("File \(filepath) could not be processed: \(result.text)", Int32(result.errorCode.rawValue))
        } else {
            reportWarning("File \(filepath) could not be processed: \(result.text)")
        }
    } else {
        // Report the processed text
        if !outputToFiles {
            // Output processed text to STDOUT so it's available for piping or redirection
            if doShowInfo {
                writeToStderr("File \(filepath) processed")
            }
            
            writeToStdout(result.text)
        } else {
            // Output to a file: generate the name and extension...
            var outFilepath: String = (filepath as NSString).deletingPathExtension
            outFilepath += (doReturnMarkdown ? ".md" : ".txt")
            
            // ...and attempt to write it out
            do {
                try result.text.write(toFile: outFilepath, atomically: true, encoding: .utf8)
                if doShowInfo {
                    writeToStderr("File \(filepath) processed to \(outFilepath)")
                }
            } catch {
                reportWarning("File \(outFilepath) could not be processed: writing to stdout instead")
                writeToStdout(result.text)
            }
        }
    }
}

dss.cancel()
exit(0)
