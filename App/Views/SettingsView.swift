import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.showFreeSpaceInMenuBar) private var showFreeSpace = true

    var body: some View {
        Form {
            Toggle("메뉴바에 여유 공간 숫자 표시", isOn: $showFreeSpace)
                .accessibilityIdentifier("settings.showFreeSpace")
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 420, height: 110)
    }
}
