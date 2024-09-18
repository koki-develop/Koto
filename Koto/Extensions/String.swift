//
//  String.swift
//  Koto
//
//  Created by koki sato on 2024/09/18.
//

extension String {
  func toKatakana() -> String {
    self.applyingTransform(.hiraganaToKatakana, reverse: false) ?? ""
  }
}
