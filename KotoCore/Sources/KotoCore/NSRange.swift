//
//  NSRange.swift
//  Koto
//
//  Created by koki sato on 2024/09/17.
//

import Foundation

extension NSRange {
  static var notFound: NSRange {
    NSRange(location: NSNotFound, length: NSNotFound)
  }
}
