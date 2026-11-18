# PRD — macOS 개발 환경 리소스 관리 앱

Nov 18, 2026

## 개요

**XcodeKeeper**는 저사양 Mac에서 Xcode 개발로 쌓인 디스크 찌꺼기를 찾아 안전하게 지우고, 메모리·스왑 압박을 알려주는 메뉴바 앱이다. 1차 목표는 여유 공간 16GB 상태에서 macOS 업데이트가 가능한 30GB 이상을 확보하고, 그 상태를 유지하는 것이다.

### 배경

- 기기: MacBook Air M1, RAM 8GB, SSD 256GB
- 현재 여유 공간은 약 16GB이다. 빌드 속도가 떨어지고 macOS 업데이트가 설치되지 않는다.
- 지금은 fussycat으로 리소스를 모니터링만 하고 있다. 원인을 찾고 정리하는 일은 수작업이다.

### 문제

1. Xcode는 DerivedData, 시뮬레이터 런타임, DeviceSupport, Archives, 캐시를 사용자 모르게 계속 쌓는다.
2. macOS 저장 공간 화면은 이 항목들을 "시스템 데이터"나 "개발자"로 뭉뚱그려 보여준다. 무엇을 지워도 안전한지 알려주지 않는다.
3. 8GB RAM에서는 스왑이 자주 생긴다. 스왑 파일도 디스크를 차지하고 SSD 쓰기를 늘린다.

### 목표

- 개발 관련 찌꺼기를 항목별 용량, 안전도와 함께 한 화면에 보여준다.
- 체크한 항목을 클릭 한 번으로 휴지통 또는 공식 CLI(`xcrun simctl`)로 정리한다.
- 여유 공간이 기준 아래로 떨어지면 원인 항목과 함께 알린다.
- 메모리 압박과 스왑 사용량을 메뉴바에서 바로 확인한다.

### 비목표 (MVP 범위 밖)

- 전체 디스크 시각화(DaisyDisk 같은 트리맵)
- 일반 앱 언인스톨러, 중복 파일 찾기
- 앱 스토어 배포
- 프로세스 강제 종료나 "메모리 정리" 기능 (macOS에서는 효과가 거의 없고 위험하다)

## 사용자와 시나리오

주 사용자는 개발자 본인 한 명이다. 저사양 Apple Silicon Mac에서 Xcode와 iOS 시뮬레이터를 쓰고, 터미널에 익숙하지만 정리 명령어를 매번 기억하기는 귀찮아한다.

1. **OS 업데이트 전 대청소**: 업데이트 알림이 뜨면 앱을 열고 스캔한다. "안전" 항목을 모두 선택해 정리하고, 확보된 용량과 현재 여유 공간을 확인한다.
2. **빌드가 느려졌을 때**: 메뉴바 아이콘이 노란색이다. 열어 보면 스왑이 4GB이고 메모리 압박이 "경고"다. 메모리를 많이 쓰는 앱 상위 5개를 보고 직접 종료한다.
3. **안 쓰는 시뮬레이터 정리**: iOS 17 런타임이 7GB를 차지하는 것을 보고, 해당 런타임과 그에 묶인 기기를 함께 삭제한다.
4. **예방**: 여유 공간이 30GB 아래로 떨어지면 "DerivedData 12GB" 같은 원인이 담긴 알림을 받는다. 알림을 클릭하면 해당 항목이 선택된 채로 앱이 열린다.

## 기능 요구사항 (MVP)

MVP는 F1\~F4 네 기능이고 우선순위는 F1 > F2 > F4 > F3이다. 각 기능의 수용 기준(AC)을 만족하면 완료로 본다.

### F1. 개발 찌꺼기 스캐너

아래 대상을 스캔해 항목별 실제 점유 용량(allocated size)을 보여주고, 선택한 항목을 정리한다. 대상은 코드에 하드코딩하지 않고 `CleanupTarget` 정의 목록으로 관리한다. 새 대상은 항목 하나만 추가하면 되게 한다.

| 대상 | 경로 / 방법 | 안전도 | 정리 방식 | 비고 |
| --- | --- | --- | --- | --- |
| DerivedData | `~/Library/Developer/Xcode/DerivedData/*` | 안전 | 휴지통 | 프로젝트별 하위 항목과 마지막 수정일 표시 |
| iOS DeviceSupport | `~/Library/Developer/Xcode/iOS DeviceSupport/*` | 주의 | 휴지통 | 버전별 표시, 최신 1개는 기본 미선택 |
| watchOS/tvOS DeviceSupport | `~/Library/Developer/Xcode/*OS DeviceSupport/*` | 주의 | 휴지통 | 있을 때만 표시 |
| Archives | `~/Library/Developer/Xcode/Archives/*` | 주의 | 휴지통 | 날짜별 표시, 기본 미선택 |
| Xcode 캐시 | `~/Library/Caches/com.apple.dt.Xcode` | 안전 | 휴지통 |  |
| SwiftPM 캐시 | `~/Library/Caches/org.swift.swiftpm`, `~/Library/org.swift.swiftpm` | 안전 | 휴지통 | 다음 빌드에서 다시 받음 |
| 사용 불가 시뮬레이터 기기 | `xcrun simctl delete unavailable` | 안전 | CLI | 삭제 전 개수 표시 |
| 시뮬레이터 런타임 | F2에서 처리 | 주의 | CLI |  |
| CocoaPods 캐시 | `~/Library/Caches/CocoaPods` | 안전 | 휴지통 | 있을 때만 |
| Homebrew 캐시 | `brew --cache` 경로 | 안전 | 휴지통 | brew가 있을 때만 |
| 로컬 스냅샷 | `tmutil listlocalsnapshots /` | 정보만 | 없음 | 개수만 표시하고 삭제 방법 안내 |

**AC**

- [ ] 앱 실행 후 스캔 버튼을 누르면 모든 대상의 용량이 산출되고, 스캔 중에도 항목별로 점진 표시된다.
- [ ] 용량은 `totalFileAllocatedSize` 기준이고, `du -sh` 결과와 5% 이내로 일치한다.
- [ ] "안전" 항목은 기본 선택, "주의" 항목은 기본 미선택이다.
- [ ] 정리 전 확인 창에 선택 항목 수와 예상 확보 용량을 보여준다.
- [ ] 파일 삭제는 `FileManager.trashItem`으로만 하고, 영구 삭제는 하지 않는다.
- [ ] 정리 후 "확보됨 N GB"와 "휴지통을 비워야 실제로 확보됨" 안내, 휴지통 비우기 버튼을 보여준다.
- [ ] Xcode가 실행 중이면 DerivedData 정리 전에 경고한다.

### F2. 시뮬레이터 런타임 관리

`xcrun simctl runtime list -j`와 `xcrun simctl list devices -j`를 감싸서 런타임별 용량, 연결된 기기 수, 마지막 사용일을 보여주고 삭제한다.

**AC**

- [ ] 런타임을 플랫폼·버전·용량과 함께 용량 내림차순으로 보여준다.
- [ ] 삭제는 `xcrun simctl runtime delete <identifier>`로 실행하고, 실패하면 stderr를 그대로 보여준다.
- [ ] 현재 Xcode의 기본 런타임(최신 iOS)은 "현재 사용 중" 배지를 달고, 삭제하려 하면 한 번 더 확인한다.
- [ ] 기기 목록에서 사용 불가 기기 일괄 삭제와 개별 기기 삭제(`simctl delete <udid>`)를 지원한다.
- [ ] Xcode 커맨드라인 도구가 없으면 기능을 비활성화하고 설치 방법을 안내한다.

### F3. 메모리·스왑 모니터

**AC**

- [ ] 5초 간격으로 물리 메모리 사용량(App/Wired/Compressed), 메모리 압박 단계, 스왑 사용량을 갱신한다.
- [ ] 메모리 압박은 `kern.memorystatus_vm_pressure_level` 또는 `DispatchSource.makeMemoryPressureSource`로 정상/경고/위험 3단계를 판단한다.
- [ ] 스왑은 `sysctl vm.swapusage`에서 읽는다.
- [ ] 메모리 사용량 상위 5개 프로세스를 보여준다. 종료 기능은 넣지 않고, 클릭하면 활성 모니터를 연다.
- [ ] 스왑이 기준(기본 2GB)을 넘거나 압박이 "위험"이면 메뉴바 아이콘 색이 바뀜다.

### F4. 여유 공간 알림

**AC**

- [ ] 여유 공간은 `volumeAvailableCapacityForImportantUsageKey`로 읽고, Finder 수치와 같은 기준임을 표시한다.
- [ ] 기준값(기본 30GB, 설정 가능)아래로 떨어지면 사용자 알림을 보낸다. 본문에는 마지막 스캔 기준 상위 2개 항목과 용량을 넣는다.
- [ ] 같은 알림은 24시간에 한 번만 보낸다.
- [ ] 알림을 클릭하면 스캐너 창이 열리고 해당 항목이 선택되어 있다.
- [ ] 백그라운드 스캔은 6시간마다 하되, 저전력 모드거나 배터리 20% 이하이면 건너뛴다.

## 비기능 요구사항

이 앱은 저사양 Mac을 위한 것이므로, 앱 자신이 리소스를 적게 쓰는 것이 기능만큼 중요하다.

| 항목 | 기준 |
| --- | --- |
| 유휴 메모리 | 40MB 이하 (메뉴바만 떠 있을 때) |
| 유휴 CPU | 평균 0.5% 이하, 5초 폴링은 팝오버가 열려 있거나 아이콘 색 판단에만 사용 |
| 앱 크기 | 10MB 이하, 서드파티 의존성 없음 |
| 스캔 시간 | F1 전체 스캔 30초 이내 (DerivedData 20GB 기준), 백그라운드 우선순위 `.utility` |
| 취소 | 스캔과 정리는 언제든 취소 가능 (Swift Concurrency 취소 전파) |
| 안전 | 허용 목록 경로만 삭제. 삭제 직전 경로가 허용 루트 안에 있는지 심볼릭 링크를 풀어 재검증 |
| 기록 | 정리 이력(일시, 항목, 용량)을 로컬 JSON에 최근 100건 저장 |
| 대상 OS | macOS 14 Sonoma 이상, Apple Silicon 우선 (Intel 빌드는 보장하지 않음) |
| 언어 | 한국어 UI, 문자열은 String Catalog로 분리 |

## 기술 설계

SwiftUI 메뉴바 앱 하나로 만든다. 샌드박스를 끄고 개인 서명으로 배포하며, 서드파티 의존성은 없다.

&#91;embedded content: 앱 구조 · UI 3, 상태 1, 서비스 5, 시스템 API 4\]

UI는 AppState만 구독한다. 파일·프로세스·시스템 호출은 모두 프로토콜 뒤의 서비스가 맡아, 테스트에서 가짜 구현으로 바꿀 수 있다.

### 스택

- Swift 6, SwiftUI, Swift Concurrency (strict concurrency 켜기)
- `MenuBarExtra(.window)` + 별도 `Window` 씬(스캐너), `Settings` 씬
- 상태 관리: Observation(`@Observable`)
- 설정 저장: `@AppStorage`
- 로그인 시 자동 실행: `SMAppService.mainApp`
- 테스트: Swift Testing

### 권한과 배포

- App Sandbox는 끈다. 샌드박스 안에서는 `~/Library/Developer`를 읽거나 지울 수 없고 `xcrun`도 실행할 수 없다.
- 전체 디스크 접근 권한은 MVP에서 필요 없다. 대상 경로가 모두 사용자 홈 아래에 있다. 접근이 거부되면 항목에 "권한 없음"을 표시한다.
- 배포는 Apple Development 인증서로 서명한 로컬 빌드다. 공증(notarization)은 선택 사항이다.
- `LSUIElement = YES`로 Dock 아이콘을 숨긴다.

### 핵심 모델

```swift
enum Safety { case safe, caution, infoOnly }
enum CleanupMethod { case trash, command([String]), none }

struct CleanupTarget: Identifiable, Sendable {
    let id: String            // "derivedData"
    let title: String         // "DerivedData"
    let explanation: String   // 지워도 되는 이유
    let safety: Safety
    let method: CleanupMethod
    let locate: @Sendable () async throws -> [ScanItem]
}

struct ScanItem: Identifiable, Sendable {
    let id: URL
    let name: String
    let bytes: Int64
    let lastModified: Date?
}
```

### 주요 API

| 용도 | API |
| --- | --- |
| 폴더 용량 | `FileManager.enumerator(at:includingPropertiesForKeys:)` + `totalFileAllocatedSizeKey`, 하드링크 중복 제거는 `fileResourceIdentifierKey` |
| 휴지통 이동 | `FileManager.trashItem(at:resultingItemURL:)` |
| 여유 공간 | `URLResourceValues.volumeAvailableCapacityForImportantUsage` |
| 메모리 통계 | `host_statistics64(HOST_VM_INFO64)`, `sysctl hw.memsize` |
| 스왑 | `sysctlbyname("vm.swapusage")` → `xsw_usage` |
| 메모리 압박 | `DispatchSource.makeMemoryPressureSource` |
| 프로세스별 메모리 | `proc_listpids` + `proc_pid_rusage` (`ri_phys_footprint`) |
| simctl | `Process`로 `/usr/bin/xcrun simctl ... -j` 실행, JSON 디코딩 |
| 알림 | `UNUserNotificationCenter` |
| 주기 작업 | `NSBackgroundActivityScheduler` (6시간, tolerance 1시간) |

### 프로젝트 구조

```
XcodeKeeper/
  XcodeKeeper.xcodeproj
  XcodeKeeper/
    App/            XcodeKeeperApp.swift, AppState.swift
    Models/         CleanupTarget.swift, ScanItem.swift, MemorySnapshot.swift
    Targets/        BuiltinTargets.swift   // F1 표의 대상 정의
    Services/       Scanner.swift, Cleaner.swift, SimctlClient.swift,
                    SystemMonitor.swift, Notifier.swift, ShellRunner.swift
    Views/          MenuBarView.swift, ScannerWindow.swift,
                    SimulatorView.swift, SettingsView.swift
    Resources/      Localizable.xcstrings
  XcodeKeeperTests/
```

## UI 명세

화면은 메뉴바 팝오버, 스캐너 창, 설정 창 세 개다. 팝오버는 "지금 상태"를 보여주고, 스캐너 창은 "정리 작업"을 맡는다.

### 메뉴바 아이콘

- SF Symbol `internaldrive` + 여유 공간 숫자(예: `16G`). 숫자 표시는 설정에서 끌 수 있다.
- 색: 정상 기본색, 여유 공간 기준 미만이거나 스왑 기준 초과면 노랑, 여유 10GB 미만이거나 메모리 압박 "위험"이면 빨강.

### 팝오버 (폭 320pt)

1. **디스크**: 사용/전체 막대, "여유 16.2GB · 업데이트까지 약 14GB 부족" 한 줄
2. **정리 가능**: 마지막 스캔 기준 상위 3개 항목과 용량, 스캔 시각, "스캐너 열기" 버튼
3. **메모리**: 압박 단계 배지, 사용량 막대(App/Wired/Compressed), 스왑 GB
4. **상위 프로세스 5개**: 이름 + 메모리, 클릭 시 활성 모니터 열기
5. **하단**: 설정, 종료

### 스캐너 창 (최소 720×520pt)

- 사이드바: "개발 찌꺼기", "시뮬레이터", "정리 이력"
- 개발 찌꺼기: 대상별 접을 수 있는 그룹 목록. 그룹 행에는 체크박스, 이름, 안전도 배지, 합계 용량을, 하위 행에는 항목별 용량과 마지막 수정일을 둔다. 항목 우클릭으로 "Finder에서 보기".
- 각 대상 이름 옆 (i) 버튼: `explanation`(지워도 되는 이유, 지우면 생기는 일)을 팝오버로 표시
- 하단 바: "선택 9.4GB" + "휴지통으로 정리" 기본 버튼 + "다시 스캔"
- 시뮬레이터: 런타임 표(플랫폼, 버전, 용량, 기기 수, 상태) + 기기 표, 행별 삭제 버튼
- 정리 이력: 일시, 항목, 확보 용량 목록과 누적 합계

### 설정 창

- 여유 공간 알림 기준(GB, 기본 30), 스왑 경고 기준(GB, 기본 2)
- 백그라운드 스캔 켜기/끄기, 로그인 시 실행
- 메뉴바에 숫자 표시
- 대상별 포함/제외 토글

## 마일스톤과 Claude Code 작업 지시

다섯 단계로 나눠 구현한다. 단계마다 빌드와 테스트가 통과한 상태로 커밋하고, 다음 단계로 넘어가기 전에 사용자에게 확인받는다.

1. **M0 뼈대**: 프로젝트 생성, `MenuBarExtra` + 빈 스캐너 창 + 설정 창, `LSUIElement`, 샌드박스 끄기, `ShellRunner`(Process 래퍼, 타임아웃 30초)
2. **M1 스캐너 (F1 읽기)**: `CleanupTarget` 모델, F1 표의 대상 정의, 병렬 용량 계산(`TaskGroup`), 스캐너 창 목록 UI
3. **M2 정리 (F1 쓰기)**: 허용 루트 검증, 휴지통 이동, 확인 창, Xcode 실행 여부 검사, 정리 이력 저장
4. **M3 시뮬레이터 (F2)**: `SimctlClient`, JSON 디코딩, 런타임·기기 표와 삭제
5. **M4 모니터와 알림 (F3, F4)**: `SystemMonitor`, 팝오버 완성, 아이콘 색, 백그라운드 스캔, 알림, 로그인 시 실행

### Claude Code에 줄 지시문

```markdown
이 PRD(XcodeKeeper)를 구현해 줘. 규칙:
- M0부터 순서대로 진행하고, 마일스톤마다 빌드·테스트 통과 후 커밋한 뒤 멈추고 결과를 요약해.
- 빌드는 xcodebuild -scheme XcodeKeeper -derivedDataPath ./build 로 해서
  ~/Library/Developer/Xcode/DerivedData를 늘리지 마. ./build는 .gitignore에 추가.
- 서드파티 패키지 쓰지 마.
- 파일 삭제 코드는 Cleaner 한 곳에만 두고, 허용 루트 검증을 반드시 거치게 해.
  테스트에서 실제 ~/Library를 지우는 일이 없도록 임시 디렉터리와 가짜 FileManager를 써.
- 개발 중 내 맥에서 실제로 파일을 지우는 명령을 실행하기 전에는 물어봐.
```

### 테스트

- **단위**: 용량 합산(하드링크 중복 제외), 허용 루트 검증(`..`, 심볼릭 링크로 루트 밖을 가리키는 경우 거부), simctl JSON 디코딩(샘플 JSON 파일), `vm.swapusage` 파싱
- **통합**: 임시 디렉터리에 가짜 DerivedData 트리를 만들고 스캔→정리→재스캔
- **수동**: 실제 기기에서 `du -sh` 결과와 비교, Activity Monitor로 앱 자체 메모리·CPU 확인

## 리스크, 향후 확장, 미결 사항

### 리스크

| 리스크 | 대응 |
| --- | --- |
| 잘못된 경로 삭제 | 허용 루트 재검증, 휴지통만 사용, 삭제 코드 한 곳에 집중 |
| Xcode 버전마다 경로·simctl 출력이 바뀜 | 대상 정의를 한 파일에 모음, JSON 디코딩 실패 시 항목만 비활성화 |
| 휴지통으로 옮겨도 공간이 안 늘어 혼란 | 정리 후 안내와 휴지통 비우기 버튼 제공 |
| 개발 중 이 앱의 빌드가 공간을 더 줌 | `-derivedDataPath ./build` 고정, 주기적으로 `./build` 삭제 |
| 디스크가 거의 차서 빌드 자체가 실패 | 개발 시작 전 수동 정리로 30GB 이상 확보 |

### 향후 확장 (MVP 이후)

- 프로젝트별 `node_modules`, `.build`, `Pods` 찾기 (지정한 폴더 아래)
- Docker, Android SDK, 오래된 Xcode 본체 등 대상 추가
- 용량 추이 그래프 (항목별 증가 속도)
- 자동 정리 규칙 (예: 14일 넘은 DerivedData 자동 정리)
- fussycat 기능 흡수 여부 검토 (CPU·네트워크 모니터링)

### 미결 사항

- [ ] 앱 이름 확정: XcodeKeeper (GitHub 공개 시 Apple 상표 문제 재검토)
- [ ] 최소 지원 OS를 macOS 14로 할지, 현재 설치된 버전에 맞출지
- [ ] fussycat과 별도 앱으로 둘지, fussycat에 기능을 추가할지
- [ ] GitHub 공개 여부와 라이선스
