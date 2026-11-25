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

/// What a card shows. Empty parts are hidden.
struct Card {
    var header = ""
    var body: NSAttributedString?
    /// Smaller, secondary text under the body (e.g. what a message implies).
    var note = ""
    /// Small buttons in a row: rewrite modes, translate.
    var actions: [(id: String, title: String)] = []
    /// The action whose result is showing, drawn highlighted.
    var activeAction: String?
    var primary: String?
    var secondary: String?
    /// Just the action buttons, sized to fit: the "Translate" chip.
    var compact = false
}

/// A floating card next to a field or a selection: header, diff or text,
/// action buttons, and Apply/Dismiss.
final class SuggestionPanel {
    private let panel: FloatingPanel
    private let header = NSTextField(labelWithString: "")
    private let body = NSTextField(labelWithString: "")
    private let note = NSTextField(labelWithString: "")
    private let actionsRow = NSStackView()
    private let primaryButton = FirstMouseButton(title: "", target: nil, action: nil)
    private let secondaryButton = FirstMouseButton(title: "", target: nil, action: nil)
    private let buttons = NSStackView()
    private let stack = NSStackView()
    private let width: CGFloat = 400
    private var fixedWidth: [NSLayoutConstraint] = []
    private var actionIDs: [String] = []

    var onPrimary: (() -> Void)?
    var onSecondary: (() -> Void)?
    var onAction: ((String) -> Void)?
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

        for label in [body, note] {
            label.maximumNumberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            label.preferredMaxLayoutWidth = width - 24
            label.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        body.maximumNumberOfLines = 24
        body.lineBreakMode = .byTruncatingTail
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabelColor

        actionsRow.orientation = .horizontal
        actionsRow.spacing = 6

        primaryButton.bezelStyle = .rounded
        primaryButton.contentTintColor = .controlAccentColor
        secondaryButton.bezelStyle = .rounded
        primaryButton.target = self
        primaryButton.action = #selector(primaryClicked)
        secondaryButton.target = self
        secondaryButton.action = #selector(secondaryClicked)

        [NSView(), secondaryButton, primaryButton].forEach(buttons.addArrangedSubview)
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        [header, body, note, actionsRow, buttons].forEach(stack.addArrangedSubview)
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
        ])
        fixedWidth = [
            stack.widthAnchor.constraint(equalToConstant: width),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
        ]
        panel.contentView = background
    }

    @objc private func primaryClicked() { onPrimary?() }
    @objc private func secondaryClicked() { onSecondary?() }
    @objc private func actionClicked(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < actionIDs.count else { return }
        onAction?(actionIDs[sender.tag])
    }

    /// Shows the card below `anchor` (AX coordinates), or above it when there's no room.
    func show(_ card: Card, anchor: CGRect) {
        header.stringValue = card.header
        header.isHidden = card.header.isEmpty
        body.attributedStringValue = card.body ?? NSAttributedString()
        body.isHidden = card.body == nil
        note.stringValue = card.note
        note.isHidden = card.note.isEmpty

        actionsRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        actionIDs = card.actions.map(\.id)
        for (i, action) in card.actions.enumerated() {
            let button = FirstMouseButton(title: action.title, target: self, action: #selector(actionClicked(_:)))
            button.tag = i
            button.bezelStyle = .rounded
            button.controlSize = card.compact ? .regular : .small
            button.font = .systemFont(ofSize: card.compact ? 13 : 11, weight: action.id == card.activeAction ? .semibold : .regular)
            if action.id == card.activeAction { button.contentTintColor = .controlAccentColor }
            actionsRow.addArrangedSubview(button)
        }
        actionsRow.isHidden = card.actions.isEmpty

        primaryButton.title = card.primary ?? ""
        primaryButton.isHidden = card.primary == nil
        secondaryButton.title = card.secondary ?? ""
        secondaryButton.isHidden = card.secondary == nil
        buttons.isHidden = card.primary == nil && card.secondary == nil

        stack.edgeInsets = card.compact ? NSEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
                                        : NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        if card.compact { NSLayoutConstraint.deactivate(fixedWidth) } else { NSLayoutConstraint.activate(fixedWidth) }

        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? NSSize(width: width, height: 120)

        let a = AX.toCocoa(anchor)
        let screen = NSScreen.screens.first { $0.frame.intersects(a) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let gap: CGFloat = card.compact ? 4 : 8
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
    /// Plain text in the card's body style; `dim` for "working on it" states.
    static func text(_ s: String, dim: Bool = false, font: NSFont = .systemFont(ofSize: 13)) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: dim ? NSColor.secondaryLabelColor : NSColor.labelColor])
    }

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
