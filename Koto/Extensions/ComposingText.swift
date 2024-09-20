//
//  ComposingText.swift
//  Koto
//
//  Created by koki sato on 2024/09/16.
//

import KanaKanjiConverterModule

private let hankakuToZenkakuMap: [String: String] = [
  // 記号
  "!": "！", "\"": "”", "#": "＃", "$": "＄", "%": "％",
  "&": "＆", "'": "’", "(": "（", ")": "）", "*": "＊",
  "+": "＋", ",": "、", "-": "ー", ".": "。", "/": "・",
  ":": "：", ";": "；", "<": "＜", "=": "＝", ">": "＞",
  "?": "？", "@": "＠", "[": "「", "¥": "￥", "]": "」",
  "^": "＾", "_": "＿", "`": "｀", "{": "『", "|": "｜",
  "}": "』", "~": "〜", "\\": "＼",
  // 数字
  "0": "０", "1": "１", "2": "２", "3": "３", "4": "４",
  "5": "５", "6": "６", "7": "７", "8": "８", "9": "９",
]

extension ComposingText {
  mutating func append(_ text: String, inputStyle: InputStyle) {
    var text = text

    switch inputStyle {
    case .direct:
      self.insertAtCursorPosition(text, inputStyle: .direct)

    case .roman2kana:
      if let zenkaku = hankakuToZenkakuMap[text] {
        text = zenkaku
      }
      if self.shouldInsertN(next: text) {
        self.insertAtCursorPosition("n", inputStyle: .roman2kana)
      }
      self.insertAtCursorPosition(text, inputStyle: .roman2kana)
    }
  }

  func hasSuffix(_ suffix: String) -> Bool {
    return self.convertTarget.hasSuffix(suffix)
  }

  mutating func removeLast() {
    self.deleteBackwardFromCursorPosition(count: 1)
  }

  func toKatakana() -> ComposingText {
    let katakana = self.convertTarget.toKatakana()
    var after = ComposingText()
    after.insertAtCursorPosition(katakana, inputStyle: .direct)
    return after
  }

  func shouldInsertN(next: String? = nil) -> Bool {
    if !self.convertTarget.hasSuffix("n") {
      return false
    }

    guard let last = self.input.last else {
      return false
    }

    if last.inputStyle != .roman2kana {
      return false
    }

    if let next = next, ["n", "a", "i", "u", "e", "o", "y"].contains(next) {
      return false
    }

    return true
  }
}
