import Foundation
import UIKit
import Display
import TelegramPresentationData
import ComponentFlow
import ComponentDisplayAdapters
import GlassBackgroundComponent
import MultilineTextComponent
import LottieComponent
import UIKitRuntimeUtils
import BundleIconComponent
import TextBadgeComponent
import LiquidLens
import AppBundle

private final class TabSelectionRecognizer: UIGestureRecognizer {
    private var initialLocation: CGPoint?
    private var currentLocation: CGPoint?
    
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        
        self.delaysTouchesBegan = false
        self.delaysTouchesEnded = false
    }
    
    override func reset() {
        super.reset()
        
        self.initialLocation = nil
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        
        if self.initialLocation == nil {
            self.initialLocation = touches.first?.location(in: self.view)
        }
        self.currentLocation = self.initialLocation
        
        self.state = .began
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        
        self.state = .ended
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        
        self.state = .cancelled
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        
        self.currentLocation = touches.first?.location(in: self.view)
        
        self.state = .changed
    }
    
    func translation(in: UIView?) -> CGPoint {
        if let initialLocation = self.initialLocation, let currentLocation = self.currentLocation {
            return CGPoint(x: currentLocation.x - initialLocation.x, y: currentLocation.y - initialLocation.y)
        }
        return CGPoint()
    }
}

public final class TabBarSearchView: UIView {
    private let backgroundView: GlassBackgroundView
    private let iconView: GlassBackgroundView.ContentImageView
    
    override public init(frame: CGRect) {
        self.backgroundView = GlassBackgroundView()
        self.iconView = GlassBackgroundView.ContentImageView()

        super.init(frame: frame)

        self.addSubview(self.backgroundView)
        self.backgroundView.contentView.addSubview(self.iconView)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(size: CGSize, isDark: Bool, tintColor: GlassBackgroundView.TintColor, iconColor: UIColor, transition: ComponentTransition) { 
        transition.setFrame(view: self.backgroundView, frame: CGRect(origin: CGPoint(), size: size))
        self.backgroundView.update(size: size, cornerRadius: size.height * 0.5, isDark: isDark, tintColor: tintColor, transition: transition)

        if self.iconView.image == nil {
            self.iconView.image = UIImage(bundleImageName: "Navigation/Search")?.withRenderingMode(.alwaysTemplate)
        }
        self.iconView.tintColor = iconColor
        
        if let image = self.iconView.image {
            transition.setFrame(view: self.iconView, frame: CGRect(origin: CGPoint(x: floor((size.width - image.size.width) * 0.5), y: floor((size.height - image.size.height) * 0.5)), size: image.size))
        }
    }
}

private extension CGRect {
    init(center: CGPoint, size: CGSize) {
        let origin = CGPoint(
            x: center.x.addingProduct(-0.5, size.width),
            y: center.y.addingProduct(-0.5, size.height)
        )
        self.init(origin: origin, size: size)
    }
}

/// A custom tab bar that mimics the Liquid Glass tab bar of iOS 26.
public final class FallbackTabBar: UIControl, UIGestureRecognizerDelegate {
    
    private struct Geometry {
        let paletteHeight: CGFloat
        let idealItemWidth: CGFloat
        let lensInset: CGFloat
        let itemInset: CGFloat
        let itemOverlap: CGFloat
        let borderBlur: CGFloat
        
        var availableWidth: CGFloat = 0 {
            didSet {
                guard availableWidth != oldValue else { return }
                update()
            }
        }
        
        var numItems: CGFloat = 0 {
            didSet {
                guard numItems != oldValue else { return }
                update()
            }
        }
        private(set) var paletteBounds: CGRect = .zero
        private(set) var itemSize: CGSize = .zero
        private(set) var rubberBand = RubberBand.Model<CGFloat>()
        
        var spaceBetweenCenters: CGFloat {
            return itemSize.width - itemOverlap
        }
        
        init() {
            paletteHeight = 62
            idealItemWidth = 96
            lensInset = 4
            itemInset = 4
            itemOverlap = 8
            borderBlur = 8
        }
        
        func centerXInPalette(at index: CGFloat) -> CGFloat {
            var x = paletteBounds.minX + itemInset
            x.addProduct(0.5, itemSize.width)
            x.addProduct(index, spaceBetweenCenters)
            return x
        }
            
        private mutating func update() {
            // Update palette bounds
            let paletteSize = CGSize(
                width: min(availableWidth, numItems * idealItemWidth),
                height: paletteHeight
            )
            paletteBounds = CGRect(origin: .zero, size: paletteSize)
            
            // Update item size
            let available = paletteBounds.insetBy(dx: itemInset, dy: itemInset)
            itemSize = CGSize(
                width: available.width.addingProduct(numItems - 1, itemOverlap) / numItems,
                height: available.height
            )
            
            // Update rubber band
            rubberBand.bounds = (0, numItems - 1)
            rubberBand.dimension = 0.1
        }
    }
    
    private var items: [TabBarComponent.Item] = []
    
    private(set) var selectedTabIndex: Int = 0 {
        didSet {
            if selectedTabIndex != oldValue || shouldFireWhenSelectionDidNotChange {
                didSelectTab(at: selectedTabIndex)
            }
        }
    }
    
    private var shouldFireWhenSelectionDidNotChange = true
    
    private var itemViews: [ItemView] = []
    private var gooItemViews: [ItemView] = []
    private var gooSolidItemViews: [ItemView] = []
    private var reusableItemViews: [ItemView] = []
    
    private let paletteView = GlassBackgroundView()
    private let knockoutLayer = CALayer()
    private let lensView = UIView()
    private let lensPaletteView = GlassBackgroundView()
    private let gooContainer = UIView()
    private let borderLayer = CALayer()
    private let lensFillView = UIView()
    private let lensShadingView = LensShadingView()
    
    private let contextGestureSourceView = ContextControllerSourceView()
    private var itemWithActiveContextGesture: Int?
    
    private var geo = Geometry()
    
    private var component: TabBarComponent?
    
    private let panRecognizer = UIPanGestureRecognizer()
    
    private let slideAnimator = DynamicAnimator<CGFloat>()
    private let jiggleAnimator = DynamicAnimator<CGFloat>()
    private let scaleAnimator = DynamicAnimator<CGFloat>()
    
    private var minPressTimer: Timer?
    private var minPressElapsed = false
    private var pendingScaleDown = false
    
    override public var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: geo.paletteHeight)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        let blurFilter = CALayer.blur()
        let variableBlurFilter = CALayer.variableBlur()
        let alphaFilter = CALayer.alphaThreshold()
        if let blurFilter, let variableBlurFilter, let alphaFilter {
            
            let blurMask = UIImage(named: "Components/TabBar/BlurMask")?.cgImage
            let blurMaskTight = UIImage(named: "Components/TabBar/BlurMaskTight")?.cgImage
            
            borderLayer.filters = [blurFilter]
            borderLayer.setValue(geo.borderBlur, forKeyPath: "filters.gaussianBlur.inputRadius")
            
            gooContainer.layer.filters = [variableBlurFilter, alphaFilter]
            gooContainer.layer.setValue(blurMaskTight, forKeyPath: "filters.variableBlur.inputMaskImage")
            gooContainer.layer.setValue(2, forKeyPath: "filters.variableBlur.inputRadius")
            gooContainer.layer.setValue(0.5, forKeyPath: "filters.alphaThreshold.inputAmount")
            
            lensView.layer.filters = [variableBlurFilter]
            lensView.layer.setValue(blurMask, forKeyPath: "filters.variableBlur.inputMaskImage")
            lensView.layer.setValue(1, forKeyPath: "filters.variableBlur.inputRadius")
        }
        
        // Palette view
        paletteView.isUserInteractionEnabled = false
        addSubview(paletteView)
        
        // Knockout layer
        knockoutLayer.masksToBounds = true
        knockoutLayer.compositingFilter = "sourceIn"
        layer.addSublayer(knockoutLayer)
        
        // Lens view
        lensView.isUserInteractionEnabled = false
        lensView.layer.masksToBounds = true
        addSubview(lensView)
        
        // Lens palette view
        lensPaletteView.isUserInteractionEnabled = false
        lensView.addSubview(lensPaletteView)
        
        // Goo container
        lensView.addSubview(gooContainer)

        // Border layer
        gooContainer.layer.addSublayer(borderLayer)
        
        // Lens fill view
        lensView.addSubview(lensFillView)
        
        // Lens shading view
        addSubview(lensShadingView)
        
        // Context gesture source view
        contextGestureSourceView.isGestureEnabled = true
        contextGestureSourceView.customActivationProgress = { _, _ in }
        contextGestureSourceView.isUserInteractionEnabled = false
        addSubview(contextGestureSourceView)
        
        if let gesture = contextGestureSourceView.contextGesture {
            addGestureRecognizer(gesture)
        }
        
        contextGestureSourceView.shouldBegin = { [weak self] point in
            guard let self else { return false }
            if let index = selectedIndex(at: point), items.indices.contains(index) {
                if items[index].contextAction != nil {
                    itemWithActiveContextGesture = index
                    return true
                }
            }
            return false
        }
        
        contextGestureSourceView.activated = { [weak self] gesture, _ in
            guard let self, let index = itemWithActiveContextGesture else {
                gesture.cancel()
                return
            }
            
            cancelTracking(with: nil)
            
            // Determine which view is currently visible for the item
            let targetView: ItemView
            if index == selectedTabIndex {
                targetView = gooSolidItemViews[index]
            } else {
                targetView = itemViews[index]
            }
            
            if let contextContainer = targetView.contextContainerView {
                items[index].contextAction?(gesture, contextContainer)
            } else {
                gesture.cancel()
            }
        }
        
        // Pan recognizer
        panRecognizer.addTarget(self, action: #selector(handlePan))
        panRecognizer.delegate = self
        panRecognizer.cancelsTouchesInView = false
        addGestureRecognizer(panRecognizer)
        
        // Slide animator
        slideAnimator.value = 0
        slideAnimator.onValueChanged { [unowned self] update in
            jiggleAnimator.target = .lerp(update.velocity, 1, 1.02)
            jiggleAnimator.run()
            setNeedsLayout()
        }
        
        // Jiggle animator
        jiggleAnimator.model = Spring(response: 0.5, dampingRatio: 0.5)
        jiggleAnimator.value = 1
        jiggleAnimator.onValueChanged { [unowned self] _ in
            setNeedsLayout()
        }
        
        // Scale animator
        set(scaled: false, animated: false)
        scaleAnimator.value = 0
        scaleAnimator.onValueChanged { [unowned self] _ in
            setNeedsLayout()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func layoutSubviews() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        geo.numItems = CGFloat(items.count)
        geo.availableWidth = bounds.width
        
        let tx: CGFloat = .lerpRange(slideAnimator.value, 0, CGFloat(items.count - 1), -1, 1) * scaleAnimator.value
        
        let paletteCenter = CGPoint(x: bounds.midX + tx, y: bounds.midY)
        let paletteFrame = CGRect(
            center: paletteCenter,
            size: geo.paletteBounds.size
        )
        
        let centerYInPalette = geo.paletteBounds.midY
        
        let lensOutset: CGFloat = .lerp(scaleAnimator.value, 0, 22)
        let lensBounds = CGRect(origin: .zero, size: CGSize(
            width: (geo.itemSize.width * jiggleAnimator.value) + lensOutset,
            height: (geo.itemSize.height / jiggleAnimator.value) + lensOutset
        ))
        let lensCenter = CGPoint(
            x: paletteFrame.minX + geo.centerXInPalette(at: slideAnimator.value),
            y: paletteFrame.minY + centerYInPalette
        )
        
        let lensPaletteBounds = geo.paletteBounds
        
        if let component {
            let paletteTintColor = GlassBackgroundView.TintColor(
                kind: .panel,
                color: component.theme.chat.inputPanel.inputBackgroundColor.withMultipliedAlpha(0.7)
            )
            
            paletteView.update(
                size: geo.paletteBounds.size,
                cornerRadius: 0.5 * geo.paletteBounds.height,
                isDark: component.theme.overallDarkAppearance,
                tintColor: paletteTintColor,
                transition: .immediate
            )
            
            lensPaletteView.update(
                size: lensPaletteBounds.size,
                cornerRadius: 0.5 * lensPaletteBounds.height,
                isDark: component.theme.overallDarkAppearance,
                tintColor: paletteTintColor,
                transition: .immediate
            )
        }
        
        // Context gesture source view
        contextGestureSourceView.frame = bounds
        
        // Palette view
        let paletteMaxScaleIncrease: CGFloat = 0.04
        let paletteScale: CGFloat = .lerp(scaleAnimator.value, 1, 1 + paletteMaxScaleIncrease)
        paletteView.bounds = geo.paletteBounds
        paletteView.center = paletteCenter
        paletteView.transform = CGAffineTransform(
            scaleX: paletteScale,
            y: paletteScale
        )
        
        // Item views
        for (n, itemView) in itemViews.enumerated() {
            itemView.bounds = CGRect(origin: .zero, size: geo.itemSize)
            itemView.center = CGPoint(
                x: geo.centerXInPalette(at: CGFloat(n)),
                y: centerYInPalette
            )
        }
        
        // Knockout layer
        knockoutLayer.cornerRadius = 0.5 * lensBounds.height
        knockoutLayer.bounds = lensBounds
        knockoutLayer.position = lensCenter
        
        // Lens view
        lensView.layer.cornerRadius = 0.5 * lensBounds.height
        lensView.bounds = lensBounds
        lensView.center = lensCenter
        
        // Lens palette view
        lensPaletteView.bounds = lensPaletteBounds
        lensPaletteView.center = convert(paletteCenter, to: lensView)
        
        // Goo container
        gooContainer.alpha = scaleAnimator.value
        gooContainer.frame = lensBounds
        
        // Border layer
        let borderWidth: CGFloat = 2 * geo.borderBlur
        let borderFrame = lensBounds.insetBy(
            dx: -1.1 * borderWidth,
            dy: -1.1 * borderWidth
        )
        borderLayer.borderWidth = borderWidth
        borderLayer.frame = borderFrame
        borderLayer.cornerRadius = 0.5 * borderFrame.height
        
        // Lens fill view
        lensFillView.alpha = 1 - scaleAnimator.value
        lensFillView.frame = lensBounds
        
        // Lens shading view
        lensShadingView.alpha = scaleAnimator.value
        lensShadingView.layer.cornerRadius = 0.5 * lensBounds.height
        lensShadingView.bounds = lensBounds
        lensShadingView.center = lensCenter
        
        // Goo item views
        let gooItemScale: CGFloat = .lerp(scaleAnimator.value, 1, 1.25)
        let gooItemTransform = CGAffineTransform(
            scaleX: gooItemScale,
            y: gooItemScale
        )
        for (n, gooItemView) in gooItemViews.enumerated() {
            let c = CGPoint(
                x: geo.centerXInPalette(at: CGFloat(n)),
                y: centerYInPalette
            )
            gooItemView.bounds = CGRect(origin: .zero, size: geo.itemSize)
            gooItemView.center = paletteView.convert(c, to: gooContainer)
            gooItemView.transform = gooItemTransform
        }
        
        // Goo solid item views
        for (n, gooSolidItemView) in gooSolidItemViews.enumerated() {
            let c = CGPoint(
                x: geo.centerXInPalette(at: CGFloat(n)),
                y: centerYInPalette
            )
            gooSolidItemView.bounds = CGRect(origin: .zero, size: geo.itemSize)
            gooSolidItemView.center = paletteView.convert(c, to: lensView)
            gooSolidItemView.transform = gooItemTransform
        }
        
        CATransaction.commit()
    }
    
    public func update(
        component: TabBarComponent,
        availableSize: CGSize,
        state: EmptyComponentState,
        environment: Environment<Empty>,
        transition: ComponentTransition
    ) -> CGSize {
        let previousComponent = self.component
        self.component = component
        
        // Update items
        if component.items != previousComponent?.items {
            items = component.items
            
            for itemView in itemViews {
                itemView.removeFromSuperview()
                itemView.prepareForReuse()
            }
            for gooItemView in gooItemViews {
                gooItemView.removeFromSuperview()
                gooItemView.prepareForReuse()
            }
            for gooSolidItemView in gooSolidItemViews {
                gooSolidItemView.removeFromSuperview()
                gooSolidItemView.prepareForReuse()
            }
            reusableItemViews.append(contentsOf: itemViews)
            reusableItemViews.append(contentsOf: gooItemViews)
            reusableItemViews.append(contentsOf: gooSolidItemViews)
            itemViews.removeAll(keepingCapacity: true)
            gooItemViews.removeAll(keepingCapacity: true)
            gooSolidItemViews.removeAll(keepingCapacity: true)
            for item in items {
                let itemView = reusableItemViews.popLast() ?? ItemView()
                itemView.update(item: item, theme: component.theme, isSelected: false)
                paletteView.addSubview(itemView)
                itemViews.append(itemView)
                
                let gooItemView = reusableItemViews.popLast() ?? ItemView()
                gooItemView.update(item: item, theme: component.theme, isSelected: false)
                gooContainer.addSubview(gooItemView)
                gooItemViews.append(gooItemView)
                
                let gooSolidItemView = reusableItemViews.popLast() ?? ItemView()
                gooSolidItemView.update(item: item, theme: component.theme, isSelected: true)
                lensView.addSubview(gooSolidItemView)
                gooSolidItemViews.append(gooSolidItemView)
            }
            
            if let index = component.items.firstIndex(where: { $0.id == component.selectedId }) {
                set(selectedTabIndex: index, animated: false)
            }
        } else {
            for itemView in itemViews {
                itemView.update(item: itemView.item, theme: component.theme, isSelected: false)
            }
            for gooItemView in gooItemViews {
                gooItemView.update(item: gooItemView.item, theme: component.theme, isSelected: false)
            }
            for gooSolidItemView in gooSolidItemViews {
                gooSolidItemView.update(item: gooSolidItemView.item, theme: component.theme, isSelected: true)
            }
        }
        
        // Update colors
        lensFillView.backgroundColor = component.theme.list.itemPrimaryTextColor.withMultipliedAlpha(0.05)
        gooContainer.layer.setValue(component.theme.rootController.tabBar.selectedTextColor.cgColor, forKeyPath: "filters.alphaThreshold.inputColor")
        
        return availableSize
    }
    
    public func set(selectedTabIndex: Int, animated: Bool) {
        self.selectedTabIndex = selectedTabIndex
        slideAnimator.target = CGFloat(selectedTabIndex)
        if animated {
            slideAnimator.model = Spring(response: 0.5, dampingRatio: 0.75)
            slideAnimator.run()
        } else {
            slideAnimator.stop(at: .target)
        }
    }
    
    private func didSelectTab(at index: Int) {
        guard let component else { return }
        guard component.items.indices.contains(index) else { return }
        component.items[index].action(false)
        itemViews[index].playSelectionAnimation()
        gooItemViews[index].isHidden = true
        gooSolidItemViews[index].playSelectionAnimation { [weak self] in
            self?.gooItemViews[index].isHidden = false
        }
    }
    
    @objc private func handlePan(_ sender: UIPanGestureRecognizer) {
        let t = sender.translation(in: self)
        sender.setTranslation(.zero, in: self)
        
        switch sender.state {
        case .began:
            slideAnimator.model = Spring(response: 0.25, dampingRatio: 0.75)
            shouldFireWhenSelectionDidNotChange = false
        case .changed:
            let dx = t.x / geo.spaceBetweenCenters
            geo.rubberBand.modifyAsUnbandedValue(&slideAnimator.target) { target in
                target += dx
            }
            slideAnimator.run()
        case .ended, .cancelled:
            slideAnimator.model = Spring(response: 0.5, dampingRatio: 0.75)
            slideAnimator.target.round()
            slideAnimator.run()
        default:
            break
        }
    }
    
    override public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panRecognizer {
            return true
        } else {
            return false
        }
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === panRecognizer else { return true }
        let location = touch.location(in: paletteView)
        return paletteView.bounds.contains(location)
    }
    
    override public func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let point = touch.location(in: self)
        if let index = selectedIndex(at: point) {
            startMinPressWindow()
            set(scaled: true, animated: true)
            
            shouldFireWhenSelectionDidNotChange = true
            
            slideAnimator.model = Spring(response: 0.5, dampingRatio: 0.75)
            slideAnimator.target = CGFloat(index)
            slideAnimator.run()
            
            return true
        } else {
            return false
        }
    }
    
    override public func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        finishTracking()
        super.endTracking(touch, with: event)
    }
    
    override public func cancelTracking(with event: UIEvent?) {
        finishTracking()
        super.cancelTracking(with: event)
    }
    
    private func finishTracking() {
        queueOrRunScaleDown()
        selectedTabIndex = Int(slideAnimator.target.rounded())
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
                scaleAnimator.model = Spring(response: 0.2, dampingRatio: 0.75)
            } else {
                scaleAnimator.model = Spring(response: 0.4, dampingRatio: 0.75)
            }
            scaleAnimator.run()
        } else {
            scaleAnimator.stop(at: .target)
        }
    }
    
    private func selectedIndex(at point: CGPoint) -> Int? {
        let pointInPalette = convert(point, to: paletteView)
        guard paletteView.bounds.contains(pointInPalette) else { return nil }
        let raw = (pointInPalette.x * CGFloat(items.count) / paletteView.bounds.width) - 0.5
        return .clip(Int(raw.rounded()), lower: 0, upper: items.count - 1)
    }
}

// MARK: LensShadingView

extension FallbackTabBar {
    private class LensShadingView: UIView {
        
        private let gradientLayer = CAGradientLayer()
        private let borderHighlightLayer = CAGradientLayer()
        private let borderMaskLayer = CAShapeLayer()
        
        private var borderStroke: CGFloat = 0 {
            didSet { gradientLayer.borderWidth = borderStroke }
        }
        
        private var borderHighlightBlur: CGFloat = 1 {
            didSet { setNeedsLayout() }
        }
        
        private var borderHighlightSpread: CGFloat = 0 {
            didSet { setNeedsLayout() }
        }
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            
            isUserInteractionEnabled = false
            
            // Shadow
            layer.shadowOffset = CGSize(width: 0, height: 8)
            layer.shadowOpacity = 0.2
            layer.shadowRadius = 8
            
            // Gradient layer
            gradientLayer.masksToBounds = true
            gradientLayer.compositingFilter = "copy"
            gradientLayer.colors = [
                CGColor(gray: 0, alpha: 0.05),
                CGColor(gray: 0, alpha: 0.03)
            ]
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
            gradientLayer.endPoint = CGPoint(x: 0.5, y: 0.5)
            gradientLayer.borderColor = CGColor(gray: 1, alpha: 1)
            gradientLayer.borderWidth = borderStroke
            layer.addSublayer(gradientLayer)
            
            // Border highlight layer
            if let blurFilter = CALayer.blur() {
                borderMaskLayer.filters = [blurFilter]
                borderMaskLayer.setValue(borderHighlightBlur, forKeyPath: "filters.gaussianBlur.inputRadius")
            }
            
            borderHighlightLayer.colors = [
                CGColor(gray: 1, alpha: 1),
                CGColor(gray: 1, alpha: 0),
                CGColor(gray: 1, alpha: 1)
            ]
            borderHighlightLayer.startPoint = CGPoint(x: 0, y: 0)
            borderHighlightLayer.endPoint = CGPoint(x: 1, y: 1)
            
            borderMaskLayer.fillColor = CGColor(gray: 0, alpha: 0)
            borderMaskLayer.strokeColor = CGColor(gray: 0, alpha: 1)
            borderHighlightLayer.mask = borderMaskLayer
            
            gradientLayer.addSublayer(borderHighlightLayer)
            
            updateForTraits()
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func layoutSubviews() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            
            // Shadow
            layer.shadowPath = CGPath(
                roundedRect: bounds,
                cornerWidth: 0.5 * bounds.height,
                cornerHeight: 0.5 * bounds.height,
                transform: nil
            )
            
            // Gradient layer
            gradientLayer.cornerRadius = 0.5 * bounds.height
            gradientLayer.frame = bounds
            
            // Border highlight layer
            let inset = -(borderHighlightBlur + borderHighlightSpread)
            let borderHighlightFrame = gradientLayer.bounds.insetBy(dx: inset, dy: inset)
            borderHighlightLayer.frame = borderHighlightFrame
            
            // Border mask layer
            borderMaskLayer.frame = borderHighlightLayer.bounds
            let borderWidth = 2 * (borderHighlightBlur + borderHighlightSpread)
            borderMaskLayer.lineWidth = borderWidth
            
            // Inset path by half line width so stroke stays inside bounds
            let pathInset = 0.5 * borderWidth
            let cornerRadius = 0.5 * borderHighlightFrame.height
            let maskPath = UIBezierPath(
                roundedRect: borderHighlightLayer.bounds.insetBy(dx: pathInset, dy: pathInset),
                cornerRadius: cornerRadius - pathInset
            )
            borderMaskLayer.path = maskPath.cgPath
            
            CATransaction.commit()
        }
        
        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            updateForTraits()
        }
        
        private func updateForTraits() {
            if case .dark = traitCollection.userInterfaceStyle {
                borderHighlightSpread = 0.5
                borderStroke = 0
            } else {
                borderHighlightSpread = 1
                borderStroke = 0.33
            }
        }
    }
}

// MARK: ItemView

extension FallbackTabBar {
    private class ItemView: UIView {
        
        private let componentView = ComponentView<Empty>()
        
        private(set) var item: TabBarComponent.Item?
        private(set) var theme: PresentationTheme?
        private(set) var isSelected: Bool = false

        func prepareForReuse() {
            item = nil
            theme = nil
            isSelected = false
        }
        
        override func layoutSubviews() {
            updateComponent()
        }
        
        var contextContainerView: ContextExtractedContentContainingView? {
            return (componentView.view as? ItemComponent.View)?.contextContainerView
        }
        
        func playSelectionAnimation(completion: (() -> Void)? = nil) {
            if let itemComponentView = componentView.view as? ItemComponent.View {
                itemComponentView.playSelectionAnimation(completion: completion)
            } else {
                completion?()
            }
        }
        
        func update(
            item: TabBarComponent.Item?,
            theme: PresentationTheme,
            isSelected: Bool
        ) {
            self.item = item
            self.theme = theme
            self.isSelected = isSelected
            updateComponent()
        }
        
        private func updateComponent() {
            guard let item, let theme else { return }
            
            let component = ItemComponent(
                item: item,
                theme: theme,
                isSelected: isSelected
            )
            
            let _ = componentView.update(
                transition: .immediate,
                component: AnyComponent(component),
                environment: {},
                containerSize: bounds.size
            )
            
            if let view = componentView.view {
                if view.superview == nil {
                    addSubview(view)
                }
                view.frame = bounds
            }
        }
    }
}

// MARK: NativeTabBar

public final class NativeTabBar: UIView, UITabBarDelegate {
    
    private let bar = UITabBar()
    private let contextGestureContainerView = ContextControllerSourceView()
    
    private var itemViews: [AnyHashable: ComponentView<Empty>] = [:]
    private var selectedItemViews: [AnyHashable: ComponentView<Empty>] = [:]
    
    private var component: TabBarComponent?
    
    private var itemWithActiveContextGesture: AnyHashable?
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        
        // Context gesture container view
        contextGestureContainerView.isGestureEnabled = true
        addSubview(contextGestureContainerView)
        
        // Bar
        bar.delegate = self
        contextGestureContainerView.addSubview(bar)
        
        let itemFont = Font.semibold(10.0)
        let itemColor: UIColor = .clear
        
        if #available(iOS 17.0, *) {
            traitOverrides.verticalSizeClass = .compact
            traitOverrides.horizontalSizeClass = .compact
        }
        
        bar.standardAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: itemColor,
            .font: itemFont
        ]
        bar.standardAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: itemColor,
            .font: itemFont
        ]
        bar.standardAppearance.inlineLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: itemColor,
            .font: itemFont
        ]
        bar.standardAppearance.inlineLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: itemColor,
            .font: itemFont
        ]
        bar.standardAppearance.compactInlineLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: itemColor,
            .font: itemFont
        ]
        bar.standardAppearance.compactInlineLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: itemColor,
            .font: itemFont
        ]
        
        contextGestureContainerView.shouldBegin = { [weak self] point in
            guard let self, let component else { return false }
            for (id, itemView) in itemViews {
                if let itemView = itemView.view {
                    if convert(itemView.bounds, from: itemView).contains(point) {
                        guard let item = component.items.first(where: { $0.id == id }) else {
                            return false
                        }
                        if item.contextAction == nil {
                            return false
                        }

                        itemWithActiveContextGesture = id

                        let startPoint = point
                        contextGestureContainerView.contextGesture?.externalUpdated = { [weak self] _, point in
                            guard let self else { return }

                            let dist = sqrt(pow(startPoint.x - point.x, 2.0) + pow(startPoint.y - point.y, 2.0))
                            if dist > 10.0 {
                                contextGestureContainerView.contextGesture?.cancel()
                            }
                        }

                        return true
                    }
                }
            }
            return false
        }
        contextGestureContainerView.customActivationProgress = { _, _ in
        }
        self.contextGestureContainerView.activated = { [weak self] gesture, _ in
            guard let self, let component else { return }
            guard let itemWithActiveContextGesture else { return }

            guard let itemView = selectedItemViews[itemWithActiveContextGesture]?.view as? ItemComponent.View else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                func cancelGestures(view: UIView) {
                    for recognizer in view.gestureRecognizers ?? [] {
                        if NSStringFromClass(type(of: recognizer)).contains("sSelectionGestureRecognizer") {
                            recognizer.state = .ended
                        }
                    }
                    for subview in view.subviews {
                        cancelGestures(view: subview)
                    }
                }

                cancelGestures(view: bar)
            }

            guard let item = component.items.first(where: { $0.id == itemWithActiveContextGesture }) else { return }
            item.contextAction?(gesture, itemView.contextContainerView)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        guard let component else { return }
        if let index = tabBar.items?.firstIndex(where: { $0 === item }) {
            if index < component.items.count {
                component.items[index].action(false)
            }
        }
    }
    
    func frameForItem(at index: Int) -> CGRect? {
        guard let component else { return nil }
        guard component.items.indices.contains(index) else { return nil }
        guard let itemView = itemViews[component.items[index].id]?.view else { return nil }
        return convert(itemView.bounds, from: itemView)
    }
    
    func update(
        component: TabBarComponent,
        availableSize: CGSize,
        state: EmptyComponentState,
        environment: Environment<Empty>,
        transition: ComponentTransition
    ) -> CGSize {
        let innerInset: CGFloat = 3
        
        let previousComponent = self.component
        self.component = component
        
        if component.items != previousComponent?.items {
            bar.items = component.items.indices.map { i in
                UITabBarItem(
                    title: component.items[i].item.title,
                    image: nil,
                    tag: i
                )
            }
            for (_, itemView) in itemViews {
                itemView.view?.removeFromSuperview()
            }
            for (_, selectedItemView) in selectedItemViews {
                selectedItemView.view?.removeFromSuperview()
            }
            if let index = component.items.firstIndex(where: { $0.id == component.selectedId}) {
                bar.selectedItem = bar.items?[index]
            }
        }
        
        bar.frame = CGRect(origin: .zero, size: CGSize(
            width: availableSize.width,
            height: component.isTablet ? 74 : 83
        ))
        setNeedsLayout()
        layoutIfNeeded()
        
        var nativeItemContainers: [Int: UIView] = [:]
        var nativeSelectedItemContainers: [Int: UIView] = [:]
        for subview in bar.subviews {
            if NSStringFromClass(type(of: subview)).contains("PlatterView") {
                for subview in subview.subviews {
                    if NSStringFromClass(type(of: subview)).hasSuffix("SelectedContentView") {
                        for subview in subview.subviews {
                            if NSStringFromClass(type(of: subview)).hasSuffix("TabButton") {
                                nativeSelectedItemContainers[nativeSelectedItemContainers.count] = subview
                            }
                        }
                    } else if NSStringFromClass(type(of: subview)).hasSuffix("ContentView") {
                        for subview in subview.subviews {
                            if NSStringFromClass(type(of: subview)).hasSuffix("TabButton") {
                                nativeItemContainers[nativeItemContainers.count] = subview
                            }
                        }
                    }
                }
            }
        }
        
        var itemSize = CGSize(
            width: floor((availableSize.width - innerInset * 2.0) / CGFloat(component.items.count)),
            height: 56
        )
        itemSize.width = min(94, itemSize.width)

        if let itemContainer = nativeItemContainers[0] {
            itemSize = itemContainer.bounds.size
        }
        
        let contentHeight = itemSize.height.addingProduct(2, innerInset)
        var contentWidth = innerInset
        
        var validIds: [AnyHashable] = []
        for index in component.items.indices {
            let item = component.items[index]
            validIds.append(item.id)

            let itemView: ComponentView<Empty>
            var itemTransition = transition

            if let current = itemViews[item.id] {
                itemView = current
            } else {
                itemTransition = itemTransition.withAnimation(.none)
                itemView = ComponentView()
                itemViews[item.id] = itemView
            }

            let selectedItemView: ComponentView<Empty>
            if let current = selectedItemViews[item.id] {
                selectedItemView = current
            } else {
                selectedItemView = ComponentView()
                selectedItemViews[item.id] = selectedItemView
            }

            let isItemSelected = component.selectedId == item.id

            let _ = itemView.update(
                transition: itemTransition,
                component: AnyComponent(ItemComponent(
                    item: item,
                    theme: component.theme,
                    isSelected: false
                )),
                environment: {},
                containerSize: itemSize
            )
            let _ = selectedItemView.update(
                transition: itemTransition,
                component: AnyComponent(ItemComponent(
                    item: item,
                    theme: component.theme,
                    isSelected: true
                )),
                environment: {},
                containerSize: itemSize
            )

            let itemFrame = CGRect(
                origin: CGPoint(
                    x: contentWidth,
                    y: floor((contentHeight - itemSize.height) * 0.5)
                ),
                size: itemSize
            )
            if let itemComponentView = itemView.view as? ItemComponent.View, let selectedItemComponentView = selectedItemView.view as? ItemComponent.View {
                if itemComponentView.superview == nil {
                    itemComponentView.isUserInteractionEnabled = false
                    selectedItemComponentView.isUserInteractionEnabled = false

                    if let itemContainer = nativeItemContainers[index] {
                        itemContainer.addSubview(itemComponentView)
                    }
                    if let itemContainer = nativeSelectedItemContainers[index] {
                        itemContainer.addSubview(selectedItemComponentView)
                    }
                }
                if let parentView = itemComponentView.superview {
                    let itemFrame = CGRect(
                        origin: CGPoint(
                            x: floor((parentView.bounds.width - itemSize.width) * 0.5),
                            y: floor((parentView.bounds.height - itemSize.height) * 0.5)
                        ),
                        size: itemSize
                    )
                    itemTransition.setFrame(view: itemComponentView, frame: itemFrame)
                    itemTransition.setFrame(view: selectedItemComponentView, frame: itemFrame)
                }

                if let previousComponent, previousComponent.selectedId != item.id, isItemSelected {
                    itemComponentView.playSelectionAnimation()
                    selectedItemComponentView.playSelectionAnimation()
                }
            }

            contentWidth += itemFrame.width
        }
        contentWidth += innerInset
        
        var removeIds: [AnyHashable] = []
        for (id, itemView) in itemViews {
            if !validIds.contains(id) {
                removeIds.append(id)
                itemView.view?.removeFromSuperview()
                selectedItemViews[id]?.view?.removeFromSuperview()
            }
        }
        for id in removeIds {
            itemViews.removeValue(forKey: id)
            selectedItemViews.removeValue(forKey: id)
        }
        
        let finalSize = CGSize(width: availableSize.width, height: 62.0)
        transition.setFrame(
            view: contextGestureContainerView,
            frame: CGRect(origin: .zero, size: finalSize)
        )
        return finalSize
    }
}

// MARK: TabBarComponent

public final class TabBarComponent: Component {
    
    public let theme: PresentationTheme
    public let items: [Item]
    public let selectedId: AnyHashable?
    public let isTablet: Bool
    
    public init(
        theme: PresentationTheme,
        items: [Item],
        selectedId: AnyHashable?,
        isTablet: Bool
    ) {
        self.theme = theme
        self.items = items
        self.selectedId = selectedId
        self.isTablet = isTablet
    }
    
    public static func == (lhs: TabBarComponent, rhs: TabBarComponent) -> Bool {
        guard lhs.theme == rhs.theme else { return false }
        guard lhs.items == rhs.items else { return false }
        guard lhs.selectedId == rhs.selectedId else { return false }
        guard lhs.isTablet == rhs.isTablet else { return false }
        return true
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

// MARK: Item

extension TabBarComponent {
    public final class Item: Equatable {
        public let item: UITabBarItem
        public let action: (Bool) -> Void
        public let contextAction: ((ContextGesture, ContextExtractedContentContainingView) -> Void)?
        
        fileprivate var id: AnyHashable {
            return AnyHashable(ObjectIdentifier(self.item))
        }
        
        public init(
            item: UITabBarItem,
            action: @escaping (Bool) -> Void,
            contextAction: ((ContextGesture, ContextExtractedContentContainingView) -> Void)?
        ) {
            self.item = item
            self.action = action
            self.contextAction = contextAction
        }
        
        public static func ==(lhs: Item, rhs: Item) -> Bool {
            if lhs === rhs {
                return true
            }
            if lhs.item !== rhs.item {
                return false
            }
            if (lhs.contextAction == nil) != (rhs.contextAction == nil) {
                return false
            }
            return true
        }
    }
}

// MARK: View

extension TabBarComponent {
    public final class View: UIView {
        enum TabBar {
            case native(NativeTabBar)
            case fallback(FallbackTabBar)
        }
        
        private var tabBar: TabBar
        
        override init(frame: CGRect) {
            if #available(iOS 26.0, *) {
                tabBar = .native(.init())
            } else {
                tabBar = .fallback(.init())
            }
            super.init(frame: frame)
            
            if #available(iOS 17.0, *) {
                traitOverrides.verticalSizeClass = .compact
                traitOverrides.horizontalSizeClass = .compact
            }
            
            switch tabBar {
            case .native(let nativeTabBar):
                addSubview(nativeTabBar)
            case .fallback(let fallbackTabBar):
                addSubview(fallbackTabBar)
            }
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public func frameForItem(at index: Int) -> CGRect? {
            switch tabBar {
            case .native(let nativeTabBar):
                return nativeTabBar.frameForItem(at: index)
            case .fallback:
                return nil
            }
        }
        
        func update(
            component: TabBarComponent,
            availableSize: CGSize,
            state: EmptyComponentState,
            environment: Environment<Empty>,
            transition: ComponentTransition
        ) -> CGSize {
            let availableSize = CGSize(
                width: min(500, availableSize.width),
                height: availableSize.height
            )
            
            overrideUserInterfaceStyle = component.theme.overallDarkAppearance ? .dark : .light
            
            switch tabBar {
            case .native(let nativeTabBar):
                let size = nativeTabBar.update(
                    component: component,
                    availableSize: availableSize,
                    state: state,
                    environment: environment,
                    transition: transition
                )
                transition.setFrame(
                    view: nativeTabBar,
                    frame: CGRect(origin: .zero, size: size)
                )
                return size
            case .fallback(let fallbackTabBar):
                let size = fallbackTabBar.update(
                    component: component,
                    availableSize: availableSize,
                    state: state,
                    environment: environment,
                    transition: transition
                )
                transition.setFrame(
                    view: fallbackTabBar,
                    frame: CGRect(origin: .zero, size: size)
                )
                return size
            }
        }
    }
}

// MARK: ItemComponent

private final class ItemComponent: Component {
    let item: TabBarComponent.Item
    let theme: PresentationTheme
    let isSelected: Bool
 
    init(
        item: TabBarComponent.Item,
        theme: PresentationTheme,
        isSelected: Bool
    ) {
        self.item = item
        self.theme = theme
        self.isSelected = isSelected
    }
 
    static func ==(lhs: ItemComponent, rhs: ItemComponent) -> Bool {
        guard lhs.item == rhs.item else { return false }
        guard lhs.theme == rhs.theme else { return false }
        guard lhs.isSelected == rhs.isSelected else { return false }
        return true
    }
 
    final class View: UIView {
        let contextContainerView: ContextExtractedContentContainingView
 
        private var imageIcon: ComponentView<Empty>?
        private var animationIcon: ComponentView<Empty>?
        private let title = ComponentView<Empty>()
        private var badge: ComponentView<Empty>?
 
        private var component: ItemComponent?
        private weak var state: EmptyComponentState?
 
        private var setImageListener: Int?
        private var setSelectedImageListener: Int?
        private var setBadgeListener: Int?
 
        override init(frame: CGRect) {
            self.contextContainerView = ContextExtractedContentContainingView()
 
            super.init(frame: frame)
 
            self.addSubview(self.contextContainerView)
        }
 
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
 
        deinit {
            if let component = self.component {
                if let setImageListener = self.setImageListener {
                    component.item.item.removeSetImageListener(setImageListener)
                }
                if let setSelectedImageListener = self.setSelectedImageListener {
                    component.item.item.removeSetSelectedImageListener(setSelectedImageListener)
                }
                if let setBadgeListener = self.setBadgeListener {
                    component.item.item.removeSetBadgeListener(setBadgeListener)
                }
            }
        }
 
        func playSelectionAnimation(completion: (() -> Void)? = nil) {
            if let animationIconView = self.animationIcon?.view as? LottieComponent.View, animationIconView.isEffectivelyVisible {
                animationIconView.playOnce(completion: completion)
            } else {
                completion?()
            }
        }
 
        func update(
            component: ItemComponent,
            availableSize: CGSize,
            state: EmptyComponentState,
            environment: Environment<Empty>,
            transition: ComponentTransition
        ) -> CGSize {
            let previousComponent = self.component
 
            if previousComponent?.item.item !== component.item.item {
                if let setImageListener = self.setImageListener {
                    self.component?.item.item.removeSetImageListener(setImageListener)
                }
                if let setSelectedImageListener = self.setSelectedImageListener {
                    self.component?.item.item.removeSetSelectedImageListener(setSelectedImageListener)
                }
                if let setBadgeListener = self.setBadgeListener {
                    self.component?.item.item.removeSetBadgeListener(setBadgeListener)
                }
                self.setImageListener = component.item.item.addSetImageListener { [weak self] _ in
                        guard let self else { return }
                        self.state?.updated(transition: .immediate, isLocal: true)
                    }
                self.setSelectedImageListener = component.item.item.addSetSelectedImageListener { [weak self] _ in
                        guard let self else { return }
                        self.state?.updated(transition: .immediate, isLocal: true)
                    }
                self.setBadgeListener = UITabBarItem_addSetBadgeListener(component.item.item) { [weak self] _ in
                    guard let self else { return }
                    self.state?.updated(transition: .immediate, isLocal: true)
                }
            }
 
            self.component = component
            self.state = state
 
            if let animationName = component.item.item.animationName {
                if let imageIcon = self.imageIcon {
                    self.imageIcon = nil
                    imageIcon.view?.removeFromSuperview()
                }
 
                let animationIcon: ComponentView<Empty>
                var iconTransition = transition
                if let current = self.animationIcon {
                    animationIcon = current
                } else {
                    iconTransition = iconTransition.withAnimation(.none)
                    animationIcon = ComponentView()
                    self.animationIcon = animationIcon
                }
 
                let iconSize = animationIcon.update(
                    transition: iconTransition,
                    component: AnyComponent(LottieComponent(
                        content: LottieComponent.AppBundleContent(name: animationName),
                        color: component.isSelected ? component.theme.rootController.tabBar.selectedTextColor : component.theme.rootController.tabBar.textColor,
                        placeholderColor: nil,
                        startingPosition: .end,
                        size: CGSize(width: 48.0, height: 48.0),
                        loop: false
                    )),
                    environment: {},
                    containerSize: CGSize(width: 48.0, height: 48.0)
                )
                let iconFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - iconSize.width) * 0.5), y: -4.0), size: iconSize).offsetBy(
                    dx: component.item.item.animationOffset.x,
                    dy: component.item.item.animationOffset.y
                )
                if let animationIconView = animationIcon.view {
                    if animationIconView.superview == nil {
                        if let badgeView = self.badge?.view {
                            self.contextContainerView.contentView.insertSubview(animationIconView, belowSubview: badgeView)
                        } else {
                            self.contextContainerView.contentView.addSubview(animationIconView)
                        }
                    }
                    iconTransition.setFrame(view: animationIconView, frame: iconFrame)
                }
            } else {
                if let animationIcon = self.animationIcon {
                    self.animationIcon = nil
                    animationIcon.view?.removeFromSuperview()
                }
 
                let imageIcon: ComponentView<Empty>
                var iconTransition = transition
                if let current = self.imageIcon {
                    imageIcon = current
                } else {
                    iconTransition = iconTransition.withAnimation(.none)
                    imageIcon = ComponentView()
                    self.imageIcon = imageIcon
                }
 
                let iconSize = imageIcon.update(
                    transition: iconTransition,
                    component: AnyComponent(Image(
                        image: component.isSelected ? component.item.item.selectedImage : component.item.item.image,
                        tintColor: nil,
                        contentMode: .center
                    )),
                    environment: {},
                    containerSize: CGSize(width: 100.0, height: 100.0)
                )
                let iconFrame = CGRect(
                    origin: CGPoint(
                        x: floor((availableSize.width - iconSize.width) * 0.5),
                        y: 3.0
                    ),
                    size: iconSize
                )
                if let imageIconView = imageIcon.view {
                    if imageIconView.superview == nil {
                        if let badgeView = self.badge?.view {
                            self.contextContainerView.contentView.insertSubview(imageIconView, belowSubview: badgeView)
                        } else {
                            self.contextContainerView.contentView.addSubview(imageIconView)
                        }
                    }
                    iconTransition.setFrame(view: imageIconView, frame: iconFrame)
                }
            }
 
            let titleSize = self.title.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(text: .plain(NSAttributedString(
                    string: component.item.item.title ?? " ",
                    font: Font.semibold(10.0),
                    textColor: component.isSelected ? component.theme.rootController.tabBar.selectedTextColor : component.theme.rootController.tabBar.textColor
                )))),
                environment: {},
                containerSize: CGSize(width: availableSize.width, height: 100.0)
            )
            let titleFrame = CGRect(
                origin: CGPoint(
                    x: floor((availableSize.width - titleSize.width) * 0.5),
                    y: availableSize.height - 8.0 - titleSize.height
                ),
                size: titleSize
            )
            if let titleView = self.title.view {
                if titleView.superview == nil {
                    self.contextContainerView.contentView.addSubview(titleView)
                }
                titleView.frame = titleFrame
            }
 
            if let badgeText = component.item.item.badgeValue, !badgeText.isEmpty {
                let badge: ComponentView<Empty>
                var badgeTransition = transition
                if let current = self.badge {
                    badge = current
                } else {
                    badgeTransition = badgeTransition.withAnimation(.none)
                    badge = ComponentView()
                    self.badge = badge
                }
                let badgeSize = badge.update(
                    transition: badgeTransition,
                    component: AnyComponent(TextBadgeComponent(
                        text: badgeText,
                        font: Font.regular(13.0),
                        background: component.theme.rootController.tabBar.badgeBackgroundColor,
                        foreground: component.theme.rootController.tabBar.badgeTextColor,
                        insets: UIEdgeInsets(top: 0.0, left: 6.0, bottom: 1.0, right: 6.0)
                    )),
                    environment: {},
                    containerSize: CGSize(width: 100.0, height: 100.0)
                )
                let contentWidth: CGFloat = 25.0
                let badgeFrame = CGRect(
                    origin: CGPoint(
                        x: floor(availableSize.width / 2.0) + contentWidth - badgeSize.width - 1.0,
                        y: 5.0
                    ),
                    size: badgeSize
                )
                if let badgeView = badge.view {
                    if badgeView.superview == nil {
                        self.contextContainerView.contentView.addSubview(badgeView)
                    }
                    badgeTransition.setFrame(view: badgeView, frame: badgeFrame)
                }
            } else if let badge = self.badge {
                self.badge = nil
                badge.view?.removeFromSuperview()
            }
 
            transition.setFrame(view: self.contextContainerView, frame: CGRect(origin: CGPoint(), size: availableSize))
            transition.setFrame(view: self.contextContainerView.contentView, frame: CGRect(origin: CGPoint(), size: availableSize))
            self.contextContainerView.contentRect = CGRect(
                origin: CGPoint(),
                size: availableSize
            )
 
            return availableSize
        }
    }
 
    func makeView() -> View {
        return View(frame: CGRect())
    }
 
    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(
            component: self,
            availableSize: availableSize,
            state: state,
            environment: environment,
            transition: transition
        )
    }
}
