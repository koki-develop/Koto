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

  override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
    self.candidates = IMKCandidates(
      server: server, panelType: kIMKSingleColumnScrollingCandidatePanel)
    super.init(server: server, delegate: delegate, client: inputClient)
  }

  override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
    guard let eventType = getEventType(event) else {
      return false
    }

    switch (eventType, self.state) {
    case (.input(let text), .normal):
      self.state = .composing
      fallthrough
    case (.input(let text), .composing):
      self.composingText.append(text)
      self.setMarkedText(self.composingText.convertTarget)
      self.showCandidates()
      return true

    case (.backspace, .composing):
      self.composingText.deleteBackwardFromCursorPosition(count: 1)
      self.setMarkedText(self.composingText.convertTarget)
      if self.composingText.isEmpty {
        self.state = .normal
      }
      return true

    case (.enter, .composing):
      self.insertText(self.composingText.convertTarget)
      self.setMarkedText("")
      self.hideCandidates()
      self.state = .normal
      self.composingText = ComposingText()
      return true

    default:
      return false
    }
  }

  @MainActor override func candidates(_ sender: Any!) -> [Any]! {
    let results = self.converter.requestCandidates(
      self.composingText,
      options: .withDefaultDictionary(
        requireJapanesePrediction: true,
        requireEnglishPrediction: false,
        keyboardLanguage:  .ja_JP,
        learningType: .nothing,
        memoryDirectoryURL: .documentsDirectory,
        sharedContainerURL: .documentsDirectory,
        metadata: .init(appVersionString: "dev")
      )
    )
    return results.mainResults.map { $0.text }
  }

  private func showCandidates() {
    self.candidates.update()
    self.candidates.show()
  }

  private func hideCandidates() {
    self.candidates.hide()
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
}
