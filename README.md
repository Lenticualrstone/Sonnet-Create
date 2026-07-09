<p align="center">
  <img src="App/SonnetCreate/Assets.xcassets/BrandMark.imageset/brandmark@2x.png" width="96" alt="Sonnet Create" />
</p>

<h1 align="center">Sonnet Create</h1>

<p align="center">
  <em>marks · scenes · worlds — 하나의 워크스페이스에서 쓰는 이야기</em>
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2026%2B-9C4A2E" />
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6.0-9C4A2E" />
  <img alt="License" src="https://img.shields.io/badge/license-MIT-9C4A2E" />
  <img alt="Version" src="https://img.shields.io/badge/version-1.0-9C4A2E" />
</p>

---

마크다운 기반으로 **시나리오·마인드맵·문서**를 하나의 앱에서 편집하고, 프로젝트 단위로
세계관과 캐릭터를 관리하는 macOS 네이티브 창작 워크스페이스. 앤티크 페이퍼와 적갈색
액센트, 깃털 아이콘 — 화면 위에서도 종이 냄새가 나길 바라며 만들었다.

macOS 26 Tahoe / 27 GoldenGate의 Liquid Glass 디자인 언어를 기준으로 하되, 기본값은
평면(레트로 미니멀) 표면이다.

## 주요 기능

- **시나리오 에디터(`.scen`)** — 채팅형 대사/지침 블록, 다중 화자 지정, 장면 분기(본편↔분기 전환)
- **마인드맵 에디터(`.scno`)** — 무한 캔버스, 팬/줌, 문서와 연결되는 링크 노드
- **블록 페이지 에디터(`.scpa`)** — Notion형 `/` 커맨드, 표·이미지·토글 등 12종 블록, Markdown 왕복 변환
- **캐릭터 페이지** — 프로필/노트/관계/갤러리/보이스 탭, 캐스트와 양방향으로 연결
- **참조 패널** — 문서 간 링크·백링크 자동 추적, 본문까지 포함한 딥서치
- **AI 에이전트** — Apple 온디바이스 / Anthropic / 오프라인 초안, 시나리오 자동작성 제안
- **자동 백업 & 타임라인 복원**, 파일 아카이브(가리기·휴지통, Touch ID 게이트)

전체 변경 이력은 [CHANGELOG.md](CHANGELOG.md)에서 확인할 수 있다.

## 구조

하이브리드 구성 — 앱만 Xcode 프로젝트, 나머지 모듈은 로컬 SPM 패키지 (macOS 26+, Swift 6).

```
SonnetCreate.xcworkspace   # 워크스페이스 진입점 (Xcode에서 이걸 열 것)
App/
  project.yml              # xcodegen 스펙 — .xcodeproj의 소스. 이 파일을 수정할 것
  SonnetCreate.xcodeproj   # project.yml로부터 생성됨 (직접 편집 금지)
  SonnetCreate/             # 앱 소스 — 탭/사이드바/홈/문서 세션/조립(AppState)
Packages/
  AppCore/                 # 공용 유틸, 한/일/영 로컬라이저, 품질 어휘
  DesignSystem/             # Liquid Glass 토큰·컴포넌트 (glassEffect, 저장 배지, 쉐이크 모션)
  PersistenceKit/           # SQLite(UUID→경로) 색인, 폴더 감시
  RenderingKit/              # Wavy Dot Field Metal 셰이더 배경, 품질 거버너
  DocumentKit/               # 문서 모델 + 번들 I/O + 프로젝트 매니페스트 + Markdown 변환
  FileManagerKit/            # 워크스페이스 스토어, 파일 아카이브(카테고리/그리드/가리기/휴지통)
  AIAgentKit/                 # AI 제공자 추상화 (Apple FM / Anthropic / 오프라인) + 시나리오 자동작성
  ScenarioEditor/             # 채팅형 시나리오 에디터 (.scen)
  MindMapEditor/               # 무한 캔버스 마인드맵 에디터 (.scno)
  MarkdownEditor/               # Notion형 블록 에디터 + 캐릭터 페이지 (.scpa)
  SettingsKit/                   # 탭형 설정 (기본/테마/텍스트/베타), 저장 버튼으로 반영
  BackupKit/                      # 타임라인 백업/복구, .scproj 내보내기/가져오기
  SecurityKit/                     # Touch ID 게이트(세션 한정), Keychain 저장소
Scripts/
  DemoProjectGenerator/            # DocumentKit API로 튜토리얼 프로젝트를 생성하는 도구
  build-dmg.sh                    # 배포용 DMG 빌드 파이프라인
```

의존성은 단방향 계층 구조: Presentation → Feature → Domain → Data → Infra.

## 파일 포맷 (확정)

| 대상 | 확장자 | 형식 |
|---|---|---|
| 채팅형 시나리오 | `.scen` | 번들 (metadata/content/refs JSON + resources/) |
| 노드 마인드맵 | `.scno` | 〃 |
| 블록형 페이지 | `.scpa` | 〃 — 캐릭터 페이지는 `.scpa`의 서브타입(pageRole=character) |
| 프로젝트 백업 | `.scproj` | ZIP 패키지 + project.json 매니페스트 |

프로젝트는 일반 폴더(`project.json` + `world/` + `documents/` + `resources/`),
문서 참조는 경로가 아닌 UUID(SQLite 색인이 해석)라 이동/이름변경에도 링크가 유지된다.

## 시작하기

### 소스에서 빌드

필요 도구: Xcode 26+ (Metal Toolchain 포함), Homebrew의 `xcodegen`, `swiftlint`, `swiftformat`, `xcbeautify`.

```
brew install xcodegen swiftlint swiftformat xcbeautify
xcodebuild -downloadComponent MetalToolchain   # 최초 1회
```

앱 타겟의 파일/설정/패키지 의존성 변경은 `App/project.yml` 수정 후 재생성:

```
cd App && xcodegen generate
```

빌드/실행:

```
open SonnetCreate.xcworkspace
# 또는
xcodebuild -workspace SonnetCreate.xcworkspace -scheme SonnetCreate -configuration Debug build | xcbeautify
```

### 배포용 DMG 만들기

```
Scripts/build-dmg.sh
```

Release 빌드 → 튜토리얼 프로젝트 생성 → 배경/볼륨 아이콘 준비 → DMG 패키징까지
한 번에 실행한다. 결과물은 `dist/`(gitignore됨)에 생성된다. 아직 Developer ID
서명·노터라이제이션 전이라, 배포받은 쪽에서는 앱 아이콘을 우클릭 → 열기로 최초 실행해야 한다.

## 로드맵

읽기 전용 뷰어 모드, 인라인 @멘션, CloudKit 동기화, Developer ID 서명 등은 아직
진행 중이다. 자세한 목록은 [CHANGELOG.md](CHANGELOG.md#다음-단계) 참고.

## 라이선스

[MIT](LICENSE)
