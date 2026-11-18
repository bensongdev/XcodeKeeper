import SwiftUI

enum WindowID {
    static let scanner = "scanner"
}

// 단위 테스트는 이 앱을 테스트 호스트로 실행한다. 그때는 메뉴바 아이콘이나 창을 띄우지 않고 앞으로 나오지도 않게 해서
// 테스트 중에도 사용자의 작업을 방해하지 않는다. 실제 디스크를 읽는 앱 상태도 만들지 않는다.
// UI 테스트로 실행한 앱에는 이 환경 변수가 없다.
@main
enum AppEntry {
    @MainActor
    static func main() {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            TestHostApp.main()
        } else {
            XcodeKeeperApp.main()
        }
    }
}

private struct TestHostApp: App {
    @NSApplicationDelegateAdaptor(TestHostDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
private final class TestHostDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Dock에 나타나지 않고 활성화(앞으로 나오기)도 하지 않는다.
        NSApp.setActivationPolicy(.prohibited)
    }
}

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
