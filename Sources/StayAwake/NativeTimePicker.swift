import AppKit
import SwiftUI

/// Let AppKit measure its own time field. SwiftUI only positions the control;
/// it never stretches the text field into an unrelated decorative container.
struct NativeTimePicker: NSViewRepresentable {
    @Binding var date: Date

    func makeCoordinator() -> Coordinator { Coordinator(date: $date) }

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textField
        picker.datePickerMode = .single
        picker.datePickerElements = [.hourMinute]
        picker.controlSize = .regular
        picker.font = .systemFont(ofSize: 13)
        picker.isBezeled = true
        picker.drawsBackground = true
        picker.backgroundColor = .textBackgroundColor
        picker.textColor = .labelColor
        picker.locale = .autoupdatingCurrent
        picker.calendar = .autoupdatingCurrent
        picker.timeZone = .autoupdatingCurrent
        picker.dateValue = date
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        picker.setAccessibilityLabel("End time")
        picker.setContentHuggingPriority(.required, for: .horizontal)
        picker.setContentCompressionResistancePriority(.required, for: .horizontal)
        picker.sizeToFit()
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.date = $date
        if abs(picker.dateValue.timeIntervalSince(date)) > 0.5 {
            picker.dateValue = date
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSDatePicker, context: Context) -> CGSize? {
        let natural = nsView.cell?.cellSize ?? nsView.intrinsicContentSize
        return CGSize(width: max(80, ceil(natural.width)), height: max(22, ceil(natural.height)))
    }

    @MainActor
    final class Coordinator: NSObject {
        var date: Binding<Date>
        init(date: Binding<Date>) { self.date = date }
        @objc func changed(_ sender: NSDatePicker) { date.wrappedValue = sender.dateValue }
    }
}
