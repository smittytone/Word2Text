/*
    word2text
    entities.swift

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
    Structure to hold the outcome of a failed file processing operation.
    Supports `error.localizedDescription`.

    The `code` value will be an error code (ProcessErrorKind). Its raw value can be used as an exit code.

    The `text` property will be an error message. It is required only by certain errors,
    specifically those which interpolate information into the error message.
*/
public struct ProcessError: Error, LocalizedError {
    public var code: ProcessErrorKind                  = .noError
    public var text: String?                           = nil
    public var errorDescription: String? {
        switch self.code {
            case .noError:
                return nil
            case .badFile:
                return "file not found"
            case .badPsionFileType:
                return "not a Psion Series 3 Word file"
            case .badFileEncrypted:
                return "Word file is encrypted"
            case .badRecordLengthFileInfo,
                 .badRecordLengthPrinterConfig,
                 .badRecordLengthStyleDefinition,
                 .badRecordLengthEmphasisDefinition,
                 .badRecordType:
                if let text = self.text {
                    return text
                } else {
                    return "Error message not provided"
                }
            case .badFileMissingRecords:
                return "file did not include required records"
            }
        }
}


/*
    Configuration data for Word file processing operations.
*/
public struct ProcessSettings {

    public var doShowInfo: Bool                        = false
    public var doIncludeHeader: Bool                   = false
    public var doReturnMarkdown: Bool                  = false

    public init() {
    }
}


/*
    Notification for libraries.
 
    FROM 0.2.1
*/
public struct ProcessNotification {
    
    public static let log       = Notification.Name(rawValue: "com.bps.word2text.note.log.message")
    public static let warning   = Notification.Name(rawValue: "com.bps.word2text.note.log.warning")
}

/*
    Structure to hold a Style or Emphasis record.
 
    Not all of the fields are used by each type
*/
public struct PsionWordStyle {
    public var code: String                            = ""
    public var name: String                            = ""
    public var isStyle: Bool                           = true      // `true` for a style, `false` for an emphasis
    public var isUndeletable: Bool                     = false
    public var isDefault: Bool                         = false
    public var fontCode: Int                           = 0
    public var underlined: Bool                        = false
    public var bold: Bool                              = false
    public var italic: Bool                            = false
    public var superScript: Bool                       = false     // Emphasis only
    public var subScript: Bool                         = false     // Emphasis only
    public var fontSize: Int                           = 10        // Multiple of 0.05
    public var inheritUnderline: Bool                  = false
    public var inheritBold: Bool                       = false
    public var inheritItalic: Bool                     = false
    public var inheritSuperScript: Bool                = false
    public var inheritSubScript: Bool                  = false
    public var leftIndent: Int                         = 0         // This and all remaining members
    public var rightIndent: Int                        = 0         // are Style only
    public var firstIdent: Int                         = 0
    public var alignment: PsionWordAlignment           = .left
    public var lineSpacing: Int                        = 0
    public var spaceAbovePara: Int                     = 0
    public var spaceBelowPara: Int                     = 0
    public var spacing: PsionWordSpacing               = .keepTogether
    public var outlineLevel: Int                       = 0
    public var tabPositions: [Int]                     = []
    public var tabTypes: [PsionWordTabType]            = []
}


/*
    Text section formatting information.
*/
public struct PsionWordFormatBlock {
    public var startIndex: Int                         = 0
    public var endIndex: Int                           = 0
    public var styleCode: String                       = "BT"
    public var emphasisCode: String                    = "NN"
}


/*
    Word file processing error codes.
    NOTE We require raw values for these, for output as stderr codes.
*/
public enum ProcessErrorKind: Int, Error {
    case noError                                = 0
    case badFile                                = 1
    case badPsionFileType                       = 2
    case badFileEncrypted                       = 3
    case badRecordLengthFileInfo                = 4
    case badRecordLengthPrinterConfig           = 5
    case badRecordLengthStyleDefinition         = 6
    case badRecordLengthEmphasisDefinition     = 7
    case badRecordType                          = 8
    case badFileMissingRecords                  = 9
}


/*
    Text alignment options.
    NOTE We require raw values for these
*/
public enum PsionWordAlignment: Int {
    case left                                   = 0
    case right                                  = 1
    case centered                               = 2
    case justified                              = 3
    case unknown                                = 99
}


/*
    Paragraph spacing options
*/
public enum PsionWordSpacing {
    case keepWithNext
    case keepTogether
    case newPage
    case noSpacing
}

extension PsionWordSpacing {
    mutating func set(_ value: UInt8) {
        if value & 0x01 > 0 {
            self = .keepWithNext
        } else if value & 0x02 > 0 {
            self = .keepTogether
        } else if value & 0x04 > 0 {
            self = .newPage
        } else {
            self = .noSpacing
        }
    }
}


/*
    Tabulation options
*/
public enum PsionWordTabType: Int {
    case left                                   = 0
    case right                                  = 1
    case centered                               = 2
}


/*
    Word file record types.
    NOTE We require raw values for these, to match to record type bytes.
*/
public enum PsionWordRecordType: Int {
    case fileInfo                               = 1
    case printerConfig                          = 2
    case printerDriver                          = 3
    case headerText                             = 4
    case footerText                             = 5
    case styleDefinition                        = 6
    case emphasisDefinition                     = 7
    case bodyText                               = 8
    case blockInfo                              = 9
    case unknown                                = 99
}
