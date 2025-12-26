import Foundation

public enum RubberBand {
    public static let toastDimension: Double = 96

    public struct Model<T: VectorLike & RubberBandable> {
        public var bounds: (T, T)
        public var dimension: T
        public var c: Double

        public init(bounds: (T, T), dimension: T, c: Double = 0.55) {
            self.bounds = bounds
            self.dimension = dimension
            self.c = c
        }

        public init() {
            self.init(bounds: (.zero, .zero), dimension: .zero)
        }

        public func unband(value: T) -> T {
            let (base, clip) = value.clip(to: bounds)
            return base + clip.unbanded(dimension: dimension, c: c)
        }

        public func band(value: T) -> T {
            let (base, clip) = value.clip(to: bounds)
            return base + clip.banded(dimension: dimension, c: c)
        }

        public func unband(velocity: T, bandedValue: T) -> T {
            let factor: T = .bandFactor(b: bandedValue.clip(to: bounds).clip, dimension: dimension, c: c)
            return velocity.dividedMemberwise(by: factor)
        }

        public func band(velocity: T, bandedValue: T) -> T {
            let factor: T = .bandFactor(b: bandedValue.clip(to: bounds).clip, dimension: dimension, c: c)
            return velocity.scaledMemberwise(by: factor)
        }

        public func modifyAsUnbandedValue(_ value: inout T, _ modify: (inout T) -> Void) {
            value = unband(value: value)
            modify(&value)
            value = band(value: value)
        }

        public mutating func bound(to range: Range<Int>) where T: FloatingPoint {
            let lower = T(range.lowerBound)
            let upper = T(max(range.upperBound - 1, range.lowerBound))
            bounds = (lower, upper)
        }
    }
}
