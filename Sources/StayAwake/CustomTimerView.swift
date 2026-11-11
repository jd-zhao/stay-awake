import SwiftUI

enum TimerEditorKind: Int, Hashable {
    case duration, endTime
}

struct CustomTimerView: View {
    @ObservedObject var session: AwakeSession
    let initialKind: TimerEditorKind
    var close: () -> Void
    @State private var kind: TimerEditorKind = .duration
    @State private var hours = "1"
    @State private var minutes = "30"
    @State private var endTime = Date().addingTimeInterval(3600)
    @State private var validation: String?
    @FocusState private var field: Field?
    enum Field { case hours, minutes }

    private var nextEndDate: Date {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: endTime)
        return Calendar.current.nextDate(after: Date(), matching: parts, matchingPolicy: .nextTime) ?? Date().addingTimeInterval(3600)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FormRow(title: "Type") {
                PopUpField(label: "Timer type", value: kind, options: [(.duration, "Duration"), (.endTime, "End time")]) { kind = $0 }
            }
            if kind == .duration {
                FormRow(title: "Length") {
                    HStack(spacing: 6) {
                        TextField("0", text: $hours).frame(width: 46).focused($field, equals: .hours)
                            .accessibilityLabel("Hours")
                        Text("h").foregroundStyle(.secondary)
                        TextField("0", text: $minutes).frame(width: 46).focused($field, equals: .minutes)
                            .accessibilityLabel("Minutes")
                        Text("min").foregroundStyle(.secondary)
                    }.textFieldStyle(.roundedBorder).font(.system(size: 12)).monospacedDigit()
                        .onSubmit { apply() }
                }
                helper("1 minute to 7 days.")
            } else {
                FormRow(title: "Until") {
                    NativeTimePicker(date: $endTime).fixedSize()
                }
                helper((Calendar.current.isDateInTomorrow(nextEndDate) ? "Tomorrow, " : "Today, ") + nextEndDate.formatted(date: .omitted, time: .shortened))
            }
            if let validation {
                Text(validation).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Invalid time. " + validation)
            }
            Spacer(minLength: 0)
            Text(session.isActive ? "Saving resets the running timer." : "The timer begins when you start.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Divider()
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: close).buttonStyle(UtilityButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
                Button(session.isActive ? "Apply" : "Save", action: apply)
                    .buttonStyle(UtilityButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            kind = initialKind
            hours = String(session.customMinutes / 60)
            minutes = String(session.customMinutes % 60)
            if let selected = session.selectedEndTime { endTime = selected }
        }
        .onChange(of: kind) { _, _ in validation = nil }
        .onChange(of: hours) { _, _ in validation = nil }
        .onChange(of: minutes) { _, _ in validation = nil }
        .onChange(of: endTime) { _, _ in validation = nil }
    }

    private func helper(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(.leading, UtilityLayout.labelWidth + UtilityLayout.columnSpacing)
    }

    private func apply() {
        if kind == .duration {
            guard let h = Int(hours), let m = Int(minutes), session.setCustomDuration(hours: h, minutes: m) else {
                validation = "Use 0–168 hours and 0–59 minutes, up to 7 days. Choose at least 1 minute."
                return
            }
        } else if !session.setEndTime(nextEndDate) {
            validation = "Choose an end time in the future."
            return
        }
        close()
    }
}
