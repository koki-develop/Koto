//
//  KanaKanjiConverter.swift
//  Koto
//
//  Created by koki sato on 2024/09/21.
//

import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

private let kotoDirectoryURL = URL.applicationSupportDirectory
  .appending(path: "Koto", directoryHint: .isDirectory)

// 学習データの置き場。.cachesDirectory は OS にパージされうるため
// Application Support 配下に置く。ディレクトリを用意できない場合のみ
// 従来の .cachesDirectory にフォールバックする。
private let memoryDirectoryURL: URL = {
  let directoryURL = kotoDirectoryURL.appending(path: "memory", directoryHint: .isDirectory)
  do {
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
  } catch {
    NSLog("Koto: failed to create learning data directory: \(error)")
    return .cachesDirectory
  }
  return directoryURL
}()

private func options() -> ConvertRequestOptions {
  return ConvertRequestOptions(
    requireJapanesePrediction: false,
    requireEnglishPrediction: false,
    keyboardLanguage: .ja_JP,
    learningType: .inputAndOutput,
    memoryDirectoryURL: memoryDirectoryURL,
    sharedContainerURL: kotoDirectoryURL,
    textReplacer: .empty,
    specialCandidateProviders: nil,
    zenzaiMode: .off,
    metadata: .init()
  )
}

extension KanaKanjiConverter {
  convenience init() {
    self.init(dicdataStore: .withDefaultDictionary())
  }

  func convert(_ composingText: ComposingText) -> ConversionResult {
    return self.requestCandidates(composingText, options: options())
  }

  func saveLearningData() {
    self.commitUpdateLearningData()
  }

  func resetLearningData() {
    // 一度も変換していないと resetMemory() は memoryURL が nil のまま無音で
    // 何もしないため、捨て変換で設定をシードしてからリセットする。
    // (saveLearningData は保存対象が生じる時点で必ず変換済みのため不要)
    var seed = ComposingText()
    seed.insertAtCursorPosition("あ", inputStyle: .direct)
    _ = self.convert(seed)
    self.stopComposition()
    self.resetMemory()
  }
}
