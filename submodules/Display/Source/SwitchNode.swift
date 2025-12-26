import Foundation
import UIKit
import UIKitRuntimeUtils
import AsyncDisplayKit
import AppBundle

/// A custom switch that mimics the Liquid Glass switch of iOS 26.
private class FallbackSwitch: UIControl {
    
    private struct Geometry {
        let size: CGSize
        let minThumb: CGSize
        let maxThumb: CGSize
        let xOff: CGFloat
        let xOn: CGFloat
        let y: CGFloat
        let borderWidth: CGFloat
        let gooSize: CGSize
        let shadingInsets: UIEdgeInsets
        let rubberBand: RubberBand.Model<CGFloat>
        
        init() {
            size = CGSize(width: 64, height: 28)
            minThumb = CGSize(width: 38, height: 24)
            maxThumb = CGSize(width: 58, height: 38)
            xOff = 2 + 0.5 * minThumb.width
            xOn = size.width - xOff
            y = 0.5 * size.height
            borderWidth = 3
            gooSize = CGSize(width: 60, height: 24)
            shadingInsets = UIEdgeInsets(top: 9, left: 9, bottom: 16, right: 13)
            rubberBand = RubberBand.Model(
                bounds: (xOff, xOn),
                dimension: xOff.addingProduct(-0.5, size.height)
            )
        }
    }
    
    override var intrinsicContentSize: CGSize { geo.size }
    
    var offTintColor: UIColor = .tertiaryLabel
    var onTintColor: UIColor = .systemGreen
    
    private(set) var isOn: Bool = false
    
    private var normalizedPosition: Bool = false {
        didSet {
            guard normalizedPosition != oldValue else { return }
            haptic.selectionChanged()
            shouldToggleOnEndTracking = false
            colorAnimator.target = normalizedPosition ? 1 : 0
            colorAnimator.run()
        }
    }
    
    private let geo = Geometry()
    
    private let thumbView = UIView()
    private let borderView = UIView()
    private let gooView = UIView()
    private let opaqueView = UIView()
    private let shadingView = UIImageView()
    
    private let slideAnimator = DynamicAnimator<CGFloat>()
    private let jiggleAnimator = DynamicAnimator<CGFloat>()
    private let scaleAnimator = DynamicAnimator<CGFloat>()
    private let colorAnimator = DynamicAnimator<CGFloat>()
    
    private var shouldToggleOnEndTracking = false
    private var needsColorUpdate = true
    
    private let haptic = UISelectionFeedbackGenerator()
    
    private var minPressTimer: Timer?
    private var minPressElapsed = false
    private var pendingScaleDown = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.cornerRadius = 0.5 * geo.size.height
        
        // Thumb view
        let blurFilter = CALayer.blur()
        let alphaFilter = CALayer.alphaThreshold()
        let variableBlurFilter = CALayer.variableBlur()
        if let blurFilter, let alphaFilter {
            if let variableBlurFilter {
                thumbView.layer.filters = [blurFilter, alphaFilter, variableBlurFilter]
                
                let blurMask = UIImage(named: "FallbackThumbBlurMask", in: getAppBundle(), compatibleWith: nil)?.cgImage
                thumbView.layer.setValue(blurMask, forKeyPath: "filters.variableBlur.inputMaskImage")
                thumbView.layer.setValue(1, forKeyPath: "filters.variableBlur.inputRadius")
            } else {
                thumbView.layer.filters = [blurFilter, alphaFilter]
            }
            thumbView.layer.setValue(3, forKeyPath: "filters.gaussianBlur.inputRadius")
            thumbView.layer.setValue(0.69, forKeyPath: "filters.alphaThreshold.inputAmount")
        }
        
        thumbView.isUserInteractionEnabled = false
        thumbView.layer.compositingFilter = "copy"
        thumbView.layer.masksToBounds = true
        thumbView.layer.cornerCurve = .circular
        thumbView.layer.allowsEdgeAntialiasing = true
        addSubview(thumbView)
        
        // Border view
        borderView.layer.borderWidth = 2 * geo.borderWidth
        borderView.layer.cornerCurve = .circular
        borderView.layer.allowsEdgeAntialiasing = true
        thumbView.addSubview(borderView)
        
        // Goo view
        gooView.backgroundColor = .black
        gooView.layer.cornerRadius = 0.5 * geo.gooSize.height
        gooView.bounds = CGRect(origin: .zero, size: geo.gooSize)
        thumbView.addSubview(gooView)
        
        // Opaque view
        opaqueView.isUserInteractionEnabled = false
        opaqueView.backgroundColor = .white
        addSubview(opaqueView)
        
        // Shading view
        shadingView.image = UIImage(named: "FallbackThumbShading", in: getAppBundle(), compatibleWith: nil)
        shadingView.layer.compositingFilter = "multiplyBlendMode"
        shadingView.bounds = CGRect(origin: .zero, size: shadingView.intrinsicContentSize)
        shadingView.layer.anchorPoint = CGPoint(
            x: geo.shadingInsets.left.addingProduct(0.5, geo.maxThumb.width) / shadingView.bounds.width,
            y: geo.shadingInsets.top.addingProduct(0.5, geo.maxThumb.height) / shadingView.bounds.height
        )
        addSubview(shadingView)
        
        // Slide animator
        slideAnimator.model = Spring(response: 0.4, dampingRatio: 0.75)
        slideAnimator.value = geo.xOff
        slideAnimator.onValueChanged { [unowned self] update in
            jiggleAnimator.target = .lerp(update.velocity / 250, 1, 1.1)
            jiggleAnimator.run()
            let normalized: CGFloat = .normalize(update.new, geo.xOff, geo.xOn)
            normalizedPosition = normalized > 0.5
            setNeedsLayout()
        }
        
        // Jiggle animator
        jiggleAnimator.model = Spring(response: 0.5, dampingRatio: 0.4)
        jiggleAnimator.value = 1
        jiggleAnimator.onValueChanged { [unowned self] _ in
            setNeedsLayout()
        }
        
        // Scale animator
        set(scaled: false, animated: false)
        scaleAnimator.onValueChanged { [unowned self] _ in
            setNeedsLayout()
        }
        
        // Color animator
        colorAnimator.model = Spring(response: 0.5, dampingRatio: 0.75)
        colorAnimator.value = 0
        colorAnimator.onValueChanged { [unowned self] _ in
            needsColorUpdate = true
            setNeedsLayout()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        let thumbSize: CGSize = .lerp(scaleAnimator.value, geo.minThumb, geo.maxThumb)
        let thumbCenter = CGPoint(x: slideAnimator.value, y: geo.y)
        let thumbRadius = 0.5 * thumbSize.height
        
        let jiggleTransform = CGAffineTransform(
            scaleX: jiggleAnimator.value,
            y: 1 / jiggleAnimator.value
        )
        
        // Thumb view
        thumbView.layer.cornerRadius = thumbRadius
        thumbView.bounds = CGRect(origin: .zero, size: thumbSize)
        thumbView.center = thumbCenter
        thumbView.transform = jiggleTransform
        
        // Border view
        borderView.layer.cornerRadius = 0.5 * borderView.bounds.height
        borderView.frame = thumbView.bounds.insetBy(dx: -geo.borderWidth, dy: -geo.borderWidth)
        
        // Goo view
        gooView.center = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: thumbView)
        
        // Opaque view
        opaqueView.layer.cornerRadius = thumbRadius
        opaqueView.bounds = CGRect(origin: .zero, size: thumbSize)
        opaqueView.center = thumbCenter
        opaqueView.alpha = 1 - scaleAnimator.value
        
        // Shading view
        shadingView.transform = CGAffineTransform(
            scaleX: (thumbSize.width / geo.maxThumb.width) * jiggleAnimator.value,
            y: (thumbSize.height / geo.maxThumb.height) / jiggleAnimator.value
        )
        shadingView.center = thumbCenter
        shadingView.alpha = scaleAnimator.value
        
        // Color update
        if needsColorUpdate {
            let c: UIColor = blend(colorAnimator.value, offTintColor, onTintColor)
            backgroundColor = c
            thumbView.layer.setValue(c.cgColor, forKeyPath: "filters.alphaThreshold.inputColor")
            needsColorUpdate = false
        }
        
        CATransaction.commit()
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            needsColorUpdate = true
            setNeedsLayout()
        }
    }
    
    func setOn(_ value: Bool, animated: Bool) {
        isOn = value
        slideAnimator.target = value ? geo.xOn : geo.xOff
        if animated {
            slideAnimator.run()
        } else {
            slideAnimator.stop(at: .target)
        }
    }
    
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
    
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        startMinPressWindow()
        set(scaled: true, animated: true)
        shouldToggleOnEndTracking = true
        slideAnimator.target = slideAnimator.value
        return super.beginTracking(touch, with: event)
    }
    
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let dx = touch.location(in: self).x - touch.previousLocation(in: self).x
        var unbanded = geo.rubberBand.unband(value: slideAnimator.target)
        unbanded += dx
        slideAnimator.target = geo.rubberBand.band(value: unbanded)
        slideAnimator.run()
        return super.continueTracking(touch, with: event)
    }
    
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        queueOrRunScaleDown()
        slideToEndValueAfterTracking()
        super.endTracking(touch, with: event)
    }
    
    override func cancelTracking(with event: UIEvent?) {
        queueOrRunScaleDown()
        slideToEndValueAfterTracking()
        super.cancelTracking(with: event)
    }
    
    private func slideToEndValueAfterTracking() {
        let endValue: Bool
        if shouldToggleOnEndTracking {
            endValue = !isOn
        } else {
            let v = slideAnimator.value
            endValue = abs(v - geo.xOn) < abs(v - geo.xOff)
        }
        if endValue != isOn {
            isOn = endValue
            sendActions(for: .valueChanged)
        }
        slideAnimator.target = endValue ? geo.xOn : geo.xOff
        slideAnimator.run()
    }
    
    private func startMinPressWindow() {
        minPressTimer?.invalidate()
        minPressElapsed = false
        pendingScaleDown = false
        
        minPressTimer = .scheduledTimer(
            withTimeInterval: 0.2,
            repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            minPressElapsed = true
            if pendingScaleDown {
                pendingScaleDown = false
                set(scaled: false, animated: true)
            }
        }
    }
    
    private func queueOrRunScaleDown() {
        if minPressElapsed {
            set(scaled: false, animated: true)
        } else {
            pendingScaleDown = true
        }
    }
    
    private func set(scaled: Bool, animated: Bool) {
        scaleAnimator.target = scaled ? 1 : 0
        if animated {
            if scaled {
                scaleAnimator.model = Spring(response: 0.2, dampingRatio: 0.6)
            } else {
                scaleAnimator.model = Spring(response: 0.5, dampingRatio: 0.6)
            }
            scaleAnimator.run()
        } else {
            scaleAnimator.stop(at: .target)
        }
    }
    
    private func blend(_ n: CGFloat, _ c0: UIColor, _ c1: UIColor) -> UIColor {
        let resolved0 = c0.resolvedColor(with: traitCollection)
        let resolved1 = c1.resolvedColor(with: traitCollection)
        var (r0, g0, b0, a0): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        resolved0.getRed(&r0, green: &g0, blue: &b0, alpha: &a0)
        resolved1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        let na1 = n * a1
        let a = na1 + a0 * (1 - na1)
        guard a > 0 else { return .clear }
        let r = (r1 * na1 + r0 * a0 * (1 - na1)) / a
        let g = (g1 * na1 + g0 * a0 * (1 - na1)) / a
        let b = (b1 * na1 + b0 * a0 * (1 - na1)) / a
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}

open class SwitchNode: ASControlNode {
    public var valueUpdated: ((Bool) -> Void)?
    
    public var frameColor = UIColor(rgb: 0xe0e0e0) {
        didSet {
            guard isNodeLoaded else { return }
            guard frameColor != oldValue else { return }
            if let s = view as? UISwitch {
                s.tintColor = frameColor
            } else {
                (view as! FallbackSwitch).tintColor = frameColor
            }
        }
    }
    public var handleColor = UIColor(rgb: 0xffffff)
    public var contentColor = UIColor(rgb: 0x42d451) {
        didSet {
            guard isNodeLoaded else { return }
            guard contentColor != oldValue else { return }
            if let s = view as? UISwitch {
                s.onTintColor = contentColor
            } else {
                (view as! FallbackSwitch).onTintColor = contentColor
            }
        }
    }
    
    private var _isOn: Bool = false
    public var isOn: Bool {
        get { _isOn }
        set { setOn(newValue, animated: false) }
    }
    
    override public init() {
        super.init()
        
        setViewBlock { [self] in
            if #available(iOS 26.0, *) {
                let s = UISwitch()
                s.isAccessibilityElement = false
                s.tintColor = frameColor
                s.onTintColor = contentColor
                s.setOn(_isOn, animated: false)
                s.addTarget(self, action: #selector(switchValueChanged), for: .valueChanged)
                return s
            } else {
                let s = FallbackSwitch()
                s.isAccessibilityElement = false
                s.tintColor = frameColor
                s.onTintColor = contentColor
                s.setOn(_isOn, animated: false)
                s.addTarget(self, action: #selector(fallbackSwitchValueChanged), for: .valueChanged)
                return s
            }
        }
    }
    
    public func setOn(_ value: Bool, animated: Bool) {
        guard value != _isOn else { return }
        _isOn = value
        guard isNodeLoaded else { return }
        if let s = view as? UISwitch {
            s.setOn(value, animated: animated)
        } else {
            (view as! FallbackSwitch).setOn(value, animated: animated)
        }
    }
    
    override open func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        return view.intrinsicContentSize
    }
    
    @objc private func switchValueChanged(_ sender: UISwitch) {
        _isOn = sender.isOn
        valueUpdated?(sender.isOn)
    }
    
    @objc private func fallbackSwitchValueChanged(_ sender: FallbackSwitch) {
        _isOn = sender.isOn
        valueUpdated?(sender.isOn)
    }
}
