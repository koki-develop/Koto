//
//  Utils.swift
//  Koto
//
//  Created by koki sato on 2024/09/24.
//

import Foundation

func isPrintable(_ text: String) -> Bool {
  let printable = [
    CharacterSet.alphanumerics,
    CharacterSet.symbols,
    CharacterSet.punctuationCharacters,
  ].reduce(CharacterSet()) { $0.union($1) }
  return !text.unicodeScalars.contains(where: { !printable.contains($0) })
}

/// ASCII 数字 1 文字なら 0〜9 の値を返す。全角数字や他言語の数字は対象外。
func asciiDigit(_ text: String) -> Int? {
  guard text.unicodeScalars.count == 1, let scalar = text.unicodeScalars.first else {
    return nil
  }
  guard ("0" as Unicode.Scalar).value...("9" as Unicode.Scalar).value ~= scalar.value else {
    return nil
  }
  return Int(scalar.value - ("0" as Unicode.Scalar).value)
}
