import Foundation
import CoreGraphics

public protocol RubberBandable {
    func clip(to bounds: (Self, Self)) -> (base: Self, clip: Self)
    func banded(dimension d: Self, c: Double) -> Self
    func unbanded(dimension d: Self, c: Double) -> Self
    /// The derivative db/dx at the given value of b.
    static func bandFactor(b: Self, dimension d: Self, c: Double) -> Self
}

extension RubberBandable where Self: VectorLike {
    public func clip(to bounds: (Self, Self)) -> (base: Self, clip: Self) {
        let lower = bounds.0.memberwise(bounds.1, min)
        let upper = bounds.0.memberwise(bounds.1, max)
        let base = memberwise(lower, max).memberwise(upper, min)
        let clip = self - base
        return (base, clip)
    }

    public func banded(dimension d: Self, c: Scalar) -> Self {
        return memberwise(d) { (n, d) -> Scalar in
            guard n != 0 else { return 0 }
            let b = { d.addingProduct(-d, d / d.addingProduct($0, c)) }
            return n > 0 ? b(n) : -b(-n)
        }
    }

    public func unbanded(dimension d: Self, c: Scalar) -> Self {
        return memberwise(d) { (n, d) -> Scalar in
            guard n != 0 else { return 0 }
            let x = { ($0 * d) / (c * (d - $0)) }
            return n > 0 ? x(n) : -x(-n)
        }
    }

    public static func bandFactor(b: Self, dimension d: Self, c: Scalar) -> Self {
        return b.memberwise(d) { (b, d) -> Scalar in
            guard b != 0 else { return 1 }
            let dif = d - abs(b)
            return (c * (dif*dif)) / (d*d)
        }
    }
}

extension CGFloat: RubberBandable {
}

extension Double: RubberBandable {
}
