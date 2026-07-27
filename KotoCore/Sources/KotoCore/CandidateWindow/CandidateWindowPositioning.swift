//
//  CandidateWindowPositioning.swift
//  Koto
//

import AppKit

/// 候補ウィンドウの配置計算。
///
/// 配置ロジックをウィンドウ管理から切り離して純粋な幾何計算に閉じてある。
/// 座標系は AppKit のグローバル座標(左下原点・Y 軸上向き)。
enum CandidateWindowPositioning {
  /// カーソル(未確定文字列の先頭)の矩形の近傍に `size` のウィンドウを置いた矩形を返す。
  ///
  /// 下に収まるなら下へ。収まらない場合は空きの大きい側へ寄せる。
  /// どちらにも収まらないときに下へ固定してしまうと、作業領域へのクランプで
  /// 変換中の文字にウィンドウが被さるため、必ず広いほうを選ぶ。
  static func frame(
    below cursorRect: NSRect,
    size: NSSize,
    within visibleFrame: NSRect,
    gap: CGFloat = 4
  ) -> NSRect {
    let spaceBelow = cursorRect.minY - gap - visibleFrame.minY
    let spaceAbove = visibleFrame.maxY - (cursorRect.maxY + gap)
    let placeBelow = size.height <= spaceBelow || spaceBelow >= spaceAbove

    var origin = NSPoint(
      x: cursorRect.minX,
      y: placeBelow ? cursorRect.minY - gap - size.height : cursorRect.maxY + gap)

    // ウィンドウが作業領域より大きい場合などに備えて最後にクランプする。
    origin.x = max(min(origin.x, visibleFrame.maxX - size.width), visibleFrame.minX)
    origin.y = max(min(origin.y, visibleFrame.maxY - size.height), visibleFrame.minY)

    return NSRect(origin: origin, size: size)
  }

  /// `point` を含むスクリーンを返す。どれにも含まれない場合は最も近いものを返す。
  ///
  /// 包含判定に `visibleFrame` ではなく `frame` を使うのは、メニューバー直下や
  /// Dock 上の座標を取りこぼさないため。クランプに使う作業領域は呼び出し側が
  /// 返り値の `visibleFrame` から取る。
  @MainActor
  static func screen(containing point: NSPoint) -> NSScreen? {
    if let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) {
      return screen
    }
    let nearest = NSScreen.screens.min {
      self.squaredDistance(from: point, to: $0.frame)
        < self.squaredDistance(from: point, to: $1.frame)
    }
    return nearest ?? NSScreen.main
  }

  private static func squaredDistance(from point: NSPoint, to rect: NSRect) -> CGFloat {
    let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
    let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
    return dx * dx + dy * dy
  }
}
