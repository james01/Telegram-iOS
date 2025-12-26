import Foundation
import UIKit
import Display
import AsyncDisplayKit
import TelegramPresentationData
import LegacyComponents
import ComponentFlow
import AppBundle

/// A custom slider that mimics the Liquid Glass slider of iOS 26.
private class FallbackSlider: UIControl, UIGestureRecognizerDelegate {
    
    enum Mode {
        case continuous
        case discrete(Int)
    }
    
    private struct Geometry {
        let trackHeight: CGFloat
        let minThumb: CGSize
        let maxThumb: CGSize
        let shadingInsets: UIEdgeInsets
        let borderWidth: CGFloat
        let touchPadding: UIEdgeInsets
        let rubberBand: RubberBand.Model<CGFloat>
        
        init() {
            trackHeight = 6
            minThumb = CGSize(width: 38, height: 24)
            maxThumb = CGSize(width: 58, height: 38)
            shadingInsets = UIEdgeInsets(top: 9, left: 9, bottom: 16, right: 13)
            borderWidth = trackHeight
            touchPadding = UIEdgeInsets(top: -6, left: -6, bottom: -6, right: -6)
            rubberBand = RubberBand.Model(
                bounds: (0, 1),
                dimension: 0.1
            )
        }
    }
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: 34)
    }
    
    var mode: Mode = .continuous {
        didSet {
            adjustTargetForMode()
            slideAnimator.stop(at: .target)
            updateValue()
            switch mode {
            case .continuous:
                notchView.isHidden = true
                notchView.count = 0
            case .discrete(let valueCount):
                notchView.isHidden = false
                notchView.count = valueCount
            }
        }
    }
    
    var minimumValue: Double = 0 {
        didSet { updateValue() }
    }
    
    var maximumValue: Double = 1 {
        didSet { updateValue() }
    }
    
    var trackBackgroundColor: UIColor {
        get { trackView.fillColor }
        set { trackView.fillColor = newValue }
    }
    
    var trackForegroundColor: UIColor {
        get { colorView.fillColor }
        set { colorView.fillColor = newValue }
    }
    
    private(set) var value: Double = 0
    
    private let geo = Geometry()
    
    private let notchView = NotchView()
    private let trackView = TrackView()
    private let colorView = TrackView()
    private let opaqueView = UIView()
    private let shadingView = UIImageView()
    
    private let panRecognizer = UIPanGestureRecognizer()
    
    private let slideAnimator = DynamicAnimator<CGFloat>()
    private let jiggleAnimator = DynamicAnimator<CGFloat>()
    private let scaleAnimator = DynamicAnimator<CGFloat>()
    
    private var shouldSendActionsOnValueUpdate = false
    
    private var minPressTimer: Timer?
    private var minPressElapsed = false
    private var pendingScaleDown = false
    
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        // Notch view
        notchView.isHidden = true
        addSubview(notchView)
        
        // Track view
        addSubview(trackView)
        
        // Color view
        addSubview(colorView)
        
        // Opaque view
        opaqueView.isUserInteractionEnabled = false
        opaqueView.backgroundColor = .white
        opaqueView.layer.shadowOffset = CGSize(width: 0, height: 1)
        opaqueView.layer.shadowOpacity = 0.14
        opaqueView.layer.shadowRadius = 5
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
        
        // Pan recognizer
        panRecognizer.addTarget(self, action: #selector(handlePan))
        panRecognizer.delegate = self
        panRecognizer.cancelsTouchesInView = false
        addGestureRecognizer(panRecognizer)
        
        // Slide animator
        slideAnimator.onValueChanged { [unowned self] update in
            let oldValue = value
            updateValue()
            if value != oldValue {
                switch mode {
                case .continuous:
                    if value == minimumValue {
                        haptic.impactOccurred(intensity: 0.5)
                    } else if value == maximumValue {
                        haptic.impactOccurred(intensity: 1)
                    }
                case .discrete:
                    haptic.impactOccurred(
                        intensity: .lerpRange(value, minimumValue, maximumValue, 0.5, 1)
                    )
                }
            }
            if shouldSendActionsOnValueUpdate, value != oldValue {
                sendActions(for: .valueChanged)
            }
            let bandedValue = geo.rubberBand.band(value: update.new)
            let bandedVelocity = geo.rubberBand.band(
                velocity: update.velocity,
                bandedValue: bandedValue
            )
            jiggleAnimator.target = .lerp(bandedVelocity, 1, 1.03)
            jiggleAnimator.run()
            setNeedsLayout()
        }
        
        // Jiggle animator
        jiggleAnimator.model = Spring(response: 0.4, dampingRatio: 0.25)
        jiggleAnimator.value = 1
        jiggleAnimator.onValueChanged { [unowned self] _ in
            setNeedsLayout()
        }
        
        // Scale animator
        set(scaled: false, animated: false)
        scaleAnimator.onValueChanged { [unowned self] _ in
            setNeedsLayout()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        let sliderAmount = geo.rubberBand.band(value: slideAnimator.value)
        
        let xInset = 0.5 * geo.minThumb.width
        let minX = bounds.minX + xInset
        let maxX = bounds.maxX - xInset
        
        let thumbSize: CGSize = .lerp(scaleAnimator.value, geo.minThumb, geo.maxThumb)
        let thumbCenter = CGPoint(
            x: .lerp(sliderAmount, minX, maxX),
            y: bounds.midY
        )
        
        let jiggleTransform = CGAffineTransform(
            scaleX: jiggleAnimator.value,
            y: 1 / jiggleAnimator.value
        )
        
        let borderWidth: CGFloat = .lerp(scaleAnimator.value, 0, geo.borderWidth)
        
        // Track frame
        let trackFrame = stretchedTrackFrame(
            from: CGRect(
                x: bounds.minX,
                y: bounds.midY.addingProduct(-0.5, geo.trackHeight),
                width: bounds.width,
                height: geo.trackHeight
            ),
            sliderAmount: sliderAmount
        )
        
        // Color width
        let colorWidth: CGFloat
        let minColorWidth: CGFloat = 0
        let maxColorWidth: CGFloat = trackFrame.width
        let linearCutoff: CGFloat = 0.02
        
        func linearColorWidth(at value: CGFloat) -> CGFloat {
            return .lerp(value, minX, maxX) - bounds.minX
        }
        
        let edgeColorAmount: CGFloat
        if sliderAmount < linearCutoff {
            let widthAtCutoff = linearColorWidth(at: linearCutoff)
            colorWidth = .clip(
                .lerpRange(sliderAmount, 0, linearCutoff, minColorWidth, widthAtCutoff),
                lower: minColorWidth,
                upper: maxColorWidth
            )
            edgeColorAmount = .clipUnit(.lerpRange(sliderAmount, 0, linearCutoff, 0, 1))
        } else if sliderAmount > 1 - linearCutoff {
            let widthAtCutoff = linearColorWidth(at: 1 - linearCutoff)
            colorWidth = .clip(
                .lerpRange(sliderAmount, 1 - linearCutoff, 1, widthAtCutoff, maxColorWidth),
                lower: minColorWidth,
                upper: maxColorWidth
            )
            edgeColorAmount = 1
        } else {
            colorWidth = linearColorWidth(at: sliderAmount)
            edgeColorAmount = 1
        }
        
        // Notch view
        notchView.horizontalInset = 0.5 * geo.minThumb.width
        notchView.frame = CGRect(
            x: trackFrame.minX,
            y: trackFrame.maxY + 4,
            width: trackFrame.width,
            height: 2 * notchView.dotRadius
        )
        
        // Track view
        trackView.frame = bounds
        trackView.set(
            trackFrame: trackFrame,
            thumbSize: thumbSize,
            thumbCenter: convert(thumbCenter, to: nil),
            thumbTransform: jiggleTransform,
            borderWidth: borderWidth,
            edgeColorAmount: edgeColorAmount
        )
        
        // Color view
        colorView.frame = bounds
        var colorFrame = trackFrame
        colorFrame.size.width = colorWidth
        colorView.set(
            trackFrame: colorFrame,
            thumbSize: thumbSize,
            thumbCenter: convert(thumbCenter, to: nil),
            thumbTransform: jiggleTransform,
            borderWidth: borderWidth,
            edgeColorAmount: edgeColorAmount
        )
        
        // Opaque view
        opaqueView.layer.cornerRadius = 0.5 * thumbSize.height
        opaqueView.bounds = CGRect(origin: .zero, size: thumbSize)
        opaqueView.center = thumbCenter
        opaqueView.transform = jiggleTransform
        opaqueView.alpha = 1 - scaleAnimator.value
        
        // Shading view
        shadingView.transform = CGAffineTransform(
            scaleX: (thumbSize.width / geo.maxThumb.width) * jiggleAnimator.value,
            y: (thumbSize.height / geo.maxThumb.height) / jiggleAnimator.value
        )
        shadingView.center = thumbCenter
        shadingView.alpha = scaleAnimator.value
    }
    
    func setValue(_ value: Double, animated: Bool) {
        self.value = value
        shouldSendActionsOnValueUpdate = false
        slideAnimator.target = .normalize(value, minimumValue, maximumValue)
        if animated {
            slideAnimator.model = Spring(response: 0.5, dampingRatio: 0.75)
            slideAnimator.run()
        } else {
            slideAnimator.stop(at: .target)
        }
    }
    
    private func updateValue() {
        var val: CGFloat = .lerp(slideAnimator.value, minimumValue, maximumValue)
        if case .discrete(let valueCount) = mode {
            let step = (maximumValue - minimumValue) / CGFloat(valueCount - 1)
            val = round(val / step) * step
        }
        value = .clip(val, lower: minimumValue, upper: maximumValue)
    }
    
    private func adjustTargetForMode() {
        if case .discrete(let valueCount) = mode {
            let step = 1 / CGFloat(valueCount - 1)
            slideAnimator.target = round(slideAnimator.target / step) * step
        }
    }
    
    @objc private func handlePan(_ sender: UIPanGestureRecognizer) {
        let t = sender.translation(in: self)
        let v = sender.velocity(in: self)
        sender.setTranslation(.zero, in: self)
        
        shouldSendActionsOnValueUpdate = true
        
        switch sender.state {
        case .began:
            slideAnimator.stop(at: .currentValue)
            slideAnimator.model = Spring(response: 0.05, dampingRatio: 1)
        case .changed:
            let dx = t.x / bounds.width
            slideAnimator.target += dx
            slideAnimator.run()
        case .ended, .cancelled:
            finishSliding(with: v.x / bounds.width)
        default:
            break
        }
    }
    
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panRecognizer {
            return true
        } else {
            return false
        }
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === panRecognizer else { return true }
        return shouldBeginTracking(touch: touch)
    }
    
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        if shouldBeginTracking(touch: touch) {
            startMinPressWindow()
            set(scaled: true, animated: true)
            return true
        } else {
            return false
        }
    }
    
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        queueOrRunScaleDown()
        super.endTracking(touch, with: event)
    }
    
    override func cancelTracking(with event: UIEvent?) {
        queueOrRunScaleDown()
        super.cancelTracking(with: event)
    }
    
    private func shouldBeginTracking(touch: UITouch) -> Bool {
        let location = touch.location(in: opaqueView)
        let touchIsInThumb = opaqueView.bounds.inset(by: geo.touchPadding).contains(location)
        return touchIsInThumb
    }
    
    private func finishSliding(with velocity: CGFloat = 0) {
        slideAnimator.model = Spring(response: 0.5, dampingRatio: 1)
        slideAnimator.velocity = velocity
        let target: CGFloat = .project(
            value: slideAnimator.value,
            velocity: velocity,
            decelerationRate: 0.99
        )
        slideAnimator.target = .clipUnit(target)
        adjustTargetForMode()
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
                scaleAnimator.model = Spring(response: 0.5, dampingRatio: 0.75)
            }
            scaleAnimator.run()
        } else {
            scaleAnimator.stop(at: .target)
        }
    }
    
    private func stretchedTrackFrame(from base: CGRect, sliderAmount: CGFloat) -> CGRect {
        let overshoot: CGFloat
        let minX: CGFloat
        let maxX: CGFloat
        
        if sliderAmount < 0 {
            overshoot = -sliderAmount
            minX = base.minX.addingProduct(-overshoot, base.width)
            maxX = base.maxX.addingProduct(-0.25 * overshoot, base.width)
        } else if sliderAmount > 1 {
            overshoot = sliderAmount - 1
            minX = base.minX.addingProduct(0.25 * overshoot, base.width)
            maxX = base.maxX.addingProduct(overshoot, base.width)
        } else {
            return base
        }
        
        let yScale: CGFloat = .lerpRange(overshoot, 0, 0.1, 1, 3)
        let height = base.height / yScale
        
        return CGRect(
            x: minX,
            y: base.midY.addingProduct(-0.5, height),
            width: maxX - minX,
            height: height
        )
    }
}


extension FallbackSlider {
    private class NotchView: UIView {
        var count: Int = 0 {
            didSet {
                guard count != oldValue else { return }
                setNeedsDisplay()
            }
            
        }
        var horizontalInset: CGFloat = 0 {
            didSet {
                guard horizontalInset != oldValue else { return }
                setNeedsDisplay()
            }
        }
        
        var dotRadius: CGFloat = 1.5 {
            didSet {
                guard dotRadius != oldValue else { return }
                setNeedsDisplay()
            }
        }
        
        var color: UIColor = .opaqueSeparator {
            didSet {
                guard color != oldValue else { return }
                setNeedsDisplay()
            }
        }
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            
            isOpaque = false
            isUserInteractionEnabled = false
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func draw(_ rect: CGRect) {
            guard let ctx = UIGraphicsGetCurrentContext(), count > 0 else { return }
            ctx.setFillColor(color.cgColor)

            let available = max(rect.width.addingProduct(-2, horizontalInset), 0)
            let step = count > 1 ? available / CGFloat(count - 1) : 0
            let y = rect.midY

            for i in 0..<count {
                let x = horizontalInset + CGFloat(i) * step
                let dotRect = CGRect(
                    x: x - dotRadius,
                    y: y - dotRadius,
                    width: 2 * dotRadius,
                    height: 2 * dotRadius
                )
                ctx.fillEllipse(in: dotRect)
            }
        }
        
        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
                setNeedsDisplay()
            }
        }
    }
}

extension FallbackSlider {
    private class TrackView: UIView {
        
        var fillColor: UIColor = .black {
            didSet { colorFill.backgroundColor = fillColor.cgColor }
        }
        
        private let trackLayer = CALayer()
        private let gooContainer = CALayer()
        private let gooLayer = CALayer()
        private let borderLayer = CALayer()
        private let colorFill = CALayer()
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            
            let black = CGColor(gray: 0, alpha: 1)
            
            isUserInteractionEnabled = false
            
            // Track layer
            trackLayer.backgroundColor = black
            layer.addSublayer(trackLayer)
            
            // Goo container
            gooContainer.masksToBounds = true
            gooContainer.cornerCurve = .circular
            gooContainer.allowsEdgeAntialiasing = true
            layer.addSublayer(gooContainer)
            
            let blurFilter = CALayer.blur()
            let alphaFilter = CALayer.alphaThreshold()
            let variableBlurFilter = CALayer.variableBlur()
            if let blurFilter, let alphaFilter {
                if let variableBlurFilter {
                    gooContainer.filters = [blurFilter, alphaFilter, variableBlurFilter]
                    
                    let blurMask = UIImage(named: "FallbackThumbBlurMask", in: getAppBundle(), compatibleWith: nil)?.cgImage
                    gooContainer.setValue(blurMask, forKeyPath: "filters.variableBlur.inputMaskImage")
                    gooContainer.setValue(0.5, forKeyPath: "filters.variableBlur.inputRadius")
                } else {
                    gooContainer.filters = [blurFilter, alphaFilter]
                }
                gooContainer.setValue(0.5, forKeyPath: "filters.alphaThreshold.inputAmount")
                gooContainer.setValue(black, forKeyPath: "filters.alphaThreshold.inputColor")
            }
            
            // Goo layer
            gooLayer.backgroundColor = black
            gooContainer.addSublayer(gooLayer)
            
            // Border layer
            borderLayer.borderColor = black
            borderLayer.cornerCurve = .circular
            borderLayer.allowsEdgeAntialiasing = true
            gooContainer.addSublayer(borderLayer)
            
            // Color fill
            colorFill.backgroundColor = fillColor.cgColor
            colorFill.compositingFilter = "sourceIn"
            layer.addSublayer(colorFill)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func set(
            trackFrame: CGRect,
            thumbSize: CGSize,
            thumbCenter: CGPoint,
            thumbTransform: CGAffineTransform,
            borderWidth: CGFloat,
            edgeColorAmount: CGFloat
        ) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            
            // Track layer
            trackLayer.cornerRadius = 0.5 * trackFrame.height
            trackLayer.frame = trackFrame
            
            // Goo container
            gooContainer.cornerRadius = 0.5 * thumbSize.height
            gooContainer.bounds = CGRect(origin: .zero, size: thumbSize)
            gooContainer.position = convert(thumbCenter, from: nil)
            gooContainer.setAffineTransform(thumbTransform)
            
            let blurRadius = 0.5 * trackFrame.height
            gooContainer.setValue(blurRadius, forKeyPath: "filters.gaussianBlur.inputRadius")
            
            // Goo layer
            gooLayer.cornerRadius = 0.5 * trackFrame.height
            gooLayer.frame = layer.convert(trackFrame, to: gooContainer)
            
            // Border layer
            borderLayer.borderWidth = borderWidth
            let borderFrame = gooContainer.bounds.insetBy(
                dx: borderWidth * .lerp(edgeColorAmount, -1.2, -1),
                dy: borderWidth * .lerp(edgeColorAmount, -1.2, -1.1)
            )
            borderLayer.frame = borderFrame
            borderLayer.cornerRadius = 0.5 * borderFrame.height
            
            // Color fill
            colorFill.frame = trackFrame.union(gooContainer.frame)
            
            CATransaction.commit()
        }
    }
}

public final class SliderComponent: Component {
    public final class Discrete: Equatable {
        public let valueCount: Int
        public let value: Int
        public let minValue: Int?
        public let markPositions: Bool
        public let valueUpdated: (Int) -> Void
        
        public init(valueCount: Int, value: Int, minValue: Int? = nil, markPositions: Bool, valueUpdated: @escaping (Int) -> Void) {
            self.valueCount = valueCount
            self.value = value
            self.minValue = minValue
            self.markPositions = markPositions
            self.valueUpdated = valueUpdated
        }
        
        public static func ==(lhs: Discrete, rhs: Discrete) -> Bool {
            if lhs.valueCount != rhs.valueCount {
                return false
            }
            if lhs.value != rhs.value {
                return false
            }
            if lhs.minValue != rhs.minValue {
                return false
            }
            if lhs.markPositions != rhs.markPositions {
                return false
            }
            return true
        }
    }
    
    public final class Continuous: Equatable {
        public let value: CGFloat
        public let minValue: CGFloat?
        public let valueUpdated: (CGFloat) -> Void
        
        public init(value: CGFloat, minValue: CGFloat? = nil, valueUpdated: @escaping (CGFloat) -> Void) {
            self.value = value
            self.minValue = minValue
            self.valueUpdated = valueUpdated
        }
        
        public static func ==(lhs: Continuous, rhs: Continuous) -> Bool {
            if lhs.value != rhs.value {
                return false
            }
            if lhs.minValue != rhs.minValue {
                return false
            }
            return true
        }
    }
    
    public enum Content: Equatable {
        case discrete(Discrete)
        case continuous(Continuous)
    }
    
    public let content: Content
    public let useNative: Bool
    public let trackBackgroundColor: UIColor
    public let trackForegroundColor: UIColor
    public let minTrackForegroundColor: UIColor?
    public let knobSize: CGFloat?
    public let knobColor: UIColor?
    public let isTrackingUpdated: ((Bool) -> Void)?
    
    public init(
        content: Content,
        useNative: Bool = false,
        trackBackgroundColor: UIColor,
        trackForegroundColor: UIColor,
        minTrackForegroundColor: UIColor? = nil,
        knobSize: CGFloat? = nil,
        knobColor: UIColor? = nil,
        isTrackingUpdated: ((Bool) -> Void)? = nil
    ) {
        self.content = content
        self.useNative = useNative
        self.trackBackgroundColor = trackBackgroundColor
        self.trackForegroundColor = trackForegroundColor
        self.minTrackForegroundColor = minTrackForegroundColor
        self.knobSize = knobSize
        self.knobColor = knobColor
        self.isTrackingUpdated = isTrackingUpdated
    }
    
    public static func ==(lhs: SliderComponent, rhs: SliderComponent) -> Bool {
        if lhs.content != rhs.content {
            return false
        }
        if lhs.trackBackgroundColor != rhs.trackBackgroundColor {
            return false
        }
        if lhs.trackForegroundColor != rhs.trackForegroundColor {
            return false
        }
        if lhs.minTrackForegroundColor != rhs.minTrackForegroundColor {
            return false
        }
        if lhs.knobSize != rhs.knobSize {
            return false
        }
        if lhs.knobColor != rhs.knobColor {
            return false
        }
        return true
    }
    
    public final class View: UIView {
        private var nativeSlider: UISlider?
        private var fallbackSlider: FallbackSlider?
        
        private var component: SliderComponent?
        private weak var state: EmptyComponentState?
        
        public var hitTestTarget: UIView? {
//            return self.sliderView
            return nil
        }
                
        public func cancelGestures() {
//            if let sliderView = self.sliderView, let gestureRecognizers = sliderView.gestureRecognizers {
//                for gestureRecognizer in gestureRecognizers {
//                    if gestureRecognizer.isEnabled {
//                        gestureRecognizer.isEnabled = false
//                        gestureRecognizer.isEnabled = true
//                    }
//                }
//            }
        }
        
        func update(
            component: SliderComponent,
            availableSize: CGSize,
            state: EmptyComponentState,
            environment: Environment<Empty>,
            transition: ComponentTransition
        ) -> CGSize {
            self.component = component
            self.state = state
            
            let size = CGSize(width: availableSize.width, height: 44.0)
            
            if #available(iOS 26.0, *), component.useNative {
                let slider: UISlider
                if let nativeSlider {
                    slider = nativeSlider
                } else {
                    slider = UISlider()
                    slider.disablesInteractiveTransitionGestureRecognizer = true
                    slider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
                    slider.layer.allowsGroupOpacity = true
                    
                    switch component.content {
                    case let .continuous(continuous):
                        slider.minimumValue = Float(continuous.minValue ?? 0.0)
                        slider.maximumValue = 1.0
                    case let .discrete(discrete):
                        slider.minimumValue = 0.0
                        slider.maximumValue = Float(discrete.valueCount - 1)
                        slider.trackConfiguration = .init(numberOfTicks: discrete.valueCount)
                    }
                    
                    addSubview(slider)
                    nativeSlider = slider
                }
                switch component.content {
                case let .continuous(continuous):
                    slider.value = Float(continuous.value)
                case let .discrete(discrete):
                    slider.value = Float(discrete.value)
                }
                slider.minimumTrackTintColor = component.trackForegroundColor
                slider.maximumTrackTintColor = component.trackBackgroundColor
                
                transition.setFrame(view: slider, frame: CGRect(origin: .zero, size: CGSize(width: availableSize.width, height: 44.0)))
            } else {
                let slider: FallbackSlider
                if let fallbackSlider {
                    slider = fallbackSlider
                } else {
                    slider = FallbackSlider()
                    slider.disablesInteractiveTransitionGestureRecognizer = true
                    slider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
                    slider.layer.allowsGroupOpacity = true
                    
                    switch component.content {
                    case let .continuous(continuous):
                        slider.mode = .continuous
                        slider.minimumValue = continuous.minValue ?? 0.0
                        slider.maximumValue = 1.0
                        slider.setValue(continuous.value, animated: false)
                    case let .discrete(discrete):
                        slider.mode = .discrete(discrete.valueCount)
                        slider.minimumValue = 0.0
                        slider.maximumValue = Double(discrete.valueCount - 1)
                        slider.setValue(Double(discrete.value), animated: false)
                    }
                    
                    addSubview(slider)
                    fallbackSlider = slider
                }
                slider.trackForegroundColor = component.trackForegroundColor
                slider.trackBackgroundColor = component.trackBackgroundColor
//                slider.minimumTrackTintColor = component.trackForegroundColor
//                slider.maximumTrackTintColor = component.trackBackgroundColor
                
                transition.setFrame(view: slider, frame: CGRect(origin: .zero, size: CGSize(width: availableSize.width, height: 44.0)))
            }
            
            return size
        }
        
        @objc private func sliderValueChanged() {
            guard let component else { return }
            let floatValue: CGFloat
            if let fallbackSlider {
                floatValue = fallbackSlider.value
            } else if let nativeSlider {
                floatValue = CGFloat(nativeSlider.value)
            } else {
                return
            }
            switch component.content {
            case let .discrete(discrete):
                discrete.valueUpdated(Int(floatValue))
            case let .continuous(continuous):
                continuous.valueUpdated(floatValue)
            }
        }
    }

    public func makeView() -> View {
        return View()
    }
    
    public func update(
        view: View,
        availableSize: CGSize,
        state: EmptyComponentState,
        environment: Environment<Empty>,
        transition: ComponentTransition
    ) -> CGSize {
        return view.update(
            component: self,
            availableSize: availableSize,
            state: state,
            environment: environment,
            transition: transition
        )
    }
}
