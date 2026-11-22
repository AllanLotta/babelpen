import AppKit
import BabelpenCore

/// A floating panel that can be clicked without activating Babelpen, so the
/// keyboard focus stays in the app you're typing in.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Buttons that respond to the first click even though their window is never key.
final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The suggestion card: header, diff (red strikethrough = removed, blue = added), buttons.
final class SuggestionPanel {
    private let panel: FloatingPanel
    private let header = NSTextField(labelWithString: "")
    private let body = NSTextField(labelWithString: "")
    private let applyButton = FirstMouseButton(title: "", target: nil, action: nil)
    private let dismissButton = FirstMouseButton(title: "", target: nil, action: nil)
    private let width: CGFloat = 380

    var onApply: (() -> Void)?
    var onDismiss: (() -> Void)?
    var isVisible: Bool { panel.isVisible }

    init() {
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: 120),
                              styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true

        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor

        body.maximumNumberOfLines = 0
        body.lineBreakMode = .byWordWrapping
        body.preferredMaxLayoutWidth = width - 24
        body.setContentCompressionResistancePriority(.required, for: .vertical)

        applyButton.bezelStyle = .rounded
        applyButton.contentTintColor = .controlAccentColor
        dismissButton.bezelStyle = .rounded
        applyButton.target = self
        applyButton.action = #selector(applyClicked)
        dismissButton.target = self
        dismissButton.action = #selector(dismissClicked)

        let buttons = NSStackView(views: [NSView(), dismissButton, applyButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [header, body, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false

        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: width),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
        ])
        panel.contentView = background
    }

    func setStrings(_ l10n: L10n) {
        applyButton.title = l10n.apply
        dismissButton.title = l10n.dismiss
    }

    @objc private func applyClicked() { onApply?() }
    @objc private func dismissClicked() { onDismiss?() }

    /// Shows the card below `anchor` (AX coordinates), or above it when there's no room.
    func show(diff: NSAttributedString, header text: String, anchor: CGRect) {
        header.stringValue = text
        body.attributedStringValue = diff
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? NSSize(width: width, height: 120)

        let a = AX.toCocoa(anchor)
        let screen = NSScreen.screens.first { $0.frame.intersects(a) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let gap: CGFloat = 8
        let below = a.minY - size.height - gap
        var origin = NSPoint(x: a.minX, y: below >= visible.minY ? below : a.maxY + gap)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    func hide() { if panel.isVisible { panel.orderOut(nil) } }
}

enum DiffRenderer {
    static func render(_ ops: [Diff.Op], font: NSFont = .systemFont(ofSize: 13)) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let same: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let removed: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor.systemRed,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: NSColor.systemRed,
        ]
        let added: [NSAttributedString.Key: Any] = [
            .font: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask), .foregroundColor: NSColor.systemBlue,
        ]
        for (i, op) in ops.enumerated() {
            switch op {
            case .same(let t): out.append(NSAttributedString(string: t, attributes: same))
            case .delete(let t):
                out.append(NSAttributedString(string: t, attributes: removed))
                // Keep "old" and "new" visually apart when a replacement follows.
                if i + 1 < ops.count, case .insert = ops[i + 1] { out.append(NSAttributedString(string: " ", attributes: same)) }
            case .insert(let t): out.append(NSAttributedString(string: t, attributes: added))
            }
        }
        return out
    }
}
