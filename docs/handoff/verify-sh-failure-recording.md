# 인계: UI 테스트 실패 시 전체 화면 녹화가 증거에 남는 문제

작성: 2026-11-18, XcodeKeeper M0~M2 작업 세션
대상: `scripts/verify.sh` 수정을 맡을 다음 세션

> **해결됨 (2026-11-18)**: 템플릿 mac-native-ai-system 커밋 c9c9432에서 고치고 이 저장소에 같은 변경을 적용했다.
> - `project.yml` 스킴: `preferredScreenCaptureFormat: screenshots`, `captureScreenshotsAutomatically: false`, `systemAttachmentLifetime: keepNever`
>   (XcodeGen은 `captureScreenshotsAutomatically: false`가 있어야 `systemAttachmentLifetime`을 기록한다). 사용자 `.keepAlways` 첨부는 유지된다.
> - `verify.sh`: 이름 규칙(`NN-상태-설명`) 밖의 첨부(녹화, 자동 스크린샷)를 `## 자동 첨부 (FAIL)`로 보고하고 실패 처리. `results.xcresult`는 수정하지 않는다.
> - 템플릿에서 실패 주입으로 확인: 설정 있음 → 녹화 0개, 설정 없음 → 녹화 2개 감지·FAIL. XcodeKeeper에서는 UI 실패 주입을 다시 돌리지 않았다(같은 스크립트·설정).
> - 함께 적용: 기본 검증 `verify.sh all`은 화면 밖 스냅샷만 쓰고 UI 테스트는 `AI_UI_CONTROL=1 ./scripts/verify.sh full`일 때만 실행.

## 요약
UI 테스트가 실패하면 Xcode가 **전체 화면**을 자동으로 녹화(mp4)해 `.xcresult`에 넣는다. `verify.sh`는 이것을 `.artifacts/runs/<시각>/attachments/`로 그대로 내보낸다. 그래서 테스트와 상관없는 다른 앱 화면(터미널 내용, 에이전트·스페이스 이름, 호스트 이름 등)이 실행 증거에 들어간다. AGENTS.md의 "비밀 정보나 개인 데이터를 ... 스크린샷, 생성된 보고서에 절대 넣지 않는다" 규칙을 어긴다.

`verify.sh`는 이미 `-collect-test-diagnostics never`를 기본으로 쓰지만, 이 옵션은 sysdiagnose 같은 진단만 끄고 **실패 녹화는 막지 않는다.**

## 확인된 사실
- 환경: macOS 26.6.2, Xcode 27.0 (27A266a), Apple Silicon M1 8GB.
- 2026-11-18 UI 테스트가 실패한 실행 3개에서 mp4 4개가 나왔다(실행당 1~2개, 3.1~9.2MB). `qlmanage -t`로 프레임을 뽑아 보니 테스트 앱 창만이 아니라 화면 전체가 녹화되어 있었다.
  - 해당 실행 폴더는 사용자 승인을 받아 삭제했다. 지금은 남아 있지 않다.
- 성공한 실행에서는 mp4가 0개였다. 마지막 확인은 `.artifacts/runs/20261118-215325`.
- `xcodebuild -help`(Xcode 27.0)에서 녹화와 관련된 플래그는 찾지 못했다. 관련 옵션은 `-collect-test-diagnostics on-failure|never`뿐이다.
- 녹화는 내보낸 `attachments/` 폴더뿐 아니라 `results.xcresult` 안에도 들어 있다. 내보낸 파일만 지우면 해결되지 않는다.
- `verify.sh`는 첨부물 중 `*.png`만 `screenshots/`로 정리하고, mp4는 `attachments/`에 그대로 둔다(119~140행 부근).
- 별도 문제(이번 작업 범위 아님, 참고용): 직접 넣은 디버그 출력 `print(app.debugDescription)`이 Apple 메뉴의 "최근 사용 항목"과 로그아웃 메뉴의 사용자 이름까지 `xcodebuild.log`에 남겼다. 앱 전체가 아니라 `app.windows.firstMatch.debugDescription`처럼 창 단위로 출력하면 피할 수 있었다.
- CI(`.github/workflows/verify.yml`)는 `verify.sh unit`만 실행하고 `.artifacts/runs/`를 GitHub 아티팩트로 7일간 올린다. 지금은 UI 테스트를 돌리지 않으므로 CI에서는 녹화가 생기지 않는다. 다만 나중에 CI에서 UI 테스트를 켜면 같은 문제가 생긴다.

## 확인하지 않은 것 (다음 세션에서 확인 필요)
아래는 가설이다. 실제로 동작하는지 확인하지 않았다.
1. **녹화 자체를 끄는 설정**: Xcode 테스트 플랜(`.xctestplan`)의 스크린 캡처 형식 설정(예: `preferredScreenCaptureFormat`을 스크린샷으로)이나, 스킴 TestAction의 시스템 첨부 보존 설정(`systemAttachmentLifetime`)으로 끌 수 있을 수 있다.
   - 이 프로젝트는 빌드 설정과 스킴을 `project.yml`(XcodeGen)에서만 바꾼다. XcodeGen이 해당 키나 테스트 플랜 연결을 지원하는지 확인해야 한다.
   - `.keepAlways`로 첨부하는 우리 스크린샷(`NN-상태-설명`)은 꺼지면 안 된다. 사용자 첨부와 시스템 첨부를 따로 다루는 설정인지 확인해야 한다.
2. **Xcode 자동 실패 스크린샷**: 녹화 말고 Xcode가 실패 순간에 자동으로 찍는 스크린샷도 전체 화면일 수 있다. 녹화를 끈 뒤 남는 자동 첨부가 무엇인지 확인해야 한다.
3. **사후 처리로 막기**: 녹화를 끌 수 없다면 `verify.sh`가 mp4(및 우리 이름 형식이 아닌 자동 첨부)를 찾았을 때 어떻게 할지 정해야 한다. 경고만 할지, FAIL로 할지, `results.xcresult`에서 제거할지. `xcresult` 수정은 증거 보존 요구와 부딪히므로 사람의 결정이 필요하다.

## 수용 기준 (제안)
- [ ] UI 테스트가 실패해도 `.artifacts/runs/<시각>/` 안(`attachments/`, `results.xcresult` 포함)에 전체 화면 녹화가 남지 않는다. 남는다면 `verification.md`에 그 사실과 경로가 표시되고 결과가 PASS가 되지 않는다.
- [ ] 우리가 `.keepAlways`로 첨부한 창 스크린샷은 지금처럼 `screenshots/<테스트>/NN-상태-설명.png`로 추출된다.
- [ ] 실패 메시지, `test-summary.json`의 실패 목록, 실패 시 종료 코드 1은 그대로다.
- [ ] macOS 기본 `/bin/bash` 3.2에서 동작한다(`set -u`와 빈 배열을 함께 쓰지 않는다).

## 재현과 검증 방법 (주의)
- 재현하면 녹화가 실제로 만들어진다. **화면에 개인 정보가 있는 창을 모두 닫거나 가린 뒤** 진행하고, 만든 실행 폴더는 확인이 끝나면 사용자 승인을 받아 지운다.
- 통제된 실패를 넣는 방법: UI 테스트 하나에 `XCTFail("의도한 실패")`를 잠시 넣고 `scripts/verify.sh ui`를 실행한다. 예: `AppUITests/XcodeKeeperUITests.swift`의 `testSettingsWindowShowsMenuBarToggle`.
  - 확인할 것: FAIL, 0이 아닌 종료 코드, 녹화 처리 결과.
  - 확인이 끝나면 주입한 변경을 원상 복구한다.
- 녹화 내용 확인: `qlmanage -t -s 900 -o <임시폴더> <mp4>`로 프레임을 PNG로 뽑아 연다. 뽑은 PNG도 개인 정보이므로 확인 후 지운다.
- AGENTS.md 규칙: 검증 스크립트를 고치면 통제된 실패(테스트 실패, 컴파일 오류)를 넣어 FAIL과 0이 아닌 종료 코드를 확인하고 원상 복구해야 한다. 검증은 한 번에 하나만 돌린다(8GB 기기, `.artifacts/verify.lock`).

## 관련 파일
- `scripts/verify.sh`: 63행(`-collect-test-diagnostics`), 116~145행(첨부물 내보내기와 스크린샷 정리), 보고서 작성부
- `project.yml`: 스킴 `XcodeKeeper`의 test 설정
- `.github/workflows/verify.yml`: `.artifacts/runs/` 업로드
- `AppUITests/UITestCase.swift`: `capture(_:_:)`(창 단위 `.keepAlways` 스크린샷)
- `AGENTS.md`, `~/.claude/CLAUDE.md`: 증거·개인 정보·검증 스크립트 수정 규칙

## 하지 않은 것
- `verify.sh`, `project.yml`의 테스트 설정은 이 문제 때문에 바꾸지 않았다.
- 이 문서는 커밋하지 않았다(사용자 지시 대기).
