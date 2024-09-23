//
//  KanaKanjiConverter.swift
//  Koto
//
//  Created by koki sato on 2024/09/21.
//

import KanaKanjiConverterModuleWithDefaultDictionary

private var convertOptions: ConvertRequestOptions {
  .withDefaultDictionary(
    requireJapanesePrediction: false,
    requireEnglishPrediction: false,
    keyboardLanguage: .ja_JP,
    learningType: .inputAndOutput,
    memoryDirectoryURL: .cachesDirectory,
    sharedContainerURL: .cachesDirectory,
    zenzaiMode: .off,
    metadata: .init()
  )
}

extension KanaKanjiConverter {
  convenience init() {
    let dicdataStore = DicdataStore(convertRequestOptions: convertOptions)
    self.init(dicdataStore: dicdataStore)
  }

  func convert(_ composingText: ComposingText) -> ConversionResult {
    return self.requestCandidates(composingText, options: convertOptions)
  }

  func saveLearningData() {
    self.sendToDicdataStore(.closeKeyboard)
  }
}
