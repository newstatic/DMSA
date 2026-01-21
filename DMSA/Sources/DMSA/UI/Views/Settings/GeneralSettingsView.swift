import SwiftUI

/// General settings view
struct GeneralSettingsView: View {
    @Binding var config: AppConfig
    @ObservedObject private var localizationManager = LocalizationManager.shared

    var body: some View {
        SettingsContentView(title: L10n.Settings.General.title) {
            // Startup Section
            SectionHeader(title: L10n.Settings.General.startup)

            VStack(alignment: .leading, spacing: 8) {
                CheckboxRow(
                    title: L10n.Settings.General.launchAtLogin,
                    isChecked: $config.general.launchAtLogin
                )

                CheckboxRow(
                    title: L10n.Settings.General.showInDock,
                    isChecked: $config.general.showInDock
                )
            }

            SectionDivider(title: L10n.Settings.General.updates)

            VStack(alignment: .leading, spacing: 8) {
                CheckboxRow(
                    title: L10n.Settings.General.checkForUpdates,
                    isChecked: $config.general.checkForUpdates
                )
            }

            SectionDivider(title: L10n.Settings.General.language)

            PickerRow(
                title: L10n.Settings.General.language,
                selection: $config.general.language
            ) {
                Text(L10n.Settings.General.languageSystem).tag("system")
                Text(L10n.Settings.General.languageEn).tag("en")
                Text(L10n.Settings.General.languageZhHans).tag("zh-Hans")
                Text(L10n.Settings.General.languageZhHant).tag("zh-Hant")
            }
            .onChange(of: config.general.language) { newLanguage in
                localizationManager.setLanguage(newLanguage)
            }

            SectionDivider(title: L10n.Settings.General.menuBarStyle)

            RadioGroup(
                options: UIConfig.MenuBarStyle.allCases,
                selection: $config.ui.menuBarStyle,
                label: { menuBarStyleLabel($0) },
                description: { menuBarStyleDescription($0) }
            )
        }
    }

    private func menuBarStyleLabel(_ style: UIConfig.MenuBarStyle) -> String {
        switch style {
        case .icon: return L10n.Settings.General.menuBarIcon
        case .iconText: return L10n.Settings.General.menuBarIconText
        case .text: return L10n.Settings.General.menuBarIconProgress
        }
    }

    private func menuBarStyleDescription(_ style: UIConfig.MenuBarStyle) -> String? {
        switch style {
        case .icon: return nil
        case .iconText: return nil
        case .text: return nil
        }
    }
}

// Make MenuBarStyle conform to Identifiable
extension UIConfig.MenuBarStyle: Identifiable {
    var id: String { rawValue }
}

// MARK: - Previews

#if DEBUG
struct GeneralSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        GeneralSettingsView(config: .constant(AppConfig()))
            .frame(width: 450, height: 500)
    }
}
#endif
