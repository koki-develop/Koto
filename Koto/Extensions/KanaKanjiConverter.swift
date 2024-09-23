//
//  KanaKanjiConverter.swift
//  Koto
//
//  Created by koki sato on 2024/09/21.
//

import KanaKanjiConverterModuleWithDefaultDictionary

private func options(reset: Bool = false) -> ConvertRequestOptions {
  return .withDefaultDictionary(
    requireJapanesePrediction: false,
    requireEnglishPrediction: false,
    keyboardLanguage: .ja_JP,
    learningType: .inputAndOutput,
    shouldResetMemory: reset,
    memoryDirectoryURL: .cachesDirectory,
    sharedContainerURL: .cachesDirectory,
    zenzaiMode: .off,
    metadata: .init()
  )
}

extension KanaKanjiConverter {
  convenience init() {
    let dicdataStore = DicdataStore(convertRequestOptions: options())
    self.init(dicdataStore: dicdataStore)
  }

  func convert(_ composingText: ComposingText) -> ConversionResult {
    return self.requestCandidates(composingText, options: options())
  }

  func saveLearningData() {
    self.sendToDicdataStore(.closeKeyboard)
  }

  func resetLearningData() {
    self.sendToDicdataStore(.setRequestOptions(options(reset: true)))
  }
}
