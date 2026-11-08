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
                    case "-r", "--reverse":
                        settings.reverseConversion = true
                    case "-h", "-help", "--help":
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
        settings.files = processPaths(files, settings.reverseConversion)
        if settings.files.count == 0 {
            let errorMessage = settings.reverseConversion ? "No Markdown files passed for conversion" : "No Psion Word files passed for conversion"
            Stdio.reportErrorAndExit(errorMessage)
        }

        if settings.files.count > 1 {
            settings.outputAsFile = true
        }

        // FROM 0.4.0 -- check we have extant files
        settings.files = checkFiles(settings.files)
        if settings.files.count == 0 {
            let errorMessage = settings.reverseConversion ? "No Markdown files located for conversion" : "No Psion Word files located for conversion"
            Stdio.reportErrorAndExit(errorMessage)
        }

        // Convert the file(s) to text/markdown
        processFiles(settings)

        // All done -- exit gracefully
        Stdio.exitApp()
    }


    /**
     Convert paths into absolutes, resolving passed directory paths
     as we go.

     - Parameters:
        - paths:   An array of paths as passed via the command line.
        - toPsion: Are we converting to .WRD not from it? Default: `false`.

     - Returns: An array of absolute paths to `WRD` files.
     */
    internal static func processPaths(_ paths: [String], _ toPsion: Bool = false) -> [String] {

        let supportedExtensions = toPsion ? ["TXT", "MD", "MARKDOWN"] : ["WRD"]
        var validFiles: [String] = []
        for path in paths {
            let absolutePath = Path.getFullPath(path)
            if Path.doesPathReferenceDirectory(absolutePath) {
                // `absolutePath` references a directory so get the file list from it
                let directoryContentsEnumerator = FileManager.default.enumerator(atPath: absolutePath)
                while let file = directoryContentsEnumerator?.nextObject() as? String {
                    let extn = (file as NSString).pathExtension.uppercased()
                    if supportedExtensions.contains(extn) {
                        validFiles.append(absolutePath + "/" + file)
                    }
                }
            } else {
                // `absolutePath` references a file, so check its extension
                let extn = (absolutePath as NSString).pathExtension.uppercased()
                if supportedExtensions.contains(extn) {
                    validFiles.append(absolutePath)
                } else {
                    Stdio.reportWarning("\(path) is not of the correct type -- it will not be processed")
                }
            }
        }

        return validFiles
    }


    /**
     Check the existence of each file in a list of paths.

     FROM 0.4.0

     - Parameters:
        - files: Array of paths to check.

     - Returns: An array of extant files. Empty on error.
     */
    private static func checkFiles(_ files: [String]) -> [String] {

        let fm = FileManager.default
        var validFiles: [String] = []
        for file in files {
            if fm.fileExists(atPath: file) {
                validFiles.append(file)
            } else {
                Stdio.reportError("file \(file) cannot be located -- it will be ignored")
            }
        }

        return validFiles
    }


    /**
     Process a sequence of Psion WRD or Text/Markdown files.

     UPDATED 0.4.0

     - Parameters:
        - settings: The processing preferences.
     */
    private static func processFiles(_ settings: ProcessSettings) {

        for filepath in settings.files {
            let data = Path.getFileContents(filepath)
            if settings.reverseConversion {
                // Convert text or Markdown to WRD
                let markdown = String(bytes: data, encoding: .utf8)
                let result: Result<Data, ProcessError> = markdown != nil
                ? PsionWord.generateFile(fromMarkdown: markdown!)
                : .failure(ProcessError(code: .badFile))
                outputWord(result, settings, filepath)
            } else {
                // Convert WRD to text or Markdown
                let result: Result<String, ProcessError> = !data.isEmpty
                ? PsionWord.processFile(data, filepath, settings)
                : .failure(ProcessError(code: .badFile))
                outputText(result, settings, filepath)
            }
        }
    }


    /**
     Output the result of a Text/Markdown to Psion Word conversion.

     FROM 0.4.0

     - Parameters:
        - result:         The result of the conversion operation.
        - settings:       Conversion preferences.
        - sourceFilePath: The path of the source file, for reporting.
     */
    private static func outputWord(_ result: Result<Data, ProcessError>, _ settings: ProcessSettings, _ sourceFilePath: String) {

        switch result {
            case .failure(let error):
                let errorMessage = "File \(sourceFilePath) could not be converted: \(error.localizedDescription)"
                if settings.haltOnFirstError {
                    Stdio.reportErrorAndExit(errorMessage, Int32(error.code.rawValue))
                } else {
                    Stdio.reportWarning(errorMessage)
                }
            case .success(let fileData):
                // Output to a file: generate the name and extension
                let outFilePath = (sourceFilePath as NSString).deletingPathExtension + ".wrd"
                let outFileURL = URL(fileURLWithPath: outFilePath)
                do {
                    try fileData.write(to: outFileURL)
                    if settings.showInfo {
                        Stdio.report("File \(sourceFilePath) converted to \(outFilePath)")
                    }
                } catch {
                    let errorMessage = "File \(outFilePath) could not be written"
                    if settings.haltOnFirstError {
                        Stdio.reportErrorAndExit(errorMessage)
                    } else {
                        Stdio.reportError(errorMessage)
                    }
                }
        }
    }


    /**
     Output the result of a Psion Word to Text/Markdown conversion.

     FROM 0.4.0

     - Parameters:
        - result:         The result of the conversion operation.
        - settings:       Conversion preferences.
        - sourceFilePath: The path of the source file, for reporting.
     */
    private static func outputText(_ result: Result<String, ProcessError>, _ settings: ProcessSettings, _ sourceFilePath: String) {

        switch result {
            case .failure(let error):
                let errorMessage = "File \(sourceFilePath) could not be converted: \(error.localizedDescription)"
                if settings.haltOnFirstError {
                    Stdio.reportErrorAndExit(errorMessage, Int32(error.code.rawValue))
                } else {
                    Stdio.reportWarning(errorMessage)
                }
            case .success(let processedText):
                // Report the processed text
                if !settings.outputAsFile {
                    // Output processed text to STDOUT so it's available for piping or redirection
                    if settings.showInfo {
                        Stdio.report("File \(sourceFilePath) converted")
                    }

                    Stdio.output(processedText)
                } else {
                    // Output to a file: generate the name and extension...
                    var outFilePath = (sourceFilePath as NSString).deletingPathExtension
                    outFilePath += settings.returnMarkdown ? ".md" : ".txt"
                    do {
                        try processedText.write(toFile: outFilePath, atomically: true, encoding: .utf8)
                        if settings.showInfo {
                            Stdio.report("File \(sourceFilePath) converted to \(outFilePath)")
                        }
                    } catch {
                        Stdio.reportWarning("File \(outFilePath) could not be written: writing to stdout instead:")
                        Stdio.output(processedText)
                    }
                }
        }
    }
}
