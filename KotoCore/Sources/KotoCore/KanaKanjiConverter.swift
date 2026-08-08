//
//  KanaKanjiConverter.swift
//  Koto
//
//  Created by koki sato on 2024/09/21.
//

import Foundation
import KanaKanjiConverterModule
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
    Log.lifecycle.error("failed to create learning data directory: \(error, privacy: .public)")
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
}

/// Koto が持つ変換器。
///
/// 変換そのものは `KanaKanjiConverter` に委ね、この型は **学習データをいつ
/// 永続化するか** の方針を受け持つ。
///
/// azooKey の `commitUpdateLearningData()` は、更新の有無に関わらず学習メモリ全体を
/// 読み直してマージし、書き戻す。無視できない長さのメインスレッド I/O になるため、
/// 呼ぶ場所とタイミングを選ぶ必要がある。`KanaKanjiConverter` は `final class` で
/// `Sendable` でもないため、バックグラウンドへ逃がすことはできない。
///
/// 保存のタイミングは 2 つの待ち時間で決める:
///
/// - `saveDelay` — 入力が落ち着くまで待つ。連続する確定を 1 回の保存にまとめる。
/// - `maxSaveDelay` — 待つだけだと確定が途切れない間ずっと保存されないため、
///   最初の未保存更新からの上限で頭を押さえる。以降の更新でこの締切は延ばさない。
@MainActor
final class Converter {
  private let converter = KanaKanjiConverter()
  private let convertOptions: ConvertRequestOptions
  /// 最後の学習更新からこれだけ間が空いたら保存する。
  private let saveDelay: Duration
  /// 最初の未保存更新からこれを過ぎたら、確定が続いていても保存する。
  private let maxSaveDelay: Duration

  /// 保存待ちのタスク。`nil` でないことが「未保存の学習更新がある」印を兼ねる。
  private var pendingSave: Task<Void, Never>?
  /// 最初の未保存更新から `maxSaveDelay` 後の時刻。保存すると `nil` に戻る。
  private var saveDeadline: ContinuousClock.Instant?

  /// - Parameters:
  ///   - convertOptions: 変換オプション。既定はユーザの実データを指すため、
  ///     テストからは必ず捨てて良いディレクトリを向けたものを渡すこと。
  ///   - saveDelay: 最後の学習更新から保存するまでの待ち時間。
  ///   - maxSaveDelay: 最初の未保存更新から保存を先延ばしにできる上限。
  init(
    convertOptions: ConvertRequestOptions = options(),
    saveDelay: Duration = .seconds(5),
    maxSaveDelay: Duration = .seconds(30)
  ) {
    self.convertOptions = convertOptions
    self.saveDelay = saveDelay
    self.maxSaveDelay = maxSaveDelay
  }

  /// 保存を予約しているか。
  ///
  /// 「未保存の学習が残っているか」ではないことに注意。azooKey の
  /// `commitUpdateLearningData()` は `Void` を返し、マージに失敗しても内部で
  /// 握り潰す(失敗時は書き込み前の状態が保たれ、次の保存に持ち越される)ため、
  /// 保存が本当に成功したかはこちらからは分からない。
  var hasUnsavedLearningData: Bool {
    return self.pendingSave != nil
  }

  func convert(_ composingText: ComposingText) -> ConversionResult {
    return self.converter.requestCandidates(composingText, options: self.convertOptions)
  }

  func stopComposition() {
    self.converter.stopComposition()
  }

  func setCompletedData(_ candidate: Candidate) {
    self.converter.setCompletedData(candidate)
  }

  /// 確定した候補を学習に反映し、必要なら保存を予約する。
  func updateLearningData(_ candidate: Candidate) {
    self.converter.updateLearningData(candidate)

    // 学習対象外の候補は azooKey 側が捨てる(`DicdataStoreState.updateLearningData` が
    // `isLearningTarget` を見て早期 return する)。丸数字などの注入候補や azooKey 既定の
    // 特殊変換がこれにあたる。ここで予約すると、何も変わっていない学習メモリを
    // まるごと書き直すだけになる。
    guard candidate.isLearningTarget else {
      return
    }
    self.scheduleSave()
  }

  /// 保存待ちの学習データがあれば、予約を待たずに書き出す。プロセス終了時に呼ぶ。
  func flushLearningData() {
    guard let pendingSave = self.pendingSave else {
      return
    }
    pendingSave.cancel()
    self.save()
  }

  func resetLearningData() {
    self.pendingSave?.cancel()
    self.pendingSave = nil
    self.saveDeadline = nil

    // 一度も変換していないと resetMemory() は memoryURL が nil のまま無音で
    // 何もしないため、捨て変換で設定をシードしてからリセットする。
    var seed = ComposingText()
    seed.insertAtCursorPosition("あ", inputStyle: .direct)
    _ = self.convert(seed)
    self.converter.stopComposition()
    self.converter.resetMemory()
  }

  private func scheduleSave() {
    let now = ContinuousClock.now
    // 締切は最初の未保存更新のときに決めて、以降の更新では延ばさない。
    let deadline = self.saveDeadline ?? now.advanced(by: self.maxSaveDelay)
    self.saveDeadline = deadline
    let wakeUp = min(now.advanced(by: self.saveDelay), deadline)

    self.pendingSave?.cancel()
    self.pendingSave = Task { [weak self] in
      try? await Task.sleep(until: wakeUp, clock: .continuous)
      guard !Task.isCancelled else {
        return
      }
      self?.save()
    }
  }

  private func save() {
    self.pendingSave = nil
    self.saveDeadline = nil
    self.converter.commitUpdateLearningData()
  }
}
