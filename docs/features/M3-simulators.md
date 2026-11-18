# M3 시뮬레이터 (F2)

PRD 마일스톤 M3. `xcrun simctl`로 시뮬레이터 런타임과 기기를 보여 주고 삭제한다.

## 사용자 이야기
나는 저사양 Mac을 쓰는 개발자로서, 어떤 시뮬레이터 런타임이 얼마나 공간을 차지하고 어떤 기기가 묶여 있는지 보고, 안 쓰는 것을 안전하게 지우고 싶다. 그래야 7~8GB씩 하는 런타임을 정리해 공간을 확보할 수 있다.

## 수용 기준
- [ ] "시뮬레이터" 화면을 열면 `xcrun simctl runtime list -j`와 `xcrun simctl list devices -j`를 읽어 보여 준다. "새로고침" 버튼으로 다시 읽는다.
- [ ] 런타임 표: 플랫폼, 버전(빌드), 용량, 연결된 기기 수, 마지막 사용일, 상태. **용량 내림차순**으로 정렬한다.
- [ ] 현재 Xcode의 기본 런타임에 "현재 사용 중" 배지를 단다. 기준: `xcrun --sdk iphonesimulator --show-sdk-version`과 버전이 같은 iOS 런타임. SDK 버전을 읽지 못하면 가장 높은 iOS 버전.
- [ ] 런타임 삭제는 `xcrun simctl runtime delete <UUID>`로 실행한다. 삭제 전 확인 창(이름, 용량, "휴지통을 거치지 않고 바로 삭제" 안내)을 띄운다. "현재 사용 중" 런타임은 확인을 한 번 더 받는다.
- [ ] `deletable`이 false인 런타임은 삭제 버튼이 비활성이다.
- [ ] 기기 목록: 이름, 런타임, 상태, 마지막 사용일. 사용 불가 기기는 "사용 불가" 배지. 개별 삭제(`xcrun simctl delete <UDID>`)와 "사용 불가 기기 모두 삭제"(`xcrun simctl delete unavailable`, 개수 표시)를 지원한다. 둘 다 확인 창을 띄운다.
- [ ] 명령이 실패하면 stderr를 그대로(앞뒤 공백만 제거) 화면에 보여 준다. 성공하면 목록을 다시 읽는다.
- [ ] **인자 검증**: 런타임 identifier와 기기 UDID는 UUID 형식(8-4-4-4-12 16진수)만 허용한다. `simctl runtime delete`는 `all`(모든 런타임 삭제)과 `--unusable` 같은 옵션을 받으므로, 형식이 아니면 명령을 실행하지 않는다.
- [ ] `xcrun`이 실패하고 개발자 도구 오류(`xcrun: error`, `xcode-select`)이면 기능을 비활성화하고 설치·선택 방법을 안내한다. JSON을 읽지 못하면 오류 안내를 보여 주고 다른 화면은 영향이 없다.
- [ ] UI 테스트 모드에서는 실제 simctl을 실행하지 않는 가짜 관리자를 쓴다.

## 위험 요소
- 런타임·기기 삭제는 휴지통을 거치지 않는 영구 삭제다(PRD가 정한 공식 CLI). 확인 창에 명시하고, 사용 중 런타임은 두 번 확인한다.
- 잘못된 인자로 `all`이 전달되면 모든 런타임이 지워진다 → UUID 형식 검증, 단위 테스트.
- 개발 중 실제 Mac에서 삭제 명령은 실행하지 않는다(사용자 승인 전). 실제 Mac에서는 읽기 명령만 실행한다.

## 테스트 계획
| 동작 | 테스트 방법 | 증거 |
|---|---|---|
| JSON 디코딩(실제 출력 형식 fixture), 기기 수, 정렬, 현재 런타임 판정 | 단위 (`SimulatorInventoryTests`) | 테스트 로그 |
| UUID 검증, 명령 인자, stderr 전달, 도구 없음 판정 | 단위 (`SimctlClientTests`, 가짜 셸) | 테스트 로그 |
| 화면 상태 전이(불러오기, 확인, 두 번 확인, 실패, 재로드) | 단위 (`AppStateSimulatorTests`) | 테스트 로그 |
| 런타임 목록 / 사용 중 재확인 / 삭제 실패 stderr / 도구 없음 / 기기 삭제 후 | UI assertion | `01-runtime-list`, `02-in-use-reconfirm`, `01-delete-error-stderr`, `01-clt-missing`, `01-after-delete-unavailable` |
| 실제 Mac에서 목록 읽기 | 수동(읽기 전용) | 보고서에 수치 기록 |

## 검토 판정
- [ ] 빌드와 테스트 PASS (`verification.md`의 전체 결과)
- [ ] 스크린샷을 직접 열어 확인함
- [ ] 기능에 대한 주장이 assertion으로 뒷받침됨
- [ ] 알려진 한계를 문서화함
- [ ] 사람이 승인함
