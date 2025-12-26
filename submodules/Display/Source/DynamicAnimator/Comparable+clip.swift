//
//  Comparable+clip.swift
//  Telegram
//
//  Created by James Randolph on 12/16/25.
//

import Foundation

extension Comparable {
    /// Returns a value bounded by the provided range.
    /// - parameter lower: The minimum allowable value (inclusive).
    /// - parameter upper: The maximum allowable value (inclusive).
    public static func clip(_ value: Self, lower: Self, upper: Self) -> Self {
        return min(upper, max(value, lower))
    }
}

extension FloatingPoint {
    /// Returns a value clipped between 0 and 1.
    public static func clipUnit(_ value: Self) -> Self {
        return clip(value, lower: 0, upper: 1)
    }
}
