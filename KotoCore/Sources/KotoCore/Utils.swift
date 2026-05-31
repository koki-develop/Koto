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
