import AppKit
import SwiftUI

/// 스캐너 창 "개발 찌꺼기": 대상별 접을 수 있는 그룹 목록과 하단 바.
struct JunkListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if case .finished(let outcome) = appState.cleanupPhase {
                CleanupResultBanner(outcome: outcome)
            }
            if appState.lastScanDate == nil && !appState.isScanning && !hasAnyResult {
                ContentUnavailableView {
                    Label("아직 스캔하지 않았습니다", systemImage: "magnifyingglass")
                } description: {
                    Text("스캔을 누르면 개발 찌꺼기가 얼마나 쌓였는지 대상별로 보여 줍니다.")
                }
                .accessibilityIdentifier("junk.empty")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(appState.scanResults.visibleTargets) { target in
                        TargetGroupRow(target: target)
                    }
                }
                .accessibilityIdentifier("junk.list")
            }
            Divider()
            bottomBar
        }
        .sheet(isPresented: confirmationBinding) {
            if case .confirming(let warning) = appState.cleanupPhase {
                CleanupConfirmSheet(xcodeRunningWarning: warning)
                    .environment(appState)
            }
        }
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { if case .confirming = appState.cleanupPhase { true } else { false } },
            set: { if !$0 { appState.dismissCleanupConfirmation() } }
        )
    }

    private var hasAnyResult: Bool {
        appState.scanResults.targets.contains { appState.scanResults.status(of: $0.id) != .notScanned }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(ScannerSection.junk.title)
                .font(.title2.bold())
                .accessibilityIdentifier("detail.title")
            Spacer()
            if let date = appState.lastScanDate {
                Text("마지막 스캔 \(date.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("scan.lastDate")
            }
        }
        .padding(20)
    }

    private var bottomBar: some View {
        let scanned = appState.lastScanDate != nil
        return HStack {
            Text("선택 \(ByteFormat.gigabytes(appState.scanResults.selectedBytes))")
                .font(.body.monospacedDigit().bold())
                .accessibilityIdentifier("selection.total")
            Spacer()
            if appState.isCleaning {
                ProgressView().controlSize(.small)
                Text("정리 중…")
                    .accessibilityIdentifier("cleanup.progress")
                Button("취소") { appState.cancelCleanup() }
                    .accessibilityIdentifier("cleanup.cancel")
            } else if appState.isScanning {
                Button("취소") { appState.cancelScan() }
                    .accessibilityIdentifier("scan.cancel")
            }
            Button(scanned ? "다시 스캔" : "스캔") { appState.startScan() }
                .modifier(DefaultActionIf(isOn: !scanned))
                .disabled(appState.isScanning || appState.isCleaning)
                .accessibilityIdentifier("scan.start")
            if scanned {
                Button("휴지통으로 정리") { appState.requestCleanup() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!appState.canStartCleanup)
                    .accessibilityIdentifier("cleanup.start")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

/// 조건부 기본 버튼(Return 키). 스캔 전에는 "스캔", 스캔 후에는 "휴지통으로 정리"가 기본 버튼이다.
private struct DefaultActionIf: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn { content.keyboardShortcut(.defaultAction) } else { content }
    }
}

/// 대상 하나의 그룹 행과 하위 항목들.
private struct TargetGroupRow: View {
    @Environment(AppState.self) private var appState
    let target: CleanupTarget
    @State private var isExpanded = false
    @State private var showsExplanation = false

    private var status: TargetScanStatus { appState.scanResults.status(of: target.id) }

    // DisclosureGroup은 macOS 목록에서 라벨 전체를 체크박스 하나로 합쳐 설명 버튼과 상태를 따로 접근할 수 없게 한다.
    // 그래서 펼침 버튼과 하위 행을 직접 그린다.
    var body: some View {
        Group {
            HStack(spacing: 8) {
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 12)
                }
                .buttonStyle(.borderless)
                .disabled(status.items.isEmpty)
                .accessibilityLabel(Text(isExpanded ? "\(target.title) 접기" : "\(target.title) 펼치기"))
                .accessibilityIdentifier("target.\(target.id).expand")
                groupCheckbox
                Text(target.title)
                    .accessibilityIdentifier("target.\(target.id).title")
                Button {
                    showsExplanation.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("\(target.title) 설명"))
                .accessibilityIdentifier("target.\(target.id).info")
                .popover(isPresented: $showsExplanation, arrowEdge: .bottom) {
                    Text(target.explanation)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 320, alignment: .leading)
                        .padding(14)
                        .accessibilityIdentifier("target.\(target.id).explanation")
                }
                SafetyBadge(safety: target.safety)
                Spacer()
                statusView
            }
            .padding(.vertical, 2)
            if isExpanded {
                ForEach(status.items) { item in
                    ItemRow(target: target, item: item)
                        .padding(.leading, 40)
                }
            }
        }
    }

    @ViewBuilder private var groupCheckbox: some View {
        if target.isSelectable {
            let bindings = status.items.map { item in
                Binding(
                    get: { appState.scanResults.isSelected(target.id, item.id) },
                    set: { appState.scanResults.setSelected($0, targetID: target.id, itemID: item.id) }
                )
            }
            Group {
                // 항목이 없을 때 Toggle(sources:)는 '켬'으로 그려지므로, 꺼진 비활성 체크박스를 따로 보여 준다.
                if bindings.isEmpty {
                    Toggle(isOn: .constant(false)) { Text(target.title) }
                        .disabled(true)
                } else {
                    Toggle(sources: bindings, isOn: \.self) { Text(target.title) }
                }
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityIdentifier("target.\(target.id).checkbox")
        } else {
            Image(systemName: "info.square")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var statusView: some View {
        let text = TargetStatusText.text(for: status, safety: target.safety)
        switch status {
        case .scanning:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                statusText(text)
            }
        case .failed(let failure):
            statusText(text)
                .foregroundStyle(.orange)
                .help(failureDetail(failure))
        default:
            statusText(text)
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(.body.monospacedDigit())
            .accessibilityIdentifier("target.\(target.id).status")
    }

    private func failureDetail(_ failure: ScanFailure) -> String {
        switch failure {
        case .permissionDenied: String(localized: "이 폴더를 읽을 권한이 없습니다.")
        case .commandFailed(let message), .other(let message): message
        }
    }
}

private struct ItemRow: View {
    @Environment(AppState.self) private var appState
    let target: CleanupTarget
    let item: ScanItem

    var body: some View {
        HStack(spacing: 8) {
            if target.isSelectable && !target.selectsAsGroup {
                Toggle(isOn: Binding(
                    get: { appState.scanResults.isSelected(target.id, item.id) },
                    set: { appState.scanResults.setSelected($0, targetID: target.id, itemID: item.id) }
                )) { Text(item.name) }
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }
            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityIdentifier("item.\(target.id).\(item.name)")
            Spacer()
            if let date = item.lastModified {
                Text(date.formatted(date: .numeric, time: .omitted))
                    .foregroundStyle(.secondary)
            }
            if target.safety != .infoOnly {
                Text(ByteFormat.size(item.bytes))
                    .font(.body.monospacedDigit())
                    .accessibilityIdentifier("item.\(target.id).\(item.name).size")
                    .frame(minWidth: 70, alignment: .trailing)
            }
        }
        .contextMenu {
            if let url = item.url {
                Button("Finder에서 보기") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
    }
}

private struct SafetyBadge: View {
    let safety: Safety

    var body: some View {
        Text(safety.title)
            .font(.caption.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch safety {
        case .safe: .green
        case .caution: .orange
        case .infoOnly: .secondary
        }
    }
}
