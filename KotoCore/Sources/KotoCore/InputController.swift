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
  // IMKCandidates と KanaKanjiConverter はコントローラに持たせず全体で共有する。
  // インスタンスごとに生成すると、破棄済み IMKCandidates への参照を IMK 内部が
  // 触って SIGSEGV する(macOS 26 の _IMKServerLegacy)ほか、辞書の重複ロードと
  // 同一ディレクトリへの学習データ多重書き込みが起きる。
  static var sharedCandidates: IMKCandidates!

  @MainActor
  static let sharedConverter = KanaKanjiConverter()

  var candidates: IMKCandidates { Self.sharedCandidates }

  @MainActor
  var converter: KanaKanjiConverter { Self.sharedConverter }

  let appMenu = NSMenu()

  var state: InputState = .normal
  var composingText: ComposingText = ComposingText()
  var currentCandidates: [Candidate] = []
  var selectingCandidate: Candidate?

  public override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
    NSLog("KotoInputController init")

    self.appMenu.addItem(
      NSMenuItem(
        title: "学習データをリセット", action: #selector(self.resetLearningData(_:)), keyEquivalent: ""
      ))

    if Self.sharedCandidates == nil {
      Self.sharedCandidates = IMKCandidates(
        server: server, panelType: kIMKSingleColumnScrollingCandidatePanel)
    }

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

    switch (eventType, self.state) {
    case (.input(let text), .selecting):
      self.insertSelectingCandidate()
      self.insertComposingText()
      self.clear()
      fallthrough

    case (.input(let text), .normal):
      self.state = .composing
      fallthrough

    case (.input(let text), .composing):
      self.composingText.append(text, inputStyle: .roman2kana)
      self.setComposingMarkedText()
      return true

    case (.backspace, .composing):
      self.composingText.removeLast()
      if self.composingText.isEmpty {
        self.clear()
      } else {
        self.setComposingMarkedText()
      }
      return true

    case (.backspace, .selecting):
      self.insertSelectingCandidate()
      self.insertComposingText()
      self.clear()
      return false

    case (.space, .normal):
      self.insertText("　")
      return true

    case (.space, .composing), (.down, .composing):
      self.state = .selecting
      if self.composingText.shouldInsertN() {
        self.composingText.append("n", inputStyle: .roman2kana)
      }
      self.candidates.update()
      self.candidates.show()
      return true

    case (.space, .selecting):
      self.candidates.moveDown(sender)
      return true

    case (.enter, .composing):
      self.insertComposingText()
      self.clear()
      return true

    case (.enter, .selecting):
      self.candidates.interpretKeyEvents([event])
      return true

    case (.down, .selecting):
      self.candidates.moveDown(sender)
      return true

    case (.up, .selecting):
      self.candidates.moveUp(sender)
      return true

    case (.esc, .composing):
      self.clear()
      return true

    case (.esc, .selecting):
      self.state = .composing
      self.setComposingMarkedText()
      self.candidates.hide()
      return true

    case (.ctrlK, .composing):
      self.composingText = self.composingText.toKatakana()
      self.setComposingMarkedText()
      return true

    case (.ctrlK, .selecting):
      self.state = .composing
      self.candidates.hide()
      self.composingText = self.composingText.toKatakana()
      self.setComposingMarkedText()
      return true

    case (.shiftLeft, .selecting):
      if self.composingText.convertTargetCursorPosition > 1 {
        _ = self.composingText.moveCursorFromCursorPosition(count: -1)
        self.candidates.update()
      }
      return true

    case (.shiftRight, .selecting):
      if !self.composingText.isAtEndIndex {
        _ = self.composingText.moveCursorFromCursorPosition(count: 1)
        self.candidates.update()
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

  @MainActor
  public override func candidates(_ sender: Any!) -> [Any]! {
    let results = self.converter.convert(self.composingText.prefixToCursorPosition())
    self.currentCandidates = results.mainResults
    return self.currentCandidates.map { $0.text }
  }

  @MainActor
  public override func candidateSelected(_ candidateString: NSAttributedString!) {
    self.insertSelectingCandidate()

    if self.composingText.isEmpty {
      self.clear()
    } else {
      self.candidates.update()
    }
  }

  public override func candidateSelectionChanged(_ candidateString: NSAttributedString!) {
    guard let candidate = currentCandidates.first(where: { $0.text == candidateString.string })
    else {
      return
    }
    self.selectingCandidate = candidate
    self.setSelectingMarkedText()
  }

  // フォーカス喪失やクリックで OS が未確定テキストの確定を要求したときに呼ばれる。
  // super.commitComposition は呼ばない(切り替え時にハングする既知問題がある)。
  @MainActor
  public override func commitComposition(_ sender: Any!) {
    self.insertSelectingCandidate()
    self.insertComposingText()
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

  private func setSelectingMarkedText() {
    guard let candidate = self.selectingCandidate else {
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

  @MainActor
  private func insertSelectingCandidate() {
    guard let candidate = self.selectingCandidate else {
      return
    }
    self.insertText(candidate.text)

    self.composingText.prefixComplete(composingCount: candidate.composingCount)
    self.converter.setCompletedData(candidate)
    self.converter.updateLearningData(candidate)
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
    self.candidates.hide()

    self.state = .normal
    self.converter.stopComposition()
    self.composingText.stopComposition()
    self.currentCandidates = []
    self.selectingCandidate = nil
  }

  @objc @MainActor
  func resetLearningData(_ sender: Any) {
    self.converter.resetLearningData()
  }

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

    if let text = event.characters, isPrintable(text) {
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
