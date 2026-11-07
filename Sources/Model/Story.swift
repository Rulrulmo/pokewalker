import Foundation
// docs/plans/19 §12.4 · §12.10 (5.3, content53): 칼로스 이야기's scenes — the server's data, sent in /v2/expedition's reply (ExpReply.story), so a
// line can change without an app. A scene goes with a stage of the story's expeditions (Expeditions.since53: its index), shown when that stage
// comes ("start") or after its trainer or fight is won ("won"). A page is two lines of about 14 letters; who nil: the narration.

enum Story {
    static let professor = "플라타느 박사", lysandre = "플라드리"
    /// The chapters' names (ExpStage.chapter's).
    static let chapters = [1: "수상한 무리", 2: "전설의 이야기", 3: "기지로 가는 길", 4: "플라드리", 5: "남은 하나"]
    private static func scene(_ id: String, _ stage: Int, _ at: String, _ pages: [(String?, String, String)]) -> StoryScene {
        let ch = Expeditions.since53.first { $0.id == id }?.stages[safe: stage]?.chapter ?? 0
        return StoryScene(id: id, stage: stage, at: at, pages: pages.map { StoryPage(who: $0.0, lines: [$0.1, $0.2]) }, title: chapters[ch])
    }
    static let scenes: [StoryScene] = {
        let s = Expeditions.story, s5 = Expeditions.story5, p = professor
        let grunt = "플레어단 조무래기", admin = "플레어단 간부", sci = "플레어단 과학자"
        return [
            // 1장 — 수상한 무리
            scene(s, 0, "start", [(nil, "칼로스 지방에서", "소식이 왔다."), (p, "안녕! 나는 칼로스의", "플라타느 박사야."), (p, "요즘 플레어단이라는", "무리가 수상해."),
                                  (p, "칼로스를 걸으면서", "무슨 일인지 봐 줄래?"), (nil, "칼로스 코스를", "2만 걸음 걸어 보자.")]),
            scene(s, 1, "start", [(grunt, "거기 서! 우리는", "멋진 플레어단이다!"), (grunt, "세련되지 못한 녀석은", "비켜 줘야겠어!")]),
            scene(s, 1, "won", [(grunt, "이, 이럴 수가...", "멋이 모자랐나..."), (grunt, "하지만 계획은", "이미 시작됐다고!"), (p, "계획이라니...", "조금 더 알아보자.")]),
            // 2장 — 전설의 이야기
            scene(s, 2, "start", [(p, "플레어단이 전설의", "포켓몬을 찾는대."), (p, "생명을 주는 포켓몬과", "모든 걸 앗는 포켓몬."), (nil, "다시 칼로스를", "2만 걸음 걸어 보자.")]),
            scene(s, 3, "start", [(admin, "박사의 심부름꾼?", "귀찮게 됐네."), (admin, "아름다운 세상은", "선택받은 자의 것!")]),
            scene(s, 3, "won", [(admin, "흥, 오늘은", "물러나 주지."), (admin, "보스께서 곧", "최종병기를 깨우실 거야."), (p, "최종병기...?", "서두르는 게 좋겠어.")]),
            // 3장 — 기지로 가는 길
            scene(s, 4, "start", [(p, "플레어단 기지는", "칼로스 깊은 곳이야."), (p, "칼로스 포켓몬을", "5종 넘게 만나 봐."), (nil, "칼로스 도감이 5종이", "되면 3장이 열린다.")]),
            scene(s, 5, "start", [(p, "좋아, 이제 기지로", "가는 길을 찾자.")]),
            scene(s, 6, "start", [(sci, "여기까지 오다니.", "흥미로운 데이터군."), (sci, "최종병기 실험을", "방해하게 둘 순 없지.")]),
            scene(s, 6, "won", [(sci, "계산에 없던", "결과로군..."), (sci, "보스는 이미", "열쇠를 손에 넣었다."), (p, "열쇠는 전설의", "포켓몬일 거야.")]),
            // 4장 — 플라드리
            scene(s, 7, "start", [(p, "마지막이야.", "플레어단 기지로!"), (nil, "칼로스를 2만 걸음", "걸으면 기지다.")]),
            scene(s, 8, "start", [(lysandre, "어서 오게.", "나는 플라드리."), (lysandre, "세상은 너무 많은", "것을 원하지."), (lysandre, "그러니 고르겠네.", "남길 것만 남기도록."),
                                  (lysandre, "막고 싶다면", "힘을 보여 주게!")]),
            scene(s, 8, "won", [(lysandre, "...졌군.", "하지만 늦었네."), (lysandre, "최종병기가 울리고", "전설이 눈을 뜬다!")]),
            scene(s, 9, "start", [(nil, "기지 깊은 곳에서", "두 빛이 깨어났다."), (nil, "푸른 나무의 빛과", "붉은 고치의 빛."), (p, "둘 중 하나와", "마주해야 해."),
                                  (nil, "제르네아스?", "이벨타르? 골라 보자.")]),
            scene(s, 10, "start", [(nil, "전설의 포켓몬이", "앞을 막아섰다!")]),
            scene(s, 10, "won", [(nil, "전설의 포켓몬이", "마음을 열었다."), (p, "해냈구나!", "칼로스는 무사해."), (p, "남은 하나도", "언젠가 깨어날 거야.")]),
            // 5장 — 남은 하나
            scene(s5, 0, "start", [(p, "남은 전설이 다시", "잠들었다는구나."), (p, "칼로스 포켓몬을", "10종 넘게 만나 봐.")]),
            scene(s5, 1, "start", [(p, "칼로스를 4만 걸음", "걸으면 닿을 거야.")]),
            scene(s5, 2, "start", [(nil, "남은 전설이", "조용히 기다린다.")]),
            scene(s5, 2, "won", [(p, "두 전설이 모두", "너와 함께하는구나."), (p, "칼로스 이야기는", "여기까지야. 고마워!")]),
        ]
    }()
}
