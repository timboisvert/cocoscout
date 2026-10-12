import SwiftUI
import UIKit

/// Everything drawn over the camera: the show at the top with close and the
/// flashlight, a frame to aim with, and the last result at the bottom in the
/// door page's banner colors (green in, amber already in, red no).
struct ScannerOverlay: View {
    @ObservedObject var model: ScannerModel
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 16) {
            topBar
            Spacer(minLength: 0)
            middle
            Spacer(minLength: 0)
            bottom
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    // MARK: Top

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            roundButton(systemImage: "xmark", label: "Close the scanner", action: model.onClose)
            VStack(spacing: 2) {
                Text(model.title)
                    .font(Font(AppConfig.coustard(18)))
                    .lineLimit(1)
                if !model.subtitle.isEmpty {
                    Text(model.subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .opacity(0.85)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 4)
            .frame(maxWidth: .infinity)
            if model.hasTorch {
                roundButton(systemImage: model.torchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                            label: model.torchOn ? "Turn the flashlight off" : "Turn the flashlight on",
                            highlighted: model.torchOn,
                            action: model.onTorch)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
    }

    private func roundButton(systemImage: String, label: String, highlighted: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(highlighted ? Tailwind.gray900 : .white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(highlighted ? Color.white : Color.black.opacity(0.45)))
        }
        .accessibilityLabel(label)
    }

    // MARK: Middle

    @ViewBuilder
    private var middle: some View {
        switch model.camera {
        case .starting, .running:
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 3)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 280)
                .shadow(color: .black.opacity(0.35), radius: 6)
                .accessibilityHidden(true)
        case .unavailable:
            typeACode(headline: "No camera here",
                      detail: "Type the code from their ticket instead.")
        case .denied:
            typeACode(headline: "The camera is off for CocoScout",
                      detail: "Turn it on in Settings to scan tickets, or type the code from their ticket.",
                      settings: true)
        }
    }

    private func typeACode(headline: String, detail: String, settings: Bool = false) -> some View {
        VStack(spacing: 12) {
            Text(headline)
                .font(.system(size: 20, weight: .bold))
            Text(detail)
                .font(.system(size: 15))
                .opacity(0.85)
                .multilineTextAlignment(.center)
            if settings, let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { UIApplication.shared.open(url) }
                    .buttonStyle(SharedButtonStyle(variant: .secondary, size: .small))
            }
            HStack(spacing: 8) {
                TextField("Ticket code", text: $model.typedCode)
                    // Ticket codes are case-sensitive.
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($typing)
                    .onSubmit(checkInTyped)
                    .font(.system(size: 15))
                    .foregroundStyle(Tailwind.gray900)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                Button("Check in", action: checkInTyped)
                    .buttonStyle(SharedButtonStyle(variant: .primary, size: .medium))
                    .disabled(model.typedCode.trimmingCharacters(in: .whitespaces).isEmpty || model.waiting)
            }
            .padding(.top, 4)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: 420)
    }

    private func checkInTyped() {
        model.onCode(model.typedCode)
    }

    // MARK: Bottom

    @ViewBuilder
    private var bottom: some View {
        if let result = model.result {
            ResultCard(result: result, delivering: model.delivering, onUndo: model.onUndo, onFulfill: model.onFulfill)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if model.waiting {
            pill {
                ProgressView().tint(.white)
                Text("Checking…")
            }
        } else if model.camera == .running || model.camera == .starting {
            pill { Text("Point at the code on their phone or printout") }
        }
    }

    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8, content: content)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.black.opacity(0.55)))
    }
}

/// The door page's result banner, in the hand: the name or the problem big,
/// the details under it, Undo on a fresh admit, and anything they pre-bought
/// with a Delivered button.
private struct ResultCard: View {
    let result: DoorResult
    let delivering: Set<String>
    let onUndo: (String) -> Void
    let onFulfill: (String) -> Void

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(result.lines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(index == 0 ? .system(size: 24, weight: .bold) : .system(size: 15, weight: .medium))
                    .multilineTextAlignment(.center)
            }
            if let ticketID = result.undoTicketID {
                // A text link, as on the door page's banner.
                Button { onUndo(ticketID) } label: {
                    Text("Undo").underline().font(.system(size: 15, weight: .medium))
                }
                .padding(.top, 6)
            }
            ForEach(result.items) { item in
                HStack(spacing: 12) {
                    Text(item.fulfilled ? "\(item.label) · delivered" : item.label)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !item.fulfilled {
                        Button("Delivered") { onFulfill(item.fulfillURL) }
                            .buttonStyle(SharedButtonStyle(variant: .primary, size: .small))
                            .disabled(delivering.contains(item.fulfillURL))
                    }
                }
                .foregroundStyle(Tailwind.gray900)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.92)))
                .padding(.top, 8)
            }
        }
        .foregroundStyle(result.tone == .already ? Tailwind.gray900 : .white)
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(background))
        .accessibilityElement(children: .contain)
    }

    private var background: Color {
        switch result.tone {
        case .admitted: Tailwind.green600
        case .already: Tailwind.amber300
        case .error: Tailwind.red600
        }
    }
}
