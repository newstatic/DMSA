import SwiftUI

/// Notification settings view
struct NotificationSettingsView: View {
    @Binding var config: AppConfig

    @State private var customScheduleEnabled: Bool = false
    @State private var scheduleStart: Date = Calendar.current.date(from: DateComponents(hour: 22, minute: 0)) ?? Date()
    @State private var scheduleEnd: Date = Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? Date()

    var body: some View {
        SettingsContentView(title: L10n.Settings.Notifications.title) {
            // Enable notifications
            ToggleRow(
                title: L10n.Settings.Notifications.enable,
                isOn: $config.notifications.enabled
            )

            if config.notifications.enabled {
                SectionDivider(title: L10n.Settings.Notifications.types)

                // Notification types
                VStack(alignment: .leading, spacing: 8) {
                    CheckboxRow(
                        title: L10n.Settings.Notifications.onDiskConnect,
                        isChecked: $config.notifications.showOnDiskConnect
                    )

                    CheckboxRow(
                        title: L10n.Settings.Notifications.onDiskDisconnect,
                        isChecked: $config.notifications.showOnDiskDisconnect
                    )

                    CheckboxRow(
                        title: L10n.Settings.Notifications.onSyncStart,
                        isChecked: $config.notifications.showOnSyncStart
                    )

                    CheckboxRow(
                        title: L10n.Settings.Notifications.onSyncComplete,
                        isChecked: $config.notifications.showOnSyncComplete
                    )

                    CheckboxRow(
                        title: L10n.Settings.Notifications.onSyncError,
                        isChecked: $config.notifications.showOnSyncError
                    )
                }

                SectionDivider(title: L10n.Settings.Notifications.style)

                // Sound
                CheckboxRow(
                    title: L10n.Settings.Notifications.playSound,
                    isChecked: $config.notifications.soundEnabled
                )

                SectionDivider(title: L10n.Settings.Notifications.doNotDisturb)

                // Do Not Disturb
                VStack(alignment: .leading, spacing: 8) {
                    CheckboxRow(
                        title: L10n.Settings.Notifications.followSystem,
                        isChecked: .constant(true) // This would need system integration
                    )
                    .disabled(true)

                    CheckboxRow(
                        title: L10n.Settings.Notifications.customSchedule,
                        isChecked: $customScheduleEnabled
                    )

                    if customScheduleEnabled {
                        HStack(spacing: 12) {
                            Text(L10n.Settings.Notifications.scheduleFrom)
                                .foregroundColor(.secondary)

                            DatePicker(
                                "",
                                selection: $scheduleStart,
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                            .frame(width: 80)

                            Text(L10n.Settings.Notifications.scheduleTo)
                                .foregroundColor(.secondary)

                            DatePicker(
                                "",
                                selection: $scheduleEnd,
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                            .frame(width: 80)
                        }
                        .padding(.leading, 24)
                    }
                }

                Divider()
                    .padding(.vertical, 8)

                // Test notification button
                HStack {
                    Spacer()

                    Button(L10n.Settings.Notifications.testNotification) {
                        sendTestNotification()
                    }
                }
            }
        }
    }

    private func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = L10n.App.name
        content.body = "This is a test notification from DMSA."

        if config.notifications.soundEnabled {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send test notification: \(error)")
            }
        }
    }
}

import UserNotifications

// MARK: - Previews

#if DEBUG
struct NotificationSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationSettingsView(config: .constant(AppConfig()))
            .frame(width: 450, height: 500)
    }
}
#endif
