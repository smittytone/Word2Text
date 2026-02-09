/*
 *  AppDelegate.swift
 *  Word2text library demo on macOS
 *
 *  Created by Tony Smith on 09/02/2026.
 *  Copyright © 2026 Tony Smith. All rights reserved.
 */

import Cocoa
import Word2text


@main
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    // MARK: Public UI Elements
    @IBOutlet var appWindow: NSWindow!
    @IBOutlet var appMainView: NSView!
    @IBOutlet var appScrollView: NSScrollView!
    @IBOutlet var appTextView: NSTextView!


    // MARK: App Lifecyle Methods
    func applicationDidFinishLaunching(_ aNotification: Notification) {

        // Register to receive notifications from the Word2text library
        let nc: NotificationCenter = NotificationCenter.default
                nc.addObserver(self,
                               selector: #selector(self.printLog(_:)),
                               name: ProcessNotification.log,
                               object: nil)

                nc.addObserver(self,
                               selector: #selector(self.printLog(_:)),
                               name: ProcessNotification.warning,
                               object: nil)

        // Fix the primary view to the edges of the window's view
        self.appScrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.appScrollView.leadingAnchor.constraint(equalTo: self.appMainView.leadingAnchor),
            self.appScrollView.trailingAnchor.constraint(equalTo: self.appMainView.trailingAnchor),
            self.appScrollView.topAnchor.constraint(equalTo: self.appMainView.topAnchor),
            self.appScrollView.bottomAnchor.constraint(equalTo: self.appMainView.bottomAnchor)
        ])

        // Windows management operations
        self.appWindow.title = "Word2text Library Demo"
        self.appWindow.delegate = self
        self.appWindow.center()
        self.appWindow.makeKeyAndOrderFront(self)

        // Finally, present a Psion Word file
        let wordFilePath = "/Users/smitty/GitHub/word2text/samples/SAMPLE.WRD"
        showWordFile(self.appTextView, wordFilePath)
    }


    func applicationWillTerminate(_ aNotification: Notification) {

        NotificationCenter.default.removeObserver(self)
    }


    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {

        return true
    }


    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {

        // When the main window closed, shut down the app
        return true
    }
    

    /**
     Process and present a Psion Word file in the specified NSTextView.

     - Parameters:
        - textView:     The target text view.
        - wordFilePath: A path to a Psion Word file.
     */
   private func showWordFile(_ textView: NSTextView, _ wordFilePath: String) {

       // Check the file is available to use
       if !FileManager.default.fileExists(atPath: wordFilePath) {
           textView.string = "ERROR — file \(wordFilePath) can’t be located"
           return
       }

       // Load and process the Word file
       do {
           let data = try Data(contentsOf: URL(filePath: wordFilePath))
           let settings: ProcessSettings = [.doShowInfo, .doReturnMarkdown]
           let result = PsionWord.processFile(data, settings, wordFilePath)

           switch result {
               case .failure(let error):
                   textView.string = error.localizedDescription
               case .success(let processedText):
                   if let renderTextStorage: NSTextStorage = textView.textStorage {
                       let processedTextAttributes: [NSAttributedString.Key:Any] = [
                            .foregroundColor: NSColor.labelColor,
                            .font: NSFont.systemFont(ofSize: 18.0, weight: .bold)
                       ]

                       let processedAttrString = NSAttributedString(string: processedText, attributes: processedTextAttributes)

                       renderTextStorage.beginEditing()
                       renderTextStorage.setAttributedString(processedAttrString)
                       renderTextStorage.endEditing()
                   }
           }
        } catch {
            textView.string = "ERROR — \(wordFilePath) can’t be processed"
        }
    }


    @objc
    func printLog(_ note: Notification) {

        let message = note.object as! String
        print(message)
    }

}

