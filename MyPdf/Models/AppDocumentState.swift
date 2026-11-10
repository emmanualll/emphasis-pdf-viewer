import SwiftUI
import Combine

extension Notification.Name {
    static let commitCanvaTextBoxes = Notification.Name("commitCanvaTextBoxes")
    static let openDocumentTriggered = Notification.Name("openDocumentTriggered")
    static let saveDocumentTriggered = Notification.Name("saveDocumentTriggered")
    static let exportTwoUpTriggered = Notification.Name("exportTwoUpTriggered")
    static let toggleSidebarTriggered = Notification.Name("toggleSidebarTriggered")
    static let toggleBookViewTriggered = Notification.Name("toggleBookViewTriggered")
    static let focusSearchTriggered = Notification.Name("focusSearchTriggered")
    static let findNextTriggered = Notification.Name("findNextTriggered")
    static let findPreviousTriggered = Notification.Name("findPreviousTriggered")
    static let selectToolHighlight = Notification.Name("selectToolHighlight")
    static let selectToolTextBox = Notification.Name("selectToolTextBox")
    static let selectToolErase = Notification.Name("selectToolErase")
}

@MainActor
final class AppDocumentState: ObservableObject {
    static let shared = AppDocumentState()
    @Published var isDocumentOpen: Bool = false
    @Published var hasSearchHits: Bool = false
    @Published var isSidebarOpen: Bool = true
    @Published var isBookView: Bool = false
}
