import SwiftUI

struct LogsView: View {
    @ObservedObject var logManager = LogManager.shared
    @State private var selectedLevel: LogLevel? = nil
    @State private var selectedCategory: LogCategory? = nil
    @State private var searchText = ""
    @State private var showingClearAlert = false
    @State private var showingShareSheet = false
    @State private var autoScroll = true
    
    private var filteredLogs: [AppLogEntry] {
        logManager.filteredLogs(level: selectedLevel, category: selectedCategory, searchText: searchText)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search logs...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            
            // Filter buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Level filters
                    FilterButton(title: "All", isSelected: selectedLevel == nil) {
                        selectedLevel = nil
                    }
                    
                    ForEach([LogLevel.error, .warning, .upload, .network, .bot], id: \.self) { level in
                        FilterButton(title: level.rawValue, isSelected: selectedLevel == level) {
                            selectedLevel = selectedLevel == level ? nil : level
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 8)
            
            // Stats
            HStack(spacing: 16) {
                Label("\(filteredLogs.count)", systemImage: "list.bullet")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .font(.caption)
                    .toggleStyle(.switch)
                    .labelsHidden()
                
                Text("Auto")
                    .font(.caption)
                    .foregroundColor(autoScroll ? .purple : .secondary)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            Divider()
            
            // Logs list
            if filteredLogs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No logs found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(filteredLogs) { entry in
                                LogRowView(entry: entry)
                                    .id(entry.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: filteredLogs.count) { _ in
                        if autoScroll, let lastLog = filteredLogs.last {
                            withAnimation {
                                proxy.scrollTo(lastLog.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showingShareSheet = true }) {
                        Label("Share Logs", systemImage: "square.and.arrow.up")
                    }
                    
                    Button(role: .destructive, action: { showingClearAlert = true }) {
                        Label("Clear All Logs", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: [logManager.exportLogsAsText()])
        }
        .alert("Clear All Logs?", isPresented: $showingClearAlert) {
            Button("Clear", role: .destructive) {
                logManager.clearAllLogs()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will delete all \(logManager.logs.count) log entries. This action cannot be undone.")
        }
    }
}

// MARK: - Filter Button

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .foregroundColor(isSelected ? .white : .purple)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.purple : Color.purple.opacity(0.1))
                .cornerRadius(16)
        }
    }
}

// MARK: - Log Row View

struct LogRowView: View {
    let entry: AppLogEntry
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // Time
                Text(entry.timeString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                
                // Level badge
                Text(entry.level.rawValue)
                    .font(.system(.caption2, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(entry.color)
                    .cornerRadius(4)
                
                // Category
                Text(entry.category.rawValue)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Expand button
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Message preview
            Text(entry.message)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(isExpanded ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color(uiColor: .systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
