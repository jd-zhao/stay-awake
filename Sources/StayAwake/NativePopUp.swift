import AppKit
import SwiftUI

struct PopUpField<Value: Hashable>: NSViewRepresentable {
    let label: String
    let value: Value
    let options: [(Value, String)]
    var select: (Value) -> Void

    func makeCoordinator() -> PopUpCoordinator { PopUpCoordinator() }

    func makeNSView(context: Context) -> PopUpHost {
        let view = PopUpHost()
        view.button.target = context.coordinator
        view.button.action = #selector(PopUpCoordinator.changed(_:))
        return view
    }

    func updateNSView(_ view: PopUpHost, context: Context) {
        let titles = options.map(\.1)
        if view.button.itemTitles != titles {
            view.button.removeAllItems()
            view.button.addItems(withTitles: titles)
        }
        if let index = options.firstIndex(where: { $0.0 == value }) { view.button.selectItem(at: index) }
        view.button.setAccessibilityLabel(label)
        context.coordinator.selectIndex = { index in
            guard options.indices.contains(index) else { return }
            select(options[index].0)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PopUpHost, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 180, height: 24)
    }
}

@MainActor
final class PopUpCoordinator: NSObject {
    var selectIndex: (Int) -> Void = { _ in }
    @objc func changed(_ sender: NSPopUpButton) { selectIndex(sender.indexOfSelectedItem) }
}

@MainActor
final class PopUpHost: NSView {
    let button = NSPopUpButton(frame: .zero, pullsDown: false)
    private let arrow = NonInteractiveImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 12)
        button.alignment = .left
        button.bezelStyle = .rounded
        button.bezelColor = .controlBackgroundColor
        button.contentTintColor = .labelColor
        button.cell?.lineBreakMode = .byTruncatingTail
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        arrow.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold))
        arrow.contentTintColor = .secondaryLabelColor
        arrow.imageScaling = .scaleProportionallyDown
        arrow.setAccessibilityElement(false)
        addSubview(button)
        addSubview(arrow)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var intrinsicContentSize: NSSize { NSSize(width: 180, height: 24) }
    override func layout() {
        super.layout()
        button.frame = bounds
        arrow.frame = NSRect(x: bounds.maxX - 16, y: (bounds.height - 8) / 2, width: 8, height: 8)
    }
}

@MainActor
private final class NonInteractiveImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
