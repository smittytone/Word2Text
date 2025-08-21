/*
    word2text
    main.swift

    Copyright © 2025 Tony Smith. All rights reserved.

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
import Clicore


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
var outputAsFile: Bool      = false
var files: [String]         = []


// MARK: Runtime Start

// Make sure the signal does not terminate the application
Stdio.enableCtrlHandler("word2text interrupted -- halting")

// No arguments? Show Help
if CommandLine.arguments.count == 1 {
    showHelp()
    Stdio.disableCtrlHandler()
    exit(EXIT_SUCCESS)
}

// Expand composite flags
var args: [String] = Cli.unify(args: CommandLine.arguments)

// Process the (separated) arguments
for argument in args {
    // Ignore the first command line argument
    if argCount == 0 {
        argCount += 1
        continue
    }

    if argIsAValue {
        // Make sure we're not reading in an option rather than a value
        if argument.prefix(1) == "-" {
            Stdio.reportErrorAndExit("Missing value for \(prevArg)")
        }

        argIsAValue = false
    } else {
        switch argument {
        case "-v", "--verbose":
            doShowInfo = true
        case "-s", "--stop":
            haltOnFirstError = true
        case "-o", "--outer":
            doIncludeHeader = true
        case "-m","--markdown":
            doReturnMarkdown = true
        case "-f", "--file":
            outputAsFile = true
        case "-h", "-help":
            showHelp()
            Stdio.disableCtrlHandler()
            exit(EXIT_SUCCESS)
        case "--version":
            showHeader()
            Stdio.disableCtrlHandler()
            exit(EXIT_SUCCESS)
        default:
            if argument.prefix(1) == "-" {
                Stdio.reportErrorAndExit("Unknown argument: \(argument)")
            } else {
                files.append(argument)
            }
        }

        prevArg = argument
    }

    argCount += 1

    // Trap commands that come last and therefore have missing args
    if argCount == CommandLine.arguments.count && argIsAValue {
        Stdio.reportErrorAndExit("Missing value for \(argument)")
    }
}

// Pre-process the file list looking for directories.
// We also take the time to rationalise the paths of passed files
var finalFiles: [String] = []
for filepath in files {
    let absolutePath: String = Path.getFullPath(filepath)
    if Path.doesPathReferenceDirectory(absolutePath) {
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
let outputToFiles: Bool = outputAsFile || finalFiles.count > 1
for filepath in finalFiles {
    let data = Path.getFileContents(filepath)
    let result: ProcessResult = !data.isEmpty
    ? PsionWord.processFile(data, filepath)
    : ProcessResult(text: "file not found", errorCode: .badFile)

    // Handle the outcome of processing
    if result.errorCode != .noError {
        // Report the error and, if required, bail
        if haltOnFirstError {
            Stdio.reportErrorAndExit("File \(filepath) could not be processed: \(result.text)", Int32(result.errorCode.rawValue))
        } else {
            Stdio.reportWarning("File \(filepath) could not be processed: \(result.text)")
        }
    } else {
        // Report the processed text
        if !outputToFiles {
            // Output processed text to STDOUT so it's available for piping or redirection
            if doShowInfo {
                Stdio.report("File \(filepath) processed")
            }

            Stdio.output(result.text)
        } else {
            // Output to a file: generate the name and extension...
            var outFilepath: String = (filepath as NSString).deletingPathExtension
            outFilepath += (doReturnMarkdown ? ".md" : ".txt")

            // ...and attempt to write it out
            do {
                try result.text.write(toFile: outFilepath, atomically: true, encoding: .utf8)
                if doShowInfo {
                    Stdio.report("File \(filepath) processed to \(outFilepath)")
                }
            } catch {
                Stdio.reportWarning("File \(outFilepath) could not be processed: writing to stdout instead")
                Stdio.output(result.text)
            }
        }
    }
}

// Exit gracefully
Stdio.disableCtrlHandler()
exit(EXIT_SUCCESS)


// MARK: Help/Info Functions

/**
 Display the help text.
 */
func showHelp() {

    showHeader()

    Stdio.report("\nConvert a Psion Series 3 Word document to plain text or Markdown.\n")
    Stdio.report("\(String(.bold))USAGE\(String(.normal))\n    word2text [-s] [-o] [-v] [-h] file(s)\n")
    Stdio.report("\(String(.bold))OPTIONS\(String(.normal))")
    Stdio.report("    -s | --stop          Stop on first file that can't be processed. Default: false")
    Stdio.report("    -o | --outer         Include outer text (header and footer) in output.")
    Stdio.report("    -m | --markdown      Include outer text (header and footer) in output.")
    Stdio.report("    -f | --file          Output to file, not stdout. Default: false for one file,")
    Stdio.report("                         true for multiple files/directories")
    Stdio.report("    -v | --verbose       Show progress information. Otherwise only errors are shown.")
    Stdio.report("    -h | --help          This help screen.")
    Stdio.report("         --version       Show word2text version information.\n")
    Stdio.report("\(String(.italic))https://smittytone.net/word2text/index.html\(String(.normal))")
}


/**
 Display the app's version number.
 */
func showHeader() {

#if os(macOS)
    let version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
    let build: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
    let name:String = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as! String
    Stdio.report("\(String(.bold))\(name) \(version) (\(build))\(String(.normal)) for macOS")
#else
    // Linux output
    // TODO Automate based on build settings
    Stdio.report("\(String(.bold))word2text \(LINUX_VERSION) (\(LINUX_BUILD))\(String(.normal)) for Linux")
#endif
    Stdio.report("Copyright © 2025, Tony Smith (@smittytone). Source code available under the MIT licence.")
}
