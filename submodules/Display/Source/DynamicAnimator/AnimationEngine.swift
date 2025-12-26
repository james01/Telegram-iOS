import Foundation
import QuartzCore

@MainActor protocol Animating: AnyObject {
    var engineLink: AnimationEngineLink { get }
    func updateIfNeeded()
}

extension Animating {
    public var isRunning: Bool {
        return engineLink.state == .running
    }

    public var isAboutToUpdate: Bool {
        return engineLink.pendingTimestep != nil
    }
}

final class AnimationEngineLink {
    enum State {
        case running
        case stopped
        case pendingStop
    }

    fileprivate(set) var state: State = .stopped

    fileprivate var pendingTimestep: Timestep?

    func setWantsToStop() {
        pendingTimestep = nil
        if state == .running {
            state = .pendingStop
        }
    }

    func takePendingTimestep() -> Timestep? {
        return pendingTimestep.take()
    }
}

@MainActor final class AnimationEngine {

    private struct WeakAnimator {
        weak var value: (any Animating)?
    }

    static let shared = AnimationEngine()

    private var animators: [WeakAnimator] = []

    private var pendingAdditions: [WeakAnimator] = []

    private var displayLink: CADisplayLink?
    
    private var previousTargetTimestamp: CFTimeInterval?

    private init() {
    }

    private func createOrDestroyDisplayLinkIfNeeded() {
        if animators.isEmpty && pendingAdditions.isEmpty {
            displayLink?.invalidate()
            displayLink = nil
            previousTargetTimestamp = nil
        } else if displayLink == nil {
            displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired))
            displayLink?.add(to: .main, forMode: .common)
        }
    }

    @objc private func displayLinkFired(_ displayLink: CADisplayLink) {
        let prev = previousTargetTimestamp ?? displayLink.timestamp
        previousTargetTimestamp = displayLink.targetTimestamp
        let dt = Timestep(
            ideal: displayLink.targetTimestamp - displayLink.timestamp,
            actual: displayLink.targetTimestamp - prev,
        )
        
        if !pendingAdditions.isEmpty {
            animators.append(contentsOf: pendingAdditions)
            pendingAdditions.removeAll()
        }
        animators.removeAll { weakAnimator in
            guard let animator = weakAnimator.value else { return true }
            switch animator.engineLink.state {
            case .running:
                animator.engineLink.pendingTimestep = dt
                return false
            case .stopped:
                return true
            case .pendingStop:
                animator.engineLink.state = .stopped
                return true
            }
        }
        for weakAnimator in animators {
            weakAnimator.value?.updateIfNeeded()
        }
        createOrDestroyDisplayLinkIfNeeded()
    }

    func startUpdating(animator: some Animating) {
        switch animator.engineLink.state {
        case .running:
            break
        case .stopped:
            animator.engineLink.state = .running
            pendingAdditions.append(WeakAnimator(value: animator))
            createOrDestroyDisplayLinkIfNeeded()
        case .pendingStop:
            animator.engineLink.state = .running
        }
    }
}
