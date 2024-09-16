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
  "}": "』", "~": "〜",
  // 数字
  "0": "０", "1": "１", "2": "２", "3": "３", "4": "４",
  "5": "５", "6": "６", "7": "７", "8": "８", "9": "９",
]

extension ComposingText {
  mutating func append(_ text: String) {
    if let zenkaku = hankakuToZenkakuMap[text] {
      self.insertAtCursorPosition(zenkaku, inputStyle: .direct)
    } else {
      self.insertAtCursorPosition(text, inputStyle: .roman2kana)
    }
  }
}
