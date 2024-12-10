# Word2Text

Convert Psion Series 3, 3a and 3c unencrypted *Word* Documents to Plain Text.

> This utility owes a massive debt to the work of [Clive Feather](https://www.davros.org), whose [Psionics Files](https://www.davros.org/psion/psionics/) contains (among many other useful things) the results of his work reverse engineering the Series 3 applications’ document formats.

![Palmtop from the 1990s: The Psion Series 3a](./images/psion-series-3a.jpg)

## Background

Psion *Word* allows you to enter styled text. Back in the Series 3’s heyday — the mid to late 1990s — Psion provided Windows software that coverted these files to Microsoft Word. A separate DOS utility, *wrd2txt* could convert transferred files to plain text. This latter was the inspiration for *word2text*, which I wrote to perform exactly the same task, but on a modern macOS machine.

I write either plain text or, when I require formatting, in Markdown format. Psion *Word*, created long before Markdown’s conception, doesn’t support it, but both types of text file can be created in *Word* and transferred to a Mac. *Word* embeds the plain text in a document that also includes a host of file, formatting and printing related data. *word2text* strips all that away.

## Usage

Use *word2text* to convert into plain text any Psion *Word* documents that you have transferred to your Mac. Provide a `.WRD` file name as an argument and *word2text* will output a plain text version to stdout. This way you can pipe the result into other command line utilities or redirect output to a file . For example:

```shell
word2text $HOME/Psion/MAGOPUS.WRD > ~/Desktop/MyMagnumOpus.txt
```

You can also pass a directory name (or a mix of file names and directories), in which case each `.WRD` file in the directory will be converted to a text file in that directory.

```shell
word2text $HOME/Psion
```

```shell
word2text $HOME/Psion $HOME/Desktop/MY_DOC.WRD
```

For convenience, files are written using the UTF-8 encoding.

*word2text* accepts the following modifiers:

* `-s`/`--stop` — Stop processing multiple files on the first error. Default: `false`.
* `-o`/`--outer` — Include ‘outer’ text, ie. header and footer text, in addition to the body text. Default: `false`.
* `-v`/`--verbose` — Show file and content discovery information during file processing.

## Compiling

### macOS

* Clone this repo.
* Open the `.xcodeproj` file.
* Set your team under **Signing & Capabilities** for the *word2text* target.
* Select **Build** from the **Product** menu.

### Linux

* [Install Swift](https://www.swift.org/install/linux/)
* Clone this repo.
* `cd /path/to/repo`
* `swift build`

Binary located in `.build/aarch64-unknown-linux-gnu/debug/`

## Future Work

* Convert *Word* formatting to Markdown.
