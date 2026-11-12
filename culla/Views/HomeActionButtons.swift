import SwiftUI

/// The home screen's bottom row: the focus timer menu (Cullaing only) and the
/// start button, whose label and icon follow the selected mode.
struct HomeActionButtons: View {
    let selectedMode: CullaMode
    @Binding var focusDuration: TimeInterval?
    let onStart: () -> Void

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer {
                buttons
                    .buttonStyle(.glass)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        } else {
            buttons
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.bottom, 12)
        }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            if selectedMode == .cullaing {
                timerMenu
            }
            Button {
                onStart()
            } label: {
                HStack(spacing: 8) {
                    if let icon = startIcon {
                        Image(systemName: icon).imageScale(.medium)
                    }
                    Text(startLabel)
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(.primary)
            }
            .controlSize(.large)
            .animation(.easeInOut(duration: 0.2), value: selectedMode)
        }
        .tourTarget(.startButton)
    }

    private var startLabel: String {
        switch selectedMode {
        case .cullaing:
            guard let focusDuration else { return String(localized: "Start Cullaing") }
            let minutes = Int(focusDuration) / 60
            return String(localized: "Culla for \(minutes) min")
        case .thisDay:
            return String(localized: "This Day")
        case .duplicates:
            return String(localized: "Sweep")
        }
    }

    private var startIcon: String? {
        switch selectedMode {
        case .cullaing: return nil
        case .thisDay: return "clock.arrow.circlepath"
        case .duplicates: return "doc.on.doc"
        }
    }

    // MARK: - Focus Timer Menu

    private var timerMenu: some View {
        Menu {
            ForEach([2, 5, 10], id: \.self) { minutes in
                Button {
                    focusDuration = TimeInterval(minutes * 60)
                } label: {
                    HStack {
                        Text("\(minutes) min")
                        if focusDuration == TimeInterval(minutes * 60) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            if focusDuration != nil {
                Divider()
                Button("No Timer", role: .destructive) {
                    focusDuration = nil
                }
            }
        } label: {
            Image(systemName: focusDuration != nil ? "timer.circle.fill" : "timer")
                .font(.title2)
                .foregroundStyle(focusDuration != nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
    }
}
