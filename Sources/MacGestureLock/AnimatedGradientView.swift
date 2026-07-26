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
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        
        gradientLayer.colors = colorsets[0]
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
        let animation = CAKeyframeAnimation(keyPath: "colors")
        // Loop back to the first color to make the animation seamless
        animation.values = colorsets + [colorsets[0]]
        animation.duration = 12.0 // 4 seconds per color transition
        animation.repeatCount = .infinity
        animation.calculationMode = .linear

        gradientLayer.add(animation, forKey: "colorChange")
    }
}
