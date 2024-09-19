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
  mutating func append(_ text: String) {
    if let zenkaku = hankakuToZenkakuMap[text] {
      self.insertAtCursorPosition(zenkaku, inputStyle: .direct)
      return
    }

    if self.shouldInsertN(text) {
      self.insertAtCursorPosition("n", inputStyle: .roman2kana)
    }

    self.insertAtCursorPosition(text, inputStyle: .roman2kana)
  }

  func toKatakana() -> ComposingText {
    let katakana = self.convertTarget.toKatakana()
    var after = ComposingText()
    after.insertAtCursorPosition(katakana, inputStyle: .direct)
    return after
  }

  private func shouldInsertN(_ next: String) -> Bool {
    guard let last = self.input.last else {
      return false
    }

    if last.character != "n" {
      return false
    }

    if last.inputStyle == .roman2kana {
      return false
    }

    if ["n", "a", "i", "u", "e", "o", "y"].contains(next) {
      return false
    }

    return true
  }
}
