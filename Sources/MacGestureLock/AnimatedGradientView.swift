import AppKit
import QuartzCore

@MainActor
final class AnimatedGradientView: NSView {
    private let gradientLayer = CAGradientLayer()
    
    // Some liquid-like modern gradient colors
    private let colorsets: [[CGColor]] = [
        [NSColor(red: 0.1, green: 0.0, blue: 0.2, alpha: 1.0).cgColor,
         NSColor(red: 0.3, green: 0.1, blue: 0.4, alpha: 1.0).cgColor,
         NSColor(red: 0.0, green: 0.2, blue: 0.3, alpha: 1.0).cgColor],
         
        [NSColor(red: 0.0, green: 0.2, blue: 0.3, alpha: 1.0).cgColor,
         NSColor(red: 0.1, green: 0.0, blue: 0.2, alpha: 1.0).cgColor,
         NSColor(red: 0.2, green: 0.1, blue: 0.3, alpha: 1.0).cgColor],
         
        [NSColor(red: 0.2, green: 0.1, blue: 0.3, alpha: 1.0).cgColor,
         NSColor(red: 0.0, green: 0.2, blue: 0.3, alpha: 1.0).cgColor,
         NSColor(red: 0.1, green: 0.0, blue: 0.2, alpha: 1.0).cgColor]
    ]
    
    private var colorIndex = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        
        gradientLayer.colors = colorsets[colorIndex]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        gradientLayer.type = .radial
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1.5, y: 1.5)
        
        self.layer = gradientLayer
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && gradientLayer.animation(forKey: "colorChange") == nil {
            animateGradient()
        }
    }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
    }

    private func animateGradient() {
        let currentColors = colorsets[colorIndex]
        colorIndex = (colorIndex + 1) % colorsets.count
        let nextColors = colorsets[colorIndex]

        let animation = CABasicAnimation(keyPath: "colors")
        animation.fromValue = currentColors
        animation.toValue = nextColors
        animation.duration = 4.0 // Slow liquid flow
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        animation.delegate = self

        gradientLayer.add(animation, forKey: "colorChange")
    }
}

extension AnimatedGradientView: CAAnimationDelegate {
    nonisolated func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        if flag {
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.gradientLayer.colors = self.colorsets[self.colorIndex]
                self.animateGradient()
            }
        }
    }
}
