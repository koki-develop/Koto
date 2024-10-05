//
//  InputController.swift
//  Koto
//
//  Created by koki sato on 2024/09/15.
//

import InputMethodKit
import KanaKanjiConverterModuleWithDefaultDictionary

@objc(KotoInputController)
class KotoInputController: IMKInputController {
  let candidates: IMKCandidates
  let appMenu = NSMenu()

  @MainActor
  let converter = KanaKanjiConverter()

  var state: InputState = .normal
  var mode: InputMode = .ja
  var composingText: ComposingText = ComposingText()
  var currentCandidates: [Candidate] = []
  var selectingCandidate: Candidate?

  override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
    NSLog("KotoInputController init")

    self.appMenu.addItem(
      NSMenuItem(
        title: "学習データをリセット", action: #selector(self.resetLearningData(_:)), keyEquivalent: ""
      ))

    self.candidates = IMKCandidates(
      server: server, panelType: kIMKSingleColumnScrollingCandidatePanel)

    super.init(server: server, delegate: delegate, client: inputClient)
  }

  override func menu() -> NSMenu! {
    return self.appMenu
  }

  override func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
    NSLog("KotoInputController setValue (tag: \(tag), value: \(String(describing: value))")

    if let value = value as? NSString {
      switch value {
      case "com.apple.inputmethod.Japanese":
        self.mode = .ja
      case "com.apple.inputmethod.Roman":
        self.mode = .en
      default:
        break
      }
    }

    super.setValue(value, forTag: tag, client: sender)
  }

  @MainActor
  override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
    NSLog("KotoInputController handle (event: \(String(describing: event)))")

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
      if self.mode == .en {
        self.insertText(text)
        return true
      }
      self.state = .composing
      fallthrough

    case (.input(let text), .composing):
      switch self.mode {
      case .ja:
        self.composingText.append(text, inputStyle: .roman2kana)
      case .en:
        self.composingText.append(text, inputStyle: .direct)
      }
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
      switch self.mode {
      case .ja:
        self.insertText("　")
      case .en:
        self.insertText(" ")
      }
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
  override func candidates(_ sender: Any!) -> [Any]! {
    let results = self.converter.convert(self.composingText.prefixToCursorPosition())
    self.currentCandidates = results.mainResults
    return self.currentCandidates.map { $0.text }
  }

  @MainActor
  override func candidateSelected(_ candidateString: NSAttributedString!) {
    self.insertSelectingCandidate()

    if self.composingText.isEmpty {
      self.clear()
    } else {
      self.candidates.update()
    }
  }

  override func candidateSelectionChanged(_ candidateString: NSAttributedString!) {
    guard let candidate = currentCandidates.first(where: { $0.text == candidateString.string })
    else {
      return
    }
    self.selectingCandidate = candidate
    self.setSelectingMarkedText()
  }

  @MainActor
  override func deactivateServer(_ sender: Any!) {
    NSLog("KotoInputController deactivateServer")

    self.insertSelectingCandidate()
    self.insertComposingText()
    self.clear()

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
    afterComposingText.prefixComplete(correspondingCount: candidate.correspondingCount)

    let text = NSMutableAttributedString(string: "")
    text.append(NSAttributedString(string: candidate.text, attributes: self.highlightAttributes()))
    text.append(
      NSAttributedString(
        string: afterComposingText.convertTarget, attributes: self.underlineAttributes()))
    self.setMarkedText(text)
  }

  private func insertText(_ text: String) {
    self.client().insertText(text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
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

    self.composingText.prefixComplete(correspondingCount: candidate.correspondingCount)
    self.converter.setCompletedData(candidate)
    self.converter.updateLearningData(candidate)
  }

  @MainActor
  private func clear() {
    self.setMarkedText("")
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

    switch self.mode {
    case .ja:
      if event.modifierFlags.contains(.option) {
        return .input("\\")
      } else {
        return .input("¥")
      }
    case .en:
      if event.modifierFlags.contains(.option) {
        return .input("¥")
      } else {
        return .input("\\")
      }
    }
  }
}
