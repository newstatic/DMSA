import SwiftUI

/// VFS (虚拟文件系统) 设置视图
/// 管理 macFUSE 和特权助手
struct VFSSettingsView: View {
    @Binding var config: AppConfig
    @StateObject private var viewModel = VFSSettingsViewModel()

    var body: some View {
        SettingsContentView(title: "虚拟文件系统") {
            // macFUSE 状态
            macFUSESection

            Divider()

            // Helper 状态
            helperSection

            Divider()

            // VFS 状态
            vfsStatusSection
        }
        .onAppear {
            viewModel.refresh()
        }
    }

    // MARK: - macFUSE Section

    private var macFUSESection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "macFUSE")

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("状态:")
                            .foregroundColor(.secondary)
                        Text(viewModel.macFUSEStatusText)
                            .foregroundColor(viewModel.macFUSEStatusColor)
                            .fontWeight(.medium)
                    }

                    if let version = viewModel.macFUSEVersion {
                        HStack {
                            Text("版本:")
                                .foregroundColor(.secondary)
                            Text(version)
                        }
                    }

                    Text("macFUSE 用于创建虚拟文件系统，实现透明的文件合并显示")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !viewModel.isMacFUSEInstalled {
                    Button("下载 macFUSE") {
                        viewModel.openMacFUSEDownload()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("检查更新") {
                        viewModel.openMacFUSEDownload()
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    // MARK: - Helper Section

    private var helperSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "特权助手")

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("状态:")
                            .foregroundColor(.secondary)
                        Text(viewModel.helperStatusText)
                            .foregroundColor(viewModel.helperStatusColor)
                            .fontWeight(.medium)
                    }

                    if let version = viewModel.helperVersion {
                        HStack {
                            Text("版本:")
                                .foregroundColor(.secondary)
                            Text(version)
                        }
                    }

                    Text("特权助手用于保护本地缓存目录，防止用户直接访问")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(spacing: 8) {
                    if !viewModel.isHelperInstalled {
                        Button("安装助手") {
                            viewModel.installHelper()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("重新安装") {
                            viewModel.reinstallHelper()
                        }

                        if #available(macOS 13.0, *) {
                            Button("卸载助手") {
                                viewModel.uninstallHelper()
                            }
                            .foregroundColor(.red)
                        }
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Helper 路径信息
            if viewModel.isHelperInstalled {
                VStack(alignment: .leading, spacing: 4) {
                    Text("安装位置:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("/Library/PrivilegedHelperTools/com.ttttt.dmsa.helper")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - VFS Status Section

    private var vfsStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "VFS 挂载状态")

            if viewModel.mountedVFS.isEmpty {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("没有活跃的 VFS 挂载")
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            } else {
                ForEach(viewModel.mountedVFS, id: \.targetDir) { mount in
                    VFSMountRow(mount: mount)
                }
            }
        }
    }
}

// MARK: - VFS Mount Row

struct VFSMountRow: View {
    let mount: VFSMountInfo

    var body: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(mount.targetDir)
                    .fontWeight(.medium)

                HStack(spacing: 16) {
                    Label(mount.localDir, systemImage: "internaldrive")
                    Label(mount.externalDir, systemImage: "externaldrive")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - View Model

class VFSSettingsViewModel: ObservableObject {
    @Published var isMacFUSEInstalled = false
    @Published var macFUSEVersion: String?
    @Published var macFUSEStatusText = "检查中..."
    @Published var macFUSEStatusColor: Color = .secondary

    @Published var isHelperInstalled = false
    @Published var helperVersion: String?
    @Published var helperStatusText = "检查中..."
    @Published var helperStatusColor: Color = .secondary

    @Published var mountedVFS: [VFSMountInfo] = []

    private let privilegedClient = PrivilegedClient.shared

    func refresh() {
        checkMacFUSE()
        checkHelper()
        checkMountedVFS()
    }

    // MARK: - macFUSE

    private func checkMacFUSE() {
        let availability = FUSEManager.shared.checkFUSEAvailability()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch availability {
            case .available(let version):
                self.isMacFUSEInstalled = true
                self.macFUSEVersion = version
                self.macFUSEStatusText = "已安装"
                self.macFUSEStatusColor = .green
            case .notInstalled, .frameworkMissing:
                self.isMacFUSEInstalled = false
                self.macFUSEVersion = nil
                self.macFUSEStatusText = "未安装"
                self.macFUSEStatusColor = .red
            case .versionTooOld(let current, _):
                self.isMacFUSEInstalled = true
                self.macFUSEVersion = current
                self.macFUSEStatusText = "版本过旧"
                self.macFUSEStatusColor = .orange
            case .loadError(let error):
                self.isMacFUSEInstalled = false
                self.macFUSEVersion = nil
                self.macFUSEStatusText = "加载失败: \(error.localizedDescription)"
                self.macFUSEStatusColor = .red
            }
        }
    }

    func openMacFUSEDownload() {
        if let url = URL(string: "https://macfuse.github.io/") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Helper

    private func checkHelper() {
        let status = privilegedClient.getHelperStatus()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch status {
            case .installed:
                self.isHelperInstalled = true
                self.helperStatusText = "已安装"
                self.helperStatusColor = .green
                self.fetchHelperVersion()
            case .notInstalled:
                self.isHelperInstalled = false
                self.helperVersion = nil
                self.helperStatusText = "未安装"
                self.helperStatusColor = .red
            case .requiresApproval:
                self.isHelperInstalled = false
                self.helperVersion = nil
                self.helperStatusText = "需要批准"
                self.helperStatusColor = .orange
            case .notFound:
                self.isHelperInstalled = false
                self.helperVersion = nil
                self.helperStatusText = "未找到"
                self.helperStatusColor = .red
            case .unknown:
                self.isHelperInstalled = false
                self.helperVersion = nil
                self.helperStatusText = "未知"
                self.helperStatusColor = .secondary
            }
        }
    }

    private func fetchHelperVersion() {
        Task {
            do {
                let version = try await privilegedClient.getHelperVersion()
                await MainActor.run {
                    self.helperVersion = version
                }
            } catch {
                Logger.shared.warn("获取 Helper 版本失败: \(error.localizedDescription)")
            }
        }
    }

    func installHelper() {
        do {
            try privilegedClient.installHelper()
            checkHelper()
        } catch {
            Logger.shared.error("安装 Helper 失败: \(error.localizedDescription)")
        }
    }

    func reinstallHelper() {
        // 先卸载再安装
        if #available(macOS 13.0, *) {
            do {
                try privilegedClient.uninstallHelper()
            } catch {
                Logger.shared.warn("卸载 Helper 失败: \(error.localizedDescription)")
            }
        }

        installHelper()
    }

    @available(macOS 13.0, *)
    func uninstallHelper() {
        do {
            try privilegedClient.uninstallHelper()
            checkHelper()
        } catch {
            Logger.shared.error("卸载 Helper 失败: \(error.localizedDescription)")
        }
    }

    // MARK: - VFS Mounts

    private func checkMountedVFS() {
        // 从 VFSCore 获取挂载信息
        // 这里暂时使用空数组，实际应该从 VFSCore.shared 获取
        DispatchQueue.main.async { [weak self] in
            self?.mountedVFS = []
        }
    }
}

// MARK: - Data Types

struct VFSMountInfo {
    let targetDir: String
    let localDir: String
    let externalDir: String
}

// MARK: - Preview

#if DEBUG
struct VFSSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        VFSSettingsView(config: .constant(AppConfig()))
            .frame(width: 600, height: 500)
    }
}
#endif
