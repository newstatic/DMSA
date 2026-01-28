import SwiftUI

// MARK: - Conflicts Page

/// 冲突解决页面 - 显示和解决文件冲突
struct ConflictsPage: View {
    @Binding var config: AppConfig
    @ObservedObject private var stateManager = StateManager.shared

    // State
    @State private var conflicts: [ConflictItem] = []
    @State private var searchQuery: String = ""
    @State private var isLoading = false

    // Services
    private let serviceClient = ServiceClient.shared

    // MARK: - Computed Properties

    private var filteredConflicts: [ConflictItem] {
        if searchQuery.isEmpty {
            return conflicts
        }
        return conflicts.filter {
            $0.fileName.localizedCaseInsensitiveContains(searchQuery) ||
            $0.relativePath.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if conflicts.isEmpty && !isLoading {
                // Empty state
                EmptyConflictsView()
            } else {
                // Header
                conflictListHeader
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                    .padding(.bottom, 16)

                // Search bar
                searchBar
                    .padding(.horizontal, 32)
                    .padding(.bottom, 16)

                // Conflict list
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredConflicts) { conflict in
                            ConflictCard(
                                conflict: conflict,
                                onResolve: { resolution in
                                    resolveConflict(conflict, with: resolution)
                                },
                                onShowMore: {
                                    showMoreOptions(for: conflict)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadConflicts()
        }
    }

    // MARK: - Header

    private var conflictListHeader: some View {
        ConflictListHeader(
            conflictCount: conflicts.count,
            onResolveAll: { resolution in
                resolveAllConflicts(with: resolution)
            }
        )
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("conflicts.search".localized, text: $searchQuery)
                .textFieldStyle(.plain)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Actions

    private func loadConflicts() {
        isLoading = true

        // Simulated conflict loading - in real app, this would come from ServiceClient
        Task {
            // TODO: Load actual conflicts from service
            // let conflicts = try? await serviceClient.getConflicts()

            await MainActor.run {
                // For demo purposes, use empty list
                // In production, populate from service
                self.conflicts = []
                self.isLoading = false

                // Update app state
                stateManager.conflictCount = conflicts.count
            }
        }
    }

    private func resolveConflict(_ conflict: ConflictItem, with resolution: ConflictResolution) {
        Task {
            // TODO: Implement actual conflict resolution via service
            // try await serviceClient.resolveConflict(conflict.id, resolution: resolution)

            await MainActor.run {
                // Remove resolved conflict from list
                conflicts.removeAll { $0.id == conflict.id }
                stateManager.conflictCount = conflicts.count
            }
        }
    }

    private func resolveAllConflicts(with resolution: ConflictResolution) {
        Task {
            // TODO: Implement batch conflict resolution
            // try await serviceClient.resolveAllConflicts(resolution: resolution)

            await MainActor.run {
                conflicts.removeAll()
                stateManager.conflictCount = 0
            }
        }
    }

    private func showMoreOptions(for conflict: ConflictItem) {
        // Show more options menu - handled by ConflictCard's menu
    }
}

// MARK: - Previews

#if DEBUG
struct ConflictsPage_Previews: PreviewProvider {
    static var sampleConflicts: [ConflictItem] = [
        ConflictItem(
            fileName: "project_backup.zip",
            relativePath: "Projects/2026/",
            localSize: 125_000_000,
            localModified: Date().addingTimeInterval(-3600),
            externalSize: 128_500_000,
            externalModified: Date().addingTimeInterval(-7200)
        ),
        ConflictItem(
            fileName: "report.docx",
            relativePath: "Documents/Work/",
            localSize: 2_500_000,
            localModified: Date().addingTimeInterval(-1800),
            externalSize: 2_600_000,
            externalModified: Date().addingTimeInterval(-3600)
        ),
        ConflictItem(
            fileName: "config.json",
            relativePath: "Settings/",
            localSize: 15_000,
            localModified: Date().addingTimeInterval(-600),
            externalSize: 14_500,
            externalModified: Date().addingTimeInterval(-1200)
        )
    ]

    static var previews: some View {
        Group {
            // With conflicts
            ConflictsPagePreview(conflicts: sampleConflicts)
                .frame(width: 700, height: 700)
                .previewDisplayName("With Conflicts")

            // Empty state
            ConflictsPage(config: .constant(AppConfig()))
                .frame(width: 700, height: 500)
                .previewDisplayName("Empty State")
        }
    }
}

// Preview helper to inject sample conflicts
struct ConflictsPagePreview: View {
    let conflicts: [ConflictItem]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ConflictListHeader(conflictCount: conflicts.count) { _ in }
                    .padding(.horizontal, 32)

                ForEach(conflicts) { conflict in
                    ConflictCard(conflict: conflict, onResolve: { _ in })
                }
                .padding(.horizontal, 32)
            }
            .padding(.vertical, 24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}
#endif
