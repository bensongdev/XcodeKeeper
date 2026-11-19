# XcodeKeeper

**저사양 Mac에서 Xcode가 쌓은 디스크 찌꺼기를 찾아 안전하게 정리하고, 메모리·스왑·여유 공간을 메뉴바에서 알려 주는 macOS 앱**

8GB RAM / 256GB SSD Mac에서 Xcode로 개발하면 DerivedData, 시뮬레이터 런타임, DeviceSupport, 캐시가 모르는 사이에 수십 GB씩 쌓이고, macOS 저장 공간 화면은 이를 "시스템 데이터"로 뭉뚱그려 보여 줍니다. XcodeKeeper는 무엇이 얼마나 차지하는지, 지워도 안전한지를 항목별로 보여 주고, 고른 항목만 휴지통으로 옮깁니다.

## 기능

### 메뉴바
- 아이콘 옆에 여유 공간(예: `16G`)을 표시합니다. 설정에서 숫자를 끌 수 있습니다.
- 아이콘 색으로 상태를 알립니다.
  - **노랑**: 여유 공간이 알림 기준(기본 30GB) 미만이거나 스왑이 경고 기준(기본 2GB) 초과
  - **빨강**: 여유 공간 10GB 미만이거나 메모리 압박 "위험"
- 팝오버: 디스크 사용량과 "업데이트까지 약 N GB 부족", 마지막 스캔 기준 정리 가능 상위 3개, 메모리(App/Wired/압축)·압박 단계·스왑, 메모리 사용량 상위 프로세스 5개(누르면 활성 모니터가 열림)

### 개발 찌꺼기 정리
| 대상 | 안전도 | 정리 방식 |
| --- | --- | --- |
| DerivedData (프로젝트별) | 안전 | 휴지통 |
| Xcode 캐시, SwiftPM 캐시, CocoaPods 캐시, Homebrew 캐시 | 안전 | 휴지통 |
| 사용 불가 시뮬레이터 기기 | 안전 | `xcrun simctl delete unavailable` |
| iOS / watchOS / tvOS DeviceSupport (버전별) | 주의 | 휴지통 |
| Archives (날짜별) | 주의 | 휴지통 |
| 로컬 스냅샷 | 정보만 | 개수와 삭제 방법 안내 |

- "안전"은 기본 선택, "주의"는 기본 미선택입니다. 최신 DeviceSupport 1개는 선택되지 않습니다.
- 각 대상의 (i) 버튼은 지워도 되는 이유와 지우면 생기는 일을 설명합니다.
- 정리 전에 항목 수와 예상 확보 용량을 확인합니다. Xcode가 실행 중이면 DerivedData 정리 전에 경고합니다.
- 정리 이력(일시, 항목, 확보 용량)을 최근 100건까지 보관합니다.

### 시뮬레이터
- 런타임을 용량 순으로 보여 주고(연결된 기기 수, 마지막 사용일), 현재 Xcode가 쓰는 런타임에는 "현재 사용 중" 배지를 답니다. 이 런타임을 지울 때는 한 번 더 확인합니다.
- 기기 목록에서 개별 삭제와 사용 불가 기기 일괄 삭제를 지원합니다. 실패하면 `simctl`의 오류 메시지를 그대로 보여 줍니다.

### 알림과 백그라운드 스캔
- 6시간마다(실행 직후 한 번 포함) 백그라운드에서 스캔합니다. 저전력 모드이거나 배터리 20% 이하이면 건너뜁니다.
- 여유 공간이 기준 미만이면 "정리 가능: DerivedData 4.2GB, …"처럼 원인이 담긴 알림을 24시간에 한 번 보냅니다. 알림을 누르면 해당 항목이 선택된 채로 스캐너 창이 열립니다.

## 안전 원칙
- 파일은 **휴지통으로만** 옮깁니다(`FileManager.trashItem`). 영구 삭제하지 않으므로 휴지통에서 되돌릴 수 있습니다. 실제 공간은 휴지통을 비워야 확보됩니다.
- 대상마다 허용된 폴더 안의 경로만 지웁니다. 지우기 직전에 심볼릭 링크를 풀어 허용 폴더 안인지 다시 확인합니다.
- 시뮬레이터 런타임·기기 삭제는 Apple 공식 CLI(`xcrun simctl`)로 하며, 휴지통을 거치지 않으므로 확인 창에서 이를 알립니다. 잘못된 인자로 모든 런타임이 지워지지 않도록 식별자는 UUID 형식만 허용합니다.
- 프로세스를 종료하거나 "메모리를 정리"하는 기능은 없습니다.
- 네트워크를 쓰지 않고, 서드파티 의존성이 없습니다.

## 요구 사항과 설치
- macOS 14 Sonoma 이상, Apple Silicon 권장
- 시뮬레이터 기능에는 Xcode(및 `xcode-select`로 선택된 개발자 도구)가 필요합니다. 없으면 해당 화면만 비활성화되고 설치 방법을 안내합니다.

설치: Developer ID로 서명·공증된 `XcodeKeeper-<버전>.zip`을 풀어 `XcodeKeeper.app`을 `/응용 프로그램`으로 옮기고 실행합니다. Dock 아이콘 없이 메뉴바에만 나타납니다.

**권한**
- 알림: 처음 알림을 보낼 때 허용 여부를 묻습니다. 거부해도 메뉴바 아이콘 색과 팝오버는 그대로 동작합니다.
- 로그인 시 실행: 설정에서 켭니다(기본 끔). macOS가 "로그인 항목 추가됨" 알림을 띄우며, 승인이 필요하면 시스템 설정 > 일반 > 로그인 항목에서 허용합니다.
- `~/Library/Developer` 등을 읽고 정리해야 하므로 App Sandbox를 쓰지 않습니다.

**설정**: 여유 공간 알림 기준(GB), 스왑 경고 기준(GB), 백그라운드 스캔, 로그인 시 실행, 메뉴바 숫자 표시.

## 개발

이 저장소는 AI 에이전트가 구현하고 사람이 승인하는 흐름으로 만들었습니다. 작업 규칙은 [AGENTS.md](AGENTS.md), 요구사항은 [docs/PRD.md](docs/PRD.md), 마일스톤별 수용 기준은 [docs/features/](docs/features/)에 있습니다. 처음 개발 환경을 갖춘다면 [docs/GETTING_STARTED.md](docs/GETTING_STARTED.md)를 참고하세요.

### 준비와 빌드
```bash
brew install xcodegen swiftlint
./scripts/bootstrap.sh          # project.yml에서 XcodeKeeper.xcodeproj 생성
open XcodeKeeper.xcodeproj
```
`*.xcodeproj`는 `project.yml`(XcodeGen)에서 만들어지는 파일이라 Git에 올리지 않습니다. 빌드 설정과 타깃은 `project.yml`에서만 바꿉니다. 로컬 빌드는 ad-hoc 서명(`CODE_SIGN_IDENTITY = -`)을 씁니다.

### 구조
```
App/
  XcodeKeeperApp.swift   MenuBarExtra + 스캐너 창 + 설정 창, 알림 클릭 처리
  AppState*.swift        앱 상태(@Observable). 뷰는 이것만 구독
  AppSettings.swift      UserDefaults 설정
  Models/                대상·스캔 결과·정리·시뮬레이터·메모리 모델과 판정 규칙
  Targets/               BuiltinTargets.swift: 정리 대상 정의 목록(항목 하나 추가로 확장)
  Services/              JunkScanner, SizeCalculator, PathGuard, Cleaner(유일한 삭제 지점),
                         SimctlClient, SystemMonitor, Notifier, HistoryStore, ShellRunner
  Views/                 메뉴바 팝오버, 스캐너 창(찌꺼기·시뮬레이터·이력), 설정
  Support/               UI 테스트·스냅샷용 가짜 데이터(실제 디스크·명령을 건드리지 않음)
AppTests/                단위 테스트, 화면 밖 스냅샷 테스트
AppUITests/              실제 클릭 UI 테스트
scripts/                 verify.sh, release.sh, generate-app-icon.swift 등
```
시스템 호출(파일, 프로세스, simctl, 알림, 로그인 항목)은 모두 프로토콜 뒤의 서비스가 맡고, 테스트에서는 가짜 구현으로 바꿉니다. UI 테스트와 스냅샷은 `-UITestMode YES`의 고정 데이터를 써서 실제 `~/Library`와 휴지통을 건드리지 않습니다.

### 검증
```bash
./scripts/verify.sh all     # 린트 + 빌드 + 단위 테스트 + 화면 밖 스냅샷 (마우스·키보드를 쓰지 않음)
./scripts/verify.sh build   # 빌드만
./scripts/verify.sh unit    # 단위 테스트만
AI_UI_CONTROL=1 ./scripts/verify.sh full  # all + 실제 클릭 UI 테스트 (마우스·키보드를 씀)
./scripts/prune-evidence.sh # 실행 증거 목록과 크기 (삭제하지 않음)
```
- 결과는 `.artifacts/runs/<시각>/verification.md`(항목별 PASS/FAIL/NOT RUN)와 `screenshots/`에 남습니다. `전체 결과: PASS`여도 스크린샷은 사람이 직접 확인합니다.
- UI 테스트는 macOS에서 실제 마우스·키보드를 조작하므로 로컬에서는 사람이 허락할 때만 돌리고, 평소에는 GitHub Actions(`.github/workflows/verify.yml`)가 push/PR마다 `full`을 실행합니다.
- UI 테스트가 실패해도 화면 전체 녹화가 증거에 남지 않도록 `project.yml` 스킴에서 녹화와 자동 첨부를 끕니다.
- 빌드 캐시는 `.artifacts/DerivedData/`에 두어 `~/Library/Developer/Xcode/DerivedData`를 늘리지 않습니다.

### 배포 (Developer ID 서명과 Apple 공증)
```bash
./scripts/release.sh --sign-only   # 서명까지만 점검 (Apple로 보내지 않음)
./scripts/release.sh               # 서명 → 공증 → staple → Gatekeeper 검증 → zip
```
1. 사전 검증: 작업 폴더가 깨끗하고, HEAD가 푸시되어 있고, **그 커밋의 GitHub CI(`verify.sh full`)가 성공**했는지 확인한 뒤 로컬 `verify.sh all`을 돌립니다(`gh` 로그인 필요).
2. Release 아카이브 → Developer ID 내보내기
3. 서명 검사(Developer ID, 타임스탬프, Hardened Runtime, 디버그 권한 없음)
4. Apple 공증 → 5. staple → 6. Gatekeeper(`spctl`, `syspolicy_check`) → 7. `XcodeKeeper-<버전>.zip`

결과는 `.artifacts/releases/<시각>/release-verification.md`에 남습니다. 준비물은 키체인의 `Developer ID Application` 인증서와 notarytool 키체인 프로필(`xcrun notarytool store-credentials "mac-native-ai-notary" --apple-id <애플ID> --team-id <팀ID>`, 터미널 앱에서 직접 실행)입니다. 계정 정보는 저장소에 넣지 않습니다. 버전은 `project.yml`의 `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`에서 바꿉니다.

## 라이선스

MIT. [LICENSE](LICENSE)를 참고하세요.
