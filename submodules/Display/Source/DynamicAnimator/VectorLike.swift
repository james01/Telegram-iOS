import Foundation
import CoreGraphics

public protocol VectorLike<Scalar>: Zeroable, AdditiveArithmetic {
    associatedtype Scalar: BinaryFloatingPoint
    var magnitudeSquared: Scalar { get }
    func scaled(by rhs: Scalar) -> Self
    func memberwise(_ rhs: Self, _ operation: (Scalar, Scalar) -> Scalar) -> Self
}

extension VectorLike {
    public static func + (lhs: Self, rhs: Self) -> Self {
        return lhs.memberwise(rhs, +)
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        return lhs.memberwise(rhs, -)
    }

    public func scaledMemberwise(by rhs: Self) -> Self {
        return memberwise(rhs, *)
    }

    public func dividedMemberwise(by rhs: Self) -> Self {
        return memberwise(rhs, /)
    }

    public func adding(_ lhs: Self, scaledBy rhs: Scalar) -> Self {
        return memberwise(lhs) { $0.addingProduct($1, rhs) }
    }

    public mutating func add(_ lhs: Self, scaledBy rhs: Scalar) {
        self = adding(lhs, scaledBy: rhs)
    }

    public static func project(value: Self, velocity: Self, decelerationRate: Scalar = 0.998) -> Self {
        return value.adding(velocity, scaledBy: decelerationRate / (1000 * (1-decelerationRate)))
    }
}

// MARK: CGFloat

extension CGFloat: VectorLike {
    public var magnitudeSquared: Double {
        return self * self
    }

    public func scaled(by rhs: Double) -> CGFloat {
        return self * rhs
    }

    public func memberwise(_ rhs: CGFloat, _ operation: (Double, Double) -> Double) -> CGFloat {
        return operation(self, rhs)
    }
}

// MARK: Double

extension Double: VectorLike {
    public var magnitudeSquared: Double {
        return self * self
    }

    public func scaled(by rhs: Double) -> Double {
        return self * rhs
    }

    public func memberwise(_ rhs: Double, _ operation: (Double, Double) -> Double) -> Double {
        return operation(self, rhs)
    }
}

// MARK: CGPoint

extension CGPoint: @retroactive AdditiveArithmetic {}

extension CGPoint: VectorLike {
    public var magnitudeSquared: Double {
        return x*x + y*y
    }

    public func scaled(by rhs: Double) -> CGPoint {
        return CGPoint(
            x: x * rhs,
            y: y * rhs
        )
    }

    public func memberwise(_ rhs: CGPoint, _ operation: (Double, Double) -> Double) -> CGPoint {
        return CGPoint(
            x: operation(x, rhs.x),
            y: operation(y, rhs.y)
        )
    }
}

// MARK: CGSize

extension CGSize: @retroactive AdditiveArithmetic {}

extension CGSize: VectorLike {
    public var magnitudeSquared: Double {
        return width*width + height*height
    }

    public func scaled(by rhs: Double) -> CGSize {
        return CGSize(
            width: width * rhs,
            height: height * rhs
        )
    }

    public func memberwise(_ rhs: CGSize, _ operation: (Double, Double) -> Double) -> CGSize {
        return CGSize(
            width: operation(width, rhs.width),
            height: operation(height, rhs.height)
        )
    }
}

// MARK: CGRect

extension CGRect: @retroactive AdditiveArithmetic {}

extension CGRect: VectorLike {
    public var magnitudeSquared: Double {
        return origin.magnitudeSquared + size.magnitudeSquared
    }

    public func scaled(by rhs: Double) -> CGRect {
        return CGRect(
            origin: origin.scaled(by: rhs),
            size: size.scaled(by: rhs)
        )
    }

    public func memberwise(_ rhs: CGRect, _ operation: (Double, Double) -> Double) -> CGRect {
        return CGRect(
            origin: origin.memberwise(rhs.origin, operation),
            size: size.memberwise(rhs.size, operation)
        )
    }
}
