//
//  InputController.swift
//  Koto
//
//  Created by koki sato on 2024/09/15.
//

import InputMethodKit
import KanaKanjiConverterModule

@objc(KotoInputController)
class KotoInputController: IMKInputController {
  var state: InputState = .normal
  var composingText: ComposingText = ComposingText()

  override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
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
      self.state = .normal
      self.composingText = ComposingText()
      return true

    default:
      return false
    }
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
