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
  @MainActor let converter = KanaKanjiConverter()
  let candidates: IMKCandidates

  var state: InputState = .normal
  var mode: InputMode = .ja
  var composingText: ComposingText = ComposingText()
  var candidateTexts: [Candidate] = []
  var selectedCandidateText: Candidate?

  override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
    self.candidates = IMKCandidates(
      server: server, panelType: kIMKSingleColumnScrollingCandidatePanel)
    super.init(server: server, delegate: delegate, client: inputClient)
  }

  override func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
    guard let value = value as? NSString else {
      return
    }

    switch value {
    case "com.apple.inputmethod.Japanese":
      self.mode = .ja
    case "com.apple.inputmethod.Roman":
      self.mode = .en
    default:
      break
    }
  }

  override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
    guard let eventType = getEventType(event, mode: self.mode) else {
      return false
    }

    switch (eventType, self.state) {
    case (.input(let text), .selecting):
      self.insertSelectedCandidate()
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
      self.insertSelectedCandidate()
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
      if self.composingText.shouldInsertN() {
        self.composingText.append("n", inputStyle: .roman2kana)
      }
      self.candidates.update()
      self.candidates.show()
      self.state = .selecting
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
      self.setComposingMarkedText()
      self.state = .composing
      self.candidates.hide()
      return true

    case (.ctrlK, .composing):
      self.composingText = self.composingText.toKatakana()
      self.setComposingMarkedText()
      return true

    case (.ctrlK, .selecting):
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
    let results = self.converter.requestCandidates(
      self.composingText.prefixToCursorPosition(),
      options: .withDefaultDictionary(
        requireJapanesePrediction: false,
        requireEnglishPrediction: false,
        keyboardLanguage: .ja_JP,
        learningType: .nothing,
        memoryDirectoryURL: .documentsDirectory,
        sharedContainerURL: .documentsDirectory,
        zenzaiMode: .off,
        metadata: .init()
      )
    )
    self.candidateTexts = results.mainResults
    return self.candidateTexts.map { $0.text }
  }

  override func candidateSelected(_ candidateString: NSAttributedString!) {
    self.insertSelectedCandidate()

    if self.composingText.isEmpty {
      self.clear()
    } else {
      self.candidates.update()
    }
  }

  override func candidateSelectionChanged(_ candidateString: NSAttributedString!) {
    guard let candidate = candidateTexts.first(where: { $0.text == candidateString.string }) else {
      return
    }
    self.selectedCandidateText = candidate
    self.setSelectingMarkedText()
  }

  override func deactivateServer(_ sender: Any!) {
    self.insertSelectedCandidate()
    self.insertComposingText()
    self.clear()
  }

  private func setMarkedText(_ text: Any!) {
    guard let client = self.client() else {
      return
    }
    client.setMarkedText(text, selectionRange: .notFound, replacementRange: .notFound)
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
    guard let candidate = self.selectedCandidateText else {
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
    guard let client = self.client() else {
      return
    }
    client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
  }

  private func insertComposingText() {
    if self.composingText.isEmpty {
      return
    }
    self.insertText(self.composingText.convertTarget)
  }

  private func insertSelectedCandidate() {
    guard let candidate = self.selectedCandidateText else {
      return
    }
    self.insertText(candidate.text)
    self.composingText.prefixComplete(correspondingCount: candidate.correspondingCount)
  }

  private func clear() {
    self.setMarkedText("")
    self.candidates.hide()

    self.state = .normal
    self.composingText.stopComposition()
    self.candidateTexts = []
    self.selectedCandidateText = nil
  }
}
