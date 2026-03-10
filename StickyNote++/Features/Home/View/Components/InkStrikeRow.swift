import SwiftUI

/// Reusable swipe-aware row with animated strike-through completion affordance.
struct InkStrikeRow<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let isCompleted: Bool
    let canEdit: Bool
    let strikeColor: Color
    var onHorizontalSwipeActivityChange: ((Bool) -> Void)? = nil
    let onToggle: () -> Void
    @ViewBuilder var trailing: Trailing

    @State private var textWidth: CGFloat = 1
    @State private var dragProgress: CGFloat = 0
    @State private var isHorizontalDragActive = false

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
                        .font(.caption2)
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
        .glassCard(cornerRadius: 18, fill: AnyShapeStyle(AppTheme.cardSurface), shadowOpacity: 0)
        .contentShape(Rectangle())
        .simultaneousGesture(dragGesture)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(canEdit ? .isButton : [])
        .accessibilityAction {
            toggle()
        }
        .onDisappear {
            endHorizontalDragIfNeeded(notifyAsynchronously: false)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                if isHorizontal(value) {
                    beginHorizontalDragIfNeeded()
                } else {
                    dragProgress = 0
                    endHorizontalDragIfNeeded(notifyAsynchronously: false)
                    return
                }

                guard canEdit else { return }

                let progress = abs(value.translation.width) / max(textWidth, 1)
                dragProgress = min(max(progress, 0), 1)
            }
            .onEnded { value in
                defer {
                    dragProgress = 0
                    endHorizontalDragIfNeeded(notifyAsynchronously: true)
                }

                guard canEdit else { return }
                guard isHorizontal(value) else { return }

                if abs(value.translation.width) >= (textWidth * 0.5) {
                    onToggle()
                }
            }
    }

    private func isHorizontal(_ value: DragGesture.Value) -> Bool {
        abs(value.translation.width) > abs(value.translation.height) * 1.25
    }

    private func toggle() {
        guard canEdit else { return }
        onToggle()
    }

    private func beginHorizontalDragIfNeeded() {
        guard !isHorizontalDragActive else { return }
        isHorizontalDragActive = true
        onHorizontalSwipeActivityChange?(true)
    }

    private func endHorizontalDragIfNeeded(notifyAsynchronously: Bool) {
        guard isHorizontalDragActive else { return }
        isHorizontalDragActive = false

        if notifyAsynchronously {
            DispatchQueue.main.async {
                onHorizontalSwipeActivityChange?(false)
            }
        } else {
            onHorizontalSwipeActivityChange?(false)
        }
    }
}

private struct InkStrikeText: View {
    let title: String
    let isCompleted: Bool
    let dragProgress: CGFloat
    let strikeColor: Color

    var body: some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(isCompleted ? .secondary : .primary)
            .animation(.easeInOut(duration: 0.2), value: dragProgress)
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
