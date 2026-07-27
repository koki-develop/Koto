//
//  ScrollAccumulator.swift
//  Koto
//

import CoreGraphics

/// ホイール・トラックパッドの移動量を行数に均すための端数の持ち越し。
///
/// 1 イベントあたりの移動量は 1 行に満たないことが多いため、端数を溜めて
/// 1 行分に達したときだけ行を送る。ただし持ち越した端数が意味を持つのは
/// 同じ向きに続けて動かす場合だけなので、向きが変わったら捨てる。
struct ScrollAccumulator {
  private var residual: CGFloat = 0

  /// 行数に換算済みの移動量を受け取り、送るべき行数を返す。
  ///
  /// - Parameters:
  ///   - delta: 行数に換算した移動量。
  ///   - isGestureStart: 新しいジェスチャの開始か(トラックパッドのみ判定できる)。
  mutating func rows(forDelta delta: CGFloat, isGestureStart: Bool) -> Int {
    guard delta.isFinite else {
      return 0
    }

    // 逆向きの端数を残したまま折り返すと、その端数に相殺されて折り返し直後の
    // 1 回分がまるごと飲まれる。レガシーマウスは phase を返さないため、
    // ジェスチャの開始だけでなく向きの反転も区切りとして見る必要がある。
    if isGestureStart || delta * self.residual < 0 {
      self.residual = 0
    }

    self.residual += delta
    let rows = Int(self.residual.rounded(.towardZero))
    self.residual -= CGFloat(rows)
    return rows
  }

  mutating func reset() {
    self.residual = 0
  }
}
