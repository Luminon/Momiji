# Momiji

[![CI](https://github.com/Luminon/macoscursor/actions/workflows/ci.yml/badge.svg)](https://github.com/Luminon/macoscursor/actions/workflows/ci.yml)
[![Latest Release](https://img.shields.io/github/v/release/Luminon/macoscursor?display_name=tag)](https://github.com/Luminon/macoscursor/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Windows 커서 테마를 macOS에서 사용할 수 있게 변환하고 편집·적용하는 네이티브 SwiftUI 앱입니다. `.ani`, `.cur`, 선택적 `.inf`가 들어 있는 폴더를 가져오면 Windows 역할을 macOS 커서 역할로 자동 매핑합니다.

| 항목 | 지원 범위 |
| --- | --- |
| 운영체제 | macOS 15.0 이상 |
| 아키텍처 | Apple Silicon·Intel Universal |
| 입력 | ANI, CUR, 선택적 INF |
| 휴대용 테마 | `.momiji` 패키지 |
| 언어 | 한국어, English |
| 네트워크 | 사용하지 않음·원격 측정 없음 |

> [!WARNING]
> 시스템 전체 커서 적용은 공개 `NSCursor` API가 아닌 런타임 탐지 방식의 비공개 CoreGraphics 심볼에 의존합니다. macOS 업데이트로 호환성이 깨질 수 있습니다. 이때도 변환·편집·저장·가져오기·내보내기는 사용할 수 있으며, 적용 기능만 비활성화됩니다.

## 다운로드와 설치

1. [GitHub Releases](https://github.com/Luminon/macoscursor/releases/latest)에서 최신 `Momiji-<version>-macOS-Universal.dmg`를 받습니다.
2. DMG를 열고 `Momiji.app`을 Applications 폴더로 드래그합니다.
3. Applications에서 Momiji를 실행합니다.

서명·공증되지 않은 프리릴리스는 macOS가 개발자를 확인할 수 없다는 메시지를 표시할 수 있습니다. 해당 Release의 서명 상태와 SHA-256 체크섬을 먼저 확인하고, 신뢰하는 빌드인 경우에만 시스템 설정의 **개인정보 보호 및 보안 → 확인 없이 열기**를 사용하세요.

## 사용 방법

1. Windows 커서 테마 폴더를 Momiji 창에 드롭하거나 **가져오기**를 누릅니다.
2. 가져오기 검토에서 자동 매핑 결과와 경고를 확인합니다. 미매핑·손상 파일은 **사용 안 함**으로 둘 수 있고, 역할 충돌은 사용할 파일 하나만 남깁니다.
3. 역할별 미리보기에서 핫스폿, 논리 크기, 재생 속도와 역할을 조정합니다.
4. **저장 및 적용**을 누릅니다. 저장만 한 뒤 라이브러리에서 나중에 적용할 수도 있습니다.
5. 원래 커서로 돌아가려면 툴바의 **시스템 기본값 복원**을 누릅니다.

설정에서는 전체 커서 배율을 50–200%로 조절할 수 있습니다. **로그인 후 계속 적용**을 직접 켠 경우에만 로그인 항목을 등록하고 로그인·절전 복귀·사용자 세션 활성화 시 활성 테마를 다시 적용합니다. 관리자 권한은 요구하지 않습니다.

## 지원 기능

### 변환

- RIFF `ACON` ANI의 `anih`, `rate`, `seq`, `LIST/fram`, `icon` 청크 해석
- ANI의 1/60초 tick, 프레임 순서와 가변 재생 시간 보존
- PNG 및 DIB 1/4/8/24/32비트 CUR, 다중 해상도와 핫스폿 처리
- INF 역할 우선 매핑과 파일명 휴리스틱
- 파일별 오류, 미매핑 항목, 역할 충돌을 나머지 결과와 분리해 검토
- 프레임별 핫스폿이 다를 때 공통 캔버스에 정렬해 애니메이션 흔들림 방지

### 편집과 보관

- 체크보드 배경의 정적·애니메이션 미리보기
- 핫스폿 드래그, 논리 크기, 역할, 재생 속도 편집
- `Application Support/Momiji` 내부 라이브러리에 원자적 저장
- Finder에서 단일 문서처럼 보이는 `.momiji` 가져오기·내보내기

### 안전한 적용

- 적용 전 이미지와 런타임 형상 검증
- 적용 실패 시 시스템 기본값으로 롤백
- 부분 테마 적용 전에 기존 사용자 지정 역할 초기화
- 모든 Momiji 사용자 지정 역할을 한 번에 시스템 기본값으로 복원
- 비공개 런타임 심볼이 없는 OS에서는 적용 버튼만 비활성화

## `.momiji` 형식

`.momiji`는 디렉터리 패키지입니다. `manifest.json`에는 스키마 버전, 테마 정보, 역할, 논리 크기, 핫스폿, 표현 배율, ANI tick 타임라인과 재생 속도가 들어갑니다. PNG 프레임은 `Cursors/<role>/<scale>x/` 아래에 저장됩니다.

가져올 때 심볼릭 링크, 상위 경로 참조, 과도한 파일 수·용량, 잘못된 PNG, 중복 역할과 손상된 manifest를 거부합니다.

## 제한 사항

- v1은 Mousecape `.cape`, GIF/Linux 변환, 온라인 갤러리, 단축키, 자동 업데이트를 지원하지 않습니다.
- 시스템 런타임이 균일한 프레임 간격만 받으므로 ANI 가변 tick을 최대공약수 단위로 확장합니다. 240프레임을 넘으면 가장 가까운 시간 단위로 근사합니다.
- Momiji에는 제3자 커서 테마가 포함되지 않습니다. 가져오는 이미지와 테마의 사용 권한은 사용자에게 있습니다.
- 실제 시스템 적용은 macOS 버전별 수동 호환성 검증이 필요합니다.

## 개발

Icon Composer 앱 아이콘을 컴파일할 수 있는 Xcode 26 이상이 필요합니다. 앱의 배포 대상은 macOS 15.0입니다. Xcode에서 `Momiji.xcodeproj`를 열거나 다음 명령으로 앱과 테스트 번들을 빌드합니다.

```sh
./scripts/test.sh
```

순수 변환·저장 계층만 테스트하려면 다음 명령을 사용합니다.

```sh
swift test --disable-sandbox
```

실제 시스템 커서를 바꾸는 통합 테스트는 기본적으로 건너뜁니다. 복원 절차를 확인한 전용 테스트 환경에서만 명시적으로 실행하세요.

```sh
MOMIJI_RUN_SYSTEM_INTEGRATION_TESTS=1 \
swift test --filter SystemCursorIntegrationTests
```

개발 번들 ID는 `app.momiji.Momiji`와 `app.momiji.Momiji.Helper`입니다. 릴리스용 Team ID와 번들 접두사는 빌드 환경에서 주입하며 인증서·공증 자격 증명은 저장소에 보관하지 않습니다.

## 릴리스 패키징

Developer ID 인증서와 `notarytool` Keychain profile이 준비된 공식 릴리스는 Universal 앱을 서명·공증하고 DMG에 stapling합니다.

```sh
MOMIJI_TEAM_ID=ABCDE12345 \
MOMIJI_NOTARY_PROFILE=momiji-notary \
./scripts/release.sh
```

인증서가 없는 개발 환경에서는 배포 검토용 ad-hoc 패키지를 만들 수 있습니다. 이 결과물은 공증되지 않으므로 GitHub Release에 서명 상태를 명시해야 합니다.

```sh
MOMIJI_RELEASE_MODE=adhoc ./scripts/release.sh
```

두 모드 모두 `dist/`에 버전이 포함된 Universal DMG, ZIP과 `SHA256SUMS.txt`를 생성합니다. 실기기 검증 항목은 [수동 테스트 가이드](docs/MANUAL_TESTING.md)를 참고하세요.

## 라이선스

Momiji는 Mousecape/MaCursor의 소스 코드를 사용하지 않은 독립 구현이며 [MIT License](LICENSE)로 배포됩니다.
