/*
    word2text
    utilities.swift

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


extension PsionWord {

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


    /**
     Decode Psion Word text bytes (CP 850, plus Word's special characters) as a string.
     The inverse of `encodePsionText()`.

     Each byte becomes exactly one Unicode scalar -- nothing is dropped -- so character
     positions in the result match byte positions in the source, eg. for block ranges.

     - Parameters:
        - bytes: The bytes to decode.

     - Returns: The decoded string.
     */
    internal static func decodePsionText(_ bytes: ArraySlice<UInt8>) -> String {

        var scalars = String.UnicodeScalarView()
        for byte in bytes {
            switch byte {
                case 0:
                    // Paragraph separator
                    scalars.append("\n")
                case 7:
                    // Unbreakable hyphen
                    scalars.append("\u{2011}")
                case 14:
                    // Soft hyphen
                    scalars.append("\u{00AD}")
                case 15:
                    // Unbreakable space
                    scalars.append("\u{00A0}")
                case 0x80...0xFF:
                    scalars.append(cp850UpperHalf[Int(byte) - 0x80])
                default:
                    // 0x00-0x7F match their Unicode values
                    scalars.append(Unicode.Scalar(byte))
            }
        }

        return String(scalars)
    }


    /**
     Replace Word's special characters, which a Document holds as their Unicode equivalents,
     with plain ones, as plain text and Markdown don't need them.

     - Parameters:
        - text: The text to process.

     - Returns: The text with unbreakable spaces and hyphens made plain, and soft hyphens removed.
     */
    internal static func plainCharacters(_ text: String) -> String {

        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar {
                case "\u{00A0}":
                    // Unbreakable space
                    scalars.append(" ")
                case "\u{2011}":
                    // Unbreakable hyphen
                    scalars.append("-")
                case "\u{00AD}":
                    // Soft hyphen: only shown when a line breaks at it
                    continue
                default:
                    scalars.append(scalar)
            }
        }

        return String(scalars)
    }


    /**
     Swap a CP 850 for a CP 1252.

     Covers every CP 850 character that CP 1252 can represent: all of the
     CP 850 accented letters and symbols, which sit at their Latin-1 code points
     in CP 1252, plus ƒ. Box-drawing and other characters absent from CP 1252
     (eg. `ı`, `‗`, `■`) still become `?`.

     REVISED 0.4.0

     - Parameters:
        - char: A CP 850 integer value (0x80-0xFF).

     - Returns: The equivalent 1252 code.
     */
    internal static func charSwap(_ char: UInt8) -> UInt8 {

        guard char >= 0x80 else { return char }
        return cp850ToCp1252[Int(char) - 0x80]
    }


    /*
     CP 1252 equivalents of CP 850 bytes 0x80-0xFF, derived from `cp850UpperHalf`
     */
    internal static let cp850ToCp1252: [UInt8] = cp850UpperHalf.map { scalar in
        switch scalar.value {
            case 0xA0...0xFF:
                // Latin-1 Supplement characters have the same code in CP 1252
                return UInt8(scalar.value)
            case 0x0192:
                // ƒ
                return 0x83
            default:
                return 0x3F
        }
    }


    // MARK: - Misc.

    /**
     Combine a paragraph's spans into a single text item.

     - Parameters:
        - spans:      An array of Spans.
        - toMarkdown: Include markdown formatting. Default: `false`.

     - Returns: The combined span.
    */
    internal static func combineSpans(_ spans: [Span], _ toMarkdown: Bool = false) -> String {

        var spanText = ""
        for span in spans {
            spanText += toMarkdown ? span.markdown : span.text
        }

        return spanText
    }


    /**
     Determine the longest length of two substrings.
     */
    internal static func greater(_ a: Substring, _ b: Substring) -> String {

        if a.count > b.count {
            return String(a)
        }

        return String(b)
    }


    /**
     Output raw bytes as hex values.

     Required for debugging ONLY.
     */
    internal static func debugPrintBytes(_ data: ArraySlice<UInt8>) {

        var s = ""
        for byte in data {
            s += String(format: "%02X", byte)
        }

        print(s)
    }

}
