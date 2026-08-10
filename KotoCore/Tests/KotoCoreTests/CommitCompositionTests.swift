import AppKit
import InputMethodKit
import KanaKanjiConverterModule
import Testing

@testable import KotoCore

/// クライアント(入力先アプリ)への同期呼び出しに関する回帰テスト。
///
/// 呼び出しが 1 回でも増えれば、その分だけ入力メソッドが止まりうる時間が伸びる。
/// フォーカス遷移の最中に呼ばれる `commitComposition` がもっとも危ないので、
/// ここでは次の 2 点を固定する:
///
/// - クライアントを叩く回数が 1 回を超えないこと
/// - 叩く時点で、候補ウィンドウと内部状態の後始末が済んでいること

@Test("候補選択中の commitComposition は候補と残りをまとめて 1 回で送る")
@MainActor
func commitCompositionIssuesSingleCall() {
  let controller = makeSelectingController(
    composing: "あいうえ", candidateText: "愛", surfaceCount: 2)
  let client = FakeTextInput()

  controller.commitComposition(client)

  #expect(client.calls == [.insertText("愛うえ")])
}

@Test("commitComposition はクライアントを叩く前に内部状態を畳んでいる")
@MainActor
func commitCompositionFoldsStateBeforeCallingClient() {
  let controller = makeSelectingController(
    composing: "あいうえ", candidateText: "愛", surfaceCount: 2)
  let client = FakeTextInput()

  var stateAtCall: InputState?
  var candidateCountAtCall: Int?
  client.onCall = { [weak controller] _ in
    stateAtCall = controller?.state
    candidateCountAtCall = controller?.candidateList.count
  }

  controller.commitComposition(client)

  // 呼び出しが数秒ブロックしうる以上、その間に activateServer や handle が
  // 再入しても矛盾しないよう、叩く時点で状態は畳み終わっていること。
  #expect(stateAtCall == .normal)
  #expect(candidateCountAtCall == 0)
}

@Test("commitComposition はクライアントを叩く前に候補ウィンドウを畳んでいる")
@MainActor
func commitCompositionHidesCandidateWindowBeforeCallingClient() {
  let controller = makeSelectingController(
    composing: "あいうえ", candidateText: "愛", surfaceCount: 2)
  #expect(controller.candidateWindow.isShowing(for: controller))

  let client = FakeTextInput()
  var showingAtCall: Bool?
  client.onCall = { [weak controller] _ in
    guard let controller else {
      return
    }
    showingAtCall = controller.candidateWindow.isShowing(for: controller)
  }

  controller.commitComposition(client)

  // 逆順だと、ブロックしている数秒のあいだ候補ウィンドウが最前面に取り残される。
  #expect(showingAtCall == false)
}

@Test("何も入力していないアプリ切り替えではクライアントに触れない")
@MainActor
func commitCompositionWithNothingPendingDoesNotTouchClient() {
  let controller = makeController()
  let client = FakeTextInput()

  controller.commitComposition(client)

  // commitComposition は入力していない切り替えでも飛んでくる。ここで 1 往復投げると
  // フォーカス遷移中のアプリを待つだけで、消すべき未確定文字列も無い。
  #expect(client.calls.isEmpty)
  #expect(controller.state == .normal)
}

@Test("未確定文字列が出ているのに確定するものが無ければ、空の未確定文字列で消す")
@MainActor
func commitCompositionClearsStrandedMarkedText() {
  let controller = makeController()
  // 未確定文字列は出ているが中身が空、という壊れた状態を想定する。
  controller.state = .composing
  let client = FakeTextInput()

  controller.commitComposition(client)

  // insertText("") では未確定文字列が消えないアプリがあるため setMarkedText を使う。
  #expect(client.calls == [.setMarkedText("")])
  #expect(controller.state == .normal)
}

@Test("入力中に Enter で確定してもクライアント呼び出しは 1 回")
@MainActor
func enterWhileComposingIssuesSingleCall() {
  let controller = makeController()
  controller.composingText.append("あい", inputStyle: .direct)
  controller.state = .composing
  let client = FakeTextInput()

  let handled = controller.handle(
    makeKeyEvent(characters: "\r", keyCode: Keycodes.enter), client: client)

  #expect(handled)
  #expect(client.calls == [.insertText("あい")])
  #expect(controller.state == .normal)
}

@Test("候補選択中に文字を打つと、確定 1 回と未確定の更新 1 回で収まる")
@MainActor
func typingWhileSelectingIssuesTwoCalls() {
  let controller = makeSelectingController(
    composing: "あいうえ", candidateText: "愛", surfaceCount: 2)
  let client = FakeTextInput()

  let handled = controller.handle(makeKeyEvent(characters: "k", keyCode: 0x28), client: client)

  #expect(handled)
  #expect(client.calls.count == 2)
  #expect(client.calls.first == .insertText("愛うえ"))
  #expect(controller.state == .composing)
}

@Test("使えるクライアントがどこにも無ければ、状態だけ畳んで終わる")
@MainActor
func commitCompositionWithoutUsableClient() {
  // 引数の client も self.client() も使えない状況。IMK のヘッダ上は起きないはずだが、
  // 起きたときに状態が `.selecting` のまま生き残らないことを確かめる。
  let controller = makeSelectingController(
    composing: "あいうえ", candidateText: "愛", surfaceCount: 2)

  controller.commitComposition(nil)

  #expect(controller.state == .normal)
  #expect(controller.candidateList.isEmpty)
}

@Test("handle は client が IMKTextInput でなければ何もせず false を返す")
@MainActor
func handleWithoutUsableClient() {
  let controller = makeController()

  let handled = controller.handle(makeKeyEvent(characters: "k", keyCode: 0x28), client: nil)

  #expect(!handled)
  #expect(controller.state == .normal)
}
