//
//  BuiltinDictionary.swift
//  Koto
//

import KanaKanjiConverterModule

/// azooKey の既定辞書に欠けている語を補う、Koto 組み込みの補助辞書。
///
/// **ここは上流が取り込むまでの緩衝であって、Koto が独自辞書を持つ場所ではない。**
/// 変換そのものを azooKey に丸ごと預けている以上、一般的に使われる語の欠落は
/// azooKey-dictionary 側で直すのが筋で、ここに足すのは上流に入るまでの繋ぎか、
/// 上流に入れるほどではない語に限る。`BuiltinDictionaryTests` が 1 語ずつ
/// 「azooKey にまだ無い」ことを確かめているので、上流が取り込めばテストが落ちて
/// ここから消せと言ってくる。放っておくと膨らむ一方になるのを、それで防ぐ。
///
/// 渡し先は `KanaKanjiConverter.importDynamicUserDictionary` で、ファイルを一切
/// 経由しない。`sharedContainerURL` 配下の `user.louds` を作る道もあるが、あれは
/// 特定の `charID.chid` に対して構築されたバイナリなので azooKey の辞書バージョンと
/// 暗黙に結合し、アプリ更新をまたいでディスクに残る版とのズレを自前で面倒みる羽目になる。
/// 学習メモリのシャードで既に一度踏んでいる問題を二度持ち込む価値は、この語数には無い。
///
/// 代わりに引き当ては `DicdataStore.getMatchDynamicUserDict` の線形走査になり、
/// 変換のたびに読みの接頭辞ごとに走る。実測 (release ビルド、
/// 「きょうはいいてんきですね」1 回の変換にかかる時間):
///
/// | 語数 | 変換時間 |
/// | ---: | ---: |
/// | 0 | 3.1ms |
/// | 200 | 3.5ms |
/// | 1,000 | 6.0ms |
/// | 3,000 | 12.8ms |
///
/// 数十語のうちは誤差だが、語数に比例して効いてくる。前提が崩れたことに気付けるよう、
/// `maxEntryCount` をテストで固定してある。
enum BuiltinDictionary {
  /// 補助辞書に置ける語数の上限。
  ///
  /// 超えたならそれはもう緩衝ではなく独自辞書であり、線形走査をやめて
  /// `user.louds` のファイル方式 (LOUDS なので語数に対してフラット。10 万語でも
  /// 変換時間は据え置き) へ移す判断をすること。移行は `Converter` の内側で閉じるので、
  /// 先送りしても高くつかない。
  static let maxEntryCount = 300

  /// 補助辞書の 1 語。
  struct Entry: Sendable {
    /// 変換後の表記。
    let word: String
    /// 読み。**ひらがなで書く。** azooKey へはカタカナに直して渡す。
    let reading: String
    /// 辞書スコア。0 に近いほど強い。
    ///
    /// **既存の候補を押しのけない値を実測で選ぶこと。** 最終的な候補の並びには
    /// 品詞の連接コストが乗るため、素の辞書スコアとの大小から順位は予測できない。
    /// 語を足すときは実際に変換させて確かめるしかない。
    ///
    /// 狙うのは 1 位ではなく「1 ページ目に確実に居ること」。一度確定すれば学習が
    /// 1 位へ押し上げるので、既存の一般語を蹴落としてまで最初から 1 位に置く必要はない。
    let value: PValue
  }

  static let entries: [Entry] = [
    // azooKey では「さいばん」の候補 215 件すべてが 裁判/妻版/細版/… で、「採番」は
    // どこにも現れない。単漢字の「採」(サイ) が -30.0 で、ラティス構築時の閾値
    // (`DicdataStore.threshold` = -17) に届かずノードごと捨てられるため、
    // 「採」+「番」という分割としても組み上がらない。
    //
    // -10.5 は「裁判」を 1 位に残したまま 2 位に入る値。「自動採番」「採番する」も
    // 1 位で組める。これより強くすると「さいばんしょ」の候補が採番所/採番書/採番署で
    // 埋まり、弱くすると「自動採番」が候補から落ちる。
    Entry(word: "採番", reading: "さいばん", value: -10.5)
  ]

  /// azooKey に渡す形。
  static var dicdata: [DicdataElement] {
    return self.entries.map { entry in
      DicdataElement(
        word: entry.word,
        ruby: Self.katakanaRuby(entry.reading),
        cid: CIDData.一般名詞.cid,
        mid: MIDData.一般.mid,
        value: entry.value
      )
    }
  }

  /// 読みを、azooKey が引き当てに使うのと同じカタカナ表記に直す。
  ///
  /// **ここで `String.toKatakana()` を使ってはいけない。** あちらは ICU の
  /// `hiraganaToKatakana` で、azooKey が使う変換 (SwiftUtils の `toKatakana()`、
  /// U+3041...U+3096 を +96 するだけのもの) と 4 文字で食い違う:
  /// ICU は ゕ ゖ をひらがなのまま残し、azooKey は ヵ ヶ に送る。逆に ゝ ゞ は
  /// ICU が ヽ ヾ に送り、azooKey は範囲外なのでそのまま残す。
  ///
  /// 引き当ては `DicdataStore.getMatchDynamicUserDict` の `ruby ==` による文字列比較
  /// なので、食い違えば一致しなくなる。**変換が失敗するのではなく、その語が黙って
  /// 候補から消えるだけ**で、手がかりは何も出ない。
  ///
  /// SwiftUtils を import して azooKey の実装をそのまま呼ぶ手は使えない。同名の
  /// `String.toKatakana()` が KotoCore にもあるため、曖昧だと怒られることもなく
  /// **こちらの ICU 版が黙って優先される** (確認済み)。呼んでいるつもりで呼べていない
  /// のが一番まずいので、azooKey と同じ計算をここに書き下す。
  ///
  /// 一致していることは `BuiltinDictionaryTests` が azooKey に実際に引かせて確かめる。
  static func katakanaRuby(_ reading: String) -> String {
    let utf16 = reading.utf16.map { unit in
      (0x3041...0x3096).contains(unit) ? unit + 96 : unit
    }
    return String(utf16CodeUnits: utf16, count: utf16.count)
  }
}
