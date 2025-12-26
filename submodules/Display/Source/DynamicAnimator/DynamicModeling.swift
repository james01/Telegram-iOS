import Foundation

public protocol DynamicModeling<V> {
    associatedtype V: Zeroable
    func update(value: inout V, velocity: inout V, target: V, deltaTime: Timestep) -> Bool
}
