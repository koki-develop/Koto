import Foundation
import KanaKanjiConverterModule
import Testing

@testable import KotoCore

/// 組み込み補助辞書 (`BuiltinDictionary`) の回帰テスト。
///
/// このテスト群の役割は、語を増やすことではなく **増えすぎないようにすること** と、
/// **azooKey が追いついたら気付くこと** の 2 つ。補助辞書は放っておくと膨らむ一方で、
/// 膨らんだぶんだけ全変換が遅くなるので、上限と存在理由の両方を機械で見張る。

// MARK: - 補助辞書そのものの検査

@Test("補助辞書は語数の上限を超えない")
func doesNotExceedMaxEntryCount() {
  // 超えたときに直す先は `BuiltinDictionary.maxEntryCount` のコメントにある。
  // 上限を引き上げて済ませて良いのは、線形走査のコストを測り直した場合だけ。
  #expect(BuiltinDictionary.entries.count <= BuiltinDictionary.maxEntryCount)
}

@Test("読みはひらがなで書かれている")
func readingsAreHiragana() {
  for entry in BuiltinDictionary.entries {
    // これは正しさの防具ではなく、リストの書き方を揃えるためのもの。読みが実際に
    // 引けるかどうかは `katakanaRubyMatchesAzooKeyLookup` が azooKey に引かせて見る。
    #expect(
      entry.reading.allSatisfy(isHiraganaReadingCharacter),
      "\(entry.word) の読み「\(entry.reading)」がひらがなではない")
  }
}

@Test("同じ語を二重に登録していない")
func entriesAreUnique() {
  let keys = BuiltinDictionary.entries.map { "\($0.reading)/\($0.word)" }
  #expect(Set(keys).count == keys.count)
}

// MARK: - azooKey との関係

/// 読みからルビへの変換が、azooKey の引き当てと噛み合うか。
///
/// `BuiltinDictionary.katakanaRuby` は azooKey (SwiftUtils) の `toKatakana()` を
/// 書き写したもの。写しの正しさを同じ計算をもう一度書いて確かめても意味が無いので、
/// **azooKey に実際に引かせて** 見る。ここが落ちたら azooKey 側の変換が変わったということ。
///
/// 引数に危ない文字を並べてあるのが要点。ICU の `hiraganaToKatakana` との食い違いは
/// ゕ ゖ ゝ ゞ の 4 文字にしか出ないので、実在のエントリ (いまは「さいばん」1 件) を
/// いくら回しても踏めない。踏むのは、その 4 文字を含む語を誰かが足した日になる。
@Test(
  "読みからルビへの変換が azooKey の引き当てと一致する",
  arguments: ["さいばん", "あゕ", "あゖ", "あゝ", "あゞ", "こーど"])
@MainActor
func katakanaRubyMatchesAzooKeyLookup(reading: String) {
  // 既定辞書が同じ読みで出しうる語とぶつからないよう、辞書に無い綴りを使う。
  let probeWord = "ズンドコ"
  let converter = makeBareConverter()
  converter.importDynamicUserDictionary([
    DicdataElement(
      word: probeWord,
      ruby: BuiltinDictionary.katakanaRuby(reading),
      cid: CIDData.一般名詞.cid,
      mid: MIDData.一般.mid,
      value: -6.0
    )
  ])

  let isConvertible = convert(converter, reading).contains(probeWord)

  #expect(
    isConvertible,
    "読み「\(reading)」を ruby「\(BuiltinDictionary.katakanaRuby(reading))」で登録したが引けない")
}

@Test("azooKey の既定辞書にまだ無い語だけを持つ", arguments: BuiltinDictionary.entries)
@MainActor
func entryIsMissingFromDefaultDictionary(entry: BuiltinDictionary.Entry) {
  // このテストが落ちたら、azooKey がその語を取り込んだということ。
  // `BuiltinDictionary.entries` から **消す** のが正しい対応で、
  // 補助辞書に残したままにすると既定辞書の候補と競合するだけになる。
  let converter = makeBareConverter()
  // 候補は 200 件を超える。`#expect` に配列の式をそのまま渡すと、失敗時に全件が
  // メッセージへ展開されて何が起きたのか読めなくなるので、真偽値まで畳んでから渡す。
  let isConvertible = convert(converter, entry.reading).contains(entry.word)

  #expect(
    !isConvertible,
    "「\(entry.reading)」が azooKey 単体で「\(entry.word)」に変換できる。補助辞書から消すこと")
}

@Test("補助辞書の語が 1 ページ目に出る", arguments: BuiltinDictionary.entries)
@MainActor
func entryAppearsOnTheFirstPage(entry: BuiltinDictionary.Entry) {
  let converter = makeThrowawayConverter()
  let candidates = convert(converter, entry.reading)

  guard let index = candidates.firstIndex(of: entry.word) else {
    Issue.record("「\(entry.reading)」の候補に「\(entry.word)」が無い")
    return
  }
  // 1 位ではなく 1 ページ目を要求する。候補の並びには連接コストが乗るので順位は
  // 依存バンプで多少動くが、「スクロールせずに届く」ことさえ保てれば、あとは
  // 一度確定した時点で学習が 1 位へ押し上げる。
  #expect(
    index < CandidateList.pageSize,
    "「\(entry.word)」が \(index + 1) 番目で、1 ページ目 (\(CandidateList.pageSize) 行) に入っていない")
}

// MARK: - 補助

/// 読みに使って良い文字か。ひらがなと長音符だけを通す。
///
/// 長音符 (ー) はカタカナブロックの文字だが「こーど」のような読みに現れるうえ、
/// `BuiltinDictionary.katakanaRuby` が素通しするので、カタカナに直したあとの
/// 読みとしても正しい。
private func isHiraganaReadingCharacter(_ character: Character) -> Bool {
  guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else {
    return false
  }
  return ("\u{3041}"..."\u{3096}").contains(scalar) || scalar == "\u{30FC}"
}

/// 補助辞書を積んでいない、azooKey 素のままの変換器。
///
/// `Converter` は `init` で補助辞書を読み込んでしまうため、「azooKey 単体では
/// 変換できない」ことを確かめるにはこちらを使う。
@MainActor
private func makeBareConverter() -> KanaKanjiConverter {
  return KanaKanjiConverter()
}

@MainActor
private func convert(_ converter: KanaKanjiConverter, _ reading: String) -> [String] {
  var composingText = ComposingText()
  composingText.insertAtCursorPosition(reading, inputStyle: .direct)
  defer { converter.stopComposition() }
  return converter.requestCandidates(composingText, options: throwawayOptions()).mainResults.map {
    $0.text
  }
}

@MainActor
private func convert(_ converter: Converter, _ reading: String) -> [String] {
  var composingText = ComposingText()
  composingText.insertAtCursorPosition(reading, inputStyle: .direct)
  defer { converter.stopComposition() }
  return converter.convert(composingText).mainResults.map { $0.text }
}
