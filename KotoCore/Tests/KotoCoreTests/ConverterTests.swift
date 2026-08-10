import Foundation
import KanaKanjiConverterModule
import Testing

@testable import KotoCore

/// 学習データをいつ永続化するかについての回帰テスト。
///
/// 保存はメインスレッドを塞ぐので、走らせすぎるとフォーカス遷移が止まり、
/// 遅らせすぎると強制終了で学習が失われる。「更新があったときだけ」
/// 「入力が落ち着いてから」「ただし上限つきで」保存することを固定する。
///
/// タイミングの**方針**は `Converter.saveSchedule` を直に呼んで固定する。実時間を絡めると、
/// 並列に走る他のテストがメインスレッドを握っているだけで結果が揺れ、揺れを吸収するために
/// 待ち時間を伸ばすと、今度は守りたい回帰まで通してしまう。実際に発火することだけは
/// `debouncedSaveFires` が 1 本で見る。

// MARK: - 予約するかどうか

@Test("学習の更新が無ければ保存待ちにならない")
@MainActor
func noPendingSaveWithoutUpdate() {
  let converter = makeThrowawayConverter()

  #expect(!converter.hasUnsavedLearningData)

  converter.flushLearningData()

  #expect(!converter.hasUnsavedLearningData)
}

@Test("学習を更新すると保存待ちになり、flush で解消する")
@MainActor
func flushClearsPendingSave() {
  let converter = makeThrowawayConverter()

  converter.updateLearningData(makeCandidate("愛", surfaceCount: 2))
  #expect(converter.hasUnsavedLearningData)

  converter.flushLearningData()
  #expect(!converter.hasUnsavedLearningData)
}

@Test("学習対象外の候補では保存を予約しない")
@MainActor
func nonLearningCandidateDoesNotScheduleSave() {
  let converter = makeThrowawayConverter()

  converter.updateLearningData(
    makeCandidate("①", surfaceCount: 1, isLearningTarget: false))

  // azooKey 側が `isLearningTarget` を見て捨てるため学習メモリは変わっていない。
  // ここで予約すると、何も変わっていないメモリを丸ごと書き直すだけになる。
  #expect(!converter.hasUnsavedLearningData)
}

@Test("deactivateServer では学習データを保存しない")
@MainActor
func deactivateServerDoesNotSaveLearningData() {
  let controller = makeController()
  let converter = controller.converter
  converter.updateLearningData(makeCandidate("愛", surfaceCount: 2))

  controller.deactivateServer(nil)

  // アプリ切り替えのたびに学習メモリ全体を書き直すとフォーカス遷移がその分止まる。
  // 保存はデバウンスに任せ、ここでは走らせない。
  #expect(converter.hasUnsavedLearningData)
}

// MARK: - いつ保存するかの方針

@Test("最初の更新では、上限が締切になる")
func firstUpdateTakesTheDeadlineFromMaxSaveDelay() {
  let now = ContinuousClock.now

  let schedule = Converter.saveSchedule(
    now: now, deadline: nil, saveDelay: .seconds(5), maxSaveDelay: .seconds(30))

  #expect(schedule.deadline == now.advanced(by: .seconds(30)))
  #expect(schedule.wakeUp == now.advanced(by: .seconds(5)))
}

@Test("更新が続いている間は、次に試す時刻が後ろへ動く")
func repeatedUpdatesPostponeTheWakeUp() {
  let start = ContinuousClock.now
  let first = Converter.saveSchedule(
    now: start, deadline: nil, saveDelay: .seconds(5), maxSaveDelay: .seconds(30))

  let second = Converter.saveSchedule(
    now: start.advanced(by: .seconds(3)), deadline: first.deadline,
    saveDelay: .seconds(5), maxSaveDelay: .seconds(30))

  // 連続する確定を 1 回の保存にまとめるために、入力が落ち着くまで待ち直す。
  #expect(second.wakeUp == start.advanced(by: .seconds(8)))
}

@Test("更新を重ねても上限の締切は延びない")
func repeatedUpdatesDoNotExtendTheDeadline() {
  let start = ContinuousClock.now
  let first = Converter.saveSchedule(
    now: start, deadline: nil, saveDelay: .seconds(5), maxSaveDelay: .seconds(30))

  // 確定が途切れないまま締切の手前まで打ち続ける状況を模す。
  var deadline = first.deadline
  for second in 1...25 {
    deadline =
      Converter.saveSchedule(
        now: start.advanced(by: .seconds(second)), deadline: deadline,
        saveDelay: .seconds(5), maxSaveDelay: .seconds(30)
      ).deadline
  }

  // 締切を更新のたびに取り直す回帰なら、ここが後ろへずれる。ずれると、打ち続けている
  // 利用者の学習は永久に書き出されず、強制終了でまとめて失われる。
  #expect(deadline == first.deadline)
}

@Test("確定が途切れなくても、次に試す時刻は締切で頭打ちになる")
func wakeUpIsCappedByTheDeadline() {
  let start = ContinuousClock.now

  // 待ち時間だけなら 600 秒後。上限で切り詰められて締切と同じになる。
  let schedule = Converter.saveSchedule(
    now: start, deadline: nil, saveDelay: .seconds(600), maxSaveDelay: .seconds(30))

  #expect(schedule.wakeUp == schedule.deadline)
  #expect(schedule.wakeUp == start.advanced(by: .seconds(30)))
}

// MARK: - 方針が実際に使われていること

@Test("更新を重ねても、予約されている締切は動かない")
@MainActor
func schedulingKeepsTheDeadlineAcrossUpdates() {
  let converter = makeThrowawayConverter()

  converter.updateLearningData(makeCandidate("愛", surfaceCount: 2))
  let deadline = converter.saveDeadline
  #expect(deadline != nil)

  converter.updateLearningData(makeCandidate("藍", surfaceCount: 2))
  converter.updateLearningData(makeCandidate("哀", surfaceCount: 2))

  // `saveSchedule` が正しくても、`scheduleSave` がそこへ現在の締切を渡していなければ
  // ここでずれる。方針と配線は別に確かめる必要がある。
  #expect(converter.saveDeadline == deadline)
}

@Test("保存すると締切は白紙に戻る")
@MainActor
func savingClearsTheDeadline() {
  let converter = makeThrowawayConverter()

  converter.updateLearningData(makeCandidate("愛", surfaceCount: 2))
  #expect(converter.saveDeadline != nil)

  converter.flushLearningData()

  // 残っていると、次の未保存更新が前回の締切を引き継いで即座に発火する。
  #expect(converter.saveDeadline == nil)
}

// MARK: - 実際に発火すること

@Test("待ち時間が過ぎたら学習データが保存される")
@MainActor
func debouncedSaveFires() async throws {
  let directoryURL = throwawayDirectoryURL()
  let converter = makeThrowawayConverter(
    directoryURL: directoryURL, saveDelay: .milliseconds(10), maxSaveDelay: .seconds(600))

  // 学習メモリの置き場は一度変換を通さないと確定しないため、先に捨て変換をする。
  var composingText = ComposingText()
  composingText.append("あい", inputStyle: .direct)
  _ = converter.convert(composingText)
  converter.stopComposition()

  converter.updateLearningData(makeCandidate("愛", surfaceCount: 2))
  #expect(converter.hasUnsavedLearningData)

  // 上限は待つ側の都合に合わせて緩く取る。「いつ」ではなく「予約が実際に走ること」だけを見る。
  #expect(await waitUntil(timeout: .seconds(10)) { !converter.hasUnsavedLearningData })
  let files = (try? FileManager.default.contentsOfDirectory(atPath: directoryURL.path)) ?? []
  #expect(files.contains { $0.hasPrefix("memory") })
}
