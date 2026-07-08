# Sonnet Create

마크다운 기반으로 시나리오·마인드맵·문서를 하나의 앱에서 편집하고, 프로젝트 단위로 세계관/캐릭터를 관리하는 macOS 네이티브 창작 워크스페이스. macOS 26 Tahoe / 27 GoldenGate의 Liquid Glass 디자인 언어 기준.

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

## 현재 상태

구현 완료 (빌드·실행 검증됨):
- 시나리오 분기 — 블록 우클릭 '여기서 분기 만들기', 툴바 분기 피커(본편/분기 전환), 분기점 컨텍스트 표시, AI 이어쓰기가 활성 분기 흐름을 따름 (.scen 하위 호환 유지)
- 캐릭터 락업 양방향 — 캐스트→캐릭터 페이지 생성 + 프로젝트 캐릭터 페이지→캐스트 가져오기(프로필 승계)
- 페이지 이미지/표 블록 — 파일 선택·드래그 앤 드롭·URL 임베드, 비율 지정(원본/16:9/4:3/1:1), 클릭 확대, 편집형 표(행/열 추가·삭제), Markdown 왕복 변환
- 캐릭터 프로필 이미지 — 원형 크롭 표시 + SF Symbols 아이콘 대체
- 단축키 — ⌘T/⇧⌘A/⌘W/⌘S/⌘1~9, 슬래시 메뉴 ↑↓·Enter
- 참조 패널 — 문서별 속성/참조(추가·제거·열기)/백링크, 저장 시 캐스트·마인드맵 링크에서 자동 참조 파생
- 본문 검색 — SQLite 색인에 평문 포함, 홈 검색이 제목+본문 딥서치
- 텍스트 설정 반영 — 글자 크기/줄 간격이 페이지·시나리오 본문에 실제 적용
- 배경 세부 설정 — 도트 크기·시점 각도·색(테마/액센트)
- 페이지 Export — Markdown + HTML(이미지 base64 임베드) + PDF
- 디자인 — Sonnet 테마(앤티크 페이퍼 + 적갈 액센트, Pretendard 기본), 깃털 앱 아이콘, Chrome-tabs 풀폭 탭바(캡슐 옵션), 픽셀 브리딩 필드(홈/사이드바), Liquid Glass 끄기 기본
- 캐릭터 페이지 v2 — 탭 구조(프로필/노트/관계/갤러리/보이스): 구조화 필드, 프로필 이미지 팝업 패널(크롭 통합), 방사형 관계도, 갤러리+시점 태그, 선택적 보이스 카드(AI 말투 주입), 등장 기록 보조 집계
- AI 에이전트 채팅 — 전용 탭 + 사이드패널 미니 챗, 제공자 3종 공용
- Touch Bar 지원(베타) — 설정 토글 + 기능 목록/프리뷰 + 실제 NSTouchBar 배선
- 3종 에디터 — 시나리오(대사/지침 블록, 다중 화자 ⌘선택, 입력기, 드래그 정렬, 캐릭터 인스펙터, AI 제안 수락/무시), 마인드맵(팬/줌/더블클릭 생성/연결선+캡션/노드 인스펙터/이미지 노드), 블록 페이지(`/` 커맨드, Enter 분할, 빈 블록 Backspace 병합, Tab 들여쓰기, 토글 접기, MD Import/Export)
- 캐릭터 페이지 — `.scpa` 서브타입, 프로필 헤더(심볼/역할/설명/강조색)
- 파일 아카이브 — 카테고리/정렬/리스트·그리드, 가리기·휴지통(Touch ID 게이트, Finder 반영)
- 저장 — 자동(디바운스)/수동(⌘S), 4색 상태 배지, 종료 시 자동 백업 + 타임라인 복원
- 설정 — 4탭, 언어(한/일/영) 즉시 전환, 강조색 5종+커스텀, 품질 3단계, 배경 파라미터
- AI — 제공자 추상화(Apple 온디바이스/Anthropic/오프라인 초안), 최대 10블록 제안형 자동작성
- Wavy Dot Field — Metal 셰이더(metallib 확인됨), 셰이더 부재 시 Canvas 폴백, 홈에서 노출/그 외 블러

미구현·다음 단계 (디자인 단계와 병행 가능):
- 읽기 전용 뷰어 모드, 원형 크롭 편집 팝업, Pretendard 번들
- 인라인 @멘션(참조 패널로 대체 중), PDF 다중 페이지 분할
- App Intents(Siri/Apple Intelligence 노출), PCC 제공자, CloudKit 동기화
- 코드 서명: Automatic + 팀 미지정 — 배포(DMG) 전 Xcode에서 Development Team 지정 필요
- swiftlint/swiftformat 설정 파일, git 저장소 초기화
