//
//  InputController.swift
//  Koto
//
//  Created by koki sato on 2024/09/15.
//

import InputMethodKit
import KanaKanjiConverterModuleWithDefaultDictionary

@objc(KotoInputController)
public class KotoInputController: IMKInputController {
  // IMKInputController はクライアント(アプリ)ごとに生成・破棄されるため、
  // 候補ウィンドウと KanaKanjiConverter はコントローラに持たせず全体で共有する。
  // インスタンスごとに生成すると、辞書の重複ロードと同一ディレクトリへの学習データ
  // 多重書き込みが起きるほか、候補ウィンドウがクライアントの数だけ生成される。
  @MainActor
  static let sharedCandidateWindow = CandidateWindowController()

  @MainActor
  static let sharedConverter = KanaKanjiConverter()

  @MainActor
  var candidateWindow: CandidateWindowController { Self.sharedCandidateWindow }

  @MainActor
  var converter: KanaKanjiConverter { Self.sharedConverter }

  let appMenu = NSMenu()

  var state: InputState = .normal
  var composingText: ComposingText = ComposingText()
  /// 変換候補の唯一の情報源。候補ウィンドウはこれを描画するだけで状態を持たない。
  var candidateList = CandidateList()

  public override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
    NSLog("KotoInputController init")

    self.appMenu.addItem(
      NSMenuItem(
        title: "学習データをリセット", action: #selector(self.resetLearningData(_:)), keyEquivalent: ""
      ))

    super.init(server: server, delegate: delegate, client: inputClient)
  }

  public override func menu() -> NSMenu! {
    return self.appMenu
  }

  @MainActor
  public override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
    guard let eventType = self.getEventType(event) else {
      return false
    }

    // キーを処理する前に、候補ウィンドウの表示を自分の状態に一致させる。
    // ここを通すことで、以降の分岐は「.selecting なら候補が画面に出ている」
    // という前提を置ける。特に数字キーによる候補選択は画面上の行番号に依存する
    // ため、見えていないリストから確定してしまう経路をここで塞いでいる。
    self.syncCandidateWindow()

    switch (eventType, self.state) {
    case (.input(let text), _):
      return self.handleInputText(text)

    case (.number(let number), .selecting):
      guard let index = self.candidateList.index(forDisplayedNumber: number) else {
        // 表示されていない番号(0 や候補数に満たない番号)は通常の文字入力に回す。
        return self.handleInputText(String(number))
      }
      self.candidateList.select(index)
      self.commitSelectedCandidate()
      return true

    case (.number(let number), _):
      return self.handleInputText(String(number))

    case (.backspace, .composing):
      self.composingText.removeLast()
      if self.composingText.isEmpty {
        self.clear()
      } else {
        self.setComposingMarkedText()
      }
      return true

    case (.backspace, .selecting):
      self.flushToClient()
      self.clear()
      return false

    case (.space, .normal):
      self.insertText("　")
      return true

    case (.space, .composing), (.down, .composing):
      self.startSelecting()
      return true

    case (.space, .selecting), (.down, .selecting):
      self.candidateList.selectNext()
      self.refreshSelection()
      return true

    case (.up, .selecting):
      self.candidateList.selectPrevious()
      self.refreshSelection()
      return true

    case (.enter, .composing):
      self.insertComposingText()
      self.clear()
      return true

    case (.enter, .selecting):
      self.commitSelectedCandidate()
      return true

    case (.esc, .composing):
      self.clear()
      return true

    case (.esc, .selecting):
      self.stopSelecting()
      self.setComposingMarkedText()
      return true

    case (.ctrlK, .composing):
      self.composingText = self.composingText.toKatakana()
      self.setComposingMarkedText()
      return true

    case (.ctrlK, .selecting):
      self.stopSelecting()
      self.composingText = self.composingText.toKatakana()
      self.setComposingMarkedText()
      return true

    case (.shiftLeft, .selecting):
      if self.composingText.convertTargetCursorPosition > 1 {
        _ = self.composingText.moveCursorFromCursorPosition(count: -1)
        self.refreshCandidates()
      }
      return true

    case (.shiftRight, .selecting):
      if !self.composingText.isAtEndIndex {
        _ = self.composingText.moveCursorFromCursorPosition(count: 1)
        self.refreshCandidates()
      }
      return true

    case (.shiftLeft, .composing), (.shiftRight, .composing):
      return true

    case (.ignore, .composing), (.ignore, .selecting):
      return true

    default:
      return false
    }
  }

  // 入力セッションがこのコントローラに移ったので、共有している候補ウィンドウを
  // 引き取っていったん畳む。前のクライアントのコントローラが deactivate を
  // 受け取れないまま放置されても、パネルが最前面に残り続けないようにするため。
  //
  // 自分が変換中だった場合の再表示は行わない。activate 直後のクライアントへの
  // 同期呼び出しはアプリによってはデッドロックの引き金になるため、
  // ここではクライアントに触れず、次のキー入力時に syncCandidateWindow() へ任せる。
  @MainActor
  public override func activateServer(_ sender: Any!) {
    NSLog("KotoInputController activateServer")

    super.activateServer(sender)
    self.candidateWindow.takeOver(by: self)
  }

  // フォーカス喪失やクリックで OS が未確定テキストの確定を要求したときに呼ばれる。
  // super.commitComposition は呼ばない(切り替え時にハングする既知問題がある)。
  @MainActor
  public override func commitComposition(_ sender: Any!) {
    self.flushToClient()
    self.resetState()
  }

  // deactivate 中のクライアントへの同期呼び出しは、切り替え先セッションの
  // ブロッキングや IMK 内部のクラッシュの引き金になるため行わない。
  // 未確定テキストの確定は commitComposition に任せる。
  @MainActor
  public override func deactivateServer(_ sender: Any!) {
    NSLog("KotoInputController deactivateServer")

    self.resetState()
    self.converter.saveLearningData()
    super.deactivateServer(sender)
  }

  // MARK: - 状態遷移

  /// 文字入力を現在の状態に応じて処理する。
  /// 候補選択中なら選択中の候補と残りの未確定文字列を確定してから入力し直す。
  @MainActor
  private func handleInputText(_ text: String) -> Bool {
    if self.state == .selecting {
      self.flushToClient()
      self.clear()
    }
    if self.state == .normal {
      self.state = .composing
    }

    self.composingText.append(text, inputStyle: .roman2kana)
    self.setComposingMarkedText()
    return true
  }

  /// 変換を開始して候補ウィンドウを開く。
  @MainActor
  private func startSelecting() {
    if self.composingText.shouldInsertN() {
      self.composingText.append("n", inputStyle: .roman2kana)
    }

    self.state = .selecting
    self.refreshCandidates()
  }

  /// 未確定文字列は残したまま候補選択をやめ、`.composing` に戻す。
  @MainActor
  private func stopSelecting() {
    self.state = .composing
    // 変換範囲を縮めたまま戻ると、次の変換が見えている文字列より短い範囲だけを
    // 対象にしてしまうため、カーソルを末尾へ戻す。
    self.composingText.moveCursorToEnd()
    self.candidateList.reset()
    self.candidateWindow.hide(requestedBy: self)
  }

  /// 現在の変換対象を変換し直し、候補ウィンドウを開き直す。
  /// 候補が得られない場合は変換前(`.composing`)に戻す。
  @MainActor
  private func refreshCandidates() {
    let results = self.converter.convert(self.composingText.prefixToCursorPosition())
    self.candidateList.replace(with: results.mainResults)

    guard !self.candidateList.isEmpty else {
      self.stopSelecting()
      self.setComposingMarkedText()
      return
    }

    self.setSelectingMarkedText()
    self.candidateWindow.show(self.candidateList, at: self.cursorRect(), delegate: self)
  }

  /// 候補ウィンドウの表示を現在の状態に一致させる。
  ///
  /// ウィンドウはプロセス全体で共有していて、別クライアントのコントローラに
  /// 引き取られていることがある。変換中なのに自分の候補が出ていない場合は、
  /// 位置を取り直して開き直す。キー処理の入口で必ず通すため、以降の処理は
  /// 「`.selecting` なら候補が画面に出ている」と仮定してよい。
  @MainActor
  private func syncCandidateWindow() {
    guard self.state == .selecting, !self.candidateList.isEmpty else {
      return
    }
    guard !self.candidateWindow.isShowing(for: self) else {
      return
    }
    self.candidateWindow.show(self.candidateList, at: self.cursorRect(), delegate: self)
  }

  /// 選択位置だけが変わったときの反映。
  /// ウィンドウの位置とサイズは変わらないため、クライアントへの問い合わせは行わない。
  @MainActor
  private func refreshSelection() {
    self.setSelectingMarkedText()
    self.candidateWindow.update(self.candidateList)
  }

  /// 選択中の候補を確定する。未確定文字列が残っていれば続けて次の文節を変換する。
  @MainActor
  private func commitSelectedCandidate() {
    self.insertSelectingCandidate()

    if self.composingText.isEmpty {
      self.clear()
      return
    }
    self.refreshCandidates()
  }

  @MainActor
  private func clear() {
    self.setMarkedText("")
    self.resetState()
  }

  // クライアントへの呼び出しを伴わない状態リセット。deactivate 中など、
  // クライアントに触れたくない場面では clear() ではなくこちらを使う。
  @MainActor
  private func resetState() {
    self.candidateWindow.hide(requestedBy: self)

    self.state = .normal
    self.converter.stopComposition()
    self.composingText.stopComposition()
    self.candidateList.reset()
  }

  // MARK: - クライアントとのやり取り

  /// 未確定文字列の先頭のスクリーン座標。候補ウィンドウの配置基準に使う。
  @MainActor
  private func cursorRect() -> NSRect {
    var rect = NSRect.zero
    _ = self.client().attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
    return rect
  }

  private func setMarkedText(_ text: Any!) {
    self.client().setMarkedText(text, selectionRange: .notFound, replacementRange: .notFound)
  }

  private func underlineAttributes() -> [NSAttributedString.Key: Any]? {
    return self.mark(forStyle: kTSMHiliteConvertedText, at: .notFound)
      as? [NSAttributedString.Key: Any]
  }

  private func highlightAttributes() -> [NSAttributedString.Key: Any]? {
    return self.mark(forStyle: kTSMHiliteSelectedConvertedText, at: .notFound)
      as? [NSAttributedString.Key: Any]
  }

  private func setComposingMarkedText() {
    self.setMarkedText(
      NSAttributedString(
        string: self.composingText.convertTarget, attributes: self.underlineAttributes()))
  }

  @MainActor
  private func setSelectingMarkedText() {
    guard let candidate = self.candidateList.selected else {
      return
    }

    var afterComposingText = self.composingText
    afterComposingText.prefixComplete(composingCount: candidate.composingCount)

    let text = NSMutableAttributedString(string: "")
    text.append(NSAttributedString(string: candidate.text, attributes: self.highlightAttributes()))
    text.append(
      NSAttributedString(
        string: afterComposingText.convertTarget, attributes: self.underlineAttributes()))
    self.setMarkedText(text)
  }

  private func insertText(_ text: String) {
    self.client().insertText(
      text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
  }

  private func insertComposingText() {
    if self.composingText.isEmpty {
      return
    }
    self.insertText(self.composingText.convertTarget)
  }

  /// 未確定のものをすべてクライアントへ送り出す。
  ///
  /// 選択中の候補、続いて残りの未確定文字列の順に確定する。状態の後始末は
  /// 呼び出し側が `clear()` か `resetState()` で行う(クライアントに触れてよい
  /// 場面かどうかで使い分けるため)。
  @MainActor
  private func flushToClient() {
    self.insertSelectingCandidate()
    self.insertComposingText()
  }

  /// 選択中の候補を確定してクライアントへ送り、変換済みの部分を未確定文字列から取り除く。
  @MainActor
  private func insertSelectingCandidate() {
    guard let candidate = self.candidateList.selected else {
      return
    }
    // 確定済みの候補を二重に挿入しないよう、取り出したら候補列は空にする。
    self.candidateList.reset()

    self.insertText(candidate.text)

    self.composingText.prefixComplete(composingCount: candidate.composingCount)
    self.converter.setCompletedData(candidate)
    self.converter.updateLearningData(candidate)
  }

  @objc @MainActor
  func resetLearningData(_ sender: Any) {
    self.converter.resetLearningData()
  }

  // MARK: - キーイベントの解釈

  private func getEventType(_ event: NSEvent) -> EventType? {
    if event.type != .keyDown {
      return nil
    }

    if event.modifierFlags.contains(.command) {
      return nil
    }

    // Control key
    if event.modifierFlags.contains(.control) {
      switch event.keyCode {
      case Keycodes.h:
        return .backspace
      case Keycodes.p:
        return .up
      case Keycodes.k:
        return .ctrlK
      case Keycodes.n:
        return .down
      default:
        return .ignore
      }
    }

    switch event.keyCode {
    case Keycodes.yen:
      return getYenKeyEventType(event)
    case Keycodes.enter:
      return .enter
    case Keycodes.space:
      return .space
    case Keycodes.backspace:
      return .backspace
    case Keycodes.escape:
      return .esc
    case Keycodes.leftArrow:
      if event.modifierFlags.contains(.shift) {
        return .shiftLeft
      } else {
        return .ignore
      }
    case Keycodes.rightArrow:
      if event.modifierFlags.contains(.shift) {
        return .shiftRight
      } else {
        return .ignore
      }
    case Keycodes.downArrow:
      return .down
    case Keycodes.upArrow:
      return .up
    default:
      break
    }

    guard let text = event.characters else {
      return nil
    }

    // キーコードではなく入力文字から判定することで、キーボードレイアウトに依存しない。
    // テンキーは除く。macOS 標準の日本語入力と同様、テンキーの数字は候補選択ではなく
    // 文字入力として扱う。(矢印キーにも .numericPad が立つが、上の keyCode 分岐で
    // 先に処理されるためここには来ない)
    if !event.modifierFlags.contains(.numericPad), let number = asciiDigit(text) {
      return .number(number)
    }

    if isPrintable(text) {
      return .input(text)
    }

    return nil
  }

  private func getYenKeyEventType(_ event: NSEvent) -> EventType {
    if event.modifierFlags.contains(.shift) {
      return .input("|")
    }

    if event.modifierFlags.contains(.option) {
      return .input("\\")
    } else {
      return .input("¥")
    }
  }
}

extension KotoInputController: CandidateWindowDelegate {
  @MainActor
  func candidateWindow(_ window: CandidateWindowController, didClickCandidateAt index: Int) {
    guard self.state == .selecting else {
      return
    }
    // マウス経由の呼び出しは IMK の handle(_:client:) の外、つまり入力メソッド側の
    // AppKit イベントとして走るため、クライアントが失われている可能性がある。
    // その場合はクライアントに触れず状態だけ畳む。
    guard self.client() != nil else {
      self.resetState()
      return
    }
    self.candidateList.select(index)
    self.commitSelectedCandidate()
  }

  @MainActor
  func candidateWindow(_ window: CandidateWindowController, didScrollBy rows: Int) {
    guard self.state == .selecting else {
      return
    }
    self.candidateList.scroll(by: rows)
    self.candidateWindow.update(self.candidateList)
  }
}
