import SwiftUI

/// 添加硬盘 Sheet
struct AddDiskSheet: View {
    let onAdd: (DiskConfig) -> Void
    let existingDiskNames: Set<String>

    @Environment(\.dismiss) private var dismiss

    @State private var diskName: String = ""
    @State private var mountPath: String = ""
    @State private var priority: Int = 0
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("disks.add.title".localized)
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Content
            Form {
                Section {
                    TextField("disks.add.name".localized, text: $diskName)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        TextField("disks.add.mountPath".localized, text: $mountPath)
                            .textFieldStyle(.roundedBorder)

                        Button("common.browse".localized) {
                            browseForVolume()
                        }
                    }

                    Stepper(value: $priority, in: 0...10) {
                        HStack {
                            Text("disks.add.priority".localized)
                            Spacer()
                            Text("\(priority)")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if showError {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .formStyle(.grouped)
            .padding()

            Divider()

            // Footer
            HStack {
                Button("common.cancel".localized) {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("common.add".localized) {
                    addDisk()
                }
                .keyboardShortcut(.return)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 400, height: 300)
    }

    private var isValid: Bool {
        !diskName.isEmpty && !mountPath.isEmpty && !existingDiskNames.contains(diskName)
    }

    private func browseForVolume() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Volumes")

        if panel.runModal() == .OK, let url = panel.url {
            mountPath = url.path
            if diskName.isEmpty {
                diskName = url.lastPathComponent
            }
        }
    }

    private func addDisk() {
        guard isValid else { return }

        if existingDiskNames.contains(diskName) {
            errorMessage = "disks.add.error.duplicate".localized
            showError = true
            return
        }

        let disk = DiskConfig(name: diskName, mountPath: mountPath, priority: priority)
        onAdd(disk)
        dismiss()
    }
}

#Preview {
    AddDiskSheet(
        onAdd: { _ in },
        existingDiskNames: ["Backup", "Portable"]
    )
}
