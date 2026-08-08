import Foundation
import KanaKanjiConverterModule
import Testing

@testable import KotoCore

/// 学習メモリの置き場から、前世代の取り残しシャードを落とせているかの回帰テスト。
///
/// 取り残しを放置すると azooKey のマージがプロセスごと落ちる。しかもその状態は
/// エントリ数が変わらないため自然に解消しない。詳しくは `LearningMemory` を参照。

private let entriesPerShard = DictionaryBuilder.entriesPerShard

/// メタデータのヘッダ。先頭 4 byte のリトルエンディアン `UInt32` がエントリ数。
private func metadataHeader(entryCount: Int) -> Data {
  var header = Data()
  let value = UInt32(entryCount)
  for shift in stride(from: 0, to: 32, by: 8) {
    header.append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
  }
  return header
}

/// シャードのヘッダ。先頭 2 byte のリトルエンディアン `UInt16` がそのシャードのエントリ数。
private func shardHeader(entryCount: Int) -> Data {
  let value = UInt16(truncatingIfNeeded: entryCount)
  return Data([UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)])
}

/// テスト用の置き場を組み立てる。
///
/// 先頭シャードには実際のヘッダを持たせる。`LearningMemory` はそこを読んで、
/// 置き場がこの版と同じ分割幅で書かれたことを確かめるため。
///
/// - Parameters:
///   - entryCount: `memory.memorymetadata` に書くエントリ数。`nil` なら置かない。
///   - pendingEntryCount: `memory.memorymetadata.2`(中断された書き込みの保留分)。
///   - pause: `.pause` を置くか。あると azooKey は復元から始める。
///   - shardIndices: 用意する `memoryN.loudstxt3` の番号。`.2` も一緒に作る。
///   - leadingShardEntryCount: 先頭シャードのヘッダを明示的に上書きする。
///     分割幅の食い違いを作るときだけ使う。
private func makeMemoryDirectory(
  entryCount: Int?,
  shardIndices: [Int],
  pendingEntryCount: Int? = nil,
  pause: Bool = false,
  metadataBytes: [UInt8]? = nil,
  leadingShardEntryCount: Int? = nil
) -> URL {
  let directoryURL = throwawayDirectoryURL()

  if let metadataBytes {
    try! Data(metadataBytes).write(to: directoryURL.appending(path: "memory.memorymetadata"))
  } else if let entryCount {
    // 本体はこのテストでは読まれないので、ヘッダだけで足りる。
    try! metadataHeader(entryCount: entryCount)
      .write(to: directoryURL.appending(path: "memory.memorymetadata"))
  }
  if let pendingEntryCount {
    try! metadataHeader(entryCount: pendingEntryCount)
      .write(to: directoryURL.appending(path: "memory.memorymetadata.2"))
  }
  if pause {
    try! Data().write(to: directoryURL.appending(path: ".pause"))
  }

  for index in shardIndices {
    // 先頭以外は読まれないので中身は問わない。
    var real = Data()
    var shadow = Data()
    if index == 0 {
      real = shardHeader(
        entryCount: leadingShardEntryCount ?? min(entryCount ?? 0, entriesPerShard))
      shadow = shardHeader(
        entryCount: leadingShardEntryCount
          ?? min(pendingEntryCount ?? entryCount ?? 0, entriesPerShard))
    }
    try! real.write(to: directoryURL.appending(path: "memory\(index).loudstxt3"))
    try! shadow.write(to: directoryURL.appending(path: "memory\(index).loudstxt3.2"))
  }
  return directoryURL
}

private func fileNames(in directoryURL: URL) -> Set<String> {
  return Set((try? FileManager.default.contentsOfDirectory(atPath: directoryURL.path)) ?? [])
}

private func shardNames(_ indices: [Int]) -> Set<String> {
  return Set(indices.flatMap { ["memory\($0).loudstxt3", "memory\($0).loudstxt3.2"] })
}

@Test("エントリ数がシャード境界ちょうどでも、余分なシャードだけが消える")
func removesStaleShardsOnExactBoundary() {
  // これがまさにクラッシュを起こす形。azooKey は 5 個しか書かないのに、
  // マージは 6 個目を読みにいく。
  let directoryURL = makeMemoryDirectory(
    entryCount: entriesPerShard * 5, shardIndices: Array(0...8))

  LearningMemory.removeStaleShards(in: directoryURL)

  let names = fileNames(in: directoryURL)
  #expect(shardNames(Array(0...4)).isSubset(of: names))
  #expect(names.isDisjoint(with: shardNames(Array(5...8))))
}

@Test("端数があるときは端数ぶんのシャードを残す")
func keepsShardHoldingRemainder() {
  let directoryURL = makeMemoryDirectory(
    entryCount: entriesPerShard * 5 + 1, shardIndices: Array(0...8))

  LearningMemory.removeStaleShards(in: directoryURL)

  let names = fileNames(in: directoryURL)
  #expect(shardNames(Array(0...5)).isSubset(of: names))
  #expect(names.isDisjoint(with: shardNames(Array(6...8))))
}

@Test("エントリ数 0 は辻褄が合わないので、信じて消したりしない")
func keepsEverythingWhenEntryCountIsZero() {
  // azooKey は根ノード 2 つを必ず含めて書くので、正しく書かれたヘッダは 0 にならない。
  // 0 が出るのは形式が変わったときで、そこで信じて消すと置き場を丸ごと吹き飛ばす。
  let directoryURL = makeMemoryDirectory(entryCount: 0, shardIndices: Array(0...2))

  LearningMemory.removeStaleShards(in: directoryURL)

  #expect(shardNames(Array(0...2)).isSubset(of: fileNames(in: directoryURL)))
}

@Test("エントリが 1 件でもシャードは 1 枚必要")
func keepsFirstShardForASingleEntry() {
  let directoryURL = makeMemoryDirectory(entryCount: 1, shardIndices: Array(0...2))

  LearningMemory.removeStaleShards(in: directoryURL)

  let names = fileNames(in: directoryURL)
  #expect(shardNames([0]).isSubset(of: names))
  #expect(names.isDisjoint(with: shardNames([1, 2])))
}

@Test("番号を持たないファイルは現世代の一部なので触らない")
func keepsUnnumberedFiles() {
  let directoryURL = makeMemoryDirectory(entryCount: 1, shardIndices: [0, 1])
  for name in ["memory.louds", "memory.louds.2", "memory.loudschars2"] {
    try! Data().write(to: directoryURL.appending(path: name))
  }

  LearningMemory.removeStaleShards(in: directoryURL)

  let names = fileNames(in: directoryURL)
  #expect(names.contains("memory.louds"))
  #expect(names.contains("memory.louds.2"))
  #expect(names.contains("memory.loudschars2"))
  #expect(names.contains("memory.memorymetadata"))
}

@Test("メタデータが無ければシャードはもう誰にも読めないので、全部落とす")
func removesOrphanedShardsWithoutMetadata() {
  // 学習データのリセットが途中で失敗するとこの状態になりうる(azooKey の `reset` は
  // 順不同に消して、1 つでも失敗するとそこで中断する)。放置するとマージが
  // 4 byte の代用メタデータの先を読んでプロセスごと落ちる。
  let directoryURL = makeMemoryDirectory(entryCount: nil, shardIndices: Array(0...2))
  try! Data().write(to: directoryURL.appending(path: "memory.louds"))

  LearningMemory.removeStaleShards(in: directoryURL)

  let names = fileNames(in: directoryURL)
  #expect(names.isDisjoint(with: shardNames(Array(0...2))))
  // 番号を持たないファイルは対象外のまま。次のマージが書き直す。
  #expect(names.contains("memory.louds"))
}

@Test("メタデータが短すぎて読めなければ何も消さない")
func keepsEverythingWithTruncatedMetadata() {
  let directoryURL = makeMemoryDirectory(
    entryCount: nil, shardIndices: Array(0...2), metadataBytes: [0x00, 0x01])

  LearningMemory.removeStaleShards(in: directoryURL)

  #expect(shardNames(Array(0...2)).isSubset(of: fileNames(in: directoryURL)))
}

@Test("中断された書き込みが残っているときは、保留中の世代を正として数える")
func countsPendingGenerationWhileRecovering() {
  // 中断前の本ファイルは古い小さな世代を指したまま、`.2` には大きな新世代が
  // 書き終わっている状態。本ファイル側で数えると、新世代の末尾シャードを
  // 取り残しと誤認して消してしまう。それを消すと azooKey の復元が
  // 中途半端な世代を復元することになる。
  let directoryURL = makeMemoryDirectory(
    entryCount: entriesPerShard * 2,
    shardIndices: Array(0...8),
    pendingEntryCount: entriesPerShard * 6,
    pause: true
  )

  LearningMemory.removeStaleShards(in: directoryURL)

  let names = fileNames(in: directoryURL)
  #expect(shardNames(Array(0...5)).isSubset(of: names))
  #expect(names.isDisjoint(with: shardNames(Array(6...8))))
  #expect(names.contains(".pause"))
  #expect(names.contains("memory.memorymetadata.2"))
}

@Test("違う分割幅で書かれた置き場には手を出さない")
func keepsEverythingWrittenWithADifferentShardSize() {
  // 依存を上げて `shardShift` が変わると、置き場は前のビルドの幅で書かれたまま残る。
  // それに気づかず今の幅で数えると、まだ現役のシャードを取り残しと誤認して消す。
  // 先頭シャードの詰まり具合が合わないことで検知する。
  let directoryURL = makeMemoryDirectory(
    entryCount: entriesPerShard * 5,
    shardIndices: Array(0...8),
    leadingShardEntryCount: entriesPerShard / 2
  )

  LearningMemory.removeStaleShards(in: directoryURL)

  #expect(shardNames(Array(0...8)).isSubset(of: fileNames(in: directoryURL)))
}

@Test("先頭シャードが読めなければ分割幅を確かめられないので何も消さない")
func keepsEverythingWithoutALeadingShard() {
  let directoryURL = makeMemoryDirectory(
    entryCount: entriesPerShard * 5, shardIndices: Array(1...8))

  LearningMemory.removeStaleShards(in: directoryURL)

  #expect(shardNames(Array(1...8)).isSubset(of: fileNames(in: directoryURL)))
}

@Test("中断されているのに保留中のメタデータが無ければ何も消さない")
func keepsEverythingWhileRecoveringWithoutPendingMetadata() {
  let directoryURL = makeMemoryDirectory(
    entryCount: entriesPerShard * 2, shardIndices: Array(0...8), pause: true)

  LearningMemory.removeStaleShards(in: directoryURL)

  #expect(shardNames(Array(0...8)).isSubset(of: fileNames(in: directoryURL)))
}

// MARK: - azooKey の実物との突き合わせ

/// メタデータのヘッダの並びは azooKey の非公開フォーマットで、こちらは読み返しているだけ。
/// 合成したデータを同じ方式で読むテストでは、形式が変わっても必ず一致してしまって検知できない。
/// ここだけは azooKey に本物を書かせて、こちらの数え方と突き合わせる。
///
/// これが落ちたら、まず疑うのは Koto ではなく依存の更新。
@Test("azooKey が実際に書いた置き場と、こちらの数え方が一致する")
@MainActor
func agreesWithLayoutWrittenByAzooKey() throws {
  let directoryURL = throwawayDirectoryURL()
  let converter = Converter(
    convertOptions: options(memoryDirectoryURL: directoryURL, sharedContainerURL: directoryURL),
    saveDelay: .seconds(600),
    maxSaveDelay: .seconds(600)
  )

  // 実際に学習させて、azooKey に本物の学習メモリを書かせる。
  var composing = ComposingText()
  composing.insertAtCursorPosition("あい", inputStyle: .direct)
  let candidate = try #require(converter.convert(composing).mainResults.first)
  converter.stopComposition()
  converter.updateLearningData(candidate)
  converter.flushLearningData()

  let writtenShardCount = fileNames(in: directoryURL)
    .filter { $0.hasSuffix(".loudstxt3") }
    .count
  // 学習が本当に書かれたことを先に押さえる。0 同士で一致しても意味がない。
  #expect(writtenShardCount > 0)
  #expect(LearningMemory.currentShardCount(in: directoryURL) == writtenShardCount)
}

// MARK: - 呼び出し箇所

/// 掃除は `Converter` の 4 か所(生成時、最初の変換の後、保存の前後)から呼ばれている。
/// 実際に一度、復元マージの経路を取りこぼしているので、消えたら気づけるようにしておく。
///
/// **保存「後」の呼び出しだけは固定できていない。** 前の呼び出しが先に取り残しを
/// 落としてしまうため、ファイルを見るだけでは前後を区別できない。後の呼び出しが効くのは
/// 「マージ自身が世代を縮めて取り残しを作った」ときで、それを単体テストから
/// 狙って起こす方法が無い。消しても以下のテストは通ってしまうので、
/// 消さないこと(理由は `LearningMemory.removeStaleShards` を参照)。

/// azooKey に本物の学習メモリを書かせた置き場を返す。
///
/// 合成したメタデータで代用しないこと。エントリ数だけ書いて中身の無いメタデータは
/// azooKey から見れば壊れた置き場で、変換を走らせた時点でプロセスごと落ちる。
@MainActor
private func makeDirectoryWithRealMemory() throws -> (URL, Converter) {
  let directoryURL = throwawayDirectoryURL()
  let converter = makeConverter(for: directoryURL)
  var composing = ComposingText()
  composing.insertAtCursorPosition("あい", inputStyle: .direct)
  let candidate = try #require(converter.convert(composing).mainResults.first)
  converter.stopComposition()
  converter.updateLearningData(candidate)
  converter.flushLearningData()
  // 生成済みの `Converter` も返す。辞書の読み込みは軽くないので、作り直さずに
  // 済ませられるテストでは使い回す。
  return (directoryURL, converter)
}

@MainActor
private func makeConverter(for directoryURL: URL) -> Converter {
  return Converter(
    convertOptions: options(memoryDirectoryURL: directoryURL, sharedContainerURL: directoryURL),
    saveDelay: .seconds(600),
    maxSaveDelay: .seconds(600)
  )
}

/// どんなに学習しても現世代には入りえない番号。メタデータには一切触れない。
private let staleShardName = "memory999.loudstxt3"

private func addStaleShard(to directoryURL: URL) {
  try! Data().write(to: directoryURL.appending(path: staleShardName))
}

private func hasStaleShard(in directoryURL: URL) -> Bool {
  return fileNames(in: directoryURL).contains(staleShardName)
}

@Test("Converter を作った時点で掃除されている")
@MainActor
func cleansOnInit() throws {
  let (directoryURL, _) = try makeDirectoryWithRealMemory()
  addStaleShard(to: directoryURL)

  _ = makeConverter(for: directoryURL)

  #expect(!hasStaleShard(in: directoryURL))
}

@Test("最初の変換の後にも掃除される(復元マージが取り残すため)")
@MainActor
func cleansAfterFirstConversion() throws {
  // ここは `hasConverted` がまだ立っていない `Converter` が要るので作り直す。
  let (directoryURL, _) = try makeDirectoryWithRealMemory()
  let converter = makeConverter(for: directoryURL)
  // 生成時の掃除では拾えない位置に置く。
  addStaleShard(to: directoryURL)

  var composing = ComposingText()
  composing.insertAtCursorPosition("あ", inputStyle: .direct)
  _ = converter.convert(composing)
  converter.stopComposition()

  #expect(!hasStaleShard(in: directoryURL))
}

@Test("保存でも掃除される")
@MainActor
func cleansAroundSave() throws {
  // 生成時と最初の変換の掃除はこの `Converter` で済んでいる。保存だけを見たいので
  // 作り直さずに使い回す。
  let (directoryURL, converter) = try makeDirectoryWithRealMemory()
  var composing = ComposingText()
  composing.insertAtCursorPosition("あい", inputStyle: .direct)
  let candidate = try #require(converter.convert(composing).mainResults.first)
  converter.stopComposition()
  addStaleShard(to: directoryURL)

  converter.updateLearningData(candidate)
  converter.flushLearningData()

  #expect(!hasStaleShard(in: directoryURL))
}
