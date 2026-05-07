import SwiftUI

/// Full-screen preview of a `SummaryReport` shown before the user exports a PDF.
/// Renders the same SwiftUI pages used by `SummaryReportPDF`, scaled down to
/// fit the device width.
struct SummaryReportPreviewView: View {
    let report: SummaryReport

    @Environment(\.dismiss) private var dismiss

    @State private var isExporting = false
    @State private var pdfFile: PDFFile?
    @State private var showShareSheet = false
    @State private var errorMessage: String?

    private static let pageWidth: CGFloat = 612
    private static let pageHeight: CGFloat = 792
    private static let rowsPerTablePage = 50

    private var tableChunks: [[ReportDay]] {
        guard report.days.count > 31 else { return [] }
        return stride(from: 0, to: report.days.count, by: Self.rowsPerTablePage).map { start in
            let end = min(start + Self.rowsPerTablePage, report.days.count)
            return Array(report.days[start..<end])
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let availableWidth = geo.size.width - 32
                let scale = max(0.1, availableWidth / Self.pageWidth)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        scaledPage(scale: scale) {
                            SummaryReportView(report: report)
                        }
                        let chunks = tableChunks
                        if !chunks.isEmpty {
                            let totalPages = 1 + chunks.count
                            ForEach(Array(chunks.enumerated()), id: \.offset) { idx, chunk in
                                scaledPage(scale: scale) {
                                    SummaryReportTablePage(
                                        report: report,
                                        pageDays: chunk,
                                        pageNumber: idx + 2,
                                        pageCount: totalPages
                                    )
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .background(Theme.background)
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                exportBar
            }
            .sheet(isPresented: $showShareSheet, onDismiss: cleanupPDF) {
                if let pdfFile {
                    ShareSheet(items: [pdfFile.url])
                }
            }
            .alert(
                "Export Failed",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var exportBar: some View {
        VStack(spacing: 0) {
            Button(action: export) {
                HStack(spacing: 8) {
                    if isExporting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Text(isExporting ? "Exporting…" : "Export PDF")
                }
                .font(.system(.headline, design: .rounded, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.caloriesGradient, in: Capsule())
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(isExporting)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .background(.ultraThinMaterial)
    }

    /// Renders a fixed 612x792 page view scaled to fit the available width while
    /// keeping its laid-out frame the same scaled size (so the surrounding
    /// `ScrollView` lays it out correctly).
    @ViewBuilder
    private func scaledPage<V: View>(scale: CGFloat, @ViewBuilder content: () -> V) -> some View {
        content()
            .frame(width: Self.pageWidth, height: Self.pageHeight)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: Self.pageWidth * scale, height: Self.pageHeight * scale)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
    }

    private func export() {
        guard !isExporting else { return }
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                let url = try SummaryReportPDF.render(report)
                pdfFile = PDFFile(url: url)
                showShareSheet = true
            } catch {
                errorMessage = "Could not generate the PDF. Please try again."
            }
        }
    }

    private func cleanupPDF() {
        if let pdfFile {
            try? FileManager.default.removeItem(at: pdfFile.url)
            self.pdfFile = nil
        }
    }
}
