import SwiftUI

enum SettingsKey {
    static let showFreeSpaceInMenuBar = "showFreeSpaceInMenuBar"
}

/// 메뉴바 아이콘: `internaldrive` + 여유 공간 숫자(설정에서 끌 수 있음).
struct MenuBarLabel: View {
    @Environment(AppState.self) private var appState
    @AppStorage(SettingsKey.showFreeSpaceInMenuBar) private var showFreeSpace = true

    var body: some View {
        if showFreeSpace {
            Label(ByteFormat.menuBarLabel(appState.availableBytes), systemImage: "internaldrive")
                .labelStyle(.titleAndIcon)
        } else {
            Image(systemName: "internaldrive")
                .accessibilityLabel(Text("XcodeKeeper"))
        }
    }
}

/// 메뉴바 팝오버. "지금 상태"를 보여 준다.
struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("디스크")
                .font(.headline)
            Text("여유 \(ByteFormat.gigabytes(appState.availableBytes))")
                .font(.body.monospacedDigit())
                .accessibilityIdentifier("menu.freeSpace")

            Divider()

            Button("스캐너 열기") {
                openWindow(id: WindowID.scanner)
                NSApp.activate()
            }
            .accessibilityIdentifier("menu.openScanner")

            Divider()

            HStack {
                SettingsLink {
                    Text("설정…")
                }
                .accessibilityIdentifier("menu.settings")
                Spacer()
                Button("종료") {
                    NSApp.terminate(nil)
                }
                .accessibilityIdentifier("menu.quit")
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear { appState.refreshDiskSpace() }
    }
}
