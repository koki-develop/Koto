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
      // TODO: implement
      return true
    case (.input(let text), .normal):
      self.state = .composing
      fallthrough
    case (.input(let text), .composing):
      self.composingText.append(text)
      self.setMarkedText(self.composingText.convertTarget)
      return true

    case (.backspace, .normal):
      // do nothing
      return false
    case (.backspace, .composing):
      self.composingText.deleteBackwardFromCursorPosition(count: 1)
      if self.composingText.isEmpty {
        self.clear()
      } else {
        self.setMarkedText(self.composingText.convertTarget)
      }
      return true
    case (.backspace, .selecting):
      // TODO: implement
      return true

    case (.space, .normal):
      self.insertText("　")
      return true
    case (.space, .composing):
      self.updateCandidates()
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

  override func candidates(_ sender: Any!) -> [Any]! {
    return self.candidateTexts.map { $0.text }
  }

  override func deactivateServer(_ sender: Any!) {
    self.clear()
  }

  @MainActor
  private func updateCandidates() {
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
    self.candidates.update()
  }

  private func insertText(_ text: String) {
    guard let client = self.client() else {
      return
    }
    client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
  }

  private func setMarkedText(_ text: String) {
    guard let client = self.client() else {
      return
    }
    let range = NSRange(location: NSNotFound, length: NSNotFound)
    client.setMarkedText(text, selectionRange: range, replacementRange: range)
  }

  private func clear() {
    self.setMarkedText("")
    self.candidates.hide()
    self.state = .normal
    self.composingText = ComposingText()
  }
}
