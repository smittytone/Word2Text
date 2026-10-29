/*
    word2text
    help.swift

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


extension Word2Text {
    /**
     Display the help text.
     */
    internal static func showHelp() {

        let helpText = """
            Convert a Psion Series 3 Word document to plain text or Markdown.
            
            \(String(.bold))USAGE\(String(.normal))
                word2text [-s] [-o] [-v] [-h] file(s)
            
            \(String(.bold))OPTIONS\(String(.normal))
                -s | --stop          Stop on first file that can't be processed. Default: false")
                -o | --outer         Include outer text (header and footer) in output.")
                -m | --markdown      Include outer text (header and footer) in output.")
                -f | --file          Output to file, not stdout. Default: false for one file,")
                                     true for multiple files/directories")
                -v | --verbose       Show progress information. Otherwise only errors are shown.")
                -h | --help          This help screen.
            
            \(String(.italic))https://smittytone.net/word2text/index.html\(String(.normal))
            """

        showHeader()
        Stdio.report(helpText)
    }


    /**
     Display the app's version number.
     */
    internal static func showHeader() {

#if os(macOS)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? SWIFT_BUILD_PROCESS_VERSION
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? String(SWIFT_BUILD_PROCESS_BUILD)
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "word2text"
        Stdio.report("\(String(.bold))\(name) \(version) (\(build))\(String(.normal)) for macOS")
#else
        // Linux output
        // TODO Automate based on build settings
        Stdio.report("\(String(.bold))word2text \(SWIFT_BUILD_PROCESS_VERSION) (\(SWIFT_BUILD_PROCESS_BUILD))\(String(.normal)) for Linux")
#endif
        Stdio.report("Copyright © 2026, Tony Smith (@smittytone). Source code available under the MIT licence.")
    }

}

