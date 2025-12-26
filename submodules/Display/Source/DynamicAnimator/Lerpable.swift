import UIKit

public protocol Lerpable<Scalar> {
    associatedtype Scalar: BinaryFloatingPoint
    static func lerp(_ value: Scalar, _ out0: Self, _ out1: Self) -> Self
}

extension Lerpable {
    public static func normalize(_ value: Scalar, _ in0: Scalar, _ in1: Scalar) -> Scalar {
        return (value - in0) / (in1 - in0)
    }

    public static func lerpRange(_ value: Scalar, _ in0: Scalar, _ in1: Scalar, _ out0: Self, _ out1: Self) -> Self {
        return lerp(normalize(value, in0, in1), out0, out1)
    }
}

extension Lerpable where Self: VectorLike {
    public static func lerp(_ value: Scalar, _ out0: Self, _ out1: Self) -> Self {
        return out0.adding(out1 - out0, scaledBy: value)
    }
}

extension CGFloat: Lerpable {
}

extension Double: Lerpable {
}

extension CGPoint: Lerpable {
}

extension CGSize: Lerpable {
}

extension CGRect: Lerpable {
}
