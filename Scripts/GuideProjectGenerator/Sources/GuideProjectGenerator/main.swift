import AppCore
import DocumentKit
import Foundation

// DocumentKit의 실제 저장 API(ProjectIO/DocumentPackageIO)만 사용해 가이드 프로젝트를 만든다.
// 손으로 JSON을 작성하지 않음으로써 앱이 읽는 포맷과 항상 일치하도록 보장한다.
// 인자: <출력 디렉토리> <ko|ja|en> [whatsnew 파일 경로]

let arguments = CommandLine.arguments

let outputDir: URL = arguments.count > 1
    ? URL(fileURLWithPath: arguments[1], isDirectory: true)
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("GeneratedGuide", isDirectory: true)

let language: AppLanguage = arguments.count > 2 ? (AppLanguage(rawValue: arguments[2]) ?? .korean) : .korean
let whatsnewPath: String? = arguments.count > 3 ? arguments[3] : nil

// MARK: - 언어별 콘텐츠

struct GuideStrings {
    let projectName: String
    let projectNote: String

    let ariaName: String
    let ariaRole: String
    let ariaSummary: String
    let ariaAgeLabel: String
    let ariaAge: String
    let ariaGuildLabel: String
    let ariaGuild: String
    let ariaCatchphraseLabel: String
    let ariaCatchphrase: String
    let ariaRelation: String
    let ariaVoiceTone: String
    let ariaVoiceTaboo: String
    let ariaVoiceSample1: String
    let ariaVoiceSample2: String

    let kyleName: String
    let kyleRole: String
    let kyleSummary: String
    let kyleAgeLabel: String
    let kyleAge: String
    let kyleGuildLabel: String
    let kyleGuild: String
    let kyleRelation: String

    let scenarioTitle: String
    let ariaCastRole: String
    let kyleCastRole: String
    let openingInstruction: String
    let line1: String
    let line2: String
    let line3: String
    let sceneTransition: String
    let branchName: String
    let branchLine: String

    let mindmapTitle: String
    let cityNodeTitle: String
    let cityNodeDetail: String
    let gateNodeTitle: String
    let gateNodeDetail: String
    let edgeCaption1: String
    let edgeCaption2: String

    let guideDocTitle: String
    let welcomeHeading: String
    let welcomeParagraph: String
    let tourHeading: String
    let tourTask1: String
    let tourTask2: String
    let tourTask3: String
    let tourCallout: String
    let blocksHeading: String
    let bulletedLabel: String
    let numberedLabel: String
    let quoteLabel: String
    let toggleLabel: String
    let tableHeaderKind: String
    let tableHeaderExt: String
    let tableScenario: String
    let tableMindmap: String
    let tablePage: String
    let closingParagraph: String

    let whatsnewDocTitle: String
}

func strings(for language: AppLanguage) -> GuideStrings {
    switch language {
    case .korean:
        return GuideStrings(
            projectName: "Sonnet Create 튜토리얼",
            projectNote: "각 에디터의 쓰임을 보여주는 예시 프로젝트입니다. 자유롭게 고쳐 쓰거나 지워도 됩니다.",
            ariaName: "아리아",
            ariaRole: "주인공 · 견습 지도 제작자",
            ariaSummary: "지도에 그려지지 않은 길을 믿는 편. 호기심이 판단력보다 반 박자 빠르다.",
            ariaAgeLabel: "나이", ariaAge: "19",
            ariaGuildLabel: "소속", ariaGuild: "루멘 지도 길드",
            ariaCatchphraseLabel: "말버릇", ariaCatchphrase: "\"일단 가보고 정하죠.\"",
            ariaRelation: "동료이자 감시자",
            ariaVoiceTone: "짧고 단정적. 확신이 없을 때만 말끝을 흐린다.",
            ariaVoiceTaboo: "존댓말을 쓰지 않는다 (친한 사이에서도 '~요'는 예외적).",
            ariaVoiceSample1: "가보면 알아.",
            ariaVoiceSample2: "지도가 틀린 거지, 내가 틀린 게 아니야.",
            kyleName: "카일",
            kyleRole: "조력자 · 전직 경비대",
            kyleSummary: "규칙을 어기는 걸 싫어하면서도 매번 아리아를 따라간다.",
            kyleAgeLabel: "나이", kyleAge: "24",
            kyleGuildLabel: "소속", kyleGuild: "전직 성벽 경비대",
            kyleRelation: "말리면서도 결국 따라가는 사이",
            scenarioTitle: "1장 - 지도에 없는 문",
            ariaCastRole: "주인공",
            kyleCastRole: "조력자",
            openingInstruction: "성벽 바깥, 오래된 지도에는 없는 돌문 앞. 저녁 안개가 낮게 깔려 있다.",
            line1: "이 문, 어떤 지도에도 없어.",
            line2: "없으니까 열지 말자는 뜻 아닐까.",
            line3: "그러니까 열어봐야지.",
            sceneTransition: "장면 전환",
            branchName: "카일이 말리는 경우",
            branchLine: "…역시 그냥 돌아가는 게 낫지 않을까?",
            mindmapTitle: "세계관 지도",
            cityNodeTitle: "루멘 성", cityNodeDetail: "지도 길드의 본거지.",
            gateNodeTitle: "이름 없는 문", gateNodeDetail: "1장의 무대.",
            edgeCaption1: "반나절 거리",
            edgeCaption2: "이야기가 시작되는 곳",
            guideDocTitle: "시작하기",
            welcomeHeading: "Sonnet Create 튜토리얼에 오신 것을 환영합니다",
            welcomeParagraph: "이 프로젝트는 세 가지 에디터와 캐릭터 페이지를 한 번에 둘러볼 수 있도록 미리 채워둔 예시입니다. 자유롭게 편집하거나 지워도 실제 작업에는 영향이 없습니다.",
            tourHeading: "둘러보기",
            tourTask1: "world/ 안의 \u{201c}아리아\u{201d}, \u{201c}카일\u{201d} 캐릭터 페이지 — 프로필/관계/보이스 탭 확인",
            tourTask2: "\u{201c}1장 - 지도에 없는 문\u{201d} 시나리오 — 대사·지침 블록, 분기(카일이 말리는 경우), 상단 플롯 타임라인에서 장면 카드 드래그 확인",
            tourTask3: "\u{201c}세계관 지도\u{201d} 마인드맵 — 노드 이동, 문서로 연결된 노드 더블클릭",
            tourCallout: "팁: 타이틀바의 링크(참조) 버튼으로 참조 패널을 열면 문서 간 백링크를 볼 수 있어요. 페이지에서는 / 커맨드의 \u{2018}문서 임베드\u{2019}로 다른 문서 미리보기를 끼워 넣을 수 있습니다.",
            blocksHeading: "블록 종류 미리보기",
            bulletedLabel: "글머리 기호 목록",
            numberedLabel: "번호 매기기 목록",
            quoteLabel: "인용 블록 — 설정 메모나 대사 초안을 남길 때 유용합니다.",
            toggleLabel: "토글 블록 — 눌러서 펼치는 보조 설명에 사용하세요.",
            tableHeaderKind: "문서 유형", tableHeaderExt: "확장자",
            tableScenario: "시나리오", tableMindmap: "마인드맵", tablePage: "페이지",
            closingParagraph: "이 페이지를 포함해 튜토리얼 프로젝트 전체를 지워도 좋습니다 — 새 프로젝트는 홈 화면에서 언제든 다시 만들 수 있습니다.",
            whatsnewDocTitle: "새로운 기능"
        )
    case .japanese:
        return GuideStrings(
            projectName: "Sonnet Create チュートリアル",
            projectNote: "3つのエディタの使い方を示すサンプルプロジェクトです。自由に書き換えたり削除しても構いません。",
            ariaName: "アリア",
            ariaRole: "主人公 · 見習い地図製作者",
            ariaSummary: "地図に描かれていない道を信じるタイプ。好奇心が判断力より半拍早い。",
            ariaAgeLabel: "年齢", ariaAge: "19",
            ariaGuildLabel: "所属", ariaGuild: "ルーメン地図ギルド",
            ariaCatchphraseLabel: "口癖", ariaCatchphrase: "「とりあえず行ってから決めよう」",
            ariaRelation: "仲間であり見張り役",
            ariaVoiceTone: "短くきっぱりとした話し方。自信がない時だけ語尾を濁す。",
            ariaVoiceTaboo: "敬語を使わない（親しい間柄でも例外的に丁寧語を避ける）。",
            ariaVoiceSample1: "行ってみればわかるよ。",
            ariaVoiceSample2: "地図が間違ってるんだ、私が間違ってるんじゃない。",
            kyleName: "カイル",
            kyleRole: "協力者 · 元衛兵",
            kyleSummary: "ルールを破るのは嫌いなのに、毎回アリアについて行く。",
            kyleAgeLabel: "年齢", kyleAge: "24",
            kyleGuildLabel: "所属", kyleGuild: "元城壁衛兵隊",
            kyleRelation: "止めながらも結局ついて行く間柄",
            scenarioTitle: "第1章 - 地図にない扉",
            ariaCastRole: "主人公",
            kyleCastRole: "協力者",
            openingInstruction: "城壁の外、古い地図には載っていない石の扉の前。夕方の霧が低く立ち込めている。",
            line1: "この扉、どの地図にも載ってない。",
            line2: "載ってないってことは、開けるなって意味じゃない？",
            line3: "だからこそ開けてみるんじゃん。",
            sceneTransition: "場面転換",
            branchName: "カイルが止める場合",
            branchLine: "…やっぱりこのまま引き返した方がよくない？",
            mindmapTitle: "世界観マップ",
            cityNodeTitle: "ルーメン城", cityNodeDetail: "地図ギルドの本拠地。",
            gateNodeTitle: "名もなき扉", gateNodeDetail: "第1章の舞台。",
            edgeCaption1: "半日の距離",
            edgeCaption2: "物語が始まる場所",
            guideDocTitle: "はじめに",
            welcomeHeading: "Sonnet Create チュートリアルへようこそ",
            welcomeParagraph: "このプロジェクトは、3つのエディタとキャラクターページを一度に見て回れるようあらかじめ用意したサンプルです。自由に編集・削除しても実際の作業には影響しません。",
            tourHeading: "見て回る",
            tourTask1: "world/ 内の「アリア」「カイル」キャラクターページ — プロフィール/関係/ボイスタブを確認",
            tourTask2: "「第1章 - 地図にない扉」シナリオ — セリフ・指示ブロック、分岐（カイルが止める場合）、上部プロットタイムラインでシーンカードのドラッグを確認",
            tourTask3: "「世界観マップ」マインドマップ — ノードの移動、ドキュメントにリンクされたノードのダブルクリック",
            tourCallout: "ヒント: タイトルバーのリンク（参照）ボタンで参照パネルを開くと、文書間のバックリンクを確認できます。ページでは / コマンドの「文書埋め込み」で他の文書のプレビューを挿入できます。",
            blocksHeading: "ブロックの種類プレビュー",
            bulletedLabel: "箇条書きリスト",
            numberedLabel: "番号付きリスト",
            quoteLabel: "引用ブロック — 設定メモやセリフ案を残すのに便利です。",
            toggleLabel: "トグルブロック — クリックで開く補足説明に使ってください。",
            tableHeaderKind: "ドキュメント種類", tableHeaderExt: "拡張子",
            tableScenario: "シナリオ", tableMindmap: "マインドマップ", tablePage: "ページ",
            closingParagraph: "このページを含め、チュートリアルプロジェクト全体を削除しても構いません — 新しいプロジェクトはホーム画面からいつでも作成できます。",
            whatsnewDocTitle: "新機能"
        )
    case .english:
        return GuideStrings(
            projectName: "Sonnet Create Tutorial",
            projectNote: "A sample project showing what each of the three editors does. Feel free to edit or delete it.",
            ariaName: "Aria",
            ariaRole: "Protagonist · Apprentice Cartographer",
            ariaSummary: "Trusts roads no map has drawn. Her curiosity outruns her judgment by half a beat.",
            ariaAgeLabel: "Age", ariaAge: "19",
            ariaGuildLabel: "Affiliation", ariaGuild: "Lumen Cartographers' Guild",
            ariaCatchphraseLabel: "Catchphrase", ariaCatchphrase: "\"Let's just go and figure it out.\"",
            ariaRelation: "Companion and watchful minder",
            ariaVoiceTone: "Short and decisive. Only trails off when she isn't sure.",
            ariaVoiceTaboo: "Never speaks formally, even to strangers.",
            ariaVoiceSample1: "You'll see once we go.",
            ariaVoiceSample2: "The map is wrong, not me.",
            kyleName: "Kyle",
            kyleRole: "Ally · Former Guard",
            kyleSummary: "Hates breaking rules, yet follows Aria every single time.",
            kyleAgeLabel: "Age", kyleAge: "24",
            kyleGuildLabel: "Affiliation", kyleGuild: "Former Wall Guard",
            kyleRelation: "Talks her out of it, then tags along anyway",
            scenarioTitle: "Chapter 1 - The Door No Map Shows",
            ariaCastRole: "Protagonist",
            kyleCastRole: "Ally",
            openingInstruction: "Outside the city wall, before a stone door no old map records. Evening fog hangs low.",
            line1: "This door isn't on any map.",
            line2: "Maybe that means we shouldn't open it.",
            line3: "All the more reason to.",
            sceneTransition: "Scene Transition",
            branchName: "If Kyle Talks Her Out Of It",
            branchLine: "…Shouldn't we just turn back?",
            mindmapTitle: "World Map",
            cityNodeTitle: "Lumen Keep", cityNodeDetail: "Home base of the Cartographers' Guild.",
            gateNodeTitle: "The Nameless Door", gateNodeDetail: "The setting of Chapter 1.",
            edgeCaption1: "Half a day's travel",
            edgeCaption2: "Where the story begins",
            guideDocTitle: "Getting Started",
            welcomeHeading: "Welcome to the Sonnet Create Tutorial",
            welcomeParagraph: "This project is a pre-filled sample so you can explore all three editors and character pages at once. Feel free to edit or delete anything — it won't affect your real work.",
            tourHeading: "What to Explore",
            tourTask1: "The \u{201c}Aria\u{201d} and \u{201c}Kyle\u{201d} character pages in world/ — check the Profile/Relations/Voice tabs",
            tourTask2: "The \u{201c}Chapter 1 - The Door No Map Shows\u{201d} scenario — dialogue/direction blocks, the branch (\u{201c}If Kyle Talks Her Out Of It\u{201d}), and dragging scene cards on the plot timeline",
            tourTask3: "The \u{201c}World Map\u{201d} mind map — drag nodes, double-click the node linked to a document",
            tourCallout: "Tip: open the References panel from the titlebar link button to see backlinks between documents. In pages, the / command\u{2019}s \u{2018}Embed Document\u{2019} inserts a live preview of another document.",
            blocksHeading: "Block Types Preview",
            bulletedLabel: "Bulleted List",
            numberedLabel: "Numbered List",
            quoteLabel: "Quote block — handy for worldbuilding notes or dialogue drafts.",
            toggleLabel: "Toggle block — use it for supplementary detail that expands on click.",
            tableHeaderKind: "Document Type", tableHeaderExt: "Extension",
            tableScenario: "Scenario", tableMindmap: "Mind Map", tablePage: "Page",
            closingParagraph: "Feel free to delete this page, or the whole tutorial project — you can always create a new one from the Home screen.",
            whatsnewDocTitle: "What's New"
        )
    }
}

let strs = strings(for: language)

// MARK: - 프로젝트 생성

try? FileManager.default.removeItem(at: outputDir.appendingPathComponent(strs.projectName))
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

var project = try ProjectIO.create(name: strs.projectName, in: outputDir)
project.manifest.note = strs.projectNote
try ProjectIO.save(project.manifest, at: project.url)

// MARK: - 캐릭터 페이지 (world/) — 관계 기능을 보여주기 위해 두 명을 만든다.

var aria = try DocumentPackageIO.create(
    title: strs.ariaName,
    kind: .page,
    pageRole: .character,
    projectID: project.id,
    in: project.worldURL
)
var kyle = try DocumentPackageIO.create(
    title: strs.kyleName,
    kind: .page,
    pageRole: .character,
    projectID: project.id,
    in: project.worldURL
)

var ariaProfile = CharacterProfile(
    role: strs.ariaRole,
    summary: strs.ariaSummary,
    symbolName: "figure.walk",
    accentHex: "#9C4A2E"
)
ariaProfile.fields = [
    CharacterField(name: strs.ariaAgeLabel, value: strs.ariaAge),
    CharacterField(name: strs.ariaGuildLabel, value: strs.ariaGuild),
    CharacterField(name: strs.ariaCatchphraseLabel, value: strs.ariaCatchphrase),
]
ariaProfile.relations = [
    CharacterRelation(targetPageID: kyle.envelope.id, label: strs.ariaRelation),
]
ariaProfile.voice = CharacterVoice(
    tone: strs.ariaVoiceTone,
    taboo: strs.ariaVoiceTaboo,
    samples: [strs.ariaVoiceSample1, strs.ariaVoiceSample2]
)
aria.content = .page(PageContent(blocks: [], profile: ariaProfile))
try DocumentPackageIO.write(aria)

var kyleProfile = CharacterProfile(
    role: strs.kyleRole,
    summary: strs.kyleSummary,
    symbolName: "shield.fill",
    accentHex: "#5C5344"
)
kyleProfile.fields = [
    CharacterField(name: strs.kyleAgeLabel, value: strs.kyleAge),
    CharacterField(name: strs.kyleGuildLabel, value: strs.kyleGuild),
]
kyleProfile.relations = [
    CharacterRelation(targetPageID: aria.envelope.id, label: strs.kyleRelation),
]
kyle.content = .page(PageContent(blocks: [], profile: kyleProfile))
try DocumentPackageIO.write(kyle)

// MARK: - 시나리오 (.scen) — 대사/지침 블록 + 분기 기능을 보여준다.

var scenario = try DocumentPackageIO.create(
    title: strs.scenarioTitle,
    kind: .scenario,
    projectID: project.id,
    in: project.documentsURL
)

let ariaCast = CastMember(
    name: strs.ariaName, roleLine: strs.ariaCastRole, symbolName: "figure.walk",
    accentHex: "#9C4A2E", characterPageID: aria.envelope.id
)
let kyleCast = CastMember(
    name: strs.kyleName, roleLine: strs.kyleCastRole, symbolName: "shield.fill",
    accentHex: "#5C5344", characterPageID: kyle.envelope.id
)

let openingInstruction = ScenarioBlock(kind: .instruction, text: strs.openingInstruction)
let line1 = ScenarioBlock(kind: .line, speakerIDs: [ariaCast.id], text: strs.line1)
let line2 = ScenarioBlock(kind: .line, speakerIDs: [kyleCast.id], text: strs.line2)
let line3 = ScenarioBlock(kind: .line, speakerIDs: [ariaCast.id], text: strs.line3)
let divider = ScenarioBlock(kind: .divider, text: strs.sceneTransition)

let mainBlocks = [openingInstruction, line1, line2, line3, divider]

let branchLine = ScenarioBlock(kind: .line, speakerIDs: [kyleCast.id], text: strs.branchLine)
let branch = ScenarioBranch(
    name: strs.branchName,
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
    .init(target: kyle.envelope.id, kind: .character),
])
try DocumentPackageIO.write(scenario)

// MARK: - 마인드맵 (.scno) — 노드/연결선 + 문서 링크 노드를 보여준다.

var mindmap = try DocumentPackageIO.create(
    title: strs.mindmapTitle,
    kind: .mindmap,
    projectID: project.id,
    in: project.documentsURL
)

let cityNode = MindMapNode(title: strs.cityNodeTitle, detail: strs.cityNodeDetail, x: 0, y: 0, colorHex: "#9C4A2E")
let gateNode = MindMapNode(title: strs.gateNodeTitle, detail: strs.gateNodeDetail, x: 220, y: -40, colorHex: "#5C5344")
let scenarioNode = MindMapNode(
    kind: .page,
    title: strs.scenarioTitle,
    x: 220,
    y: 80,
    linkedDocumentID: scenario.envelope.id
)

mindmap.content = .mindmap(MindMapContent(
    nodes: [cityNode, gateNode, scenarioNode],
    edges: [
        MindMapEdge(fromID: cityNode.id, toID: gateNode.id, caption: strs.edgeCaption1),
        MindMapEdge(fromID: gateNode.id, toID: scenarioNode.id, caption: strs.edgeCaption2),
    ]
))
mindmap.refs = ReferenceGraph(outgoing: [
    .init(target: scenario.envelope.id, kind: .link),
])
try DocumentPackageIO.write(mindmap)

// MARK: - 시작하기 페이지 (.scpa, 표준) — 블록 다양성 + 사용 안내.

var guideDoc = try DocumentPackageIO.create(
    title: strs.guideDocTitle,
    kind: .page,
    projectID: project.id,
    in: project.documentsURL
)

func block(_ kind: PageBlockKind, _ text: String, indent: Int = 0, isChecked: Bool = false, tableData: [[String]]? = nil) -> PageBlock {
    PageBlock(kind: kind, text: text, isChecked: isChecked, indent: indent, tableData: tableData)
}

let guideBlocks: [PageBlock] = [
    block(.heading1, strs.welcomeHeading),
    block(.paragraph, strs.welcomeParagraph),
    block(.heading2, strs.tourHeading),
    block(.task, strs.tourTask1),
    block(.task, strs.tourTask2),
    block(.task, strs.tourTask3),
    block(.callout, strs.tourCallout),
    block(.heading2, strs.blocksHeading),
    block(.bulleted, strs.bulletedLabel),
    block(.numbered, strs.numberedLabel),
    block(.quote, strs.quoteLabel),
    block(.toggle, strs.toggleLabel),
    block(.table, "", tableData: [
        [strs.tableHeaderKind, strs.tableHeaderExt],
        [strs.tableScenario, ".scen"],
        [strs.tableMindmap, ".scno"],
        [strs.tablePage, ".scpa"],
    ]),
    block(.divider, ""),
    block(.paragraph, strs.closingParagraph),
]

guideDoc.content = .page(PageContent(blocks: guideBlocks))
try DocumentPackageIO.write(guideDoc)

// MARK: - 새로운 기능 (.scpa) — whatsnew 파일이 주어진 경우에만 생성.
// 단순 마크다운(# 제목, ## 소제목, - 목록, 그 외 본문)을 페이지 블록으로 변환한다.

var whatsnewDoc: LoadedDocument?
if let whatsnewPath, let text = try? String(contentsOfFile: whatsnewPath, encoding: .utf8) {
    var doc = try DocumentPackageIO.create(
        title: strs.whatsnewDocTitle,
        kind: .page,
        projectID: project.id,
        in: project.documentsURL
    )
    let blocks: [PageBlock] = text
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { String($0) }
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        .map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                return block(.heading2, String(trimmed.dropFirst(3)))
            } else if trimmed.hasPrefix("# ") {
                return block(.heading1, String(trimmed.dropFirst(2)))
            } else if trimmed.hasPrefix("- ") {
                return block(.bulleted, String(trimmed.dropFirst(2)))
            } else {
                return block(.paragraph, trimmed)
            }
        }
    if !blocks.isEmpty {
        doc.content = .page(PageContent(blocks: blocks))
        try DocumentPackageIO.write(doc)
        whatsnewDoc = doc
    }
}

print("가이드 프로젝트 생성 완료 (\(language.rawValue)): \(project.url.path)")

// MARK: - 왕복 검증 — 손으로 만든 JSON이 아니라 실제 저장 API로 썼으므로,
// 앱이 쓰는 것과 동일한 읽기 API(DocumentPackageIO.read/ProjectIO.load)로
// 다시 읽어 디코딩이 성공하고 내용이 보존되는지 확인한다.

guard let loadedProject = ProjectIO.load(from: project.url) else {
    fatalError("검증 실패: project.json을 다시 읽지 못했습니다")
}
precondition(loadedProject.manifest.name == strs.projectName)

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

let expectedDocCount = 5 + (whatsnewDoc != nil ? 1 : 0)
let allDocs = ProjectIO.documentURLs(in: loadedProject)
precondition(allDocs.count == expectedDocCount, "문서 \(expectedDocCount)개가 있어야 합니다, 실제: \(allDocs.count)")

print("왕복 검증 통과: project.json + 문서 \(expectedDocCount)건 모두 정상 디코딩됨")
