import SwiftUI

struct InkStrikeRow<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let isCompleted: Bool
    let canEdit: Bool
    let strikeColor: Color
    let onToggle: () -> Void
    @ViewBuilder var trailing: Trailing

    @State private var textWidth: CGFloat = 1
    @State private var dragProgress: CGFloat = 0

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                InkStrikeText(
                    title: title,
                    isCompleted: isCompleted,
                    dragProgress: dragProgress,
                    strikeColor: strikeColor
                )
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                textWidth = max(proxy.size.width, 1)
                            }
                            .onChange(of: proxy.size.width) { _, newWidth in
                                textWidth = max(newWidth, 1)
                            }
                    }
                )

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                toggle()
            }

            Spacer(minLength: 0)

            trailing
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.7), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .gesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard canEdit else { return }
                guard isHorizontal(value) else {
                    dragProgress = 0
                    return
                }

                let progress = abs(value.translation.width) / max(textWidth, 1)
                dragProgress = min(max(progress, 0), 1)
            }
            .onEnded { value in
                defer { dragProgress = 0 }
                guard canEdit else { return }
                guard isHorizontal(value) else { return }

                if abs(value.translation.width) >= (textWidth * 0.5) {
                    onToggle()
                }
            }
    }

    private func isHorizontal(_ value: DragGesture.Value) -> Bool {
        abs(value.translation.width) > abs(value.translation.height)
    }

    private func toggle() {
        guard canEdit else { return }
        onToggle()
    }
}

private struct InkStrikeText: View {
    let title: String
    let isCompleted: Bool
    let dragProgress: CGFloat
    let strikeColor: Color

    var body: some View {
        Text(title)
            .foregroundStyle(isCompleted ? .secondary : .primary)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(strikeColor.opacity(0.92))
                        .frame(
                            width: proxy.size.width * effectiveProgress,
                            height: 2.8
                        )
                        .offset(y: proxy.size.height * 0.52)
                        .rotationEffect(.degrees(-2))
                        .opacity(effectiveProgress > 0 ? 1 : 0)
                }
            }
    }

    private var effectiveProgress: CGFloat {
        isCompleted ? 1 : dragProgress
    }
}
