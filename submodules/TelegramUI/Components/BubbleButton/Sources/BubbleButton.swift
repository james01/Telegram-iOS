import UIKit
import Display
import GlassBackgroundComponent
import ComponentFlow

open class BubbleButton: HighlightTrackingButton {
    
    public let glassBackground = GlassBackgroundView()
    public let iconView = GlassBackgroundView.ContentImageView()
    
    private let panRecognizer = UIPanGestureRecognizer()
    
    private let stretchAnimator = DynamicAnimator<Stretch>()
    private let scaleAnimator = DynamicAnimator<CGFloat>()
    
    override public init(frame: CGRect) {
        super.init(frame: .zero)
        
        // Glass background
        glassBackground.isUserInteractionEnabled = false
        addSubview(glassBackground)
        
        // Icon view
        glassBackground.contentView.addSubview(iconView)
        
        // Pan recognizer
        panRecognizer.cancelsTouchesInView = false
        panRecognizer.addTarget(self, action: #selector(handlePan))
        addGestureRecognizer(panRecognizer)
        
        // Scale animator
        set(scaled: false, animated: false)
        scaleAnimator.onValueChanged { [unowned self] _ in setNeedsLayout() }
        
        // Stretch animator
        stretchAnimator.model = Spring(response: 0.4, dampingRatio: 0.4)
        stretchAnimator.target = Stretch(offset: .zero, scale: CGPoint(x: 1, y: 1))
        stretchAnimator.stop(at: .target)
        stretchAnimator.onValueChanged { [unowned self] _ in setNeedsLayout() }
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func update(
        size: CGSize,
        cornerRadius: CGFloat,
        isDark: Bool,
        tintColor: GlassBackgroundView.TintColor,
        isInteractive: Bool,
        transition: ComponentTransition
    ) {
        let rect = CGRect(origin: .zero, size: size)
        transition.setBounds(view: self, bounds: rect)
        
        glassBackground.update(
            size: size,
            cornerRadius: cornerRadius,
            isDark: isDark,
            tintColor: tintColor,
            isInteractive: isInteractive,
            transition: transition
        )
        
        if let image = iconView.image {
            transition.setPosition(view: iconView, position: rect.center)
            transition.setBounds(view: iconView, bounds: CGRect(origin: .zero, size: image.size))
        }
    }
    
    override open func layoutSubviews() {
        transform = stretchAnimator.value.transform(baseScale: scaleAnimator.value)
    }
    
    @objc private func handlePan(_ sender: UIPanGestureRecognizer) {
        let t = sender.translation(in: nil)
        sender.setTranslation(.zero, in: nil)
        
        switch sender.state {
        case .began:
            stretchAnimator.stop(at: .currentValue)
        case .changed:
            var s = stretchAnimator.value
            s.offset.x.addProduct(0.025, t.x)
            s.offset.y.addProduct(0.025, t.y)
            s.scale.x = 1 + abs(0.01 * s.offset.x)
            s.scale.y = 1 + abs(0.01 * s.offset.y)
            s.scale = CGPoint(
                x: s.scale.x / s.scale.y,
                y: s.scale.y / s.scale.x
            )
            stretchAnimator.value = s
        case .ended, .cancelled:
            stretchAnimator.velocity = .zero
            stretchAnimator.run()
        default:
            break
        }
    }
    
    override open func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
    
    override open func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        set(scaled: true, animated: true)
        return super.beginTracking(touch, with: event)
    }
    
    override open func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        set(scaled: false, animated: true)
        super.endTracking(touch, with: event)
    }
    
    override open func cancelTracking(with event: UIEvent?) {
        set(scaled: false, animated: true)
        super.cancelTracking(with: event)
    }
    
    private func set(scaled: Bool, animated: Bool) {
        scaleAnimator.target = scaled ? 1.25 : 1
        if animated {
            if scaled {
                scaleAnimator.model = Spring(response: 0.2, dampingRatio: 0.6)
            } else {
                scaleAnimator.model = Spring(response: 0.4, dampingRatio: 0.4)
            }
            scaleAnimator.run()
        } else {
            scaleAnimator.stop(at: .target)
        }
    }
}

// MARK: TransformState

extension BubbleButton {
    private struct Stretch: VectorLike, RubberBandable {
        var offset: CGPoint
        var scale: CGPoint
        
        var magnitudeSquared: Double {
            return offset.magnitudeSquared
        }
        
        static var zero: Stretch {
            return Stretch(
                offset: .zero,
                scale: .zero
            )
        }
        
        func scaled(by rhs: Double) -> Stretch {
            return Stretch(
                offset: offset.scaled(by: rhs),
                scale: scale.scaled(by: rhs)
            )
        }
        
        func memberwise(_ rhs: Stretch, _ operation: (Double, Double) -> Double) -> Stretch {
            return Stretch(
                offset: offset.memberwise(rhs.offset, operation),
                scale: scale.memberwise(rhs.scale, operation)
            )
        }
        
        func transform(baseScale: CGFloat) -> CGAffineTransform {
            return CGAffineTransform(scaleX: baseScale, y: baseScale)
                .translatedBy(x: offset.x, y: offset.y)
                .scaledBy(x: scale.x, y: scale.y)
        }
    }
}
