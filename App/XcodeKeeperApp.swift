import SwiftUI

enum WindowID {
    static let scanner = "scanner"
}

@main
struct XcodeKeeperApp: App {
    private let launch = LaunchConfiguration.current()
    @State private var appState: AppState

    init() {
        _appState = State(initialValue: launch.makeAppState())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            MenuBarLabel()
                .environment(appState)
                .modifier(UITestWindowOpener(windowToOpen: launch.windowToOpen))
        }
        .menuBarExtraStyle(.window)

        Window("XcodeKeeper", id: WindowID.scanner) {
            ScannerWindow()
                .environment(appState)
        }
        .defaultSize(width: 760, height: 540)

        Settings {
            SettingsView()
        }
    }
}

/// UI 테스트에서 시작 시 지정한 창을 연다. 메뉴바 아이콘은 실행 직후 항상 그려지므로 여기에 붙인다.
private struct UITestWindowOpener: ViewModifier {
    let windowToOpen: String?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content.task {
            switch windowToOpen {
            case WindowID.scanner: openWindow(id: WindowID.scanner)
            case "settings": openSettings()
            default: return
            }
            NSApp.activate()
        }
    }
}
