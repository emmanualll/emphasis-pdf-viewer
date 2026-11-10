import AppKit
import PDFKit
import SwiftUI

final class UnsavedChangesManager {
    static let shared = UnsavedChangesManager()
    var hasUnsavedChanges = false
    var document: PDFDocument?
    var fileURL: URL?
    var performSave: (() -> Bool)?

    func confirmCloseOrQuit() -> Bool {
        guard hasUnsavedChanges, document != nil, let url = fileURL else {
            return true
        }

        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes made to the document “\(url.lastPathComponent)”?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.alertStyle = .warning

        let saveButton = alert.addButton(withTitle: "Save")
        saveButton.keyEquivalent = "\r"

        let dontSaveButton = alert.addButton(withTitle: "Don't Save")
        dontSaveButton.keyEquivalent = "d"
        dontSaveButton.keyEquivalentModifierMask = [.command]

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let saved = performSave?() ?? false
            if saved {
                hasUnsavedChanges = false
                return true
            }
            return false
        } else {
            hasUnsavedChanges = false
            return true
        }
    }
}

final class AppTerminationProxy: NSObject, NSApplicationDelegate {
    var originalDelegate: (any NSApplicationDelegate)?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let proceed = UnsavedChangesManager.shared.confirmCloseOrQuit()
        if !proceed {
            return .terminateCancel
        }
        return originalDelegate?.applicationShouldTerminate?(sender) ?? .terminateNow
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(applicationShouldTerminate(_:)) {
            return true
        }
        return super.responds(to: aSelector) || (originalDelegate?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        return originalDelegate
    }
}

final class WindowDelegateProxy: NSObject, NSWindowDelegate {
    var originalDelegate: (any NSWindowDelegate)?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let proceed = UnsavedChangesManager.shared.confirmCloseOrQuit()
        if !proceed {
            return false
        }
        return originalDelegate?.windowShouldClose?(sender) ?? true
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(windowShouldClose(_:)) {
            return true
        }
        return super.responds(to: aSelector) || (originalDelegate?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        return originalDelegate
    }
}

struct WindowCloseHandler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            setup(view: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            setup(view: nsView)
        }
    }

    private func setup(view: NSView) {
        if let window = view.window {
            window.titleVisibility = .hidden
            if let existing = window.delegate {
                if !(existing is WindowDelegateProxy) {
                    let proxy = WindowDelegateProxy()
                    proxy.originalDelegate = existing
                    window.delegate = proxy
                }
            } else {
                let proxy = WindowDelegateProxy()
                window.delegate = proxy
            }
        }
        if let appDelegate = NSApplication.shared.delegate, !(appDelegate is AppTerminationProxy) {
            let proxy = AppTerminationProxy()
            proxy.originalDelegate = appDelegate
            NSApplication.shared.delegate = proxy
        }
    }
}
