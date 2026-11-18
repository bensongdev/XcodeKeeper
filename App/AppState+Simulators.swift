import Foundation

/// 시뮬레이터 화면 상태.
enum SimulatorScreenState: Sendable, Equatable {
    case notLoaded
    case loading
    case loaded(SimulatorInventory)
    /// Xcode/개발자 도구가 없음. 원문 메시지.
    case toolMissing(String)
    /// 목록을 읽지 못함.
    case failed(String)

    var inventory: SimulatorInventory? {
        if case .loaded(let inventory) = self { return inventory }
        return nil
    }
}

/// 삭제할 대상.
enum SimulatorDeletion: Sendable, Equatable {
    case runtime(SimRuntime)
    case device(SimDevice)
    case unavailableDevices(count: Int)
}

/// 삭제 확인 창 상태. 현재 사용 중인 런타임은 두 번째 확인(`isSecondStep`)을 거친다.
struct SimulatorConfirmation: Sendable, Equatable {
    let deletion: SimulatorDeletion
    var isSecondStep = false
}

/// 시뮬레이터 런타임·기기 불러오기와 삭제 흐름.
extension AppState {
    func loadSimulators() async {
        simulatorState = .loading
        do {
            simulatorState = .loaded(try await simulatorManager.loadInventory())
        } catch SimctlError.toolMissing(let message) {
            simulatorState = .toolMissing(message)
        } catch let error as SimctlError {
            simulatorState = .failed(error.message)
        } catch {
            simulatorState = .failed(error.localizedDescription)
        }
    }

    /// 삭제 버튼: 확인 창을 띄운다. 삭제할 수 없는 런타임, 사용 불가 기기 0개, 진행 중이면 무시.
    func requestSimulatorDeletion(_ deletion: SimulatorDeletion) {
        guard !isSimulatorBusy else { return }
        switch deletion {
        case .runtime(let runtime) where !runtime.isDeletable: return
        case .unavailableDevices(let count) where count == 0: return
        default: break
        }
        simulatorError = nil
        simulatorConfirmation = SimulatorConfirmation(deletion: deletion)
    }

    func cancelSimulatorDeletion() {
        simulatorConfirmation = nil
    }

    /// 확인 버튼. 현재 사용 중인 런타임이면 첫 확인에서 두 번째 확인으로 넘어가고, 그다음에 삭제한다.
    func confirmSimulatorDeletion() async {
        guard var confirmation = simulatorConfirmation else { return }
        if case .runtime(let runtime) = confirmation.deletion, runtime.isCurrent, !confirmation.isSecondStep {
            confirmation.isSecondStep = true
            simulatorConfirmation = confirmation
            return
        }
        simulatorConfirmation = nil
        isSimulatorBusy = true
        defer { isSimulatorBusy = false }
        do {
            switch confirmation.deletion {
            case .runtime(let runtime): try await simulatorManager.deleteRuntime(runtime.id)
            case .device(let device): try await simulatorManager.deleteDevice(device.id)
            case .unavailableDevices: try await simulatorManager.deleteUnavailableDevices()
            }
        } catch SimctlError.toolMissing(let message) {
            simulatorState = .toolMissing(message)
            return
        } catch let error as SimctlError {
            simulatorError = error.message
            return
        } catch {
            simulatorError = error.localizedDescription
            return
        }
        await loadSimulators()
    }
}
