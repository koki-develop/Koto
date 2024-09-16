//
//  EventType.swift
//  Koto
//
//  Created by koki sato on 2024/09/16.
//

import AppKit

enum EventType {
  case input(_ text: String)
}

func getEventType(_ event: NSEvent) -> EventType? {
  if let text = event.characters, isPrintable(text) {
    return .input(text)
  }

  return nil
}

private func isPrintable(_ text: String) -> Bool {
  let printable = [
    CharacterSet.alphanumerics,
    CharacterSet.symbols,
    CharacterSet.punctuationCharacters,
  ].reduce(CharacterSet()) { $0.union($1) }
  return !text.unicodeScalars.contains(where: { !printable.contains($0) })
}
