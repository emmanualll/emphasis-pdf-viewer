import SwiftUI

@main struct MyApp: App {
    @ObservedObject private var state = AppDocumentState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    NotificationCenter.default.post(name: .openDocumentTriggered, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .saveDocumentTriggered, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!state.isDocumentOpen)

                Button("Export 2-Up PDF…") {
                    NotificationCenter.default.post(name: .exportTwoUpTriggered, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!state.isDocumentOpen)
            }

            CommandGroup(replacing: .sidebar) {
                Button(state.isSidebarOpen ? "Hide Sidebar" : "Show Sidebar") {
                    NotificationCenter.default.post(name: .toggleSidebarTriggered, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(!state.isDocumentOpen)
            }

            CommandGroup(after: .sidebar) {
                Button(state.isBookView ? "Single Page View" : "Book View") {
                    NotificationCenter.default.post(name: .toggleBookViewTriggered, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command, .option])
                .disabled(!state.isDocumentOpen)
            }

            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Find…") {
                    NotificationCenter.default.post(name: .focusSearchTriggered, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(!state.isDocumentOpen)

                Button("Find Next") {
                    NotificationCenter.default.post(name: .findNextTriggered, object: nil)
                }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(!state.isDocumentOpen || !state.hasSearchHits)

                Button("Find Previous") {
                    NotificationCenter.default.post(name: .findPreviousTriggered, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(!state.isDocumentOpen || !state.hasSearchHits)
            }

            CommandMenu("Tools") {
                Button("Highlight Tool") {
                    NotificationCenter.default.post(name: .selectToolHighlight, object: nil)
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(!state.isDocumentOpen)

                Button("Text Box Tool") {
                    NotificationCenter.default.post(name: .selectToolTextBox, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(!state.isDocumentOpen)

                Button("Erase Tool") {
                    NotificationCenter.default.post(name: .selectToolErase, object: nil)
                }
                .keyboardShortcut("x", modifiers: [.command, .shift])
                .disabled(!state.isDocumentOpen)
            }
        }
    }
}
