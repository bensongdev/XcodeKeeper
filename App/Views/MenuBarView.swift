import AppKit
import SwiftUI

/// 메뉴바 아이콘: `internaldrive` + 여유 공간 숫자(설정에서 끌 수 있음). 상태에 따라 아이콘 색이 바뀐다.
struct MenuBarLabel: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let level = appState.statusLevel
        Group {
            if appState.settings.showFreeSpaceInMenuBar {
                Label {
                    Text(ByteFormat.menuBarLabel(appState.availableBytes))
                } icon: {
                    Self.icon(for: level)
                }
                .labelStyle(.titleAndIcon)
            } else {
                Self.icon(for: level)
            }
        }
        .accessibilityLabel(Text("XcodeKeeper"))
        .accessibilityValue(Text(level.accessibilityText))
    }

    /// 메뉴바는 이미지를 템플릿(단색)으로 그리므로, 색을 넣으려면 템플릿이 아닌 이미지를 만든다.
    /// NSImage는 글꼴 크기를 따르지 않으므로 세 단계 모두 메뉴바 글자 크기로 같은 방식으로 만든다.
    static func icon(for level: StatusLevel) -> Image {
        let size = NSImage.SymbolConfiguration(pointSize: NSFont.systemFontSize, weight: .regular)
        let config = level.color.map { size.applying(NSImage.SymbolConfiguration(paletteColors: [$0])) } ?? size
        guard let image = NSImage(systemSymbolName: "internaldrive", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return Image(systemName: "internaldrive") }
        image.isTemplate = level.color == nil
        return Image(nsImage: image)
    }
}

extension StatusLevel {
    /// 아이콘 색. 정상이면 nil(시스템 기본색).
    var color: NSColor? {
        switch self {
        case .normal: nil
        case .warning: .systemYellow
        case .critical: .systemRed
        }
    }

    var accessibilityText: String {
        switch self {
        case .normal: String(localized: "정상")
        case .warning: String(localized: "주의")
        case .critical: String(localized: "위험")
        }
    }
}

/// 메뉴바 팝오버. "지금 상태"를 보여 준다: 디스크, 정리 가능, 메모리, 상위 프로세스.
struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    /// 이 팝오버를 담은 패널. 다른 창을 열 때 닫는다(같은 앱의 창이 앞에 와도 패널은 스스로 닫히지 않는다).
    @State private var panel = PanelReference()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DiskSection()
            Divider()
            CleanableSection {
                closePanelAndOpen { openWindow(id: WindowID.scanner) }
            }
            Divider()
            MemorySection()
            Divider()
            ProcessSection()
            Divider()
            HStack {
                Button("설정…") {
                    closePanelAndOpen { openSettings() }
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
        .background(WindowReader(reference: panel))
        .onAppear { appState.setPopoverVisible(true) }
        .onDisappear { appState.setPopoverVisible(false) }
    }

    private func closePanelAndOpen(_ open: () -> Void) {
        panel.window?.close()
        open()
        NSApp.activate()
    }
}

/// 뷰를 담은 NSWindow를 기억한다. 바뀌어도 다시 그릴 필요가 없으므로 관찰하지 않는 참조 객체에 둔다.
@MainActor
final class PanelReference {
    weak var window: NSWindow?
}

private struct WindowReader: NSViewRepresentable {
    let reference: PanelReference

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.reference = reference
        return view
    }

    func updateNSView(_ nsView: ReaderView, context: Context) {}

    final class ReaderView: NSView {
        var reference: PanelReference?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { reference?.window = window }
        }
    }
}

private struct DiskSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("디스크")
                    .font(.headline)
                Spacer()
                Text("Finder와 같은 기준")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(Text("중요한 용도로 사용 가능한 용량(volumeAvailableCapacityForImportantUsage)"))
            }
            if let available = appState.availableBytes, let total = appState.totalBytes, total > 0 {
                UsageBar(segments: [(Double(total - available) / Double(total), .accentColor)])
                    .accessibilityIdentifier("menu.diskBar")
                Text("사용 \(ByteFormat.gigabytes(total - available)) / 전체 \(ByteFormat.gigabytes(total))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("menu.diskUsage")
            }
            Text(freeSpaceLine)
                .font(.body.monospacedDigit())
                .foregroundStyle(appState.statusLevel == .normal ? Color.primary : levelColor)
                .accessibilityIdentifier("menu.freeSpace")
        }
    }

    private var freeSpaceLine: String {
        let free = String(localized: "여유 \(ByteFormat.gigabytes(appState.availableBytes))")
        guard let shortage = FreeSpaceAlert.shortageText(
            availableBytes: appState.availableBytes, thresholdBytes: appState.settings.freeSpaceThresholdBytes
        ) else { return free }
        return "\(free) · \(shortage)"
    }

    private var levelColor: Color {
        (appState.availableBytes ?? .max) < StatusLevel.criticalFreeBytes ? .red : .orange
    }
}

private struct CleanableSection: View {
    @Environment(AppState.self) private var appState
    let openScanner: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("정리 가능")
                    .font(.headline)
                Spacer()
                if let date = appState.lastScanDate {
                    Text("\(date.formatted(date: .abbreviated, time: .shortened)) 스캔")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("menu.lastScan")
                }
            }
            let top = appState.scanResults.topCleanable(limit: AppState.popoverTopCount)
            if appState.lastScanDate == nil {
                Text("아직 스캔하지 않았습니다")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("menu.cleanable.empty")
            } else if top.isEmpty {
                Text("정리할 항목이 없습니다")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("menu.cleanable.empty")
            } else {
                ForEach(Array(top.enumerated()), id: \.element.targetID) { index, item in
                    HStack {
                        Text(item.title)
                            .accessibilityIdentifier("menu.cleanable.\(index).title")
                        Spacer()
                        Text(ByteFormat.size(item.bytes))
                            .font(.body.monospacedDigit())
                            .accessibilityIdentifier("menu.cleanable.\(index).size")
                    }
                }
            }
            Button("스캐너 열기", action: openScanner)
                .accessibilityIdentifier("menu.openScanner")
        }
    }
}

private struct MemorySection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("메모리")
                    .font(.headline)
                Spacer()
                if let memory = appState.memory {
                    Text(memory.pressure.title)
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(memory.pressure.color.opacity(0.2), in: Capsule())
                        .foregroundStyle(memory.pressure.color)
                        .accessibilityIdentifier("menu.memory.pressure")
                }
            }
            if let memory = appState.memory, memory.totalBytes > 0 {
                let total = Double(memory.totalBytes)
                UsageBar(segments: [
                    (Double(memory.appBytes) / total, .blue),
                    (Double(memory.wiredBytes) / total, .orange),
                    (Double(memory.compressedBytes) / total, .purple)
                ])
                HStack(spacing: 10) {
                    legend("App", memory.appBytes, .blue, id: "app")
                    legend("Wired", memory.wiredBytes, .orange, id: "wired")
                    legend("압축", memory.compressedBytes, .purple, id: "compressed")
                }
                .font(.caption.monospacedDigit())
                Text("스왑 \(ByteFormat.gigabytes(memory.swapUsedBytes))")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(memory.swapUsedBytes > appState.settings.swapThresholdBytes ? .orange : .primary)
                    .accessibilityIdentifier("menu.memory.swap")
            } else {
                Text("메모리 정보를 읽지 못했습니다")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func legend(_ title: String, _ bytes: Int64, _ color: Color, id: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(title) \(ByteFormat.gigabytes(bytes))")
                .accessibilityIdentifier("menu.memory.\(id)")
        }
    }
}

extension MemoryPressure {
    var color: Color {
        switch self {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }
}

private struct ProcessSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("메모리 상위 프로세스")
                .font(.headline)
            ForEach(Array(appState.topProcesses.enumerated()), id: \.element.id) { index, process in
                Button {
                    Self.openActivityMonitor()
                } label: {
                    HStack {
                        Text(process.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(ByteFormat.size(process.bytes))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Text("활성 모니터 열기"))
                // 버튼은 안의 Text들을 한 요소로 합치므로(라벨 "Xcode, 2.1GB") 식별자는 버튼에 단다.
                .accessibilityIdentifier("menu.process.\(index)")
            }
        }
    }

    static func openActivityMonitor() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") else {
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// 가로 막대. 각 조각은 (전체 대비 비율, 색).
private struct UsageBar: View {
    let segments: [(Double, Color)]

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    Rectangle()
                        .fill(segment.1)
                        .frame(width: geometry.size.width * min(max(segment.0, 0), 1))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 8)
        .background(Color.secondary.opacity(0.2))
        .clipShape(Capsule())
    }
}
