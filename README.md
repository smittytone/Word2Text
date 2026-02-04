# Word2Text 0.2.1

Convert Psion Series 3, 3a and 3c unencrypted *Word* Documents to Plain Text.

> This utility owes a massive debt to the work of [Clive Feather](https://www.davros.org), whose [Psionics Files](https://www.davros.org/psion/psionics/) contains (among many other useful things) the results of his work reverse engineering the Series 3 applications’ document formats.

![Palmtop from the 1990s: The Psion Series 3a](./images/psion-series-3a.jpg)

## Background

Psion *Word* allows you to enter styled text. Back in the Series 3’s heyday — the mid to late 1990s — Psion provided Windows software that converted these files to Microsoft Word. A separate DOS utility, *wrd2txt* could convert transferred files to plain text. This latter was the inspiration for *word2text*, which I wrote to perform exactly the same task, but on a modern macOS machine.

I write either plain text or, when I require formatting, in Markdown format. Psion *Word*, created long before Markdown’s conception, doesn’t support it, but both types of text file can be created in *Word* and transferred to a Mac. *Word* embeds the plain text in a document that also includes a host of file, formatting and printing related data. *word2text* strips all that away.

## Character Set

The Psion Series 3a uses the IBM Code Page 850 character set. This was used in the DOS days and was superseded first by Windows Code Page 1252 and ultimately UTF-8. 850 and 1252 are not exactly the same, and though Swift can convert from 1252 to UTF-8, it doesn't speak 850. And compiled on Linux, the conversion code has issues with 1252 too, I have found.

*word2text* converts the UK pound sign `£` from 850 value 156 to 1252’s 163. At some point, I may extend this to the full set of matchable characters. If you have a character that is not being correctly converted (*word2text* should report characters that have issues), please let me know.

## Usage

Use *word2text* to convert into plain text any Psion *Word* documents that you have transferred to your Mac. Provide a `.WRD` file name as an argument and *word2text* will output a plain text version to stdout. This way you can pipe the result into other command line utilities or redirect output to a file. For example:

```shell
word2text $HOME/Psion/MAGOPUS.WRD > ~/Desktop/MyMagnumOpus.txt
```

If you include the `--file` flag, *word2text* will write the processed text to (using the example above) `MAGOPUS.txt` and not emit it to stdout.

You can also pass a directory name (or a mix of file names and directories), in which case each `.WRD` file in the directory will be converted to a text file in that directory. Files generated this way (or with the `--file` flag) are named after the source file.

```shell
word2text $HOME/Psion
```

```shell
word2text $HOME/Psion $HOME/Desktop/MY_DOC.WRD
```

For convenience, files are written using the UTF-8 encoding.

*word2text* accepts the following modifiers:

* `-m`/`--markdown` — Output the body text in Markdown formatting. Default: `false`.
* `-o`/`--outer` — Include ‘outer’ text, ie. header and footer text, in addition to the body text. Default: `false`.
* `-s`/`--stop` — Stop processing multiple files on the first error. Default: `false`.
* `-f`/`--file` — Output a single input file to a new file. Default: `false`.
* `-v`/`--verbose` — Show file and content discovery information during file processing.

For example:

```shell
word2text $HOME/Psion/BIDDRAFT.WRD
Bid headline
Bid text to go here...
```

```shell
word2text $HOME/Psion/BIDDRAFT.WRD -o
%F-%D:%T
********
Bid headline
Bid text to go here...
*******
Page %P
```

```shell
word2text $HOME/Psion/BIDDRAFT.WRD -m
# Bid headline
Bid text **to go here**...
```

```shell
word2text $HOME/Psion/BIDDRAFT.WRD -mo
%F-%D:%T
********
Bid headline
Bid text **to go here**...
********
Page %P
```

### Markdown

*word2text* can use Word files’ styling information to mark up the processed text with Markdown formatting tags. This is necessarily limited: Word has only two standard headline sizes, and the only emphasis options relevant to Markdown are bold and/or italic text. Where these apply, *word2text* will mark up the text accordingly. Text styled as a Word Bulleted List entry will be tagged as a Markdown unordered list.

For custom styles, *word2text* will apply bold and/or italic emphasis where it can. For custom headlines, *word2text* will apply a Markdown headline size based on the style’s font size.

In due course, I hope to support table formatting from Word tables and ultimately to more intelligently parse custom Word styles.

## Compiling the CLI App

Building *word2text* from source requires my [Clicore Swift Package](https://github.com/smittytone/clicore).

### macOS

* Clone this repo.
* Open the `.xcodeproj` file.
* Set your team under **Signing & Capabilities** for the *word2text* target.
* Select **Archive** from the **Product** menu.
* Export the resulting archive using **Distribute Content** > **Custom** > **Build Products** and save to desktop.
* `sudo cp path/to/exported/binary /usr/local/bin/word2text`.

### Linux

* [Install Swift](https://www.swift.org/install/linux/)
* Clone this repo.
* `cd /path/to/repo`
* `swift build`

Binary located in `.build/aarch64-unknown-linux-gnu/debug/`. Copy it to a location in your `$PATH`.

## Library Usage

From 0.2.1, you can import this repo as a library to make use of the conversion code in your own macOS app (not Linux).

Add the package via Xcode in the usual way and `import Word2text`. For example:

```swift
import Cocoa
import Word2text


@main
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet var window: NSWindow!
    @IBOutlet var textViewInWindow: NSTextView!

    func applicationDidFinishLaunching(_ aNotification: Notification) {

        do {
            let filepath = "/path/to/Psion/Word/file"
            let data = try Data(contentsOf: URL(filePath: filepath))
            var settings: ProcessSettings = ProcessSettings()
            settings.doReturnMarkdown = true
            let result = PsionWord.processFile(data.byteSlice, filepath, settings)

            switch result {
                case .failure(let error):
                    textViewInWindow.string = error.localizedDescription
                case .success(let processedText):
                    textViewInWindow.string = processedText
            }
        } catch {
            textViewInWindow.string = "File load error"
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {

        return true
    }
}


public extension Data {

    // Return data as an array of bytes
    var bytes: [UInt8] {
        return [UInt8](self)
    }


    // Return data as a slice of array of bytes
    var byteSlice: ArraySlice<UInt8> {
        return self.bytes[...]
    }
}
```

Logging can be enabled by (following the example above) adding the line:

```swift
settings.doShowInfo = true
```

In library mode, log messages and warnings are posted via the default notification centre. The names used are `ProcessNotification.log` and `ProcessNotification.warning`.

For example, add these lines to the start of the `applicationDidFinishLaunching()` function shown above:

```swift
let nc: NotificationCenter = NotificationCenter.default
nc.addObserver(self,
               selector: #selector(self.printLog(_:)),
               name: ProcessNotification.log,
               object: nil)

nc.addObserver(self,
               selector: #selector(self.printLog(_:)),
               name: ProcessNotification.warning,
               object: nil)
```

And add this method to the `AppDelegate` class:

```swift
@objc
func printLog(_ note: Notification) {

    let message = note.object as! String
    print(message)
}
```

Copyright © 2026 Tony Smith (@smittytone)
