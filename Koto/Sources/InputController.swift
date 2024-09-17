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
  var composingText: ComposingText = ComposingText()
  var candidateTexts: [Candidate] = []
  var selectedCandidateText: Candidate?

  override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
    self.candidates = IMKCandidates(
      server: server, panelType: kIMKSingleColumnScrollingCandidatePanel)
    super.init(server: server, delegate: delegate, client: inputClient)
  }

  @MainActor
  override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
    guard let eventType = getEventType(event) else {
      return false
    }

    switch (eventType, self.state) {
    case (.input(let text), .selecting):
      if let candidate = self.selectedCandidateText {
        self.insertText(candidate.text)
        self.composingText.prefixComplete(correspondingCount: candidate.correspondingCount)
      }
      if !self.composingText.isEmpty {
        self.insertText(self.composingText.convertTarget)
      }
      self.clear()
      fallthrough
    case (.input(let text), .normal):
      self.state = .composing
      fallthrough
    case (.input(let text), .composing):
      self.composingText.append(text)
      self.updateComposingMarkedText()
      return true

    case (.backspace, .normal):
      // do nothing
      return false
    case (.backspace, .composing):
      self.composingText.deleteBackwardFromCursorPosition(count: 1)
      if self.composingText.isEmpty {
        self.clear()
      } else {
        self.updateComposingMarkedText()
      }
      return true
    case (.backspace, .selecting):
      // TODO: implement
      return true

    case (.space, .normal):
      self.insertText("　")
      return true
    case (.space, .composing):
      self.state = .selecting
      self.candidates.update()
      self.candidates.show()
      return true
    case (.space, .selecting):
      self.candidates.moveDown(sender)
      return true

    case (.enter, .normal):
      // do nothing
      return false
    case (.enter, .composing):
      self.insertText(self.composingText.convertTarget)
      self.clear()
      return true
    case (.enter, .selecting):
      self.candidates.interpretKeyEvents([event])
      return true
    }
  }

  @MainActor
  override func candidates(_ sender: Any!) -> [Any]! {
    let results = self.converter.requestCandidates(
      self.composingText,
      options: .withDefaultDictionary(
        requireJapanesePrediction: true,
        requireEnglishPrediction: false,
        keyboardLanguage: .ja_JP,
        learningType: .nothing,
        memoryDirectoryURL: .documentsDirectory,
        sharedContainerURL: .documentsDirectory,
        metadata: .init(appVersionString: "dev")
      )
    )
    self.candidateTexts = results.mainResults
    return self.candidateTexts.map { $0.text }
  }

  override func candidateSelected(_ candidateString: NSAttributedString!) {
    guard let candidate = candidateTexts.first(where: { $0.text == candidateString.string }) else {
      return
    }

    self.insertText(candidate.text)
    self.composingText.prefixComplete(correspondingCount: candidate.correspondingCount)

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
    self.updateSelectingMarkedText()
  }

  override func deactivateServer(_ sender: Any!) {
    self.clear()
  }

  private func updateComposingMarkedText() {
    let underline =
        self.mark(
            forStyle: kTSMHiliteConvertedText,
            at: .notFound
        ) as? [NSAttributedString.Key: Any]
    self.setMarkedText(NSAttributedString(string: self.composingText.convertTarget))
  }

  private func updateSelectingMarkedText() {
    guard let candidate = self.selectedCandidateText else {
      return
    }

    var afterComposingText = self.composingText
    afterComposingText.prefixComplete(correspondingCount: candidate.correspondingCount)

    let highlight =
    self.mark(forStyle: kTSMHiliteSelectedConvertedText, at: .notFound)
        as? [NSAttributedString.Key: Any]
    let underline =
        self.mark(
            forStyle: kTSMHiliteConvertedText,
            at: .notFound
        ) as? [NSAttributedString.Key: Any]

    let text = NSMutableAttributedString(string: "")
    text.append(NSAttributedString(string: candidate.text, attributes: highlight))
    text.append(NSAttributedString(string: afterComposingText.convertTarget, attributes: underline))
    self.setMarkedText(text)
  }

  private func insertText(_ text: String) {
    guard let client = self.client() else {
      return
    }
    client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
  }

  private func setMarkedText(_ text: Any!) {
    guard let client = self.client() else {
      return
    }
    client.setMarkedText(text, selectionRange: .notFound, replacementRange: .notFound)
  }

  private func clear() {
    self.setMarkedText("")
    self.candidates.hide()

    self.state = .normal
    self.composingText = ComposingText()
    self.candidateTexts = []
    self.selectedCandidateText = nil
  }
}
