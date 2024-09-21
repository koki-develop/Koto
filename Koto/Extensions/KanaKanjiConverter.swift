//
//  KanaKanjiConverter.swift
//  Koto
//
//  Created by koki sato on 2024/09/21.
//

import KanaKanjiConverterModuleWithDefaultDictionary

extension KanaKanjiConverter {
  func saveLearningData() {
    self.sendToDicdataStore(.closeKeyboard)
  }
}
