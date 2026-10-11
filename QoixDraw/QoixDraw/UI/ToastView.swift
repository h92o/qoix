import UIKit

/// A small pill of text that fades in and out near the top of the screen, for one-line messages.
final class ToastView: UIView {
    private let label = UILabel()
    private let swatchView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        alpha = 0
        isUserInteractionEnabled = false
        backgroundColor = UIColor(white: 0.08, alpha: 0.88)
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous

        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        addSubview(label)

        swatchView.layer.cornerRadius = 7
        swatchView.layer.borderWidth = 1
        swatchView.layer.borderColor = UIColor(white: 1, alpha: 0.6).cgColor
        swatchView.isHidden = true
        addSubview(swatchView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows `text` near the top of `container`, then fades it out after `duration` seconds. With a `swatch`, a
    /// small dot of that color is shown beside the text.
    func show(_ text: String, swatch: UIColor? = nil, in container: UIView, duration: TimeInterval = 1.8) {
        layer.removeAllAnimations()
        if superview !== container {
            container.addSubview(self)
        }
        container.bringSubviewToFront(self)

        label.text = text
        swatchView.backgroundColor = swatch
        swatchView.isHidden = swatch == nil
        let swatchSize: CGFloat = 14
        let swatchSpace: CGFloat = swatch == nil ? 0 : swatchSize + 8
        let horizontalPadding: CGFloat = 18
        let verticalPadding: CGFloat = 11
        let maxWidth = min(container.bounds.width - 48, 420)
        let fit = label.sizeThatFits(CGSize(width: maxWidth - horizontalPadding * 2 - swatchSpace,
                                            height: .greatestFiniteMagnitude))
        let contentHeight = max(fit.height, swatchSize)
        let size = CGSize(width: fit.width + horizontalPadding * 2 + swatchSpace, height: contentHeight + verticalPadding * 2)
        let top = max(container.safeAreaInsets.top, 20) + 12
        frame = CGRect(x: (container.bounds.width - size.width) / 2, y: top, width: size.width, height: size.height)
        swatchView.frame = CGRect(x: horizontalPadding, y: (size.height - swatchSize) / 2, width: swatchSize, height: swatchSize)
        label.frame = CGRect(x: horizontalPadding + swatchSpace, y: (size.height - fit.height) / 2, width: fit.width, height: fit.height)

        UIView.animate(withDuration: 0.18, animations: {
            self.alpha = 1
        }, completion: { finished in
            // If another toast interrupted this one, `finished` is false and the newer toast owns the fade-out.
            guard finished else { return }
            UIView.animate(withDuration: 0.3, delay: duration, options: [.allowUserInteraction], animations: {
                self.alpha = 0
            })
        })

        UIAccessibility.post(notification: .announcement, argument: text)
    }
}
