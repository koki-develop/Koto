import Foundation
import KanaKanjiConverterModule
import Testing

@testable import KotoCore

/// 学習データをいつ永続化するかについての回帰テスト。
///
/// 保存はメインスレッドを塞ぐので、走らせすぎるとフォーカス遷移が止まり、
/// 遅らせすぎると強制終了で学習が失われる。「更新があったときだけ」
/// 「入力が落ち着いてから」「ただし上限つきで」保存することを固定する。

private func makeCandidate(_ text: String, surfaceCount: Int, isLearningTarget: Bool = true)
  -> Candidate
{
  return Candidate(
    text: text,
    value: 0,
    composingCount: .surfaceCount(surfaceCount),
    lastMid: 0,
    data: [],
    isLearningTarget: isLearningTarget
  )
}

/// テスト中に保存が発火しない `Converter`。
@MainActor
private func makeIdleConverter() -> Converter {
  return Converter(
    convertOptions: throwawayOptions(), saveDelay: .seconds(600), maxSaveDelay: .seconds(600))
}

@Test("学習の更新が無ければ保存待ちにならない")
@MainActor
func noPendingSaveWithoutUpdate() {
  let converter = makeIdleConverter()

  #expect(!converter.hasUnsavedLearningData)

  converter.flushLearningData()

  #expect(!converter.hasUnsavedLearningData)
}

@Test("学習を更新すると保存待ちになり、flush で解消する")
@MainActor
func flushClearsPendingSave() {
  let converter = makeIdleConverter()

  converter.updateLearningData(makeCandidate("愛", surfaceCount: 2))
  #expect(converter.hasUnsavedLearningData)

  converter.flushLearningData()
  #expect(!converter.hasUnsavedLearningData)
}

@Test("学習対象外の候補では保存を予約しない")
@MainActor
func nonLearningCandidateDoesNotScheduleSave() {
  let converter = makeIdleConverter()

  converter.updateLearningData(
    makeCandidate("①", surfaceCount: 1, isLearningTarget: false))

  // azooKey 側が `isLearningTarget` を見て捨てるため学習メモリは変わっていない。
  // ここで予約すると、何も変わっていないメモリを丸ごと書き直すだけになる。
  #expect(!converter.hasUnsavedLearningData)
}

@Test("deactivateServer では学習データを保存しない")
@MainActor
func deactivateServerDoesNotSaveLearningData() {
  let converter = makeIdleConverter()
  let controller = KotoInputController(server: nil, delegate: nil, client: nil)!
  controller.converter = converter
  converter.updateLearningData(makeCandidate("愛", surfaceCount: 2))

  controller.deactivateServer(nil)

  // アプリ切り替えのたびに学習メモリ全体を書き直すとフォーカス遷移がその分止まる。
  // 保存はデバウンスに任せ、ここでは走らせない。
  #expect(converter.hasUnsavedLearningData)
}

@Test("待ち時間が過ぎたら学習データが保存される")
@MainActor
func debouncedSaveFires() async throws {
  let directoryURL = throwawayDirectoryURL()
  let converter = Converter(
    convertOptions: throwawayOptions(directoryURL: directoryURL),
    saveDelay: .milliseconds(10),
    maxSaveDelay: .seconds(600)
  )

  // 学習メモリの置き場は一度変換を通さないと確定しないため、先に捨て変換をする。
  var composingText = ComposingText()
  composingText.append("あい", inputStyle: .direct)
  _ = converter.convert(composingText)
  converter.stopComposition()

  converter.updateLearningData(makeCandidate("愛", surfaceCount: 2))
  #expect(converter.hasUnsavedLearningData)

  try await Task.sleep(for: .seconds(1))

  #expect(!converter.hasUnsavedLearningData)
  let files = (try? FileManager.default.contentsOfDirectory(atPath: directoryURL.path)) ?? []
  #expect(files.contains { $0.hasPrefix("memory") })
}

@Test("更新が続いている間は保存を先延ばしにする")
@MainActor
func repeatedUpdatesPostponeSave() async throws {
  let converter = Converter(
    convertOptions: throwawayOptions(),
    saveDelay: .milliseconds(300),
    maxSaveDelay: .seconds(600)
  )

  converter.updateLearningData(makeCandidate("愛", surfaceCount: 2))
  try await Task.sleep(for: .milliseconds(150))
  converter.updateLearningData(makeCandidate("藍", surfaceCount: 2))
  try await Task.sleep(for: .milliseconds(150))

  // 直前の更新から 300ms 経っていないので、まだ保存されていない。
  #expect(converter.hasUnsavedLearningData)

  try await Task.sleep(for: .milliseconds(400))
  #expect(!converter.hasUnsavedLearningData)
}

@Test("確定が途切れなくても上限を過ぎたら保存する")
@MainActor
func maxSaveDelayCapsPostponement() async throws {
  // 待ち時間だけなら永久に発火しない設定にして、上限だけで保存されることを見る。
  let converter = Converter(
    convertOptions: throwawayOptions(),
    saveDelay: .seconds(600),
    maxSaveDelay: .milliseconds(300)
  )

  converter.updateLearningData(makeCandidate("愛", surfaceCount: 2))
  #expect(converter.hasUnsavedLearningData)

  try await Task.sleep(for: .milliseconds(700))

  #expect(!converter.hasUnsavedLearningData)
}

@Test("更新を重ねても上限の締切は延びない")
@MainActor
func repeatedUpdatesDoNotExtendTheDeadline() async throws {
  let converter = Converter(
    convertOptions: throwawayOptions(),
    saveDelay: .seconds(600),
    maxSaveDelay: .milliseconds(400)
  )

  converter.updateLearningData(makeCandidate("愛", surfaceCount: 2))
  try await Task.sleep(for: .milliseconds(150))
  converter.updateLearningData(makeCandidate("藍", surfaceCount: 2))
  try await Task.sleep(for: .milliseconds(150))
  converter.updateLearningData(makeCandidate("哀", surfaceCount: 2))

  // 締切は 1 回目の更新から 400ms。以降の更新で動かないので、あと少しで発火する。
  #expect(converter.hasUnsavedLearningData)

  try await Task.sleep(for: .milliseconds(400))
  #expect(!converter.hasUnsavedLearningData)
}
