//
//  CandidateList.swift
//  Koto
//

import KanaKanjiConverterModule

/// 候補ウィンドウが表示する候補列と、選択位置・表示範囲を保持する。
///
/// 表示範囲(`visibleRange`)をビューではなくこのモデルが持つのが要点。
/// ビューは `visibleRange` の行だけを描画し、数字キーの割り当ても同じ範囲から
/// 導出するため、「画面に見えている番号」と「数字キーで選ばれる候補」が
/// 構造的にずれない。
struct CandidateList {
  /// 一度に表示する行数。数字キー 1〜9 に対応させるため 9 固定。
  static let pageSize = 9

  private(set) var candidates: [Candidate] = []
  private(set) var selectedIndex: Int = 0
  /// 表示範囲の先頭。`0...(count - pageSize)` にクランプされる。
  private(set) var visibleStart: Int = 0

  var isEmpty: Bool { self.candidates.isEmpty }
  var count: Int { self.candidates.count }

  var selected: Candidate? {
    guard self.candidates.indices.contains(self.selectedIndex) else {
      return nil
    }
    return self.candidates[self.selectedIndex]
  }

  /// 実際に描画される行に対応する候補の範囲。
  var visibleRange: Range<Int> {
    return self.visibleStart..<min(self.visibleStart + Self.pageSize, self.count)
  }

  /// 候補数が表示行数を超えており、スクロールの余地があるか。
  var isScrollable: Bool { self.count > Self.pageSize }

  mutating func reset() {
    self = CandidateList()
  }

  /// 候補を差し替え、先頭を選択した状態にする。
  mutating func replace(with candidates: [Candidate]) {
    self.candidates = candidates
    self.selectedIndex = 0
    self.visibleStart = 0
  }

  mutating func select(_ index: Int) {
    guard self.candidates.indices.contains(index) else {
      return
    }
    self.selectedIndex = index
    self.scrollToSelection()
  }

  /// 次の候補へ。末尾では先頭へ回り込む。
  mutating func selectNext() {
    guard !self.isEmpty else {
      return
    }
    self.select((self.selectedIndex + 1) % self.count)
  }

  /// 前の候補へ。先頭では末尾へ回り込む。
  mutating func selectPrevious() {
    guard !self.isEmpty else {
      return
    }
    self.select((self.selectedIndex - 1 + self.count) % self.count)
  }

  /// 表示中の行に振られた番号(1〜9)に対応する候補の添字。範囲外なら nil。
  func index(forDisplayedNumber number: Int) -> Int? {
    guard (1...Self.pageSize).contains(number) else {
      return nil
    }
    let index = self.visibleStart + number - 1
    return self.visibleRange.contains(index) ? index : nil
  }

  /// 選択位置を動かさずに表示範囲だけをずらす(ホイールスクロール用)。
  mutating func scroll(by rows: Int) {
    guard self.isScrollable else {
      return
    }
    self.visibleStart = min(max(self.visibleStart + rows, 0), self.count - Self.pageSize)
  }

  /// 選択中の候補が表示範囲に入るよう、最小限だけ表示範囲をずらす。
  private mutating func scrollToSelection() {
    if self.selectedIndex < self.visibleStart {
      self.visibleStart = self.selectedIndex
    } else if self.selectedIndex >= self.visibleStart + Self.pageSize {
      self.visibleStart = self.selectedIndex - Self.pageSize + 1
    }
  }
}
