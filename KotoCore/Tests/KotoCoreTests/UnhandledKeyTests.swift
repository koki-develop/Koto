import AppKit
import InputMethodKit
import Testing

@testable import KotoCore

/// 打鍵が実を結ばなかった場合についての回帰テスト。
///
/// 「Koto を選んでいるのにローマ字がそのまま入る」という不具合は、外から見える形が
/// 正常な動作(ショートカット、ファンクションキー、いまの状態ですることが無いキー)と
/// 同じ。ここでは両者の分け方 —— **説明がつくかどうか** —— が壊れていないことを固定する。
///
/// 実際に押されている修飾キーは、テストを走らせている人の手元に依存する。
/// 押下状態は必ず差し替えてから使うこと。

@MainActor
private func makeController(held: NSEvent.ModifierFlags) -> KotoInputController {
  let controller = KotoCoreTests.makeController()
  controller.unhandledKeyMonitor.heldModifiers = { held }
  return controller
}

private let tab = "\t"
private let controlA = "\u{01}"
private let carriageReturn = "\r"
private let functionKey = "\u{F708}"

// MARK: - 説明がつくもの

@Test("ファンクションキーやタブは何度続いても異常にしない")
@MainActor
func nonPrintableKeysAreNeverUnexplained() {
  let controller = makeController(held: [])
  let client = FakeTextInput()

  for _ in 0..<10 {
    #expect(!controller.handle(makeKeyEvent(characters: tab, keyCode: 0x30), client: client))
    #expect(
      !controller.handle(makeKeyEvent(characters: functionKey, keyCode: 0x60), client: client))
  }

  // タブ送りやファンクションキーの連打で鳴っては、本物の発生が埋もれる。
  #expect(controller.unhandledKeyMonitor.unexplainedRun == 0)
  #expect(client.calls.isEmpty)
}

@Test("いまの状態ですることが無いキーは異常にしない")
@MainActor
func keysWithNoActionForTheStateAreNeverUnexplained() {
  let controller = makeController(held: [])
  let client = FakeTextInput()

  // 未入力のまま Enter や矢印を打つのは日常の操作。どれも文字を持たない。
  for _ in 0..<10 {
    #expect(
      !controller.handle(
        makeKeyEvent(characters: carriageReturn, keyCode: Keycodes.enter), client: client))
    #expect(
      !controller.handle(
        makeKeyEvent(characters: functionKey, keyCode: Keycodes.upArrow), client: client))
  }

  #expect(controller.unhandledKeyMonitor.unexplainedRun == 0)
}

@Test("本当に押している修飾キーは素通しの説明になる")
@MainActor
func heldModifiersExplainTheKey() {
  let controller = makeController(held: [.command])
  let client = FakeTextInput()

  for _ in 0..<10 {
    #expect(
      !controller.handle(
        makeKeyEvent(characters: "z", keyCode: 0x06, modifierFlags: .command), client: client))
  }

  // ⌘Z を連打しているだけ。アプリのショートカットなので Koto の出番は無い。
  #expect(controller.unhandledKeyMonitor.unexplainedRun == 0)
}

// MARK: - 説明がつかないもの

@Test("押していない ⌘ を名乗るキーは異常として数える")
@MainActor
func commandThatIsNotHeldIsUnexplained() {
  let controller = makeController(held: [])
  let client = FakeTextInput()

  for _ in 0..<5 {
    #expect(
      !controller.handle(
        makeKeyEvent(characters: "z", keyCode: 0x06, modifierFlags: .command), client: client))
  }

  // 押されていない修飾キーがイベントに乗り続けるのが、取りこぼしが残す形。
  #expect(controller.unhandledKeyMonitor.unexplainedRun == 5)
}

@Test("押していない control を名乗るキーも異常として数える")
@MainActor
func controlThatIsNotHeldIsUnexplained() {
  let controller = makeController(held: [])
  let client = FakeTextInput()

  // control 付きのキーは `.ignore` として解釈できてしまい、素通しの理由が
  // `.noActionForState` になる。理由ではなく修飾キーの裏取りで判定していないと、
  // ここがまるごと死角になる。
  for _ in 0..<5 {
    #expect(
      !controller.handle(
        makeKeyEvent(characters: controlA, keyCode: 0x00, modifierFlags: .control),
        client: client))
  }

  #expect(controller.unhandledKeyMonitor.unexplainedRun == 5)
}

@Test("解釈できるキーが 1 つ来れば連続は途切れる")
@MainActor
func handledKeyEndsTheRun() {
  let controller = makeController(held: [])
  let client = FakeTextInput()

  for _ in 0..<4 {
    _ = controller.handle(
      makeKeyEvent(characters: "z", keyCode: 0x06, modifierFlags: .command), client: client)
  }
  #expect(controller.unhandledKeyMonitor.unexplainedRun == 4)

  #expect(controller.handle(makeKeyEvent(characters: "k", keyCode: 0x28), client: client))

  #expect(controller.unhandledKeyMonitor.unexplainedRun == 0)
}

@Test("入力セッションが終わるときにも連続は閉じる")
@MainActor
func deactivatingEndsTheRun() {
  let controller = makeController(held: [])
  let client = FakeTextInput()

  for _ in 0..<4 {
    _ = controller.handle(
      makeKeyEvent(characters: "z", keyCode: 0x06, modifierFlags: .command), client: client)
  }
  #expect(controller.unhandledKeyMonitor.unexplainedRun == 4)

  // 打っても入らないので別のアプリへ移る、が利用者の自然な反応。
  // ここで閉じないと発生の終わりが記録に残らない。
  controller.deactivateServer(nil)

  #expect(controller.unhandledKeyMonitor.unexplainedRun == 0)
}

@Test("client が使えないときは連続に数えない")
@MainActor
func keyWithoutUsableClientIsNotCounted() {
  let controller = makeController(held: [])

  // こちらは専用の error ログを持つ別経路。二重に記録しない。
  #expect(!controller.handle(makeKeyEvent(characters: "k", keyCode: 0x28), client: nil))

  #expect(controller.unhandledKeyMonitor.unexplainedRun == 0)
}

@Test("説明のつくものは連続を途切れさせる")
@MainActor
func explainedKeyEndsTheRun() {
  let controller = makeController(held: [])
  let client = FakeTextInput()

  for _ in 0..<2 {
    _ = controller.handle(
      makeKeyEvent(characters: "z", keyCode: 0x06, modifierFlags: .command), client: client)
  }
  #expect(controller.unhandledKeyMonitor.unexplainedRun == 2)

  // タブは説明がつく。ここで戻さないと、何時間も離れた無関係な単発が積み上がって
  // 閾値をまたぎ、規模も長さも嘘になった error が残る。
  _ = controller.handle(makeKeyEvent(characters: tab, keyCode: 0x30), client: client)

  #expect(controller.unhandledKeyMonitor.unexplainedRun == 0)
}

// MARK: - 飲み込みと取り違え

@Test("文字を持たないキーは飲み込まずアプリへ渡す")
@MainActor
func keysWithoutCharactersAreNotSwallowed() {
  let controller = makeController(held: [])
  let client = FakeTextInput()

  // `characters` が空文字列のキー。ここを `.input("")` として受けてしまうと、
  // 未確定状態に入って空の setMarkedText を投げ、アプリにも素通しの記録にも残らない。
  let handled = controller.handle(makeKeyEvent(characters: "", keyCode: 0x66), client: client)

  #expect(!handled)
  #expect(client.calls.isEmpty)
  #expect(controller.state == .normal)
  // 文字を持たないキーなので、説明がつく。
  #expect(controller.unhandledKeyMonitor.unexplainedRun == 0)
}

@Test("候補選択中の backspace は、確定したうえでアプリにも渡す")
@MainActor
func backspaceWhileSelectingCommitsAndForwards() {
  let controller = makeSelectingController(
    composing: "あいうえ", candidateText: "愛", surfaceCount: 2)
  controller.unhandledKeyMonitor.heldModifiers = { [] }
  let client = FakeTextInput()

  let handled = controller.handle(
    makeKeyEvent(characters: "\u{8}", keyCode: Keycodes.backspace), client: client)

  // 削除そのものはアプリの仕事なので false を返すが、Koto は確定を書き込んでいる。
  #expect(!handled)
  #expect(client.calls == [.insertText("愛うえ")])
  #expect(controller.state == .normal)
}

@Test("確定したうえでアプリに渡したキーは、実を結ばなかった扱いにしない")
@MainActor
func forwardedKeyIsNotRecordedAsUnhandled() {
  let controller = makeSelectingController(
    composing: "あいうえ", candidateText: "愛", surfaceCount: 2)
  controller.unhandledKeyMonitor.heldModifiers = { [] }
  let client = FakeTextInput()

  // Ctrl+H は Koto では backspace。control を名乗るので、もし実を結ばなかったものとして記録されれば
  // 「押されていない control」として異常に数えられる — そこで取り違えが見える。
  let handled = controller.handle(
    makeKeyEvent(characters: "\u{8}", keyCode: Keycodes.h, modifierFlags: .control),
    client: client)

  #expect(!handled)
  #expect(client.calls == [.insertText("愛うえ")])
  // 確定を書き込んだのに「この状態ですることが無かった」と記録してはいけない。
  #expect(controller.unhandledKeyMonitor.unexplainedRun == 0)
}

@Test("変換中に握り潰したキーも、説明がつかなければ数える")
@MainActor
func swallowedCombinationIsRecorded() {
  let controller = makeController(held: [])
  controller.state = .composing
  controller.composingText.append("あ", inputStyle: .direct)
  let client = FakeTextInput()

  // 変換中の control 付きは Koto が握り潰す。アプリにも渡らないので、記録しなければ
  // 「キーだけが消えて痕跡が何も残らない」という一番見つけにくい形になる。
  for _ in 0..<5 {
    #expect(
      controller.handle(
        makeKeyEvent(characters: controlA, keyCode: 0x00, modifierFlags: .control),
        client: client))
  }

  #expect(controller.unhandledKeyMonitor.unexplainedRun == 5)
}

@Test("変換中でも、本当に押している control なら握り潰しは説明がつく")
@MainActor
func swallowedCombinationWithHeldControlIsExplained() {
  let controller = makeController(held: [.control])
  controller.state = .composing
  controller.composingText.append("あ", inputStyle: .direct)
  let client = FakeTextInput()

  for _ in 0..<5 {
    #expect(
      controller.handle(
        makeKeyEvent(characters: controlA, keyCode: 0x00, modifierFlags: .control),
        client: client))
  }

  #expect(controller.unhandledKeyMonitor.unexplainedRun == 0)
}
