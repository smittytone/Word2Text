/*
    word2text
    markdown.swift

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


/*
    Generate a Psion Series 3 Word file from Markdown text.

    FROM 0.4.0
*/
extension PsionWord {

    /**
     Convert Markdown-formatted text into a Psion Series 3 Word document.
     See `README.md` for details of currently supported formatting.

     FROM 0.4.0

     - Parameters:
        - markdown:      The Markdown source text.
        - header:        Page header text. Defaults to none, as in a new Series 3a document.
        - footer:        Page footer text. Defaults to Word's own default (`%P`: page number).
        - printerDriver: The printer driver library recorded in the file. Word takes its available fonts
                         from this driver, so it must be one the target device has. If it isn't, Word
                         falls back to fixed-pitch Courier when the file is opened. Defaults to the
                         Series 3a ROM's Canon BubbleJet driver.

     - Returns: A Result containing the Word file's bytes (success) or a ProcessError (failure).
     */
    static public func generateFile(fromMarkdown markdown: String, header: String = "", footer: String = "%P", printerDriver: String = "ROM::BJ.WDR") -> Result<Data, ProcessError> {

        // Break the Markdown into paragraphs, then each paragraph into emphasis runs,
        // and encode those into the body text and its style/emphasis blocks
        var textBytes: [UInt8] = []
        var blocks: [(length: Int, style: String, emphasis: String)] = []

        for paragraph in parseMarkdownParagraphs(markdown) {
            let runs = paragraph.parseInline ? parseMarkdownEmphasis(paragraph.text) : [(paragraph.text, "NN")]
            let firstBlock = blocks.count
            for run in runs {
                let runBytes = encodePsionText(run.text)
                if runBytes.isEmpty { continue }
                textBytes.append(contentsOf: runBytes)

                // Merge with the previous block if it has the same formatting (within this paragraph only)
                if blocks.count > firstBlock && blocks[blocks.count - 1].emphasis == run.emphasis {
                    blocks[blocks.count - 1].length += runBytes.count
                } else {
                    blocks.append((runBytes.count, paragraph.style, run.emphasis))
                }
            }

            // Paragraph separator: covered by the paragraph's final block
            textBytes.append(0)
            if blocks.count > firstBlock {
                blocks[blocks.count - 1].length += 1
            } else {
                blocks.append((1, paragraph.style, "NN"))
            }
        }

        // A Word document always has at least one paragraph
        if textBytes.isEmpty {
            textBytes.append(0)
            blocks.append((1, "BT", "NN"))
        }

        // The final block covers an imaginary extra separator byte
        blocks.append((1, "BT", "NN"))

        // Record lengths are 16-bit values
        if textBytes.count > 0xFFFF || blocks.count * PsionWordConstants.BlockUnitLength > 0xFFFF {
            var error = ProcessError(code: .badTextTooLong)
            error.text = "Converted Markdown too long to fit in a Psion Word file (\(textBytes.count) text bytes, \(blocks.count) format blocks)"
            return .failure(error)
        }

        // File header (unencrypted)
        var file: [UInt8] = Array("PSIONWPDATAFILE".utf8) + [0]
        // Format version
        appendWord(&file, 1)
        // Encryption algorithm version
        appendWord(&file, 0)
        file.append(contentsOf: [UInt8](repeating: 0xEA, count: 16))
        appendWord(&file, 0xEAEA)
        appendWord(&file, 0)

        // Record type 1: File info -- values as written by a Series 3a
        appendRecord(&file, .fileInfo, [0x00, 0x00, 0x19, 0x22, 0x00, 0x00, 0x08, 0x01, 0x02, 0x00])

        // Record type 2: Printer set-up -- A4 portrait, header left-aligned, values as written by a Series 3a
        appendRecord(&file, .printerConfig, [
            0x82, 0x2E, 0xC6, 0x41, 0x08, 0x07, 0x08, 0x07, 0x72, 0x20, 0xB6, 0x33, 0xD0, 0x02, 0xD0, 0x02,
            0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0xF0, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0xF0, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        ])

        // Record type 3: Printer driver -- model 0 of the specified driver library
        appendRecord(&file, .printerDriver, [0x00] + encodePsionText(printerDriver) + [0])

        // Record types 4 and 5: Header and footer text
        appendRecord(&file, .headerText, encodePsionText(header) + [0])
        appendRecord(&file, .footerText, encodePsionText(footer) + [0])

        // Record type 6: Styles
        for style in markdownStyles() {
            appendRecord(&file, .styleDefinition, style)
        }

        // Record type 7: Emphases
        for emphasis in markdownEmphases() {
            appendRecord(&file, .emphasisDefinition, emphasis)
        }

        // Record type 8: Unstyled body text
        appendRecord(&file, .bodyText, textBytes)

        // Recrd type 9: Style and emphasis blocks
        var blockBytes: [UInt8] = []
        for block in blocks {
            appendWord(&blockBytes, block.length)
            blockBytes.append(contentsOf: Array(block.style.utf8))
            blockBytes.append(contentsOf: Array(block.emphasis.utf8))
        }

        appendRecord(&file, .blockInfo, blockBytes)

        return .success(Data(file))
    }


    // MARK: Markdown Parsing

    /**
     Split Markdown source into Word paragraphs, each tagged with a Word style code.

     FROM 0.4.0

     - Parameters:
        - markdown: The Markdown source text.

     - Returns: An array of paragraphs: style code, raw text, and whether the text needs inline processing.
     */
    internal static func parseMarkdownParagraphs(_ markdown: String) -> [(style: String, text: String, parseInline: Bool)] {

        let psionHeadingCodes = ["HA", "HB", "HC", "HD", "HE", "HF"]
        var paragraphs: [(style: String, text: String, parseInline: Bool)] = []
        var current: (style: String, text: String)? = nil
        var fence: String? = nil

        func flush() {
            if let paragraph = current, !paragraph.text.isEmpty {
                paragraphs.append((paragraph.style, paragraph.text, true))
            }

            current = nil
        }

        // Convert Windows paragraph breaks to Unix style
        let normalised = markdown.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for rawLine in normalised.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Inside a fenced code block: pass lines through verbatim
            if let marker = fence {
                if trimmed.hasPrefix(marker) && trimmed.allSatisfy({ $0 == marker.first! }) {
                    fence = nil
                } else {
                    paragraphs.append(("BT", line, false))
                }

                continue
            }

            // Start of a fenced code block
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                fence = String(trimmed.prefix(3))
                continue
            }

            // Blank line ends the current paragraph
            if trimmed.isEmpty {
                flush()
                continue
            }

            // Setext heading underline -- only applies to a plain paragraph
            if let paragraph = current, paragraph.style == "BT" {
                if trimmed.allSatisfy({ $0 == "=" }) {
                    current = (psionHeadingCodes[0], paragraph.text)
                    flush()
                    continue
                }

                if trimmed.allSatisfy({ $0 == "-" }) {
                    current = (psionHeadingCodes[1], paragraph.text)
                    flush()
                    continue
                }
            }

            // Thematic break (`---`, `***`, `___`) -- not supported, so drop it
            let compact = trimmed.filter { $0 != " " && $0 != "\t" }
            if compact.count >= 3, let first = compact.first, "-*_".contains(first), compact.allSatisfy({ $0 == first }) {
                flush()
                continue
            }

            // ATX heading
            if let heading = parseAtxHeading(trimmed) {
                flush()
                paragraphs.append((psionHeadingCodes[heading.level - 1], heading.text, true))
                continue
            }

            // Bulleted list item. NOTE Psion Word has no list nesting, so nested items are flattened
            if let first = trimmed.first, "-*+".contains(first) {
                let rest = trimmed.dropFirst()
                if rest.isEmpty || rest.first == " " || rest.first == "\t" {
                    flush()
                    current = ("BL", rest.trimmingCharacters(in: .whitespaces))
                    continue
                }
            }

            // Numbered list item. NOTE Psion Word has no auto-numbering, so the number is kept in the text
            let digits = trimmed.prefix(while: { $0.isASCII && $0.isNumber })
            if !digits.isEmpty && digits.count < 10 {
                let rest = trimmed.dropFirst(digits.count)
                if let delimiter = rest.first, delimiter == "." || delimiter == ")" {
                    let afterDelimiter = rest.dropFirst()
                    if afterDelimiter.isEmpty || afterDelimiter.first == " " || afterDelimiter.first == "\t" {
                        flush()
                        current = ("NL", "\(digits). " + afterDelimiter.trimmingCharacters(in: .whitespaces))
                        continue
                    }
                }
            }

            // Continuation of the current paragraph or list item, or the start of a new paragraph
            if let paragraph = current {
                current = (paragraph.style, paragraph.text.isEmpty ? trimmed : paragraph.text + " " + trimmed)
            } else {
                current = ("BT", trimmed)
            }
        }

        flush()
        return paragraphs
    }


    /**
     Parse a `#` heading, if present.

     FROM 0.4.0

     - Parameters:
        - line: A whitespace-trimmed line of Markdown.

     - Returns: The heading level (1-6) and text, or `nil` if the line is not a heading.
     */
    private static func parseAtxHeading(_ line: String) -> (level: Int, text: String)? {

        let hashes = line.prefix(while: { $0 == "#" })
        guard hashes.count >= 1 && hashes.count <= 6 else { return nil }

        let rest = line.dropFirst(hashes.count)
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }

        // Remove any closing sequence of hashes, which must be preceded by a space
        var text = rest.trimmingCharacters(in: .whitespaces)
        let withoutClosing = String(text.reversed().drop(while: { $0 == "#" }).reversed())
        if withoutClosing.isEmpty || withoutClosing.hasSuffix(" ") || withoutClosing.hasSuffix("\t") {
            text = withoutClosing.trimmingCharacters(in: .whitespaces)
        }

        return (hashes.count, text)
    }


    /**
     Split paragraph text into runs of plain, bold, italic and bold-italic text, removing
     the Markdown emphasis markers. Follows the CommonMark delimiter-run rules, simplified
     (no 'rule of three'). Backslash escapes are honoured, and code spans are passed through
     untouched so their contents are not treated as emphasis.

     FROM 0.4.0

     - Parameters:
        - text: The paragraph text.

     - Returns: An array of text runs, each with its Psion Word emphasis code.
     */
    internal static func parseMarkdownEmphasis(_ text: String) -> [(text: String, emphasis: String)] {

        let asciiPunctuation = Set("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~")
        func isPunctuation(_ c: Character) -> Bool {
            return c.isPunctuation || c.isSymbol
        }

        // Tokenise into literal text and delimiter runs
        let chars = Array(text)
        var tokens: [MarkdownToken] = []
        var literal = ""
        var i = 0

        func flushLiteral() {
            if !literal.isEmpty {
                tokens.append(MarkdownToken(text: literal))
                literal = ""
            }
        }

        while i < chars.count {
            let c = chars[i]

            // Backslash escape
            if c == "\\" && i + 1 < chars.count && asciiPunctuation.contains(chars[i + 1]) {
                literal.append(chars[i + 1])
                i += 2
                continue
            }

            // Code span: copy verbatim up to the matching backtick run
            if c == "`" {
                var runEnd = i
                while runEnd < chars.count && chars[runEnd] == "`" { runEnd += 1 }
                let runLength = runEnd - i
                var search = runEnd
                var closeStart: Int? = nil
                while search < chars.count {
                    if chars[search] == "`" {
                        var closeEnd = search
                        while closeEnd < chars.count && chars[closeEnd] == "`" { closeEnd += 1 }
                        if closeEnd - search == runLength {
                            closeStart = search
                            break
                        }

                        search = closeEnd
                    } else {
                        search += 1
                    }
                }

                let end = closeStart != nil ? closeStart! + runLength : runEnd
                literal += String(chars[i..<end])
                i = end
                continue
            }

            // Emphasis delimiter run
            if c == "*" || c == "_" {
                var runEnd = i
                while runEnd < chars.count && chars[runEnd] == c { runEnd += 1 }

                let before: Character? = i > 0 ? chars[i - 1] : nil
                let after: Character? = runEnd < chars.count ? chars[runEnd] : nil
                let beforeIsSpace = before == nil || before!.isWhitespace
                let afterIsSpace = after == nil || after!.isWhitespace
                let beforeIsPunctuation = before != nil && isPunctuation(before!)
                let afterIsPunctuation = after != nil && isPunctuation(after!)
                let leftFlanking = !afterIsSpace && (!afterIsPunctuation || beforeIsSpace || beforeIsPunctuation)
                let rightFlanking = !beforeIsSpace && (!beforeIsPunctuation || afterIsSpace || afterIsPunctuation)

                var token = MarkdownToken(delimiter: c, count: runEnd - i)
                if c == "*" {
                    token.canOpen = leftFlanking
                    token.canClose = rightFlanking
                } else {
                    // Underscores can't create intraword emphasis
                    token.canOpen = leftFlanking && (!rightFlanking || beforeIsPunctuation)
                    token.canClose = rightFlanking && (!leftFlanking || afterIsPunctuation)
                }

                flushLiteral()
                tokens.append(token)
                i = runEnd
                continue
            }

            literal.append(c)
            i += 1
        }

        flushLiteral()

        // Pair closers with the nearest preceding compatible opener
        for closer in tokens.indices where tokens[closer].delimiter != nil && tokens[closer].canClose {
            let delimiter = tokens[closer].delimiter
            while tokens[closer].count > 0 {
                guard let opener = tokens[..<closer].lastIndex(where: { $0.delimiter == delimiter && $0.canOpen && $0.count > 0 }) else {
                    break
                }

                // Strong (2) if both runs allow it, otherwise regular (1)
                let use = (tokens[opener].count >= 2 && tokens[closer].count >= 2) ? 2 : 1
                tokens[opener].count -= use
                tokens[closer].count -= use
                tokens[opener].opens.append(use)
                tokens[closer].closes.append(use)

                // Delimiters between the pair can no longer open emphasis
                for k in (opener + 1)..<closer {
                    tokens[k].canOpen = false
                }
            }
        }

        // Emit the runs. Unmatched delimiter characters are kept as literal text
        var runs: [(text: String, emphasis: String)] = []
        var boldDepth = 0
        var italicDepth = 0

        func addRun(_ text: String) {
            guard !text.isEmpty else { return }
            let emphasis = boldDepth > 0 ? (italicDepth > 0 ? "BI" : "BB") : (italicDepth > 0 ? "II" : "NN")
            if let last = runs.last, last.emphasis == emphasis {
                runs[runs.count - 1].text += text
            } else {
                runs.append((text, emphasis))
            }
        }

        for token in tokens {
            if let delimiter = token.delimiter {
                for use in token.closes {
                    if use == 2 { boldDepth -= 1 } else { italicDepth -= 1 }
                }

                addRun(String(repeating: delimiter, count: token.count))

                for use in token.opens {
                    if use == 2 { boldDepth += 1 } else { italicDepth += 1 }
                }
            } else {
                addRun(token.text)
            }
        }

        return runs
    }


    // MARK: Record Generation

    /*
     Font code for styles that don't inherit their font.
     NOTE Font codes are interpreted by the document's printer driver: with the Series 3a's
          ROM::BJ.WDR driver, 24 (0x18, Times Roman in the Psionics list) is 'Proportional'
     */
    private static let styleFontCode: Int = 0x18

    /**
     The style records written to Markdown-derived documents.
     BT, HA and BL match the Series 3a defaults; HB to HF and NL are added to cover Markdown.
     */
    private static func markdownStyles() -> [[UInt8]] {

        let bodyStyle = PsionWordStyle(
            code: "BT",
            name: "Body text",
            isStyle: true,
            isUndeletable: true,
            isDefault: true,
            fontCode: styleFontCode,
            fontSize: 240,
            alignment: .justified,
            spaceBelowPara: 240,
            outlineLevel: 9
        )

        let headStyleA = PsionWordStyle(
            code: "HA",
            name: "Heading A",
            isStyle: true,
            fontCode: styleFontCode,
            bold: true,
            fontSize: 480,
            alignment: .centered,
            lineSpacing: 480,
            spaceBelowPara: 240,
            spacing: .keepWithNext,
            outlineLevel: 1
        )

        let headStyleB = PsionWordStyle(
            code: "HB",
            name: "Heading B",
            isStyle: true,
            fontCode: styleFontCode,
            bold: true,
            fontSize: 360,
            lineSpacing: 360,
            spaceBelowPara: 120,
            spacing: .keepWithNext,
            outlineLevel: 2
        )

        let headStyleC = PsionWordStyle(
            code: "HC",
            name: "Heading C",
            isStyle: true,
            fontCode: styleFontCode,
            bold: true,
            fontSize: 280,
            lineSpacing: 280,
            spaceBelowPara: 120,
            spacing: .keepWithNext,
            outlineLevel: 3
        )

        let headStyleD = PsionWordStyle(
            code: "HD",
            name: "Heading D",
            isStyle: true,
            fontCode: styleFontCode,
            bold: true,
            fontSize: 240,
            spaceBelowPara: 120,
            spacing: .keepWithNext,
            outlineLevel: 4
        )

        let headStyleE = PsionWordStyle(
            code: "HE",
            name: "Heading E",
            isStyle: true,
            fontCode: styleFontCode,
            bold: true,
            italic: true,
            fontSize: 240,
            spaceBelowPara: 120,
            spacing: .keepWithNext,
            outlineLevel: 5
        )

        let headStyleF = PsionWordStyle(
            code: "HF",
            name: "Heading F",
            isStyle: true,
            fontCode: styleFontCode,
            italic: true,
            fontSize: 240,
            spaceBelowPara: 120,
            spacing: .keepWithNext,
            outlineLevel: 6
        )

        let bulletListStyle = PsionWordStyle(
            code: "BL",
            name: "Bulleted list",
            isStyle: true,
            fontCode: -1,
            fontSize: 240,
            leftIndent: 720,
            firstIdent: 360,
            alignment: .justified,
            spaceBelowPara: 240,
            outlineLevel: 9
        )

        let numberListStyle = PsionWordStyle(
            code: "NL",
            name: "Numbered list",
            isStyle: true,
            fontCode: -1,
            fontSize: 240,
            leftIndent: 720,
            alignment: .justified,
            spaceBelowPara: 240,
            outlineLevel: 9
        )

        return [
            // Body text: the default style
            makeStyleRecord(bodyStyle, 8),
            //styleRecord(code: "BT", name: "Body text", flags: 0x06, fontCode: styleFontCode, style: 0x00, fontSize: 240,
            //           alignment: .justified, spaceBelow: 240, outlineLevel: 9, tabCount: 8),
            // Headings
            makeStyleRecord(headStyleA),
            //styleRecord(code: "HA", name: "Heading A", fontCode: styleFontCode, style: 0x02, fontSize: 480,
            //          alignment: .centered, lineSpacing: 480, spaceBelow: 240, keepWithNext: true, outlineLevel: 1),
            makeStyleRecord(headStyleB),
            //styleRecord(code: "HB", name: "Heading B", fontCode: styleFontCode, style: 0x02, fontSize: 360,
            //            lineSpacing: 360, spaceBelow: 120, keepWithNext: true, outlineLevel: 2),
            makeStyleRecord(headStyleC),
            //styleRecord(code: "HC", name: "Heading C", fontCode: styleFontCode, style: 0x02, fontSize: 280,
            //            lineSpacing: 280, spaceBelow: 120, keepWithNext: true, outlineLevel: 3),
            makeStyleRecord(headStyleD),
            //styleRecord(code: "HD", name: "Heading D", fontCode: styleFontCode, style: 0x02, fontSize: 240,
            //            spaceBelow: 120, keepWithNext: true, outlineLevel: 4),
            makeStyleRecord(headStyleE),
            //styleRecord(code: "HE", name: "Heading E", fontCode: styleFontCode, style: 0x06, fontSize: 240,
            //            spaceBelow: 120, keepWithNext: true, outlineLevel: 5),
            makeStyleRecord(headStyleF),
            //styleRecord(code: "HF", name: "Heading F", fontCode: styleFontCode, style: 0x04, fontSize: 240,
            ///            spaceBelow: 120, keepWithNext: true, outlineLevel: 6),
            // Lists. BL is the Series 3a's standard bulleted list
            makeStyleRecord(bulletListStyle, 1),
            //styleRecord(code: "BL", name: "Bulleted list", fontCode: -1, style: 0x00, fontSize: 240,
            //            leftIndent: 720, firstIndent: 360, alignment: .justified, spaceBelow: 240, outlineLevel: 9, tabCount: 1),
            makeStyleRecord(numberListStyle, 1)
            //styleRecord(code: "NL", name: "Numbered list", fontCode: -1, style: 0x00, fontSize: 240,
            //            leftIndent: 720, alignment: .justified, spaceBelow: 240, outlineLevel: 9, tabCount: 1)
        ]
    }


    /**
     The Word emphasis records written to Markdown-derived documents.
     `NN` to `SS` match the Series 3a defaults; `BI` is added for Markdown bold-italic.

     FROM 0.4.0

     - Returns: Array of byte arrays to add to the Word binary.
     */
    private static func markdownEmphases() -> [[UInt8]] {

        let normalEmphasis = PsionWordStyle(
            code: "NN",
            name: "Normal",
            isStyle: false,
            isUndeletable: true,
            isDefault: true,
            fontCode: -1,
            fontSize: 0,
            inheritUnderline: true,
            inheritBold: true,
            inheritItalic: true
        )

        let underlineEmphasis = PsionWordStyle(
            code: "UU",
            name: "Underline",
            isStyle: false,
            fontCode: -1,
            underlined: true,
            fontSize: 0,
            inheritBold: true,
            inheritItalic: true
        )

        let boldEmphasis = PsionWordStyle(
            code: "BB",
            name: "Bold",
            isStyle: false,
            fontCode: -1,
            bold: true,
            fontSize: 0,
            inheritUnderline: true,
            inheritItalic: true
        )

        let italicEmphasis = PsionWordStyle(
            code: "II",
            name: "Italic",
            isStyle: false,
            fontCode: -1,
            italic: true,
            fontSize: 0,
            inheritUnderline: true,
            inheritBold: true
        )

        let boldItalicEmphasis = PsionWordStyle(
            code: "BI",
            name: "Bold italic",
            isStyle: false,
            fontCode: -1,
            bold: true,
            italic: true,
            fontSize: 0,
            inheritUnderline: true
        )

        let superscriptEmphasis = PsionWordStyle(
            code: "EE",
            name: "Superscript",
            isStyle: false,
            fontCode: -1,
            superScript: true,
            fontSize: 0,
            inheritUnderline: true,
            inheritBold: true,
            inheritItalic: true
        )

        let subscriptEmphasis = PsionWordStyle(
            code: "SS",
            name: "Subscript",
            isStyle: false,
            fontCode: -1,
            subScript: true,
            fontSize: 0,
            inheritUnderline: true,
            inheritBold: true,
            inheritItalic: true
        )

        return [
            makeEmphasisRecord(normalEmphasis),
            //emphasisRecord(code: "NN", name: "Normal", flags: 0x07, style: 0x00, inherit: 0x07),
            makeEmphasisRecord(underlineEmphasis),
            //emphasisRecord(code: "UU", name: "Underline", style: 0x01, inherit: 0x06),
            makeEmphasisRecord(boldEmphasis),
            //emphasisRecord(code: "BB", name: "Bold", style: 0x02, inherit: 0x05),
            makeEmphasisRecord(italicEmphasis),
            //emphasisRecord(code: "II", name: "Italic", style: 0x04, inherit: 0x03),
            makeEmphasisRecord(superscriptEmphasis),
            //emphasisRecord(code: "EE", name: "Superscript", style: 0x08, inherit: 0x07),
            makeEmphasisRecord(subscriptEmphasis),
            //emphasisRecord(code: "SS", name: "Subscript", style: 0x10, inherit: 0x07),
            makeEmphasisRecord(boldItalicEmphasis)
            //emphasisRecord(code: "BI", name: "Bold italic", style: 0x06, inherit: 0x01)
        ]
    }


    /**
     Build an 80-byte Word style record.

     FROM 0.4.0

     - Note: Defaults reflect values used by the Series 3a. Font sizes, indents and spacing are in 1/20 points.
             All eight tab stop slots are always written (with Word's default 0.5in stops) as Word does,
             but only `tabCount` of them are active.

     - Parameters:
        - style:    A style structure.
        - tabCount: The number of tabs to apply.

     - Returns: The style record as encoded bytes.
     */
    private static func makeStyleRecord(_ style: PsionWordStyle, _ tabCount: Int = 0) -> [UInt8] {

        var record = makeStyleHeader(style)
        appendWord(&record, style.leftIndent)
        // Right indent
        appendWord(&record, 0)
        appendWord(&record, style.firstIdent)
        appendWord(&record, style.alignment.rawValue)
        appendWord(&record, style.lineSpacing)
        // Space above
        appendWord(&record, 0)
        appendWord(&record, style.spaceBelowPara)
        var keepFlags: UInt8 = 0x00
        if (style.spacing == .keepWithNext) { keepFlags |= 0x01 }
        if (style.spacing == .keepTogether) { keepFlags |= 0x02 }
        if (style.spacing == .newPage) { keepFlags |= 0x04 }
        record.append(keepFlags)
        record.append(0)
        appendWord(&record, style.outlineLevel)
        appendWord(&record, tabCount)
        for tab in 1...8 {
            // Position
            appendWord(&record, tab * 720)
            // Type
            appendWord(&record, PsionWordTabType.left.rawValue)
        }

        return record
    }


    /**
     Build a 28-byte type 7 (emphasis) record. Font and size are inherited.

     FROM 0.4.0

     - Parameters:
        - emphasis: A Word emphasis structure.

     - Returns: The emphasis record as encoded bytes.
     */
    private static func makeEmphasisRecord(_ emphasis: PsionWordStyle) -> [UInt8] {

        return makeStyleHeader(emphasis)
    }


    /**
     Build the 28 bytes common to style and emphasis records.

     FROM 0.4.0
     */
    private static func makeStyleHeader(_ style: PsionWordStyle)  -> [UInt8] {

        // Short code (2 bytes)
        var record: [UInt8] = Array(style.code.utf8.prefix(2))

        // Full name: up to 15 chars, NUL, padded with spaces as Word does, and a final NUL
        var nameBytes = Array(encodePsionText(style.name).prefix(15)) + [0]
        nameBytes += [UInt8](repeating: 0x20, count: 16 - nameBytes.count)
        nameBytes[15] = 0
        record += nameBytes

        var flags: UInt8 = style.isStyle ? 0x00 : 0x01
        flags += style.isUndeletable ? 0x02 : 0x00
        flags += style.isDefault ? 0x04 : 0x00
        record.append(flags)
        record.append(0)
        appendWord(&record, style.fontCode)

        flags = style.underlined ? 0x01 : 0x00
        flags += style.bold ? 0x02 : 0x00
        flags += style.italic ? 0x04 : 0x00
        if !style.isStyle {
            flags += style.superScript ? 0x08 : 0x00
            flags += style.subScript ? 0x10 : 0x00
        }
        record.append(flags)

        // Unused (older files may have 0x80)
        record.append(0)
        appendWord(&record, style.fontSize)

        flags = style.inheritUnderline ? 0x01 : 0x00
        flags += style.inheritBold ? 0x02 : 0x00
        flags += style.inheritItalic ? 0x04 : 0x00
        if !style.isStyle {
            flags += style.inheritSuperScript ? 0x08 : 0x00
            flags += style.inheritSubScript ? 0x10 : 0x00
        }
        record.append(flags)
        // Unused
        record.append(0)
        return record
    }

    /*
    private static func styleRecord(code: String, name: String, flags: UInt8 = 0x00, fontCode: Int, style: UInt8,
                                    fontSize: Int, leftIndent: Int = 0, firstIndent: Int = 0,
                                    alignment: PsionWordAlignment = .left, lineSpacing: Int = 240, spaceBelow: Int = 0,
                                    keepWithNext: Bool = false, outlineLevel: Int, tabCount: Int = 0) -> [UInt8] {

        var record = styleHeader(code: code, name: name, flags: flags, fontCode: fontCode, style: style,
                                 fontSize: fontSize, inherit: 0x00)
        appendWord(&record, leftIndent)
        // Right indent
        appendWord(&record, 0)
        appendWord(&record, firstIndent)
        appendWord(&record, alignment.rawValue)
        appendWord(&record, lineSpacing)
        // Space above
        appendWord(&record, 0)
        appendWord(&record, spaceBelow)
        record.append(keepWithNext ? 0x01 : 0x00)
        record.append(0)
        appendWord(&record, outlineLevel)
        appendWord(&record, tabCount)
        for tab in 1...8 {
            // Position
            appendWord(&record, tab * 720)
            // Type
            appendWord(&record, PsionWordTabType.left.rawValue)
        }

        return record
    }


    private static func emphasisRecord(code: String, name: String, flags: UInt8 = 0x01, style: UInt8, inherit: UInt8) -> [UInt8] {

        return styleHeader(code: code, name: name, flags: flags, fontCode: -1, style: style, fontSize: 0, inherit: inherit)
    }


    private static func styleHeader(code: String, name: String, flags: UInt8, fontCode: Int, style: UInt8,
                                    fontSize: Int, inherit: UInt8) -> [UInt8] {

        // Short code (2 bytes)
        var record: [UInt8] = Array(code.utf8.prefix(2))

        // Full name: up to 15 chars, NUL, padded with spaces as Word does, and a final NUL
        var nameBytes = Array(encodePsionText(name).prefix(15)) + [0]
        nameBytes += [UInt8](repeating: 0x20, count: 16 - nameBytes.count)
        nameBytes[15] = 0
        record += nameBytes

        record.append(flags)
        record.append(0)
        appendWord(&record, fontCode)
        record.append(style)
        // Unused (older files may have 0x80)
        record.append(0)
        appendWord(&record, fontSize)
        record.append(inherit)
        record.append(0)
        return record
    }
     */

    /**
     Append a record (type, length, data) to the file bytes.

     FROM 0.4.0

     - Parameters:
        - file: Pointer to the byte array forming a record.
        - type: The Word record type.
        - data: The record bytes to append.
     */
    private static func appendRecord(_ file: inout [UInt8], _ type: PsionWordRecordType, _ data: [UInt8]) {

        appendWord(&file, type.rawValue)
        appendWord(&file, data.count)
        file.append(contentsOf: data)
    }


    /**
     Append a 16-bit little endian value. Negative values (eg. -1 for 'inherited') wrap to their two's complement.

     FROM 0.4.0

     - Parameters:
        - bytes: Pointer to the byte array forming a record.
        - value: The value to inject as a pair of bytes.
     */
    private static func appendWord(_ bytes: inout [UInt8], _ value: Int) {

        let word = UInt16(truncatingIfNeeded: value)
        bytes.append(UInt8(word & 0xFF))
        bytes.append(UInt8(word >> 8))
    }


    // MARK: Text Encoding

    /*
     Unicode equivalents of IBM Code Page 850 bytes 0x80-0xFF, the Series 3 character set
     */
    internal static let cp850UpperHalf: [Unicode.Scalar] = Array((
        "ÇüéâäàåçêëèïîìÄÅ" +
        "ÉæÆôöòûùÿÖÜø£Ø×ƒ" +
        "áíóúñÑªº¿®¬½¼¡«»" +
        "░▒▓│┤ÁÂÀ©╣║╗╝¢¥┐" +
        "└┴┬├─┼ãÃ╚╔╩╦╠═╬¤" +
        "ðÐÊËÈıÍÎÏ┘┌█▄¦Ì▀" +
        "ÓßÔÒõÕµþÞÚÛÙýÝ¯´" +
        "\u{00AD}±‗¾¶§÷¸°¨·¹³²■\u{00A0}"
    ).unicodeScalars)

    private static let cp850Lookup: [Unicode.Scalar: UInt8] = {
        var lookup: [Unicode.Scalar: UInt8] = [:]
        for (index, scalar) in cp850UpperHalf.enumerated() {
            lookup[scalar] = UInt8(0x80 + index)
        }

        return lookup
    }()


    /**
     Encode a string as Psion Word text bytes (CP 850, plus Word's special characters).
     Characters with no equivalent become `?`.

     FROM 0.4.0

     - Parameters:
        - text: The string to encode.

     - Returns: The encoded bytes.
     */
    internal static func encodePsionText(_ text: String) -> [UInt8] {

        var bytes: [UInt8] = []
        for scalar in text.precomposedStringWithCanonicalMapping.unicodeScalars {
            switch scalar.value {
                case 0x09, 0x20..<0x7F:
                    bytes.append(UInt8(scalar.value))
                case 0x00..<0x20, 0x7F:
                    // Drop other control characters: 0 is Word's paragraph separator
                    continue
                case 0xA0:
                    // Unbreakable space
                    bytes.append(15)
                case 0xAD:
                    // Soft hyphen
                    bytes.append(14)
                case 0x2011:
                    // Unbreakable hyphen
                    bytes.append(7)
                case 0x2018, 0x2019, 0x201A, 0x2032:
                    // Typographic single quotes
                    bytes.append(0x27)
                case 0x201C, 0x201D, 0x201E, 0x2033:
                    // Typographic double quotes
                    bytes.append(0x22)
                case 0x2010, 0x2012, 0x2013, 0x2212:
                    // Hyphens, en dash, minus
                    bytes.append(0x2D)
                case 0x2014:
                    // Em dash
                    bytes.append(contentsOf: [0x2D, 0x2D])
                case 0x2026:
                    // Ellipsis
                    bytes.append(contentsOf: [0x2E, 0x2E, 0x2E])
                default:
                    bytes.append(cp850Lookup[scalar] ?? 0x3F)
            }
        }

        return bytes
    }
}
