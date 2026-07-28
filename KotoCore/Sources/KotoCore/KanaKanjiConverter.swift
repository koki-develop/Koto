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
private let defaultMemoryDirectoryURL: URL = {
  let directoryURL = kotoDirectoryURL.appending(path: "memory", directoryHint: .isDirectory)
  do {
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
  } catch {
    NSLog("Koto: failed to create learning data directory: \(error)")
    return .cachesDirectory
  }
  return directoryURL
}()

// azooKey 既定の特殊変換(暦・メールアドレス・Unicode など)は残したまま、
// Koto 独自のものを足す。nil を渡すと既定のものだけが使われる。
private let specialCandidateProviders: [any SpecialCandidateProvider] =
  KanaKanjiConverter.defaultSpecialCandidateProviders + [NumberFormsSpecialCandidateProvider()]

/// 変換オプション。
///
/// 置き場の 2 つは既定でユーザの実データを指す。変換は学習データを読み書きし、
/// ユーザ辞書も読むため、テストからは必ず捨てて良いディレクトリを渡すこと。
func options(
  memoryDirectoryURL: URL = defaultMemoryDirectoryURL,
  sharedContainerURL: URL = kotoDirectoryURL
) -> ConvertRequestOptions {
  return ConvertRequestOptions(
    requireJapanesePrediction: false,
    requireEnglishPrediction: false,
    keyboardLanguage: .ja_JP,
    learningType: .inputAndOutput,
    memoryDirectoryURL: memoryDirectoryURL,
    sharedContainerURL: sharedContainerURL,
    textReplacer: .empty,
    specialCandidateProviders: specialCandidateProviders,
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
