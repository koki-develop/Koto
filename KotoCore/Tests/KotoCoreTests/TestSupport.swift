import Foundation
import KanaKanjiConverterModule

@testable import KotoCore

/// このテスト実行ぶんの一時ディレクトリをまとめる親。
///
/// パスをプロセス ID から決め打ちにしてあるのは、`atexit` に渡すクロージャが
/// 何も捕捉できない(C 関数ポインタに変換される)ため。
private func testRootPath() -> String {
  return NSTemporaryDirectory() + "koto-tests-\(ProcessInfo.processInfo.processIdentifier)"
}

private let testRootURL: URL = {
  let url = URL(fileURLWithPath: testRootPath(), isDirectory: true)
  try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  // 変換は学習メモリのファイルを作るため、放っておくと実行のたびに溜まっていく。
  atexit {
    try? FileManager.default.removeItem(atPath: testRootPath())
  }
  return url
}()

/// 実行ごとに作り捨てるディレクトリ。テスト終了時に親ごと消える。
func throwawayDirectoryURL() -> URL {
  let directoryURL = testRootURL.appending(path: UUID().uuidString, directoryHint: .isDirectory)
  try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
  return directoryURL
}

/// 製品コードと同じ変換オプション。ただし学習データとユーザ辞書の置き場は
/// 捨てて良いディレクトリに向ける。既定のままだと変換が
/// `~/Library/Application Support/Koto` を読み書きしてしまい、
/// 実際の学習内容でテスト結果が変わるうえ、利用者の学習データを壊す。
func throwawayOptions(directoryURL: URL = throwawayDirectoryURL()) -> ConvertRequestOptions {
  return options(memoryDirectoryURL: directoryURL, sharedContainerURL: directoryURL)
}
