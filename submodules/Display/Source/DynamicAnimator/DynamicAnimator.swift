import Foundation

public class DynamicAnimator<V: Zeroable>: Animating {

    public enum StopPoint {
        case currentValue
        case target
    }
    
    public struct Update {
        public var old: V
        public var new: V
        public var velocity: V
    }

    internal let engineLink = AnimationEngineLink()

    public var model: any DynamicModeling<V>

    public var target: V = .zero

    private var _value: V = .zero {
        didSet { valueChanged?(Update(old: oldValue, new: _value, velocity: _velocity)) }
    }
    public var value: V {
        get { updateIfNeeded(); return _value }
        set { _value = newValue }
    }

    private var _velocity: V = .zero
    public var velocity: V {
        get { updateIfNeeded(); return _velocity }
        set { _velocity = newValue }
    }

    private var valueChanged: ((Update) -> Void)?

    private var completion: ((V) -> Void)?

    public init(model: any DynamicModeling<V> = NonAnimatedModel()) {
        self.model = model
    }

    public func run() {
        AnimationEngine.shared.startUpdating(animator: self)
    }

    public func stop(at point: StopPoint) {
        engineLink.setWantsToStop()
        _velocity = .zero
        if point == .target {
            _value = target
            completion?(_value)
        }
    }

    public func updateIfNeeded() {
        guard let dt = engineLink.takePendingTimestep() else { return }
        let isFinished = model.update(value: &_value, velocity: &_velocity, target: target, deltaTime: dt)
        if isFinished {
            stop(at: .target)
        }
    }

    public func onValueChanged(_ valueChanged: ((Update) -> Void)?) {
        self.valueChanged = valueChanged
    }

    public func onCompletion(_ completion: ((V) -> Void)?) {
        self.completion = completion
    }
}
