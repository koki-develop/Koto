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
// キャッシュ配下にフォールバックする。
//
// フォールバック先も必ず Koto 専用のディレクトリにすること。ここは
// `LearningMemory` が中身を消しにいく先でもあるので、共用の場所を指すと
// 他人のファイルを消す道が開く。作成に失敗しても Koto 配下を返す
// (書けなければ学習が働かないだけで、外には手が出ない)。
private let defaultMemoryDirectoryURL: URL = {
  let directoryURL = kotoDirectoryURL.appending(path: "memory", directoryHint: .isDirectory)
  do {
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
  } catch {
    Log.lifecycle.error("failed to create learning data directory: \(error, privacy: .public)")
  }

  let fallbackURL = URL.cachesDirectory
    .appending(path: "Koto", directoryHint: .isDirectory)
    .appending(path: "memory", directoryHint: .isDirectory)
  do {
    try FileManager.default.createDirectory(at: fallbackURL, withIntermediateDirectories: true)
  } catch {
    // ここまで来ると学習は一切残らない。azooKey 側の失敗はリリースビルドでは
    // 消える `debug()` にしか出ないので、痕跡はここでしか残せない。
    Log.lifecycle.error(
      "failed to create the fallback learning data directory; learning will not persist: \(error, privacy: .public)"
    )
  }
  return fallbackURL
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

  /// 保存待ちのタスク。抱えていることが「未保存の学習更新がある」印を兼ねる。
  private var pendingSave = ExclusiveTask()
  /// 最初の未保存更新から `maxSaveDelay` 後の時刻。保存すると `nil` に戻る。
  /// 読めるようにしてあるのはテストのため。書き換えるのはこのファイルだけ。
  private(set) var saveDeadline: ContinuousClock.Instant?

  /// 一度でも変換したか。復元マージの後始末を一度だけ行うために見る。
  private var hasConverted = false

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

    // 保存だけがマージの入口ではない。前回の書き込みが中断されていると、azooKey は
    // プロセス最初の変換で復元のマージを暗黙に走らせる。そちらは `save()` を通らない
    // ので、変換を始めさせる前にここでも落としておく。
    LearningMemory.removeStaleShards(in: convertOptions.memoryDirectoryURL)
  }

  /// 保存を予約しているか。
  ///
  /// 「未保存の学習が残っているか」ではないことに注意。azooKey の
  /// `commitUpdateLearningData()` は `Void` を返し、マージに失敗しても内部で
  /// 握り潰す(失敗時は書き込み前の状態が保たれ、次の保存に持ち越される)ため、
  /// 保存が本当に成功したかはこちらからは分からない。
  var hasUnsavedLearningData: Bool {
    return self.pendingSave.isScheduled
  }

  func convert(_ composingText: ComposingText) -> ConversionResult {
    let result = self.converter.requestCandidates(composingText, options: self.convertOptions)

    // 中断からの復元マージは、このプロセス最初の変換の中で azooKey が勝手に走らせる。
    // それも世代を書き直すので、自前の取り残しを置いていく。保存経路と同じように、
    // 走り終わったところで拾っておく。判定は一度きりで済む(`updateConfig` は
    // 設定が変わったときだけ走り、Koto は同じオプションを渡し続けるため)。
    if !self.hasConverted {
      self.hasConverted = true
      LearningMemory.removeStaleShards(in: self.convertOptions.memoryDirectoryURL)
    }

    return result
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
    guard self.pendingSave.isScheduled else {
      return
    }
    self.pendingSave.cancel()
    self.save()
  }

  func resetLearningData() {
    self.pendingSave.cancel()
    self.saveDeadline = nil

    // 一度も変換していないと resetMemory() は memoryURL が nil のまま無音で
    // 何もしないため、捨て変換で設定をシードしてからリセットする。
    var seed = ComposingText()
    seed.insertAtCursorPosition("あ", inputStyle: .direct)
    _ = self.convert(seed)
    self.converter.stopComposition()
    self.converter.resetMemory()
  }

  /// 次に保存を試みる時刻と、その回の締切を決める。
  ///
  /// 2 つの待ち時間の掛け合わせは実時間に依存しない計算なので、待たずに検査できるよう
  /// 切り出してある。実時間を絡めたテストは、並列に走る他のテストがメインスレッドを
  /// 握っているだけで揺れる。揺れを吸収しようと上限を伸ばすと、今度は守りたい回帰まで
  /// 通してしまう。方針そのものは、その揺れに関係なく固定できる。
  ///
  /// - Parameters:
  ///   - now: いまの時刻。
  ///   - deadline: すでに決まっている締切。最初の未保存更新なら `nil`。
  ///   - saveDelay: 最後の学習更新から保存するまでの待ち時間。
  ///   - maxSaveDelay: 最初の未保存更新から保存を先延ばしにできる上限。
  nonisolated static func saveSchedule(
    now: ContinuousClock.Instant,
    deadline: ContinuousClock.Instant?,
    saveDelay: Duration,
    maxSaveDelay: Duration
  ) -> (wakeUp: ContinuousClock.Instant, deadline: ContinuousClock.Instant) {
    // 締切は最初の未保存更新のときに決めて、以降の更新では延ばさない。ここで `now` から
    // 取り直すと、確定が途切れないかぎり保存が来なくなり、上限の意味が無くなる。
    let deadline = deadline ?? now.advanced(by: maxSaveDelay)
    return (min(now.advanced(by: saveDelay), deadline), deadline)
  }

  private func scheduleSave() {
    let schedule = Self.saveSchedule(
      now: ContinuousClock.now,
      deadline: self.saveDeadline,
      saveDelay: self.saveDelay,
      maxSaveDelay: self.maxSaveDelay
    )
    self.saveDeadline = schedule.deadline

    self.pendingSave.replace(
      with: Task { [weak self] in
        try? await Task.sleep(until: schedule.wakeUp, clock: .continuous)
        guard !Task.isCancelled else {
          return
        }
        self?.save()
      })
  }

  private func save() {
    self.pendingSave.clear()
    self.saveDeadline = nil

    // azooKey は世代が縮んだときに余ったシャードを消さない。取り残しが揃うと
    // 次のマージがそれを読みにいってプロセスごと落ちる。理由は `LearningMemory` に書いてある。
    //
    // マージの前後の両方で落とす。前は今から走るマージを守るため、後はこのマージ自身が
    // 作った取り残しを持ち越さないため。「置き場は落ち着いているときは常に整合している」
    // という形にしておけば、マージの入口が増えたときに穴が開かない
    // (実際、保存だけだと復元のマージを取りこぼしていた)。
    let memoryDirectoryURL = self.convertOptions.memoryDirectoryURL
    LearningMemory.removeStaleShards(in: memoryDirectoryURL)
    self.converter.commitUpdateLearningData()
    LearningMemory.removeStaleShards(in: memoryDirectoryURL)
  }
}
