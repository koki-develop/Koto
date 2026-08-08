//
//  InputController.swift
//  Koto
//
//  Created by koki sato on 2024/09/15.
//

import InputMethodKit
import KanaKanjiConverterModule
import KanaKanjiConverterModuleWithDefaultDictionary

@objc(KotoInputController)
public class KotoInputController: IMKInputController {
  // IMKInputController はクライアント(アプリ)ごとに生成・破棄されるため、
  // 候補ウィンドウと変換器はコントローラに持たせず全体で共有する。
  // インスタンスごとに生成すると、辞書の重複ロードと同一ディレクトリへの学習データ
  // 多重書き込みが起きるほか、候補ウィンドウがクライアントの数だけ生成される。
  @MainActor
  static let sharedCandidateWindow = CandidateWindowController()

  // 変換器の生成は辞書の読み込みと学習データ置き場の作成を伴う。触れば作られてしまう
  // ので、「まだ作られていない」ことを判別できる形で持つ。作りたくない場面
  // (終了処理など)から誤って起こさないため。
  @MainActor
  private static var loadedConverter: Converter?

  @MainActor
  static var sharedConverter: Converter {
    if let converter = Self.loadedConverter {
      return converter
    }
    let converter = Converter()
    Self.loadedConverter = converter
    return converter
  }

  @MainActor
  var candidateWindow: CandidateWindowController { Self.sharedCandidateWindow }

  // 差し替えられるようにしてあるのはテストのため。差し替えなければ共有インスタンス。
  // 既定の変換オプションはユーザの実データを指すので、テストからは必ず捨てて良い
  // ディレクトリを向けた Converter を代入すること。
  @MainActor
  lazy var converter: Converter = Self.sharedConverter

  /// 変換器を用意する。プロセス起動時にアプリ側から呼ぶ。
  ///
  /// 放っておくと最初の `deactivateServer` — つまりフォーカス遷移の真っ最中 — に
  /// 辞書を読み込むことになるため、誰も待っていない起動時に済ませてしまう。
  @MainActor
  public static func preload() {
    _ = Self.sharedConverter
  }

  /// 保存待ちの学習データを書き出す。プロセス終了時にアプリ側から呼ぶ。
  ///
  /// 変換器が一度も作られていなければ何もしない。終了処理のためだけに辞書を
  /// 読み込むのは無駄なうえ、終了までに使える時間を食い潰す。
  @MainActor
  public static func flushLearningData() {
    Self.loadedConverter?.flushLearningData()
  }

  let appMenu = NSMenu()

  var state: InputState = .normal
  var composingText: ComposingText = ComposingText()
  /// 変換候補の唯一の情報源。候補ウィンドウはこれを描画するだけで状態を持たない。
  var candidateList = CandidateList()

  public override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
    Log.lifecycle.info("init")

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
    // クライアントへの同期呼び出しは、このコールバックが渡してきた client にだけ行う。
    // `self.client()` は IMKInputController が保持する ivar で、いつ更新されるかの
    // 保証がない。詳しくは Client.swift を参照。
    guard let client = Client(sender) else {
      // IMK のヘッダは sender が必ず IMKTextInput に適合すると書いているので、
      // ここに来たら異常。黙って素通しすると「Koto を選んでいるのに英数字しか
      // 入らない」状態そのものになるため、痕跡を残す。
      //
      // あわせて状態も畳む。変換中のまま取り残すと、次に正常な client で
      // 呼ばれたときに古い候補を確定してしまう。
      Log.lifecycle.error("handle: client is not an IMKTextInput; the event is passed through")
      self.resetState()
      return false
    }
    guard let eventType = self.getEventType(event) else {
      return false
    }

    // キーを処理する前に、候補ウィンドウの表示を自分の状態に一致させる。
    // ここを通すことで、以降の分岐は「.selecting なら候補が画面に出ている」
    // という前提を置ける。特に数字キーによる候補選択は画面上の行番号に依存する
    // ため、見えていないリストから確定してしまう経路をここで塞いでいる。
    self.syncCandidateWindow(client)

    switch (eventType, self.state) {
    case (.input(let text), _):
      return self.handleInputText(text, client: client)

    case (.number(let number), .selecting):
      guard let index = self.candidateList.index(forDisplayedNumber: number) else {
        // 表示されていない番号(0 や候補数に満たない番号)は通常の文字入力に回す。
        return self.handleInputText(String(number), client: client)
      }
      self.candidateList.select(index)
      self.commitSelectedCandidate(client)
      return true

    case (.number(let number), _):
      return self.handleInputText(String(number), client: client)

    case (.backspace, .composing):
      self.composingText.removeLast()
      if self.composingText.isEmpty {
        self.clear(client)
      } else {
        self.setComposingMarkedText(client)
      }
      return true

    case (.backspace, .selecting):
      self.commitPendingText(client)
      return false

    case (.space, .normal):
      client.insertText("　")
      return true

    case (.space, .composing), (.down, .composing):
      self.startSelecting(client)
      return true

    case (.space, .selecting), (.down, .selecting):
      self.candidateList.selectNext()
      self.refreshSelection(client)
      return true

    case (.up, .selecting):
      self.candidateList.selectPrevious()
      self.refreshSelection(client)
      return true

    case (.enter, .composing):
      self.commitPendingText(client)
      return true

    case (.enter, .selecting):
      self.commitSelectedCandidate(client)
      return true

    case (.esc, .composing):
      self.clear(client)
      return true

    case (.esc, .selecting):
      self.stopSelecting()
      self.setComposingMarkedText(client)
      return true

    case (.ctrlK, .composing):
      self.composingText = self.composingText.toKatakana()
      self.setComposingMarkedText(client)
      return true

    case (.ctrlK, .selecting):
      self.stopSelecting()
      self.composingText = self.composingText.toKatakana()
      self.setComposingMarkedText(client)
      return true

    case (.shiftLeft, .selecting):
      if self.composingText.convertTargetCursorPosition > 1 {
        _ = self.composingText.moveCursorFromCursorPosition(count: -1)
        self.refreshCandidates(client)
      }
      return true

    case (.shiftRight, .selecting):
      if !self.composingText.isAtEndIndex {
        _ = self.composingText.moveCursorFromCursorPosition(count: 1)
        self.refreshCandidates(client)
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
  // 自分が変換中だった場合の再表示は行わない。フォーカス遷移の最中に
  // クライアントへ同期呼び出しを投げると数秒ブロックしうるため、
  // ここではクライアントに触れず、次のキー入力時に syncCandidateWindow() へ任せる。
  @MainActor
  public override func activateServer(_ sender: Any!) {
    Log.lifecycle.info("activateServer")

    super.activateServer(sender)
    self.candidateWindow.takeOver(by: self)
  }

  // フォーカス喪失やクリックで OS が未確定テキストの確定を要求したときに呼ばれる。
  // super.commitComposition は呼ばない(切り替え時にハングする既知問題がある)。
  //
  // フォーカス遷移の最中にクライアントへ書き込む、唯一許された場所。順序を守ること:
  //
  //   1. 候補ウィンドウを畳む                          (クライアント非依存)
  //   2. 確定文字列を組み立て、内部状態を .normal へ戻す (クライアント非依存)
  //   3. 最後に、書き込むものがあるときだけ書き込む
  //
  // 3 がブロックしても、そのときには候補ウィンドウは畳まれ、状態も畳み終わっている。
  // 逆順にすると、ブロックしている間ずっと候補ウィンドウが最前面に取り残され、
  // 状態も .selecting のまま生き残る。
  @MainActor
  public override func commitComposition(_ sender: Any!) {
    Log.lifecycle.info("commitComposition")

    self.candidateWindow.hide(requestedBy: self)

    // 引数の client が使えないのは想定外(IMK のヘッダは sender が必ず IMKTextInput に
    // 適合すると書いている)だが、そのときに未確定文字列を黙って捨てるのは避ける。
    guard let client = Client(sender) ?? Client(self.client()) else {
      Log.lifecycle.error("commitComposition: no usable client; pending text is dropped")
      self.resetState()
      return
    }
    self.commitPendingText(client)
  }

  // ここではクライアントに触れない。未確定テキストの確定は commitComposition に任せる。
  // 学習データの保存も行わない。アプリ切り替えのたびに走らせるとフォーカス遷移が
  // その分止まるため、タイミングは Converter が持つ。
  @MainActor
  public override func deactivateServer(_ sender: Any!) {
    Log.lifecycle.info("deactivateServer")

    self.resetState()
    super.deactivateServer(sender)
  }

  // MARK: - 状態遷移

  /// 文字入力を現在の状態に応じて処理する。
  /// 候補選択中なら選択中の候補と残りの未確定文字列を確定してから入力し直す。
  @MainActor
  private func handleInputText(_ text: String, client: Client) -> Bool {
    if self.state == .selecting {
      self.commitPendingText(client)
    }
    if self.state == .normal {
      self.state = .composing
    }

    self.composingText.append(text, inputStyle: .roman2kana)
    self.setComposingMarkedText(client)
    return true
  }

  /// 変換を開始して候補ウィンドウを開く。
  @MainActor
  private func startSelecting(_ client: Client) {
    if self.composingText.shouldInsertN() {
      self.composingText.append("n", inputStyle: .roman2kana)
    }

    self.state = .selecting
    self.refreshCandidates(client)
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
  private func refreshCandidates(_ client: Client) {
    let results = self.converter.convert(self.composingText.prefixToCursorPosition())
    self.candidateList.replace(with: results.mainResults)

    guard !self.candidateList.isEmpty else {
      self.stopSelecting()
      self.setComposingMarkedText(client)
      return
    }

    self.setSelectingMarkedText(client)
    self.candidateWindow.show(self.candidateList, at: client.cursorRect(), delegate: self)
  }

  /// 候補ウィンドウの表示を現在の状態に一致させる。
  ///
  /// ウィンドウはプロセス全体で共有していて、別クライアントのコントローラに
  /// 引き取られていることがある。変換中なのに自分の候補が出ていない場合は、
  /// 位置を取り直して開き直す。キー処理の入口で必ず通すため、以降の処理は
  /// 「`.selecting` なら候補が画面に出ている」と仮定してよい。
  @MainActor
  private func syncCandidateWindow(_ client: Client) {
    guard self.state == .selecting, !self.candidateList.isEmpty else {
      return
    }
    guard !self.candidateWindow.isShowing(for: self) else {
      return
    }
    self.candidateWindow.show(self.candidateList, at: client.cursorRect(), delegate: self)
  }

  /// 選択位置だけが変わったときの反映。
  /// ウィンドウの位置とサイズは変わらないため、クライアントへの問い合わせは行わない。
  @MainActor
  private func refreshSelection(_ client: Client) {
    self.setSelectingMarkedText(client)
    self.candidateWindow.update(self.candidateList)
  }

  /// 選択中の候補を確定する。未確定文字列が残っていれば続けて次の文節を変換する。
  @MainActor
  private func commitSelectedCandidate(_ client: Client) {
    guard let candidate = self.takeSelectedCandidate() else {
      // `.selecting` なのに候補が無い状態は、下の insertText がブロックしている間だけ
      // 存在する。そこへ AppKit 経由のクリックが割り込むのが唯一の経路。
      //
      // ここで状態を畳んではいけない。ブロックが明けた外側の呼び出しが、消えた
      // 未確定文字列で変換をやり直すことになる。外側が返れば整合は戻るので、
      // 何もせず記録だけ残す。
      Log.lifecycle.error("commitSelectedCandidate: no candidate selected while .selecting")
      return
    }

    if self.composingText.isEmpty {
      // 残りがないのでこれで確定。insertText が未確定文字列を置き換えるため、
      // 続けて setMarkedText("") を呼ぶ必要はない。
      self.resetState()
      client.insertText(candidate.text)
      return
    }

    client.insertText(candidate.text)
    self.refreshCandidates(client)
  }

  /// 未確定のものをすべて確定してクライアントへ送り、状態を畳む。
  ///
  /// 選択中の候補と残りの未確定文字列を 1 本の文字列にまとめ、クライアントへの
  /// 呼び出しを 1 回に抑える。内部状態を先に畳んでから送るのは、送信がブロックしても
  /// 状態が矛盾しないようにするため。
  @MainActor
  private func commitPendingText(_ client: Client) {
    // 状態は takePendingText() が畳んでしまうため、先に控えておく。
    let hadComposition = self.state != .normal

    let text = self.takePendingText()
    if !text.isEmpty {
      client.insertText(text)
      return
    }

    // 未確定文字列がもともと無いなら、クライアントに用は無い。commitComposition は
    // 何も入力していないアプリ切り替えでも飛んでくるので、ここが最も多い経路になる。
    guard hadComposition else {
      return
    }

    // 送る文字列は空だが未確定文字列は画面に出ている。insertText("") では消えない
    // アプリがあるため、空の未確定文字列で明示的に消す。
    client.setMarkedText("")
  }

  /// 未確定のものをすべて確定文字列として取り出し、内部状態を畳む。
  /// クライアントには触れない。送るのは呼び出し側の責任。
  @MainActor
  private func takePendingText() -> String {
    let candidateText = self.takeSelectedCandidate()?.text ?? ""
    let text = candidateText + self.composingText.convertTarget
    self.resetState()
    return text
  }

  /// 選択中の候補を取り出し、確定済みの部分を未確定文字列と変換器の状態から取り除く。
  /// クライアントには触れない。
  @MainActor
  private func takeSelectedCandidate() -> Candidate? {
    guard let candidate = self.candidateList.selected else {
      return nil
    }
    // 確定済みの候補を二重に挿入しないよう、取り出したら候補列は空にする。
    self.candidateList.reset()

    self.composingText.prefixComplete(composingCount: candidate.composingCount)
    self.converter.setCompletedData(candidate)
    self.converter.updateLearningData(candidate)
    return candidate
  }

  /// 未確定文字列を捨てて状態を畳む。
  @MainActor
  private func clear(_ client: Client) {
    self.resetState()
    client.setMarkedText("")
  }

  // クライアントへの呼び出しを伴わない状態リセット。deactivate 中など、
  // クライアントに触れたくない場面ではこちらだけを使う。
  @MainActor
  private func resetState() {
    self.candidateWindow.hide(requestedBy: self)

    self.state = .normal
    self.converter.stopComposition()
    self.composingText.stopComposition()
    self.candidateList.reset()
  }

  // MARK: - クライアントとのやり取り

  private func underlineAttributes() -> [NSAttributedString.Key: Any]? {
    return self.mark(forStyle: kTSMHiliteConvertedText, at: .notFound)
      as? [NSAttributedString.Key: Any]
  }

  private func highlightAttributes() -> [NSAttributedString.Key: Any]? {
    return self.mark(forStyle: kTSMHiliteSelectedConvertedText, at: .notFound)
      as? [NSAttributedString.Key: Any]
  }

  @MainActor
  private func setComposingMarkedText(_ client: Client) {
    client.setMarkedText(
      NSAttributedString(
        string: self.composingText.convertTarget, attributes: self.underlineAttributes()))
  }

  @MainActor
  private func setSelectingMarkedText(_ client: Client) {
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
    client.setMarkedText(text)
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
    // AppKit イベントとして走るため、client が引数で渡ってこない。ここだけは
    // コントローラが保持しているクライアントを使う。失われていれば状態だけ畳む。
    guard let client = Client(self.client()) else {
      self.resetState()
      return
    }
    self.candidateList.select(index)
    self.commitSelectedCandidate(client)
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
