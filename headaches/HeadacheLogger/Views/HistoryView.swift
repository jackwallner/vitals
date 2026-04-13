import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \HeadacheEvent.timestamp, order: .reverse) private var events: [HeadacheEvent]
    @State private var exportURL: URL?
    @State private var showExportError = false
    @State private var noteTargetID: UUID?

    var body: some View {
        List {
            if events.isEmpty {
                ContentUnavailableView(
                    "No Headaches Logged Yet",
                    systemImage: "waveform.path.ecg",
                    description: Text("Use the Headache button on the Headache Logger tab and the app will start building a timeline you can share with your doctor.")
                )
                .accessibilityIdentifier("historyEmptyState")
                .listRowBackground(Color.clear)
            } else {
                Section {
                    SummaryGrid(events: events)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)

                Section("Entries") {
                    ForEach(events, id: \.id) { event in
                        DetailedEventRow(event: event) {
                            noteTargetID = event.id
                        }
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .listStyle(.plain)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("History")
        .accessibilityIdentifier("historyView")
        .toolbar {
            if !events.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        export()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("exportHistoryButton")
                }
            }
        }
        .sheet(isPresented: shareSheetBinding, onDismiss: removeTemporaryExport) {
            if let exportURL {
                ShareSheet(items: [exportURL])
            }
        }
        .alert("Export Failed", isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The CSV export could not be created. Please try again.")
        }
        .sheet(isPresented: noteSheetBinding) {
            if let targetID = noteTargetID,
               let event = events.first(where: { $0.id == targetID }) {
                EventNotesSheet(event: event)
            }
        }
    }

    private var noteSheetBinding: Binding<Bool> {
        Binding(
            get: { noteTargetID != nil },
            set: { isPresented in
                if !isPresented {
                    noteTargetID = nil
                }
            }
        )
    }

    private var shareSheetBinding: Binding<Bool> {
        Binding(
            get: { exportURL != nil },
            set: { isPresented in
                if !isPresented {
                    removeTemporaryExport()
                }
            }
        )
    }

    private func export() {
        do {
            exportURL = try ExportService.exportCSV(events: events)
        } catch {
            showExportError = true
        }
    }

    private func removeTemporaryExport() {
        if let exportURL {
            try? FileManager.default.removeItem(at: exportURL)
            self.exportURL = nil
        }
    }
}

private struct SummaryGrid: View {
    let events: [HeadacheEvent]

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                SummaryCard(title: "Total Logs", value: "\(events.count)", tint: .pink)
                SummaryCard(title: "Most Common Day", value: mostCommonWeekday ?? "—", tint: .orange)
            }
            HStack(spacing: 12) {
                SummaryCard(title: "Most Common Time", value: mostCommonPartOfDay ?? "—", tint: .purple)
                SummaryCard(title: "Avg Temp", value: averageTemperatureText, tint: .blue)
            }
        }
        .padding(.horizontal)
    }

    private var mostCommonWeekday: String? {
        groupedMax(from: events.map(\.weekdayName))
    }

    private var mostCommonPartOfDay: String? {
        groupedMax(from: events.map { $0.partOfDay.rawValue.capitalized })
    }

    private var averageTemperatureText: String {
        let temps = events.compactMap(\.temperatureC)
        guard !temps.isEmpty else { return "—" }
        let avg = temps.reduce(0, +) / Double(temps.count)
        return "\(Int(avg.rounded()))C"
    }

    private func groupedMax(from values: [String]) -> String? {
        values
            .reduce(into: [:]) { counts, value in
                counts[value, default: 0] += 1
            }
            .max(by: { lhs, rhs in lhs.value < rhs.value })?
            .key
    }
}

private struct SummaryCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(tint)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DetailedEventRow: View {
    let event: HeadacheEvent
    var onEditNotes: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.headline)
                    Text("\(event.weekdayName) • \(event.partOfDay.rawValue.capitalized)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)

                Text(event.captureStatus.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(statusColor)

                Button {
                    onEditNotes()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .tint(Color(red: 0.95, green: 0.25, blue: 0.36))
                .accessibilityLabel((event.userNotes?.isEmpty == false) ? "Edit note" : "Add note")
                .accessibilityIdentifier("historyEntryNotesButton")
            }

            if let notes = event.userNotes, !notes.isEmpty {
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .accessibilityIdentifier("historyEntryNotesPreview")
            }

            if !event.locationLabel.isEmpty || event.weatherSummary != nil {
                Text([event.locationLabel.isEmpty ? nil : event.locationLabel, weatherLine]
                    .compactMap { $0 }
                    .joined(separator: " • "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                DataPill(title: "Steps", value: event.stepsToday?.formatted(.number) ?? "—")
                DataPill(title: "Sleep", value: event.sleepHoursLastNight.map { String(format: "%.1fh", $0) } ?? "—")
                DataPill(title: "AQI", value: event.usAQI.map { String(format: "%.0f", $0) } ?? "—")
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal)
        .accessibilityIdentifier("historyEventRow")
    }

    private var weatherLine: String? {
        guard let weatherSummary = event.weatherSummary else { return nil }
        if let temperature = event.temperatureC {
            return "\(weatherSummary), \(Int(temperature.rounded()))C"
        }
        return weatherSummary
    }

    private var statusColor: Color {
        switch event.captureStatus {
        case .complete: .green
        case .partial: .orange
        case .failed: .red
        case .pending: .blue
        }
    }
}

private struct EventNotesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let event: HeadacheEvent
    @State private var text: String

    init(event: HeadacheEvent) {
        self.event = event
        _text = State(initialValue: event.userNotes ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Optional context for you or your clinician (triggers, meds, sleep, stress).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                TextEditor(text: $text)
                    .frame(minHeight: 220)
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding()
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        event.userNotes = trimmed.isEmpty ? nil : trimmed
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .accessibilityIdentifier("eventNotesSheet")
    }
}

private struct DataPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.monospacedDigit())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
