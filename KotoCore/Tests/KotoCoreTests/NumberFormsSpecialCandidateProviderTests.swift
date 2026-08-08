import Foundation
import KanaKanjiConverterModule
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

@testable import KotoCore

private let provider = NumberFormsSpecialCandidateProvider()

private func composingText(_ text: String) -> ComposingText {
  var composingText = ComposingText()
  for character in text {
    composingText.append(String(character), inputStyle: .roman2kana)
  }
  return composingText
}

private func texts(_ input: String) -> [String] {
  let converter = KanaKanjiConverter()
  return provider.provideCandidates(
    converter: converter,
    inputData: composingText(input),
    options: throwawayOptions()
  ).map(\.text)
}

@Test("1 桁の数字に丸数字・ローマ数字が付く")
func singleDigit() {
  #expect(texts("1") == ["①", "❶", "Ⅰ", "ⅰ"])
  #expect(texts("9") == ["⑨", "❾", "Ⅸ", "ⅸ"])
}

@Test("0 は丸数字だけ(ローマ数字にゼロはない)")
func zero() {
  #expect(texts("0") == ["⓪", "⓿"])
}

@Test("複数桁も系列ごとの上限まで出る")
func multipleDigits() {
  #expect(texts("12") == ["⑫", "⓬", "Ⅻ", "ⅻ"])
  #expect(texts("13") == ["⑬", "⓭"])
  #expect(texts("20") == ["⑳", "⓴"])
  #expect(texts("21") == ["㉑"])
  #expect(texts("35") == ["㉟"])
  #expect(texts("36") == ["㊱"])
  #expect(texts("50") == ["㊿"])
}

@Test("どの系列にも無い数は候補を出さない")
func outOfRange() {
  #expect(texts("51").isEmpty)
  #expect(texts("100").isEmpty)
  #expect(texts("99999999999999999999999").isEmpty)
}

@Test("数字以外や先頭ゼロ付きは対象外")
func notANumber() {
  #expect(texts("").isEmpty)
  #expect(texts("あ").isEmpty)
  #expect(texts("a").isEmpty)
  #expect(texts("01").isEmpty)
  #expect(texts("1a").isEmpty)
}

@Test("半角のまま渡されても同じ候補になる")
func halfWidthInput() {
  var composingText = ComposingText()
  composingText.append("1", inputStyle: .direct)
  let candidates = provider.provideCandidates(
    converter: KanaKanjiConverter(),
    inputData: composingText,
    options: throwawayOptions()
  )
  #expect(candidates.map(\.text) == ["①", "❶", "Ⅰ", "ⅰ"])
}

@Test("入力全体を消費し、学習の対象にはしない")
func candidateShape() {
  let input = composingText("12")
  let candidates = provider.provideCandidates(
    converter: KanaKanjiConverter(),
    inputData: input,
    options: throwawayOptions()
  )
  #expect(!candidates.isEmpty)
  for candidate in candidates {
    #expect(candidate.composingCount == .inputCount(input.input.count))
    #expect(!candidate.isLearningTarget)
    #expect(candidate.data.map(\.ruby).joined() == input.convertTarget)
  }
}

@Test("製品コードのオプションで変換すると実際に候補へ並ぶ")
func endToEnd() {
  let converter = KanaKanjiConverter()
  let results =
    converter
    .requestCandidates(composingText("1"), options: throwawayOptions())
    .mainResults
    .map(\.text)

  #expect(results.first == "１")
  for text in ["①", "❶", "Ⅰ", "ⅰ"] {
    #expect(results.contains(text))
  }

  converter.stopComposition()
}
