import DocumentKit
import Foundation

// DocumentKit의 실제 저장 API(ProjectIO/DocumentPackageIO)만 사용해 튜토리얼 프로젝트를 만든다.
// 손으로 JSON을 작성하지 않음으로써 앱이 읽는 포맷과 항상 일치하도록 보장한다.

let outputDir: URL = {
    if CommandLine.arguments.count > 1 {
        return URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("GeneratedDemo", isDirectory: true)
}()

try? FileManager.default.removeItem(at: outputDir.appendingPathComponent("Sonnet Create 튜토리얼"))
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

var project = try ProjectIO.create(name: "Sonnet Create 튜토리얼", in: outputDir)
project.manifest.note = "각 에디터의 쓰임을 보여주는 예시 프로젝트입니다. 자유롭게 고쳐 쓰거나 지워도 됩니다."
try ProjectIO.save(project.manifest, at: project.url)

// MARK: - 캐릭터 페이지 (world/) — 관계 기능을 보여주기 위해 두 명을 만든다.

var aria = try DocumentPackageIO.create(
    title: "아리아",
    kind: .page,
    pageRole: .character,
    projectID: project.id,
    in: project.worldURL
)
var kyle = try DocumentPackageIO.create(
    title: "카일",
    kind: .page,
    pageRole: .character,
    projectID: project.id,
    in: project.worldURL
)

var ariaProfile = CharacterProfile(
    role: "주인공 · 견습 지도 제작자",
    summary: "지도에 그려지지 않은 길을 믿는 편. 호기심이 판단력보다 반 박자 빠르다.",
    symbolName: "figure.walk",
    accentHex: "#9C4A2E"
)
ariaProfile.fields = [
    CharacterField(name: "나이", value: "19"),
    CharacterField(name: "소속", value: "루멘 지도 길드"),
    CharacterField(name: "말버릇", value: "\"일단 가보고 정하죠.\"")
]
ariaProfile.relations = [
    CharacterRelation(targetPageID: kyle.envelope.id, label: "동료이자 감시자")
]
ariaProfile.voice = CharacterVoice(
    tone: "짧고 단정적. 확신이 없을 때만 말끝을 흐린다.",
    taboo: "존댓말을 쓰지 않는다 (친한 사이에서도 '~요'는 예외적).",
    samples: ["가보면 알아.", "지도가 틀린 거지, 내가 틀린 게 아니야."]
)
aria.content = .page(PageContent(blocks: [], profile: ariaProfile))
try DocumentPackageIO.write(aria)

var kyleProfile = CharacterProfile(
    role: "조력자 · 전직 경비대",
    summary: "규칙을 어기는 걸 싫어하면서도 매번 아리아를 따라간다.",
    symbolName: "shield.fill",
    accentHex: "#5C5344"
)
kyleProfile.fields = [
    CharacterField(name: "나이", value: "24"),
    CharacterField(name: "소속", value: "전직 성벽 경비대")
]
kyleProfile.relations = [
    CharacterRelation(targetPageID: aria.envelope.id, label: "말리면서도 결국 따라가는 사이")
]
kyle.content = .page(PageContent(blocks: [], profile: kyleProfile))
try DocumentPackageIO.write(kyle)

// MARK: - 시나리오 (.scen) — 대사/지침 블록 + 분기 기능을 보여준다.

var scenario = try DocumentPackageIO.create(
    title: "1장 - 지도에 없는 문",
    kind: .scenario,
    projectID: project.id,
    in: project.documentsURL
)

let ariaCast = CastMember(
    name: "아리아", roleLine: "주인공", symbolName: "figure.walk",
    accentHex: "#9C4A2E", characterPageID: aria.envelope.id
)
let kyleCast = CastMember(
    name: "카일", roleLine: "조력자", symbolName: "shield.fill",
    accentHex: "#5C5344", characterPageID: kyle.envelope.id
)

let openingInstruction = ScenarioBlock(
    kind: .instruction,
    text: "성벽 바깥, 오래된 지도에는 없는 돌문 앞. 저녁 안개가 낮게 깔려 있다."
)
let line1 = ScenarioBlock(kind: .line, speakerIDs: [ariaCast.id], text: "이 문, 어떤 지도에도 없어.")
let line2 = ScenarioBlock(kind: .line, speakerIDs: [kyleCast.id], text: "없으니까 열지 말자는 뜻 아닐까.")
let line3 = ScenarioBlock(kind: .line, speakerIDs: [ariaCast.id], text: "그러니까 열어봐야지.")
let divider = ScenarioBlock(kind: .divider, text: "장면 전환")

var mainBlocks = [openingInstruction, line1, line2, line3, divider]

let branchLine = ScenarioBlock(kind: .line, speakerIDs: [kyleCast.id], text: "…역시 그냥 돌아가는 게 낫지 않을까?")
let branch = ScenarioBranch(
    name: "카일이 말리는 경우",
    parentBlockID: line3.id,
    blocks: [branchLine]
)

scenario.content = .scenario(ScenarioContent(
    cast: [ariaCast, kyleCast],
    blocks: mainBlocks,
    branches: [branch]
))
scenario.refs = ReferenceGraph(outgoing: [
    .init(target: aria.envelope.id, kind: .character),
    .init(target: kyle.envelope.id, kind: .character)
])
try DocumentPackageIO.write(scenario)

// MARK: - 마인드맵 (.scno) — 노드/연결선 + 문서 링크 노드를 보여준다.

var mindmap = try DocumentPackageIO.create(
    title: "세계관 지도",
    kind: .mindmap,
    projectID: project.id,
    in: project.documentsURL
)

let cityNode = MindMapNode(title: "루멘 성", detail: "지도 길드의 본거지.", x: 0, y: 0, colorHex: "#9C4A2E")
let gateNode = MindMapNode(title: "이름 없는 문", detail: "1장의 무대.", x: 220, y: -40, colorHex: "#5C5344")
let scenarioNode = MindMapNode(
    kind: .page,
    title: "1장 - 지도에 없는 문",
    x: 220,
    y: 80,
    linkedDocumentID: scenario.envelope.id
)

mindmap.content = .mindmap(MindMapContent(
    nodes: [cityNode, gateNode, scenarioNode],
    edges: [
        MindMapEdge(fromID: cityNode.id, toID: gateNode.id, caption: "반나절 거리"),
        MindMapEdge(fromID: gateNode.id, toID: scenarioNode.id, caption: "이야기가 시작되는 곳")
    ]
))
mindmap.refs = ReferenceGraph(outgoing: [
    .init(target: scenario.envelope.id, kind: .link)
])
try DocumentPackageIO.write(mindmap)

// MARK: - 시작하기 페이지 (.scpa, 표준) — 블록 다양성 + 사용 안내.

var guideDoc = try DocumentPackageIO.create(
    title: "시작하기",
    kind: .page,
    projectID: project.id,
    in: project.documentsURL
)

func block(_ kind: PageBlockKind, _ text: String, indent: Int = 0, isChecked: Bool = false, tableData: [[String]]? = nil) -> PageBlock {
    PageBlock(kind: kind, text: text, isChecked: isChecked, indent: indent, tableData: tableData)
}

let guideBlocks: [PageBlock] = [
    block(.heading1, "Sonnet Create 튜토리얼에 오신 것을 환영합니다"),
    block(.paragraph, "이 프로젝트는 세 가지 에디터와 캐릭터 페이지를 한 번에 둘러볼 수 있도록 미리 채워둔 예시입니다. 자유롭게 편집하거나 지워도 실제 작업에는 영향이 없습니다."),
    block(.heading2, "둘러보기"),
    block(.task, "world/ 안의 \u{201c}아리아\u{201d}, \u{201c}카일\u{201d} 캐릭터 페이지 — 프로필/관계/보이스 탭 확인"),
    block(.task, "\u{201c}1장 - 지도에 없는 문\u{201d} 시나리오 — 대사 블록, 지침 블록, 분기(카일이 말리는 경우) 확인"),
    block(.task, "\u{201c}세계관 지도\u{201d} 마인드맵 — 노드 이동, 문서로 연결된 노드 더블클릭"),
    block(.callout, "팁: 사이드바의 참조 패널에서 문서 간 백링크를 확인할 수 있어요."),
    block(.heading2, "블록 종류 미리보기"),
    block(.bulleted, "글머리 기호 목록"),
    block(.numbered, "번호 매기기 목록"),
    block(.quote, "인용 블록 — 설정 메모나 대사 초안을 남길 때 유용합니다."),
    block(.toggle, "토글 블록 — 눌러서 펼치는 보조 설명에 사용하세요."),
    block(.table, "", tableData: [["문서 유형", "확장자"], ["시나리오", ".scen"], ["마인드맵", ".scno"], ["페이지", ".scpa"]]),
    block(.divider, ""),
    block(.paragraph, "이 페이지를 포함해 튜토리얼 프로젝트 전체를 지워도 좋습니다 — 새 프로젝트는 홈 화면에서 언제든 다시 만들 수 있습니다.")
]

guideDoc.content = .page(PageContent(blocks: guideBlocks))
try DocumentPackageIO.write(guideDoc)

print("데모 프로젝트 생성 완료: \(project.url.path)")

// MARK: - 왕복 검증 — 손으로 만든 JSON이 아니라 실제 저장 API로 썼으므로,
// 앱이 쓰는 것과 동일한 읽기 API(DocumentPackageIO.read/ProjectIO.load)로
// 다시 읽어 디코딩이 성공하고 내용이 보존되는지 확인한다.

guard let loadedProject = ProjectIO.load(from: project.url) else {
    fatalError("검증 실패: project.json을 다시 읽지 못했습니다")
}
precondition(loadedProject.manifest.name == "Sonnet Create 튜토리얼")

let loadedAria = try DocumentPackageIO.read(from: aria.url)
guard case .page(let ariaPage) = loadedAria.content, let ariaLoadedProfile = ariaPage.profile else {
    fatalError("검증 실패: 아리아 캐릭터 프로필을 읽지 못했습니다")
}
precondition(ariaLoadedProfile.fields?.count == 3)
precondition(ariaLoadedProfile.relations?.first?.targetPageID == kyle.envelope.id)
precondition(ariaLoadedProfile.voice?.samples.count == 2)

let loadedScenario = try DocumentPackageIO.read(from: scenario.url)
guard case .scenario(let loadedScenarioContent) = loadedScenario.content else {
    fatalError("검증 실패: 시나리오 콘텐츠를 읽지 못했습니다")
}
precondition(loadedScenarioContent.cast.count == 2)
precondition(loadedScenarioContent.blocks.count == 5)
precondition(loadedScenarioContent.branches.first?.blocks.count == 1)
precondition(loadedScenario.refs.outgoing.count == 2)

let loadedMindmap = try DocumentPackageIO.read(from: mindmap.url)
guard case .mindmap(let loadedMindmapContent) = loadedMindmap.content else {
    fatalError("검증 실패: 마인드맵 콘텐츠를 읽지 못했습니다")
}
precondition(loadedMindmapContent.nodes.count == 3)
precondition(loadedMindmapContent.edges.count == 2)
precondition(loadedMindmapContent.nodes.contains { $0.linkedDocumentID == scenario.envelope.id })

let loadedGuide = try DocumentPackageIO.read(from: guideDoc.url)
guard case .page(let loadedGuidePage) = loadedGuide.content else {
    fatalError("검증 실패: 시작하기 페이지를 읽지 못했습니다")
}
precondition(loadedGuidePage.blocks.count == guideBlocks.count)

let allDocs = ProjectIO.documentURLs(in: loadedProject)
precondition(allDocs.count == 5, "문서 5개(캐릭터 2 + 시나리오/마인드맵/페이지 각 1)가 있어야 합니다, 실제: \(allDocs.count)")

print("왕복 검증 통과: project.json + 문서 5건 모두 정상 디코딩됨")
