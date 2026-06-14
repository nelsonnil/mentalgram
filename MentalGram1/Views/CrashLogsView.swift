import SwiftUI

struct CrashLogsView: View {
    @State private var reports: [CrashReport] = []
    @State private var selectedReport: CrashReport? = nil
    @State private var showingClearAlert = false
    @State private var shareItems: [Any]? = nil
    @State private var showingShareAll = false

    var body: some View {
        Group {
            if reports.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Crash Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !reports.isEmpty {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        let all = reports.map { $0.plainText }.joined(separator: "\n\n")
                        shareItems = [all]
                        showingShareAll = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        showingClearAlert = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .alert("Delete all crash logs?", isPresented: $showingClearAlert) {
            Button("Delete", role: .destructive) {
                CrashLoggerService.shared.clearAll()
                reports = []
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $selectedReport) { report in
            CrashDetailView(report: report)
        }
        .sheet(isPresented: $showingShareAll) {
            if let items = shareItems {
                ShareSheet(items: items)
            }
        }
        .onAppear { reload() }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 52))
                .foregroundColor(.green)
            Text("No crashes recorded")
                .font(.title3.weight(.semibold))
            Text("If a crash occurs it will appear here automatically on the next launch.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            Section {
                Text("\(reports.count) crash\(reports.count == 1 ? "" : "es") recorded. Share the report(s) with the developer to help diagnose the issue.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            ForEach(reports) { report in
                Button { selectedReport = report } label: {
                    CrashRowView(report: report)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func reload() {
        reports = CrashLoggerService.shared.storedReports
    }
}

// MARK: - Row

private struct CrashRowView: View {
    let report: CrashReport

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: report.type == "Signal" ? "waveform.badge.exclamationmark" : "bolt.trianglebadge.exclamationmark.fill")
                .font(.system(size: 22))
                .foregroundColor(.red)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(report.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Text(formattedDate(report.date))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Text(report.reason)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Label("v\(report.appVersion) (\(report.buildNumber))", systemImage: "app.badge")
                    Text("·")
                    Text("iOS \(report.osVersion)")
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .padding(.vertical, 4)
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Detail

struct CrashDetailView: View {
    let report: CrashReport
    @Environment(\.dismiss) private var dismiss
    @State private var showingShare = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header card
                    VStack(alignment: .leading, spacing: 8) {
                        Label(report.name, systemImage: "bolt.trianglebadge.exclamationmark.fill")
                            .font(.headline)
                            .foregroundColor(.red)
                        Text(report.reason)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Divider()
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                            infoRow("Type", report.type)
                            infoRow("Date", report.timestamp)
                            infoRow("App", "v\(report.appVersion) (build \(report.buildNumber))")
                            infoRow("OS", "iOS \(report.osVersion)")
                            infoRow("Device", report.deviceModel)
                        }
                        .font(.footnote)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)

                    // Stack trace
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Stack Trace")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)
                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(report.stackTrace)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                        }
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
            .navigationTitle("Crash Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingShare = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showingShare) {
                ShareSheet(items: [report.plainText])
            }
        }
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundColor(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - UIActivityViewController wrapper — defined in LogsView.swift
