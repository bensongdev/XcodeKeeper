import SwiftUI

/// 스캐너 창. 사이드바에서 "개발 찌꺼기", "시뮬레이터", "정리 이력"을 고른다.
struct ScannerWindow: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView {
            List(ScannerSection.allCases, selection: $appState.selectedSection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
                    .accessibilityIdentifier("sidebar.\(section.rawValue)")
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            ScannerDetailView(section: appState.selectedSection ?? .junk)
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}

private struct ScannerDetailView: View {
    let section: ScannerSection

    var body: some View {
        switch section {
        case .junk:
            JunkListView()
        case .history:
            HistoryView()
        case .simulators:
            SimulatorView()
        }
    }
}
