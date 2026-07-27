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

    default:
      // Koto は .direct / .roman2kana のみ使用する。カスタムテーブル等の
      // 他スタイルは渡された style のまま挿入する。
      self.insertAtCursorPosition(text, inputStyle: inputStyle)
    }
  }

  func hasSuffix(_ suffix: String) -> Bool {
    return self.convertTarget.hasSuffix(suffix)
  }

  mutating func removeLast() {
    self.deleteBackwardFromCursorPosition(count: 1)
  }

  /// 変換対象のカーソルを末尾へ戻す。
  ///
  /// 変換範囲の指定(shift + 左右)を伴う `.selecting` から `.composing` へ戻るときに使う。
  /// `.composing` の未確定テキストは全体が表示されるため、カーソルを途中に残したままだと
  /// 「見えている文字列より短い範囲しか変換されない」不可視の状態になる。
  mutating func moveCursorToEnd() {
    _ = self.moveCursorFromCursorPosition(
      count: self.convertTarget.count - self.convertTargetCursorPosition)
  }

  func toKatakana() -> ComposingText {
    var katakana = ComposingText()
    katakana.insertAtCursorPosition(self.convertTarget.toKatakana(), inputStyle: .direct)
    return katakana
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
