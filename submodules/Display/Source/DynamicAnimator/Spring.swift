import Foundation

public struct Spring<V: VectorLike<Double>>: DynamicModeling {
    public let response: Double
    public let dampingRatio: Double
    public let epsilon: Double
    
    public let naturalFrequency: Double
    public let dampedFrequency: Double
    
    public var stiffness: Double { naturalFrequency * naturalFrequency }
    public var damping: Double { 2 * dampingRatio * naturalFrequency }
    
    public init(response: Double, dampingRatio: Double, epsilon: Double = 0.00001) {
        assert(0 < response)
        assert(0 < dampingRatio && dampingRatio <= 1)
        
        self.response = response
        self.dampingRatio = dampingRatio
        self.epsilon = epsilon
        
        naturalFrequency = 2*Double.pi / response
        dampedFrequency = naturalFrequency * sqrt(1 - dampingRatio * dampingRatio)
    }

    public func update(value: inout V, velocity: inout V, target: V, deltaTime: Timestep) -> Bool {
        let dt = deltaTime.ideal
        if dampingRatio == 1 {
            // Critically damped
            let exp = exp(-naturalFrequency * dt)
            let displacement = value - target
            
            let f0 = velocity.adding(displacement, scaledBy: naturalFrequency)
            value = target.adding(displacement.adding(f0, scaledBy: dt), scaledBy: exp)
            
            velocity = f0.scaled(by: exp).adding(target - value, scaledBy: naturalFrequency)
        } else {
            // Underdamped
            let decayRate = dampingRatio * naturalFrequency
            let sin = sin(dampedFrequency * dt)
            let cos = cos(dampedFrequency * dt)
            let exp = exp(-decayRate * dt)
            let displacement = value - target
            
            let f0 = velocity.adding(displacement, scaledBy: decayRate)
            let f1 = f0.scaled(by: sin / dampedFrequency).adding(displacement, scaledBy: cos)
            value = target.adding(f1, scaledBy: exp)
            
            let f2 = displacement.scaled(by: -dampedFrequency * sin).adding(f0, scaledBy: cos)
            velocity = f2.scaled(by: exp).adding(target - value, scaledBy: decayRate)
        }

        let valueWithinThreshold = (value - target).magnitudeSquared < epsilon
        let velocityWithinThreshold = velocity.magnitudeSquared < epsilon
        return valueWithinThreshold && velocityWithinThreshold
    }
}
