/*
    word2text
    psion_word.swift

    Copyright © 2026 Tony Smith. All rights reserved.

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


public struct PsionWord {

    /**
     Convert an individual Word file to plain text.

     DEPRECATED--Use `decodeWordFile()` instead.

     - Parameters:
        - data:     Data object containing the file bytes.
                    May be better to just pass a byte array.
        - filepath: Absolute path of the target Word file. Used for logging.
        - settings: File conversion parameters.

     - Returns: A Result containing the text (success) or a ProcessError embedding the error code (failure).
     */
    static public func processFile(_ data: ArraySlice<UInt8>, _ filepath: String, _ settings: ProcessSettings) -> Result<String, ProcessError> {

        return decodeWordFile(data, filepath, settings)

        /*
        var bodyText = ""
        var byteIndex = 40
        var textBytes: [UInt8] = []
        var outerText: [String] = ["", ""]
        var styles: [String:PsionWordStyle] = [:]
        var emphases: [String:PsionWordStyle] = [:]
        var blocks: [PsionWordFormatBlock] = []

        // Check minimum file size: enough bytes to at least check the preamble
        if data.count < 16 {
            return .failure(ProcessError(code: .badPsionFileType))
        }

        // Check the data preamble (C String of up to 15 chars plus `NUL`)
        let preamble = String(decoding: data[0..<15], as: UTF8.self)
        if preamble != "PSIONWPDATAFILE" || data.count < 40 {
            // TODO Report actual file type
            return .failure(ProcessError(code: .badPsionFileType))
        }

        if settings.showInfo {
            log("File \(filepath) is a Psion Series 3 Word document")
        }

        // Check for encrypted files: look at file bytes 16 and 17
        // NOTE We can't handle these yet as the decode algorithm remains unknown
        if getWordValue(data[16..<18]) == 256 {
            return .failure(ProcessError(code: .badFileEncrypted))
        }

        // Iterate over the file's bytes to extract the records
        var recordCounter: UInt16 = 0
        while byteIndex < data.count - PsionWordConstants.RecordHeaderLength {
            // Get the 16-bit record type and 16-bit data length
            let recordType = PsionWordRecordType(rawValue: getWordValue(data[byteIndex..<byteIndex + 2])) ?? .unknown
            let recordDataLength: Int = getWordValue(data[byteIndex + 2..<byteIndex + 4])

            // Move index to start of record
            byteIndex += PsionWordConstants.RecordHeaderLength

            if settings.showInfo {
                log("Record of type \(PsionWordConstants.RecordTypes[recordType.rawValue - 1]) found at offset \(String(format: "0x%04x", arguments: [byteIndex])). Size: \(recordDataLength) bytes")
            }

            // Process the current record
            switch recordType {
                case .fileInfo:
                    // We don't care about this beyond its size
                    if recordDataLength != 10 {
                        var error = ProcessError(code: .badRecordLengthFileInfo)
                        error.text = "Bad file info record size (\(recordDataLength) not 10 bytes)"
                        return .failure(error)
                    }
                case .printerConfig:
                    // We don't care about this beyond its size
                    if recordDataLength != 58 {
                        var error = ProcessError(code: .badRecordLengthPrinterConfig)
                        error.text = "Bad printer config record size (\(recordDataLength) not 58 bytes)"
                        return .failure(error)
                    }
                case .printerDriver:
                    // We don't care about this
                    break
                case .headerText:
                    fallthrough
                case .footerText:
                    // Index in strings store is 0 for header, 1 for footer
                    let index = recordType.rawValue - PsionWordRecordType.headerText.rawValue
                    outerText[index] = getOuterText(data[byteIndex..<byteIndex + recordDataLength - 1], index == 0, settings)
                case .styleDefinition:
                    // Check the fixed size
                    if recordDataLength != 80 {
                        var error = ProcessError(code: .badRecordLengthStyleDefinition)
                        error.text = "Bad style definition record size (\(recordDataLength)) not 80 bytes)"
                        return .failure(error)
                    }

                    let style = getStyle(data[byteIndex..<byteIndex + 80], true, settings)
                    styles[style.code] = style
                case .emphasisDefinition:
                    // Check the fixed size
                    if recordDataLength != 28 {
                        var error = ProcessError(code: .badRecordLengthStyleDefinition)
                        error.text = "Bad emphasis definition record size (\(recordDataLength)) not 28 bytes"
                        return .failure(error)
                    }

                    let emphasis = getStyle(data[byteIndex..<byteIndex + 28], false, settings)
                    emphases[emphasis.code] = emphasis
                case .bodyText:
                    textBytes = getBodyText(data[byteIndex..<byteIndex + recordDataLength], settings)
                case .blockInfo:
                    blocks = getStyleBlocks(data[byteIndex..<data.endIndex], textBytes.count, settings)
                case .unknown:
                    var error = ProcessError(code: .badRecordType)
                    error.text = "Bad Word file record type (\(recordType.rawValue) at \(String(format: "0x%04x", arguments: [byteIndex]))"
                    return .failure(error)
            }

            recordCounter |= (1 << recordType.rawValue)
            byteIndex += recordDataLength
        }

        // Check we have at least one of every record
        if recordCounter != 1022 {
            // Processing ended, but without a complete set of records
            return .failure(ProcessError(code: .badFileMissingRecords))
        }

        // Process to Markdown if that's required
        if settings.returnMarkdown {
            bodyText = convertToMarkdown(textBytes, blocks, styles, emphases, settings)
        } else {
            // Psion Series 3a character set is IBM CP 850. The closest Swift supports is Windows 1252,
            // but conversion to UTF-8 using this encoding sometimes fails. So we trap this and try to
            // convert using the older NSString mechanism
            bodyText = convertText(textBytes, settings)
        }

        // Add the header and foot if requested
        if settings.includeHeader {
            // FROM 0.1.3
            // Do different delimiters for markdown output
            if settings.returnMarkdown {
                var longest = greater(outerText[0][...], outerText[1][...])
                longest = greater(longest[...], "****")
                let stars = String(repeating: "*", count: longest.count)
                bodyText = "\(outerText[0])\n\(stars)\n\(bodyText)\n\(stars)\n\(outerText[1])"
            } else {
                bodyText = "\(outerText[0])\n\(String(repeating: "*", count: outerText[0].count))\n\(bodyText)\n\(String(repeating: "*", count: outerText[1].count))\n\(outerText[1])"
            }
        }

        return .success(bodyText)
         */
    }


    /**
     Variation of the main `processFile()` to support passing in a Data object.
     */
    static public func processFile(_ data: Data, _ settings: ProcessSettings? = nil, _ filepath: String = "") -> Result<String, ProcessError> {

        let bytes = [UInt8](data)
        return decodeWordFile(bytes[...], filepath, settings == nil ? ProcessSettings() : settings!)
        //return processFile(bytes[...], filepath, settings == nil ? ProcessSettings() : settings!)
    }


    /**
     Parse a Psion Word Style or Emphasis record.

     - Parameters:
        - data:     A slice of the word file bytes.
        - isStyle: `true` if the record holds a Style; `false` if it is an Emphasis.
        - settings: File conversion parameters.

     - Returns: A PsionWordStyle containing the record's information.
     */
    internal static func getStyle(_ data: ArraySlice<UInt8>, _ isStyle: Bool, _ settings: ProcessSettings) -> PsionWordStyle {

        var style: PsionWordStyle = PsionWordStyle()

        // Code and name
        let index = data.startIndex
        style.code = String(bytes: data[index..<index + 2], encoding: .windowsCP1252) ?? ""
        style.name = String(decoding: data[index + 2..<index + 18], as: UTF8.self)
        let range: Range<String.Index> = style.name.range(of: "\0")!    // Find the first nul
        style.name = String(style.name[..<range.lowerBound])

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
        style.fontCode = getWordValue(data[index + 20..<index + 22])
        style.fontSize = getWordValue(data[index + 24..<index + 26])

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
            if settings.showInfo {
                log("  Emphasis code: \(style.code) (\(style.name))")
            }

            return style
        }

        // Indents
        style.leftIndent = getWordValue(data[index + 28..<index + 30])
        style.rightIndent = getWordValue(data[index + 30..<index + 32])
        style.firstIdent = getWordValue(data[index + 32..<index + 34])

        // Text alignment
        let alignValue: Int = getWordValue(data[index + 34..<index + 36])
        style.alignment = PsionWordAlignment(rawValue: alignValue) ?? .left

        // Spacing values
        style.lineSpacing = getWordValue(data[index + 36..<index + 38])
        style.spaceAbovePara = getWordValue(data[index + 38..<index + 40])
        style.spaceBelowPara = getWordValue(data[index + 40..<index + 42])
        style.spacing.set(data[index + 42])

        // Outline level
        style.outlineLevel = getWordValue(data[index + 44..<index + 46])

        // Tabs
        let tabCount: Int = getWordValue(data[index + 46..<index + 48])
        if tabCount > 0 {
            var tabIndex: Int = index + 48
            for _ in 0..<tabCount {
                style.tabPositions.append(getWordValue(data[tabIndex..<tabIndex + 2]))
                let tabType: Int = getWordValue(data[tabIndex + 2..<tabIndex + 4])
                style.tabTypes.append(PsionWordTabType(rawValue: tabType) ?? .left)
                tabIndex += 4
            }
        }

        if settings.showInfo {
            log("  Style code: \(style.code) (\(style.name))")
        }

        return style
    }


    /**
     Read a C string of known length from the word file byte store

     - Parameters:
        - data:     A slice of the word file bytes.
        - isHeader: `true` if the record contains header text, otherwise `false`.
        - settings: File conversion parameters.

     - Returns: The text as a string.
     */
    internal static func getOuterText(_ data: ArraySlice<UInt8>, _ isHeader: Bool, _ settings: ProcessSettings) -> String {

        var outerText: String = ""
        let rawLength = data.endIndex - data.startIndex
        if rawLength > 1 {
            // There's at least one character in addition to the C String NUL terminator
            // so remove the NUL (plus any whitespace and newlines at either end)
            outerText = String(decoding: data[..<(data.endIndex - 1)], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // String is empty (NUL only)?
        outerText = outerText.count > 0 ? outerText : (isHeader ? "No header" : "No footer")

        if settings.showInfo {
            log("  \(isHeader ? "Header" : "Footer") text length \(rawLength - 1) byte\(rawLength == 1 ? "" : "s")")
        }

        return outerText
    }


    /**
     Generate a String from the file's text bytes.

     - Parameters:
        - textBytes: The bytes from the Psion file.
        - settings:  File conversion parameters.

     - Returns: The text as a String
     */
    private static func convertText(_ textBytes: [UInt8], _ settings: ProcessSettings) -> String {

        guard textBytes.count > 0 else { return "" }

        if let text = String(bytes: textBytes, encoding: .windowsCP1252) {
            // Swift String conversion works - return the result
            return text
        } else {
            // Calculate the number of 'bad' characters and their locations
            var count = 0
            var index = 0
            var badChars: [Int: UInt8] = [:]
            for byte in textBytes {
                if byte > 127 {
                    count += 1
                    badChars[index] = byte
                }

                index += 1
            }

            // Issue a warning no matter what
            if count > 0 {
                warning("File contains \(count) invalid Windows CP 1252 character\(count == 1 ? "" : "s")")
            }

            // If the user has selected verbose mode, output the list of 'bad' characters
            if settings.showInfo {
                var msg = ""
                for (idx, badChar) in badChars {
                    msg += String(format: "%d @ %d ", badChar, idx)
                }

                warning(msg)
            }

            // Now do the secondary conversion
            // NOTE Encoding set this way to mitigate Linux build error
#if os(macOS)
            let encoding: UInt = NSWindowsCP1252StringEncoding
#elseif os(Linux)
            let encoding: UInt = 12
#endif

            // This works even when the String conversion doesn't!
            if let text: NSString = NSString(bytes: textBytes, length: textBytes.count, encoding: encoding) {
                return String(text)
            }
        }

        return ""
    }


    /**
     Read body text known length from the word file byte store.

     - Parameters:
        - data:     A slice of the word file bytes containing the body text.
        - settings: File conversion parameters.

     - Returns: The text as a byte array.
     */
    internal static func getBodyText(_ data: ArraySlice<UInt8>, _ settings: ProcessSettings) -> [UInt8] {

        var textBytes: [UInt8] = []
        for i in 0..<(data.endIndex - data.startIndex) {
            // Process Psion's special character values
            let characterByte = data[data.startIndex + i]
            if characterByte > 127 {
                textBytes.append(charSwap(characterByte))
            } else {
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
        }

        if settings.showInfo {
            log("  Processed text length \(textBytes.count) character\(textBytes.count == 1 ? "" : "s")")
        }

        return textBytes
    }


    /**
     Parse a Psion Word block styling record and extract the formatting blocks.

     - Parameters:
        - data:       A slice of the Word file bytes containing the block formatting data.
        - textLength: The number of bytes in the corresponding body text.
        - settings:   File conversion parameters.

     - Returns: An array of internal style records.
     */
    internal static func getStyleBlocks(_ data: ArraySlice<UInt8>, _ textLength: Int, _ settings: ProcessSettings) -> [PsionWordFormatBlock] {

        var blocks: [PsionWordFormatBlock] = []
        var recordByteCount = 0
        var dataByteCount = 0
        let length = data.endIndex - data.startIndex
        while recordByteCount < length {
            let blockStartByteIndex = data.startIndex + recordByteCount
            let blockLength = getWordValue(data[blockStartByteIndex..<blockStartByteIndex + 2])
            let styleCode = decodePsionText(data[blockStartByteIndex + 2..<blockStartByteIndex + 4])
            let emphasisCode = decodePsionText(data[blockStartByteIndex + 4..<blockStartByteIndex + 6])

            var block = PsionWordFormatBlock()
            block.styleCode = styleCode
            block.emphasisCode = emphasisCode
            block.startIndex = dataByteCount
            block.endIndex = dataByteCount + blockLength - 1
            if block.endIndex > textLength {
                block.endIndex = textLength
            }

            blocks.append(block)

            if settings.showInfo {
                log("  Text bytes range \(block.startIndex)-\(block.endIndex) has style code \(styleCode) and emphasis code \(emphasisCode)")
            }

            dataByteCount += blockLength
            recordByteCount += PsionWordConstants.BlockUnitLength

            if dataByteCount >= textLength {
                break
            }
        }

        return blocks
    }

    internal static func getStyleBlocks2(_ data: ArraySlice<UInt8>, _ textLength: Int, _ settings: ProcessSettings) -> [PsionWordFormatBlock] {

        var blocks: [PsionWordFormatBlock] = []
        var recordIndex = data.startIndex
        var textIndex = 0

        // Stop when the text is used up, or when there isn't a whole block unit left to read
        while textIndex < textLength && recordIndex + PsionWordConstants.BlockUnitLength <= data.endIndex {
            let blockLength = getWordValue(data[recordIndex..<recordIndex + 2])
            let styleCode = decodePsionText(data[recordIndex + 2..<recordIndex + 4])
            let emphasisCode = decodePsionText(data[recordIndex + 4..<recordIndex + 6])
            recordIndex += PsionWordConstants.BlockUnitLength

            // Skip empty blocks: they cover no text
            guard blockLength > 0 else {
                continue
            }

            // NOTE The loop condition and the guard ensure that, for every block,
            //      0 <= startIndex <= endIndex <= textLength - 1
            var block = PsionWordFormatBlock()
            block.styleCode = styleCode
            block.emphasisCode = emphasisCode
            block.startIndex = textIndex
            block.endIndex = min(textIndex + blockLength, textLength) - 1
            blocks.append(block)

            if settings.showInfo {
                log("  Text bytes range \(block.startIndex)-\(block.endIndex) has style code \(styleCode) and emphasis code \(emphasisCode)")
            }

            textIndex += blockLength
        }

        return blocks
    }


    /**
     Read a 16-bit little endian value from the Word file byte store.

     - Parameters:
        - data:  Two-byte slice of the word file bytes.

     - Returns: The value as an (unsigned) integer, or -1 on error.
     */
    internal static func getWordValue(_ data: ArraySlice<UInt8>) -> Int {

        // Make sure data slice is correctly dimensioned
        if data.isEmpty || data.count == 1 {
            return -1
        }

        return Int(data[data.startIndex]) + (Int(data[data.startIndex + 1]) << 8)
    }


    /**
     Convert plain text to Markdown by parsing the block formatting data in
     conjunction with the document's stored Style and Emphasis data.

     The raw text is a series of paragraphs separated by NEWLINE.
     A block will contain a style AND an emphasis over a range of characters, in sequence.
     Emphasis can be anywhere (ie. character level); styles are paragraph level.
     Initially we will support STANDARD Styles and Emphases. Only a subset of each require
     tagging with Markdown (eg. `HA` -> `#`, `BB` -> `**`.

     - Note This all assumes that the doc only contains standard styles, but what if it has, say,
            a headline set to bold text, ie. a custom style? A bold headline in Markdown would be
            `# **headline**, but this would not comprise separate blocks. So we need to set the `#`
            on the paragraph start and (separately) the `**` at the start and end of the actual text.

     - Parameters:
         - rawText:  The basic Ascii text.
         - blocks:   The block formatting data extracted from the document.
         - styles:   The styles extracted from the document.
         - emphases: The emphases extracted from the document.
         - settings: File conversion parameters.

     - Returns: A Markdown-formatted version of the base text.
     */
    private static func convertToMarkdown(_ rawText: [UInt8], _ blocks: [PsionWordFormatBlock], _ styles: [String:PsionWordStyle], _ emphases: [String:PsionWordStyle], _ settings: ProcessSettings) -> String {

        var markdown: String = ""
        var paraStyleSet: Bool = false
        var textEndTag: String = ""

        // FROM 0.4.0
        // Completed paragraphs and their style codes, joined with blank lines at the end
        var paragraphs: [(text: String, styleCode: String)] = []
        var paraStyleCode: String = "BT"

        // FROM 0.4.1
        // Widths of the Markdown list markers (eg. `* `, `12. `) of the open list levels, used to
        // indent nested items so they sit under their parent's text
        var listMarkerWidths: [Int] = []

        // Is a CP 1252 byte a letter or digit, ie. can't be a bullet character?
        func isAlphanumeric(_ byte: UInt8) -> Bool {
            switch byte {
                case 0x30...0x39, 0x41...0x5A, 0x61...0x7A:
                    return true
                case 0xC0...0xFF:
                    return byte != 0xD7 && byte != 0xF7
                default:
                    return false
            }
        }

        // Blocks are in stored in sequence, so we just need to iterate over them
        for block in blocks {
            // REVISED 0.4.0 Paragraph (Style) and character (Emphasis) tags are now tracked separately,
            //               so emphasis on a paragraph's first block is no longer lost
            var styleTag: String = ""

            // FROM 0.4.1 Where this block's text starts: list items skip their bullet or number
            var textStartIndex = block.startIndex

            if !paraStyleSet {
                // Starting a new para, so the Style should not change
                paraStyleSet = true
                paraStyleCode = block.styleCode

                if PsionWordConstants.listInfo(block.styleCode) == nil {
                    listMarkerWidths = []
                }

                switch block.styleCode {
                    case "HA", "HB", "HC", "HD", "HE", "HF":
                        // FROM 0.4.0 Headings A-F map to Markdown levels 1-6
                        let level = Int(block.styleCode.unicodeScalars.last!.value) - Int(("A" as Unicode.Scalar).value) + 1
                        styleTag = String(repeating: "#", count: level) + " "
                    case let code where PsionWordConstants.listInfo(code) != nil:
                        // FROM 0.4.1 Bulleted or numbered list item, at any level
                        let list = PsionWordConstants.listInfo(code)!
                        let start = block.startIndex
                        var marker = "* "
                        var prefixEnd = start
                        if list.isBullet {
                            // Skip a leading bullet character and tab, eg. `·<TAB>`
                            if start + 1 < rawText.count && rawText[start + 1] == 0x09
                                && rawText[start] != 0x20 && rawText[start] != 0x09 && !isAlphanumeric(rawText[start]) {
                                prefixEnd = start + 2
                            }
                        } else {
                            // Take the number from a leading `12.<TAB>` (or `12. `), and skip it
                            var digitEnd = start
                            while digitEnd < rawText.count && rawText[digitEnd] >= 0x30 && rawText[digitEnd] <= 0x39 {
                                digitEnd += 1
                            }

                            if digitEnd > start && digitEnd + 1 < rawText.count
                                && (rawText[digitEnd] == 0x2E || rawText[digitEnd] == 0x29)
                                && (rawText[digitEnd + 1] == 0x09 || rawText[digitEnd + 1] == 0x20) {
                                marker = String(decoding: rawText[start..<digitEnd], as: UTF8.self) + ". "
                                prefixEnd = digitEnd + 2
                            } else {
                                // No number to use: output the text as it is
                                marker = ""
                            }
                        }

                        // The prefix should be in the first block, but don't run past it
                        textStartIndex = min(prefixEnd, block.endIndex + 1)

                        // Indent by the widths of the parent levels' markers
                        let parentLevels = list.level - 1
                        while listMarkerWidths.count < parentLevels {
                            listMarkerWidths.append(2)
                        }

                        listMarkerWidths = Array(listMarkerWidths.prefix(parentLevels))
                        let indent = listMarkerWidths.reduce(0, +)
                        listMarkerWidths.append(marker.isEmpty ? 2 : marker.count)
                        styleTag = String(repeating: " ", count: indent) + marker
                    case "BT":
                        // Body text
                        break
                    default:
                        // NOTE User-defined style may have any name
                        if let style: PsionWordStyle = styles[block.styleCode] {
                            // Use font size
                            var size = (Int(0.05 * Double(style.fontSize)) >> 1)
                            if size > 10 {
                                size = 10
                            }

                            // Ignore sizes below 7 (13pt)
                            if size > 6 {
                                size = 10 - size + 1
                                styleTag = String(repeating: "#", count: size)
                                styleTag += " "
                            }

                            if style.bold {
                                styleTag += "**"
                                textEndTag = "**"
                            } else if style.italic {
                                styleTag += "*"
                                textEndTag = "*"
                            }
                        }
                }
            }

            // Look for in-paragraph tags.
            // NOTE BB (Bold), II (Italic) and BI (Bold italic) are the only ones relevant to Markdown
            var emphasisTag: String
            switch block.emphasisCode {
                case "BB":
                    emphasisTag = "**"
                case "II":
                    emphasisTag = "*"
                case "BI":
                    emphasisTag = "***"
                default:
                    emphasisTag = ""
            }

            // FROM 0.4.0
            // This feels hacky -- need to track down the issue that's causing
            // me to need to add this...
            var endIndex = block.endIndex
            if block.endIndex >= rawText.count {
                endIndex -= 1
            }

            // Add the tagged text to the string store
            var addition = textStartIndex <= endIndex ? convertText([UInt8](rawText[textStartIndex...endIndex]), settings) : ""


            // Check if we've come to the end of a paragraph - but not empty ones
            if addition.hasSuffix("\n") && addition.count > 1 {
                // Remove the NEWLINE
                _ = addition.removeLast()
                markdown += (styleTag + emphasisTag + addition + emphasisTag)

                if !textEndTag.isEmpty {
                    markdown += textEndTag
                    textEndTag = ""
                }

                // Store the completed paragraph
                paragraphs.append((markdown, paraStyleCode))
                markdown = ""

                // Reset the paragraph found flag
                paraStyleSet = false
            } else if addition.hasSuffix("\n") && addition.count ==  1 {
                // Close any style-level tag opened by an earlier block in this paragraph.
                // Empty paragraphs (Psion spacing) are dropped: blank lines are added below
                if !markdown.isEmpty {
                    paragraphs.append((markdown + textEndTag, paraStyleCode))
                    markdown = ""
                }

                textEndTag = ""
                paraStyleSet = false
            } else {
                // Just add the tags
                markdown += (styleTag + emphasisTag + addition + emphasisTag)
            }
        }

        // Catch any final paragraph that lacks a separator
        if !markdown.isEmpty {
            paragraphs.append((markdown + textEndTag, paraStyleCode))
        }

        // Join the paragraphs with blank lines, except between consecutive items
        // of the same list, which are kept together as a single Markdown list
        var output: String = ""
        for (index, paragraph) in paragraphs.enumerated() {
            if index > 0 {
                // REVISED 0.4.1 Items of the same list, including nested items, stay together.
                //               Only adjacent top-level items of different list types are separated
                var sameList = false
                if let previousList = PsionWordConstants.listInfo(paragraphs[index - 1].styleCode),
                   let currentList = PsionWordConstants.listInfo(paragraph.styleCode) {
                    sameList = previousList.level > 1 || currentList.level > 1 || previousList.isBullet == currentList.isBullet
                }

                output += sameList ? "\n" : "\n\n"
            }

            output += paragraph.text
        }

        return output.isEmpty ? output : output + "\n"
    }




    static public func decodeWordFile(_ data: ArraySlice<UInt8>, _ filepath: String, _ settings: ProcessSettings) -> Result<String, ProcessError> {

        var bodyText = ""
        var byteIndex = 40
        var textBytes: [UInt8] = []
        var outerText: [String] = ["", ""]
        var styles: [String:PsionWordStyle] = [:]
        var emphases: [String:PsionWordStyle] = [:]
        var blocks: [PsionWordFormatBlock] = []
        var document = Document()

        // Check minimum file size: enough bytes to at least check the preamble
        if data.count < PsionWordConstants.PreambleLength {
            return .failure(ProcessError(code: .badPsionFileType))
        }

        // Check the data preamble (C String of up to 15 chars plus `NUL`)
        let preamble = String(decoding: data[0..<15], as: UTF8.self)
        if preamble != "PSIONWPDATAFILE" || data.count < PsionWordConstants.HeaderLength {
            // TODO Report actual file type
            return .failure(ProcessError(code: .badPsionFileType))
        }

        if settings.showInfo {
            log("File \(filepath) is a Psion Series 3 Word document")
        }

        // Check for encrypted files: look at file bytes 16 and 17
        // NOTE We can't handle these yet as the decode algorithm remains unknown
        if getWordValue(data[16..<18]) == PsionWordConstants.EncryptionMarker {
            return .failure(ProcessError(code: .badFileEncrypted))
        }

        // Iterate over the file's bytes to extract the records
        var recordCounter: UInt16 = 0
        while byteIndex < data.count - PsionWordConstants.RecordHeaderLength {
            // Get the 16-bit record type and 16-bit data length
            let recordType = PsionWordRecordType(rawValue: getWordValue(data[byteIndex..<byteIndex + 2])) ?? .unknown
            let recordDataLength: Int = getWordValue(data[byteIndex + 2..<byteIndex + 4])

            // Move index to start of record
            byteIndex += PsionWordConstants.RecordHeaderLength

            if settings.showInfo {
                log("Record of type \(PsionWordConstants.RecordTypes[recordType.rawValue - 1]) found at offset \(String(format: "0x%04x", arguments: [byteIndex])). Size: \(recordDataLength) bytes")
            }

            // Process the current record
            switch recordType {
                case .fileInfo:
                    // We don't care about this beyond its size
                    if recordDataLength != PsionWordConstants.FileInfoRecordLength {
                        var error = ProcessError(code: .badRecordLengthFileInfo)
                        error.text = "Bad file info record size (\(recordDataLength) not \(PsionWordConstants.FileInfoRecordLength) bytes)"
                        return .failure(error)
                    }
                case .printerConfig:
                    // We don't care about this beyond its size
                    if recordDataLength != PsionWordConstants.PrinterConfigRecordLength {
                        var error = ProcessError(code: .badRecordLengthPrinterConfig)
                        error.text = "Bad printer config record size (\(recordDataLength) not \(PsionWordConstants.PrinterConfigRecordLength) bytes)"
                        return .failure(error)
                    }
                case .printerDriver:
                    // We don't care about this
                    break
                case .headerText:
                    fallthrough
                case .footerText:
                    // Index in strings store is 0 for header, 1 for footer
                    let index = recordType.rawValue - PsionWordRecordType.headerText.rawValue
                    outerText[index] = decodeOuterText(data[byteIndex..<byteIndex + recordDataLength], index == 0, settings)
                case .styleDefinition:
                    // Check the fixed size
                    if recordDataLength != PsionWordConstants.StyleRecordLength {
                        var error = ProcessError(code: .badRecordLengthStyleDefinition)
                        error.text = "Bad style definition record size (\(recordDataLength) not \(PsionWordConstants.StyleRecordLength) bytes)"
                        return .failure(error)
                    }

                    let style = getStyle(data[byteIndex..<byteIndex + PsionWordConstants.StyleRecordLength], true, settings)
                    styles[style.code] = style
                case .emphasisDefinition:
                    // Check the fixed size
                    if recordDataLength != PsionWordConstants.EmphasisRecordLength {
                        var error = ProcessError(code: .badRecordLengthStyleDefinition)
                        error.text = "Bad emphasis definition record size (\(recordDataLength)) not \(PsionWordConstants.EmphasisRecordLength) bytes"
                        return .failure(error)
                    }

                    let emphasis = getStyle(data[byteIndex..<byteIndex + PsionWordConstants.EmphasisRecordLength], false, settings)
                    emphases[emphasis.code] = emphasis
                case .bodyText:
                    // Keep the raw CP 850 bytes: they are decoded per span in `createDoc()`.
                    // NOTE No bytes are removed or replaced here, so the block ranges remain valid
                    textBytes = Array(data[byteIndex..<byteIndex + recordDataLength])
                    if settings.showInfo {
                        log("  Body text length \(textBytes.count) byte\(textBytes.count == 1 ? "" : "s")")
                    }
                case .blockInfo:
                    blocks = getStyleBlocks2(data[byteIndex..<data.endIndex], textBytes.count, settings)
                    // Set each block's style and emphasis according to the codes.
                    // NOTE We loop this way so we don't change copy-on-write array members.
                    for index in blocks.indices {
                        blocks[index].style = styles[blocks[index].styleCode]
                        blocks[index].emphasis = emphases[blocks[index].emphasisCode]
                    }
                case .unknown:
                    var error = ProcessError(code: .badRecordType)
                    error.text = "Bad Word file record type (\(recordType.rawValue) at \(String(format: "0x%04x", arguments: [byteIndex]))"
                    return .failure(error)
            }

            recordCounter |= (1 << recordType.rawValue)
            byteIndex += recordDataLength
        }

        // Check we have at least one of every record
        if recordCounter != PsionWordConstants.RecordTotal {
            // Processing ended, but without a complete set of records
            return .failure(ProcessError(code: .badFileMissingRecords))
        }

        document.paragraphs = createDoc(textBytes, blocks) //, styles, emphases, settings)

        // Add the header and foot if requested
        if settings.includeHeader {
            document.header = Paragraph(spans: [Span(text: outerText[0])])
            document.footer = Paragraph(spans: [Span(text: outerText[1])])
        }

        bodyText = convert(document: document, toMarkdown: settings.returnMarkdown, includeOuter: settings.includeHeader)
        return .success(bodyText)
    }


    /**
     Decode a header or footer record's text.

     - Parameters:
        - data:     A slice of the Word file bytes containing the whole record, including its `NUL` terminator.
        - isHeader: `true` if the record is the header; `false` if it is the footer.
        - settings: File conversion parameters.

     - Returns: The text as a string.
     */
    private static func decodeOuterText(_ data: ArraySlice<UInt8>, _ isHeader: Bool, _ settings: ProcessSettings) -> String {

        // Remove the C String NUL terminator, if present
        let textBytes = data.last == 0 ? data.dropLast() : data
        let outerText = decodePsionText(textBytes).trimmingCharacters(in: .whitespacesAndNewlines)

        if settings.showInfo {
            log("  \(isHeader ? "Header" : "Footer") text length \(textBytes.count) byte\(textBytes.count == 1 ? "" : "s")")
        }

        // String is empty (NUL only)?
        return outerText.isEmpty ? (isHeader ? "No header" : "No footer") : outerText
    }


    /**
     Convert Word Blocks into a sequence of Paragraphs.
     Paragraphs map to Word paragraphs, ie. text of a given style, ending in `0`.
     Paragraphs contain Spans, ie. text of a given emphasis within a paragraph.
     Word Blocks are text units of a given style and emphasis, so 1 Span = 1 Block, 1 Paragraph = x Blocks

     - Parameters:
        - rawText: The body text as raw CP 850 bytes, unmodified from the file.
        - blocks:  The block formatting data extracted from the document.

     - Returns: The document's paragraphs, with their text decoded to Unicode.
     */
    private static func createDoc(_ rawText: [UInt8], _ blocks: [PsionWordFormatBlock]) -> [Paragraph] {

        var paragraphs: [Paragraph] = []
        var currentParagraph = Paragraph()
        for block in blocks {
            // Check block size (negative size/extends beyond the raw text bytes)
            guard block.startIndex <= block.endIndex && block.endIndex < rawText.count else { continue }

            // Get a span's text, minus the `0` paragraph separator if the block ends a paragraph
            let isParagraphEnd = rawText[block.endIndex] == PsionWordConstants.ParagraphMarker
            let spanBytes = isParagraphEnd ? rawText[block.startIndex..<block.endIndex] : rawText[block.startIndex...block.endIndex]
            var span = Span()
            span.text = decodePsionText(spanBytes)

            if let emphasis = block.emphasis {
                if emphasis.bold {
                    span.type.insert(.bold)
                }

                if emphasis.italic {
                    span.type.insert(.italic)
                }

                if emphasis.subScript {
                    span.type.insert(.subScript)
                }

                if emphasis.superScript {
                    span.type.insert(.superScript)
                }

                if emphasis.underlined {
                    span.type.insert(.underline)
                }
            }

            currentParagraph.spans.append(span)

            if currentParagraph.spans.count == 1 {
                // A paragraph's style is set by its first block
                currentParagraph.type = paragraphType(for: block.styleCode)
                currentParagraph.word3Style = block.style
            }

            if isParagraphEnd {
                // Store the current para and prep the next one
                paragraphs.append(removeListMarker(from: currentParagraph))
                currentParagraph = Paragraph()
            }
        }

        // Catch a final paragraph that lacks a Psion Word end-of-para marker
        if !currentParagraph.spans.isEmpty {
            paragraphs.append(removeListMarker(from: currentParagraph))
        }

        return paragraphs
    }


    /**
     Remove the bullet or number that Word 3 list items carry as part of their text,
     eg. `·<TAB>` or `12.<TAB>`, and record it in the paragraph's type instead.

     The marker may be split across spans, eg. if only the number is bold, so it is
     located in the paragraph's combined text then removed span by span. Paragraphs
     that aren't list items, or which have no marker, are returned unchanged.

     - Parameters:
        - paragraph: The paragraph to process.

     - Returns: The paragraph without its list marker.
     */
    private static func removeListMarker(from paragraph: Paragraph) -> Paragraph {

        let text = Array(paragraph.spans.map { $0.text }.joined())
        var markerLength = 0
        var result = paragraph

        switch paragraph.type {
            case .bulletItem(let level, _):
                // A bullet is any single non-alphanumeric, non-space character followed by a tab
                guard text.count >= 2, text[1] == "\t" else { return paragraph }
                let bullet = text[0]
                guard !bullet.isLetter && !bullet.isNumber && !bullet.isWhitespace else { return paragraph }
                result.type = .bulletItem(level: level, bullet: bullet)
                markerLength = 2
            case .numberItem(let level, _):
                // A number is one or more digits, then `.` or `)`, then a tab or space
                let digits = text.prefix(while: { $0.isASCII && $0.isNumber })
                guard !digits.isEmpty, text.count >= digits.count + 2,
                      text[digits.count] == "." || text[digits.count] == ")",
                      text[digits.count + 1] == "\t" || text[digits.count + 1] == " ",
                      let number = Int(String(digits)) else { return paragraph }
                result.type = .numberItem(level: level, number: number)
                markerLength = digits.count + 2
            case .body, .heading:
                return paragraph
        }

        // Remove the marker's characters from the leading span(s), dropping any left empty
        var spans: [Span] = []
        for var span in result.spans {
            if markerLength > 0 {
                let removed = min(markerLength, span.text.count)
                span.text = String(span.text.dropFirst(removed))
                markerLength -= removed
                if span.text.isEmpty {
                    continue
                }
            }

            spans.append(span)
        }

        result.spans = spans
        return result
    }


    /**
     Map a Word 3 style code to a paragraph type.

     - Parameters:
        - styleCode: A two-character Word 3 style code, eg. `HA` or `B2`.

     - Returns: The matching ParagraphType. Unrecognised codes, including user-defined
                styles, are treated as body text.
     */
    private static func paragraphType(for styleCode: String) -> ParagraphType {

        // Bulleted and numbered lists, levels 1-6
        if let list = PsionWordConstants.listInfo(styleCode) {
            return list.isBullet ? .bulletItem(level: list.level, bullet: nil) : .numberItem(level: list.level, number: nil)
        }

        // Headings A-F map to levels 1-6
        if styleCode.count == 2 && styleCode.hasPrefix("H"),
           let last = styleCode.unicodeScalars.last,
           ("A"..."F").contains(last) {
            return .heading(level: Int(last.value) - Int(("A" as Unicode.Scalar).value) + 1)
        }

        return .body
    }


    /**
     Convert an internal Document instance, to plain text or Markdown.

     - Parameters:
        - document:     A Document instance instances.
        - toMarkdown:   Convert to Markdown (`true`), or not (`false`).
        - includeOuter: Add header and/or footer text if preseent

     - Returns: The conversion as a string
     */
    static func convert(document: Document, toMarkdown: Bool = false, includeOuter: Bool = false) -> String {

        var docText = ""

        if toMarkdown {
            // Paragraphs are separated by blank lines, except consecutive items of the same list,
            // which must stay together to form a single Markdown list
            var previousType: ParagraphType? = nil

            // Widths of the Markdown list markers (eg. `* `, `12. `) of the open list levels, used to
            // indent nested items so they sit under their parent's text, however wide its marker
            var listMarkerWidths: [Int] = []

            // Get the indent for a list item at `level` (1-based) with the given marker, and record
            // the marker's width for any items nested within this one
            func listIndent(_ level: Int, _ marker: String) -> String {
                let parentLevels = level - 1
                while listMarkerWidths.count < parentLevels {
                    // Missing parent levels get the width of a bullet marker
                    listMarkerWidths.append(2)
                }

                listMarkerWidths = Array(listMarkerWidths.prefix(parentLevels))
                let indent = listMarkerWidths.reduce(0, +)
                listMarkerWidths.append(marker.isEmpty ? 2 : marker.count)
                return String(repeating: " ", count: indent)
            }

            for paragraph in document.paragraphs {
                // Any paragraph that isn't a list item, including an empty one, ends the open lists
                if paragraph.type.listItem == nil {
                    listMarkerWidths = []
                }

                // Combine the paragraph's text spans
                let spanText = combineSpans(paragraph.spans, true)

                // Skip empty paragraphs, which the Psion uses for spacing: Markdown adds its own
                if spanText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continue
                }

                // Style span text according to paragraph style
                // NOTE No `default:` so the compiler flags any new ParagraphType not handled here
                var line: String
                switch paragraph.type {
                    case .body:
                        line = spanText
                    case .heading(let level):
                        line = String(repeating: "#", count: level) + " \(spanText)"
                    case .bulletItem(let level, _):
                        line = listIndent(level, "* ") + "* \(spanText)"
                    case .numberItem(let level, let number):
                        // An item with no number in its text is output without a marker
                        let marker = number.map { "\($0). " } ?? ""
                        line = listIndent(level, marker) + marker + spanText
                }

                if let previousType {
                    // Items of the same list, including nested items, stay together.
                    // Only adjacent top-level items of different list types are separated
                    var sameList = false
                    if let previousList = previousType.listItem, let currentList = paragraph.type.listItem {
                        sameList = previousList.level > 1 || currentList.level > 1 || previousList.isBullet == currentList.isBullet
                    }

                    docText += sameList ? "\n" : "\n\n"
                }

                docText += line
                previousType = paragraph.type
            }

            if !docText.isEmpty {
                docText += "\n"
            }
        } else {
            for paragraph in document.paragraphs {
                // Plain text follows the Psion layout, including empty paragraphs,
                // but restores the list markers taken from the source text
                var marker = ""
                switch paragraph.type {
                    case .bulletItem(_, let bullet):
                        if let bullet {
                            marker = "\(bullet)\t"
                        }
                    case .numberItem(_, let number):
                        if let number {
                            marker = "\(number).\t"
                        }
                    case .body, .heading:
                        break
                }

                // Indent nested list items by one tab per parent level. As markers end in a tab,
                // this places an item's marker under its parent's text, whatever the marker's width
                // NOTE The Psion stores no indentation in the text: it comes from each list style
                var indent = ""
                if let list = paragraph.type.listItem {
                    indent = String(repeating: "\t", count: list.level - 1)
                }

                docText += "\(indent)\(marker)\(combineSpans(paragraph.spans, false))\n"
            }
        }

        // Apply headers and/or footers if present and requested
        if includeOuter {
            if let footer = document.footer, let header = document.header {
                let footerText = combineSpans(footer.spans, toMarkdown)
                let headerText = combineSpans(header.spans, toMarkdown)
                let lineCount = max(footerText.count, headerText.count)
                let line = String(repeating: "*", count: lineCount)
                docText = "\(docText)\n\(line)\n\(footerText)\n"
                docText = "\(headerText)\n\(line)\n\(docText)"
            } else if let footer = document.footer {
                let footerText = combineSpans(footer.spans, toMarkdown)
                let line = String(repeating: "*", count: footerText.count)
                docText = "\(docText)\n\(line)\n\(footerText)\n"
            } else if let header = document.header {
                let headerText = combineSpans(header.spans, toMarkdown)
                let line = String(repeating: "*", count: headerText.count)
                docText = "\(headerText)\n\(line)\n\(docText)"
            }
        }
        
        return plainCharacters(docText)
    }

 }
