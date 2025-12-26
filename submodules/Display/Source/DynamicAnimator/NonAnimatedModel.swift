import Foundation

public struct NonAnimatedModel<V: Zeroable>: DynamicModeling {
    public init() {
    }
    
    public func update(value: inout V, velocity: inout V, target: V, deltaTime: Timestep) -> Bool {
        return true
    }
}
