/*
    word2text
    word2text.swift

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
import Clicore


/**
    Main entry point
 */
@main
struct Word2Text {

    public static func main() async throws {

        // Make sure the signal does not terminate the application
        Stdio.enableCtrlHandler("word2text interrupted -- halting")

        // FROM 0.4.0
        var settings = ProcessSettings()
#if os(macOS)
        // Use emoji markers on macOS
        Stdio.settings.useEmoji = true
#endif

        // No arguments? Show Help
        if CommandLine.arguments.count == 1 {
            showHelp()
            Stdio.exitApp()
        }

        // Expand composite flags
        let collatedArguments = Cli.unify(args: CommandLine.arguments)

        // Process the (separated) arguments
        var files: [String] = []
        var argIsAValue = false
        var argCount = 0
        var previousArgument = ""
        for argument in collatedArguments {
            if argIsAValue {
                // Make sure we're not reading in an option rather than a value
                if argument.prefix(1) == "-" {
                    Stdio.reportErrorAndExit("Missing value for \(previousArgument)")
                }

                argIsAValue = false
            } else {
                switch argument {
                    case "-v", "--verbose":
                        settings.showInfo = true
                    case "-o", "--outer":
                        settings.includeHeader = true
                    case "-f", "--file":
                        settings.outputAsFile = true
                    case "-m", "--markdown":
                        settings.returnMarkdown = true
                    case "-s", "--stop":
                        settings.haltOnFirstError = true
                    case "-h", "-help":
                        showHelp()
                        Stdio.exitApp()
                    case "--version":
                        showHeader()
                        Stdio.exitApp()
                    default:
                        if argument.prefix(1) == "-" {
                            Stdio.reportErrorAndExit("Unknown argument: \(argument)")
                        } else {
                            files.append(argument)
                        }
                }

                previousArgument = argument
            }

            argCount += 1

            // Trap commands that come last and therefore have missing args
            if argCount == CommandLine.arguments.count && argIsAValue {
                Stdio.reportErrorAndExit("Missing value for \(argument)")
            }
        }

        // Pre-process the file list looking for directories.
        // We also take the time to rationalise the paths of passed files
        for filepath in files {
            let absolutePath = Path.getFullPath(filepath)
            if Path.doesPathReferenceDirectory(absolutePath) {
                // References a directory so get the file list
                let directoryContentsEnumerator = FileManager.default.enumerator(atPath: absolutePath)
                while let file = directoryContentsEnumerator?.nextObject() as? String {
                    if file.hasSuffix(".WRD") {
                        settings.files.append(absolutePath + "/" + file)
                    }
                }
            } else {
                settings.files.append(absolutePath)
            }
        }

        // Convert the file(s) to text
        PsionWord.processFiles(settings)

        // Exit gracefully
        Stdio.exitApp()
    }

}
