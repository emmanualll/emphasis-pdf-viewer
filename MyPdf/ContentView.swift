import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.undoManager) private var undoManager
    @State private var document: PDFDocument?
    @State private var fileURL: URL?
    @State private var hasUnsavedChanges = false
    @State private var tool: Tool = .browse
    @State private var highlightMode: HighlightMode = .free
    @State private var bookView = false
    @StateObject private var ocr = OCRIndex()
    @State private var searchText = ""
    @State private var lastQuery = ""
    @State private var hits: [OCRHit] = []
    @State private var hitIndex = 0
    @State private var jump: JumpTarget?
    @State private var showingImporter = false
    @State private var errorMessage: String?

    // Highlight tool settings (persisted across launches)
    @AppStorage("highlightColorName") private var highlightColorName: String = HighlightColor.yellow.rawValue
    @AppStorage("highlightStrength") private var highlightStrength: Double = 0.4
    @AppStorage("highlightUseFixedHeight") private var useFixedHeight: Bool = false
    @AppStorage("highlightFixedHeight") private var fixedHeight: Double = 20.0
    @State private var showingHighlightPopover = false

    // Sidebar settings (persisted across launches)
    @AppStorage("isSidebarOpen") private var isSidebarOpen: Bool = true
    @State private var currentPageIndex: Int = 0
    @FocusState private var isSearchFocused: Bool

    private var currentHighlightColor: HighlightColor {
        HighlightColor(rawValue: highlightColorName) ?? .yellow
    }

    private var isErrorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    var body: some View {
        mainContent
            .frame(minWidth: 1300, minHeight: 700)
            .animation(.easeInOut(duration: 0.2), value: isSidebarOpen)
            .animation(.easeInOut(duration: 0.2), value: hits.isEmpty)
            .searchable(text: $searchText, prompt: "Search pages (OCR)")
            .searchFocused($isSearchFocused)
            .onSubmit(of: .search) { submitSearch() }
            .onChange(of: searchText) { _, newValue in
                if newValue.isEmpty { clearSearch() }
            }
            .onChange(of: bookView) { _, newValue in
                if let url = fileURL {
                    UserDefaults.standard.set(newValue, forKey: "bookView:" + url.path)
                }
            }
            .navigationTitle(fileURL?.lastPathComponent ?? "")
            .toolbar { toolbarContent }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.pdf]) { handleFileImport($0) }
            .background(WindowCloseHandler())
            .onAppear { setupOnAppear() }
            .modifier(UndoRedoHandlers(onUndoRedo: { markDocumentEdited() }))
            .modifier(MenuCommandHandlers(
                onOpenDocument: { showingImporter = true },
                onSaveDocument: { if document != nil { _ = save() } },
                onExportTwoUp: { if document != nil { exportTwoUp() } },
                onToggleSidebar: {
                    if document != nil {
                        withAnimation(.easeInOut(duration: 0.2)) { isSidebarOpen.toggle() }
                    }
                },
                onToggleBookView: { if document != nil { bookView.toggle() } },
                onFocusSearch: { if document != nil { focusSearch() } },
                onFindNext: { if !hits.isEmpty { stepHit(1) } },
                onFindPrevious: { if !hits.isEmpty { stepHit(-1) } },
                onSelectHighlight: { if document != nil { toggleHighlight() } },
                onSelectTextBox: {
                    if document != nil {
                        showingHighlightPopover = false
                        toggleTool(.textBox)
                    }
                },
                onSelectErase: {
                    if document != nil {
                        showingHighlightPopover = false
                        toggleTool(.erase)
                    }
                }
            ))
            .modifier(SyncHandlers(
                onSyncNeeded: { syncUnsavedChangesManager() },
                hasUnsavedChanges: hasUnsavedChanges,
                document: document,
                fileURL: fileURL,
                hitsCount: hits.count,
                isSidebarOpen: isSidebarOpen
            ))
            .alert("Couldn't save", isPresented: isErrorPresented) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }

    @ViewBuilder
    private var mainContent: some View {
        if let document {
            HStack(spacing: 0) {
                if isSidebarOpen {
                    UnifiedSidebarView(
                        document: document,
                        isSearchActive: isSearchActive,
                        isSearching: ocr.isIndexing,
                        matchingPages: matchingPages,
                        currentHitPageIndex: currentHitPageIndex,
                        totalMatches: hits.count,
                        currentPageIndex: currentPageIndex,
                        onSelectSearchPage: { item in
                            jumpToPage(item)
                        },
                        onSelectThumbnailPage: { index in
                            jumpToPageIndex(index)
                        },
                        onCloseSearch: {
                            closeSearch()
                        }
                    )
                    .frame(width: 210)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                    Divider()
                }

                PDFKitView(
                    document: document,
                    tool: tool,
                    highlightMode: highlightMode,
                    highlightColor: currentHighlightColor,
                    highlightStrength: highlightStrength,
                    useFixedHeight: useFixedHeight,
                    fixedHeight: CGFloat(fixedHeight),
                    bookView: bookView,
                    jump: jump,
                    onDocumentChanged: {
                        markDocumentEdited()
                    },
                    onCurrentPageChanged: { newPage in
                        currentPageIndex = newPage
                    },
                    onToolChanged: { newTool in
                        tool = newTool
                    }
                )
            }
        } else {
            VStack(spacing: 12) {
                Text("No PDF open")
                Button("Open PDF…") { showingImporter = true }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Group 1: Sidebar & File actions
        ToolbarItem(placement: .navigation) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSidebarOpen.toggle()
                }
            } label: {
                Image(systemName: "sidebar.leading")
            }
            .help(isSidebarOpen ? "Hide Sidebar (⌥⌘S)" : "Show Sidebar (⌥⌘S)")
            .disabled(document == nil)
        }

        ToolbarItem(placement: .navigation) {
            Button("Open", systemImage: "folder") { showingImporter = true }
                .help("Open PDF (⌘O)")
        }

        // Group 2: Annotation tools
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 8) {
                LiquidGlassSegmentContainer {
                    LiquidGlassButton(
                        icon: "highlighter",
                        tooltip: "Highlight Tool (⇧⌘H)",
                        isSelected: tool == .highlight,
                        isEnabled: true
                    ) {
                        toggleHighlight()
                    }
                    .popover(isPresented: $showingHighlightPopover, arrowEdge: .bottom) {
                        HighlightSettingsPopoverView(
                            selectedColor: Binding(
                                get: { currentHighlightColor },
                                set: { highlightColorName = $0.rawValue }
                            ),
                            strength: $highlightStrength,
                            useFixedHeight: $useFixedHeight,
                            fixedHeight: $fixedHeight
                        )
                    }

                    LiquidGlassButton(
                        icon: "character.textbox",
                        tooltip: "Text Box Tool (⇧⌘T)",
                        isSelected: tool == .textBox,
                        isEnabled: true
                    ) {
                        showingHighlightPopover = false
                        toggleTool(.textBox)
                    }

                    LiquidGlassButton(
                        icon: "eraser",
                        tooltip: "Erase Tool (⇧⌘X)",
                        isSelected: tool == .erase,
                        isEnabled: true
                    ) {
                        showingHighlightPopover = false
                        toggleTool(.erase)
                    }
                }

                LiquidGlassSegmentContainer {
                    LiquidGlassButton(
                        icon: "rectangle.dashed",
                        tooltip: "Freeform Highlight",
                        isSelected: highlightMode == .free,
                        isEnabled: tool == .highlight
                    ) {
                        selectHighlightMode(.free)
                    }

                    LiquidGlassButton(
                        icon: "character.cursor.ibeam",
                        tooltip: "Text Selection Highlight",
                        isSelected: highlightMode == .text,
                        isEnabled: tool == .highlight
                    ) {
                        selectHighlightMode(.text)
                    }
                }
                .disabled(tool != .highlight)
                .opacity(tool == .highlight ? 1.0 : 0.45)
            }
            .padding(.leading, 10)
        }

        // Title area: Filename pill
        ToolbarItem(placement: .principal) {
            if let url = fileURL, document != nil {
                Label(url.lastPathComponent, systemImage: "doc.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.45))
                    )
                    .contentShape(Capsule())
                    .onDrag { fileDragProvider() }
                    .help("Drag this into a chat or any app")
            }
        }

        ToolbarItem(placement: .automatic) {
            Spacer()
        }

        // Group 3: View & navigation
        ToolbarItem(placement: .automatic) {
            HStack(spacing: 8) {
                Toggle("Book", systemImage: "book", isOn: $bookView)
                    .toggleStyle(.button)
                    .help("Book View (⌥⌘B)")
                    .disabled(document == nil)

                if ocr.isIndexing {
                    ProgressView(value: ocr.progress)
                        .frame(width: 80)
                        .help("Reading pages…")
                } else if !hits.isEmpty {
                    Text("\(hitIndex + 1)/\(hits.count)").monospacedDigit()
                } else if !lastQuery.isEmpty {
                    Text("No matches")
                }

                Button("Previous match", systemImage: "chevron.up") { stepHit(-1) }
                    .help("Previous Match (⇧⌘G)")
                    .disabled(hits.isEmpty)

                Button("Next match", systemImage: "chevron.down") { stepHit(1) }
                    .help("Next Match (⌘G)")
                    .disabled(hits.isEmpty)
            }
        }

        ToolbarItem(placement: .automatic) {
            Spacer()
        }

        // Group 4: Export & Save
        ToolbarItem(placement: .automatic) {
            HStack(spacing: 8) {
                Button("Export 2-Up", systemImage: "rectangle.split.2x1") { exportTwoUp() }
                    .help("Export 2-Up PDF (⇧⌘E)")
                    .disabled(document == nil)

                Button("Save", systemImage: "square.and.arrow.down") { save() }
                    .help("Save (⌘S)")
                    .disabled(document == nil)
            }
        }
    }

    private var isSearchActive: Bool {
        !lastQuery.isEmpty || !hits.isEmpty
    }

    private var currentHitPageIndex: Int {
        hits.indices.contains(hitIndex) ? hits[hitIndex].pageIndex : -1
    }

    private var matchingPages: [SearchPageItem] {
        var dict: [Int: [Int]] = [:]
        var order: [Int] = []
        for (index, hit) in hits.enumerated() {
            if dict[hit.pageIndex] == nil {
                order.append(hit.pageIndex)
                dict[hit.pageIndex] = [index]
            } else {
                dict[hit.pageIndex]?.append(index)
            }
        }
        return order.map { SearchPageItem(pageIndex: $0, hitIndices: dict[$0] ?? []) }
    }

    private func setupOnAppear() {
        undoManager?.levelsOfUndo = 50
        syncUnsavedChangesManager()
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        if case .success(let url) = result {
            _ = url.startAccessingSecurityScopedResource()
            fileURL = url
            if let doc = PDFDocument(url: url) {
                upgradeFreeHighlights(in: doc)
                document = doc
            } else {
                document = nil
            }
            currentPageIndex = 0
            hasUnsavedChanges = false
            undoManager?.removeAllActions()
            bookView = UserDefaults.standard.bool(forKey: "bookView:" + url.path)
            ocr.reset()
            clearSearch()
            searchText = ""
            syncUnsavedChangesManager()
        }
    }

    private func jumpToPage(_ item: SearchPageItem) {
        guard !item.hitIndices.isEmpty else { return }
        if hits.indices.contains(hitIndex) && hits[hitIndex].pageIndex == item.pageIndex {
            // Already on this page: step to next match on the same page
            if let currentPos = item.hitIndices.firstIndex(of: hitIndex) {
                let nextPos = (currentPos + 1) % item.hitIndices.count
                hitIndex = item.hitIndices[nextPos]
            } else {
                hitIndex = item.hitIndices[0]
            }
        } else {
            hitIndex = item.hitIndices[0]
        }
        currentPageIndex = item.pageIndex
        applySearchMarks()
        jumpToCurrentHit()
    }

    private func jumpToPageIndex(_ index: Int) {
        guard let document, index >= 0, index < document.pageCount else { return }
        currentPageIndex = index
        jump = JumpTarget(pageIndex: index, rect: .zero)
    }

    private func closeSearch() {
        clearSearch()
        searchText = ""
    }

    private func upgradeFreeHighlights(in doc: PDFDocument) {
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let annots = page.annotations
            for a in annots where a.userName == "FreeHighlight" && !(a is RoundedHighlightAnnotation) {
                page.removeAnnotation(a)
                let rounded = RoundedHighlightAnnotation(bounds: a.bounds, forType: .highlight, withProperties: nil)
                rounded.color = a.color
                rounded.userName = a.userName
                rounded.quadrilateralPoints = a.quadrilateralPoints
                page.addAnnotation(rounded)
            }
        }
    }

    private func toggleTool(_ target: Tool) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if tool == target {
                tool = .browse
            } else {
                tool = target
            }
        }
    }

    private func selectHighlightMode(_ mode: HighlightMode) {
        withAnimation(.easeInOut(duration: 0.15)) {
            highlightMode = mode
        }
    }

    private func submitSearch() {
        guard let document else { return }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { clearSearch(); return }

        if !isSidebarOpen {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSidebarOpen = true
            }
        }

        // same query again: Enter jumps to the next match
        if q == lastQuery, !hits.isEmpty { stepHit(1); return }

        lastQuery = q
        Task {
            await ocr.ensureIndexed(document)
            guard self.document === document else { return }   // another file was opened meanwhile
            hits = ocr.search(q, in: document)
            hitIndex = 0
            applySearchMarks()
            jumpToCurrentHit()
        }
    }

    private func stepHit(_ delta: Int) {
        guard !hits.isEmpty else { return }
        hitIndex = (hitIndex + delta + hits.count) % hits.count
        currentPageIndex = hits[hitIndex].pageIndex
        applySearchMarks()
        jumpToCurrentHit()
    }

    private func jumpToCurrentHit() {
        guard hits.indices.contains(hitIndex), let rect = hits[hitIndex].rects.first else { return }
        currentPageIndex = hits[hitIndex].pageIndex
        jump = JumpTarget(pageIndex: hits[hitIndex].pageIndex, rect: rect)
    }

    private func clearSearch() {
        clearSearchMarks()
        hits = []
        hitIndex = 0
        lastQuery = ""
    }

    // Temporary highlights: the current match is orange, the others green
    private func applySearchMarks() {
        guard let document else { return }
        clearSearchMarks()
        for (i, hit) in hits.enumerated() {
            guard let page = document.page(at: hit.pageIndex) else { continue }
            for r in hit.rects {
                let rect = r.insetBy(dx: -2, dy: -2)
                let a = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
                a.color = i == hitIndex ? NSColor.systemOrange.withAlphaComponent(0.55)
                                        : NSColor.systemGreen.withAlphaComponent(0.35)
                a.quadrilateralPoints = [
                    NSValue(point: CGPoint(x: 0, y: rect.height)),
                    NSValue(point: CGPoint(x: rect.width, y: rect.height)),
                    NSValue(point: CGPoint(x: 0, y: 0)),
                    NSValue(point: CGPoint(x: rect.width, y: 0))
                ]
                a.userName = searchMarkTag
                page.addAnnotation(a)
            }
        }
    }

    private func clearSearchMarks() {
        guard let document else { return }
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            for a in page.annotations where a.userName == searchMarkTag {
                page.removeAnnotation(a)
            }
        }
    }

    // Take the temporary search highlights off while saving or dragging the file out
    private func withSearchMarksHidden<T>(_ body: () -> T) -> T {
        let had = !hits.isEmpty
        clearSearchMarks()
        let result = body()
        if had { applySearchMarks() }
        return result
    }

    // Drags a temp copy of the PDF that includes your unsaved highlights; the original isn't touched
    private func fileDragProvider() -> NSItemProvider {
        NotificationCenter.default.post(name: .commitCanvaTextBoxes, object: nil)
        guard let document, let url = fileURL else { return NSItemProvider() }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        if let data = withSearchMarksHidden({ document.dataRepresentation() }), (try? data.write(to: tmp)) != nil {
            return NSItemProvider(contentsOf: tmp) ?? NSItemProvider()
        }
        return NSItemProvider(contentsOf: url) ?? NSItemProvider()
    }

    private func markDocumentEdited() {
        let dirty = undoManager?.canUndo ?? true
        if hasUnsavedChanges != dirty {
            hasUnsavedChanges = dirty
            syncUnsavedChangesManager()
        }
    }

    private func syncUnsavedChangesManager() {
        UnsavedChangesManager.shared.hasUnsavedChanges = hasUnsavedChanges
        UnsavedChangesManager.shared.document = document
        UnsavedChangesManager.shared.fileURL = fileURL
        UnsavedChangesManager.shared.performSave = { [self] in
            save()
        }
        if let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? NSApplication.shared.windows.first {
            window.isDocumentEdited = hasUnsavedChanges
        }
        AppDocumentState.shared.isDocumentOpen = (document != nil)
        AppDocumentState.shared.hasSearchHits = !hits.isEmpty
        AppDocumentState.shared.isSidebarOpen = isSidebarOpen
        AppDocumentState.shared.isBookView = bookView
    }

    private func focusSearch() {
        if !isSidebarOpen {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSidebarOpen = true
            }
        }
        isSearchFocused = true
    }

    private func toggleHighlight() {
        withAnimation(.easeInOut(duration: 0.15)) {
            if tool == .highlight {
                tool = .browse
                showingHighlightPopover = false
            } else {
                tool = .highlight
                showingHighlightPopover = true
            }
        }
    }

    private func exportTwoUp() {
        guard let document, document.pageCount > 0 else { return }
        NotificationCenter.default.post(name: .commitCanvaTextBoxes, object: nil)

        let panel = NSSavePanel()
        panel.title = "Export 2-Up PDF"
        panel.prompt = "Export"
        panel.allowedContentTypes = [.pdf]
        let baseName = fileURL?.deletingPathExtension().lastPathComponent ?? "Document"
        panel.nameFieldStringValue = "\(baseName) (2-Up).pdf"
        panel.canCreateDirectories = true

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let destinationURL = panel.url else { return }
            let pdfData = withSearchMarksHidden {
                TwoUpPDFExporter.buildTwoUpPDFData(from: document)
            }
            guard let pdfData else {
                errorMessage = "Failed to generate 2-up PDF document."
                return
            }
            do {
                try pdfData.write(to: destinationURL)
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        if let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? NSApplication.shared.windows.first {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            let response = panel.runModal()
            completion(response)
        }
    }

    @discardableResult
    private func save() -> Bool {
        NotificationCenter.default.post(name: .commitCanvaTextBoxes, object: nil)
        guard let document, let url = fileURL,
              let data = withSearchMarksHidden({ document.dataRepresentation() }) else { return false }
        do {
            try data.write(to: url)
            hasUnsavedChanges = false
            undoManager?.removeAllActions()
            syncUnsavedChangesManager()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

private struct UndoRedoHandlers: ViewModifier {
    let onUndoRedo: () -> Void

    func body(content: Content) -> some View {
        var v = AnyView(content)
        v = AnyView(v.onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { _ in onUndoRedo() })
        v = AnyView(v.onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)) { _ in onUndoRedo() })
        return v
    }
}

private struct MenuCommandHandlers: ViewModifier {
    let onOpenDocument: () -> Void
    let onSaveDocument: () -> Void
    let onExportTwoUp: () -> Void
    let onToggleSidebar: () -> Void
    let onToggleBookView: () -> Void
    let onFocusSearch: () -> Void
    let onFindNext: () -> Void
    let onFindPrevious: () -> Void
    let onSelectHighlight: () -> Void
    let onSelectTextBox: () -> Void
    let onSelectErase: () -> Void

    func body(content: Content) -> some View {
        var v = AnyView(content)
        v = AnyView(v.onReceive(NotificationCenter.default.publisher(for: .openDocumentTriggered)) { _ in onOpenDocument() })
        v = AnyView(v.onReceive(NotificationCenter.default.publisher(for: .saveDocumentTriggered)) { _ in onSaveDocument() })
        v = AnyView(v.onReceive(NotificationCenter.default.publisher(for: .exportTwoUpTriggered)) { _ in onExportTwoUp() })
        v = AnyView(v.onReceive(NotificationCenter.default.publisher(for: .toggleSidebarTriggered)) { _ in onToggleSidebar() })
        v = AnyView(v.onReceive(NotificationCenter.default.publisher(for: .toggleBookViewTriggered)) { _ in onToggleBookView() })
        v = AnyView(v.onReceive(NotificationCenter.default.publisher(for: .focusSearchTriggered)) { _ in onFocusSearch() })
        v = AnyView(v.onReceive(NotificationCenter.default.publisher(for: .findNextTriggered)) { _ in onFindNext() })
        v = AnyView(v.onReceive(NotificationCenter.default.publisher(for: .findPreviousTriggered)) { _ in onFindPrevious() })
        v = AnyView(v.onReceive(NotificationCenter.default.publisher(for: .selectToolHighlight)) { _ in onSelectHighlight() })
        v = AnyView(v.onReceive(NotificationCenter.default.publisher(for: .selectToolTextBox)) { _ in onSelectTextBox() })
        v = AnyView(v.onReceive(NotificationCenter.default.publisher(for: .selectToolErase)) { _ in onSelectErase() })
        return v
    }
}

private struct SyncHandlers: ViewModifier {
    let onSyncNeeded: () -> Void
    let hasUnsavedChanges: Bool
    let document: PDFDocument?
    let fileURL: URL?
    let hitsCount: Int
    let isSidebarOpen: Bool

    func body(content: Content) -> some View {
        var v = AnyView(content)
        v = AnyView(v.onChange(of: hasUnsavedChanges) { _, _ in onSyncNeeded() })
        v = AnyView(v.onChange(of: document) { _, _ in onSyncNeeded() })
        v = AnyView(v.onChange(of: fileURL) { _, _ in onSyncNeeded() })
        v = AnyView(v.onChange(of: hitsCount) { _, _ in onSyncNeeded() })
        v = AnyView(v.onChange(of: isSidebarOpen) { _, _ in onSyncNeeded() })
        return v
    }
}
