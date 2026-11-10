import SwiftUI
import PDFKit

struct SearchPageThumbnailView: View {
    let page: PDFPage?
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.04))
                    Image(systemName: "doc.text")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
        }
        .frame(width: 52, height: 68)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
        .task(id: page) {
            guard let page else { return }
            thumbnail = page.thumbnail(of: CGSize(width: 104, height: 136), for: .cropBox)
        }
    }
}

struct SearchPageRow: View {
    let pageIndex: Int
    let matchCount: Int
    let isSelected: Bool
    let page: PDFPage?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SearchPageThumbnailView(page: page)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Page \(pageIndex + 1)")
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? .accentColor : .primary)

                    Text("\(matchCount) \(matchCount == 1 ? "match" : "matches")")
                        .font(.system(size: 11))
                        .foregroundColor(isSelected ? .accentColor.opacity(0.85) : .secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(backgroundView)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var backgroundView: some View {
        if isSelected {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.22),
                                Color.accentColor.opacity(0.14)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.40),
                                Color.accentColor.opacity(0.30)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            }
            .shadow(color: Color.accentColor.opacity(0.15), radius: 2, x: 0, y: 1)
        } else if isHovered {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        } else {
            Color.clear
        }
    }
}

struct PageThumbnailCardView: View {
    let pageIndex: Int
    let page: PDFPage?
    let isSelected: Bool
    let action: () -> Void

    @State private var thumbnail: NSImage?
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Rectangle()
                            .fill(Color.white)
                            .aspectRatio(0.77, contentMode: .fit)
                    }
                }
                .frame(maxWidth: 140, maxHeight: 180)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.primary.opacity(0.15),
                            lineWidth: isSelected ? 2.0 : 0.5
                        )
                )
                .shadow(
                    color: isSelected ? Color.accentColor.opacity(0.35) : Color.black.opacity(0.14),
                    radius: isSelected ? 4 : 2,
                    x: 0,
                    y: 1
                )

                Text("\(pageIndex + 1)")
                    .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.10) : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .task(id: page) {
            guard let page else { return }
            thumbnail = page.thumbnail(of: CGSize(width: 280, height: 360), for: .cropBox)
        }
    }
}

struct UnifiedSidebarView: View {
    let document: PDFDocument
    let isSearchActive: Bool
    let isSearching: Bool
    let matchingPages: [SearchPageItem]
    let currentHitPageIndex: Int
    let totalMatches: Int
    let currentPageIndex: Int
    let onSelectSearchPage: (SearchPageItem) -> Void
    let onSelectThumbnailPage: (Int) -> Void
    let onCloseSearch: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if isSearchActive {
                // Search Results Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Search Results")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                        if isSearching {
                            Text("Searching…")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        } else {
                            Text("\(totalMatches) \(totalMatches == 1 ? "match" : "matches") in \(matchingPages.count) \(matchingPages.count == 1 ? "page" : "pages")")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button(action: onCloseSearch) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close search results and show thumbnails")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.03))

                Divider()

                if isSearching {
                    VStack(spacing: 12) {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Searching pages…")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if matchingPages.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("No matches found")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(matchingPages) { item in
                                    SearchPageRow(
                                        pageIndex: item.pageIndex,
                                        matchCount: item.hitIndices.count,
                                        isSelected: item.pageIndex == currentHitPageIndex,
                                        page: document.page(at: item.pageIndex),
                                        action: { onSelectSearchPage(item) }
                                    )
                                    .id(item.pageIndex)
                                }
                            }
                            .padding(8)
                        }
                        .onChange(of: currentHitPageIndex) { _, newPage in
                            if newPage >= 0 {
                                withAnimation {
                                    proxy.scrollTo(newPage, anchor: .center)
                                }
                            }
                        }
                    }
                }
            } else {
                // Thumbnails Mode
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(0..<document.pageCount, id: \.self) { index in
                                PageThumbnailCardView(
                                    pageIndex: index,
                                    page: document.page(at: index),
                                    isSelected: index == currentPageIndex,
                                    action: { onSelectThumbnailPage(index) }
                                )
                                .id(index)
                            }
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 8)
                    }
                    .onChange(of: currentPageIndex) { _, newIndex in
                        if newIndex >= 0 && newIndex < document.pageCount {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(newIndex, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.85)
        )
    }
}
