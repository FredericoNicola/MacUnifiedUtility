import SwiftUI

// MARK: - Section Header

/// Reusable styled header used at the top of each module view.
struct SectionHeader: View {
    let icon:  String
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.linearGradient(
                    colors: [.accentColor, .accentColor.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.accentColor.opacity(0.12))
                )
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
        }
    }
}

// MARK: - Error Banner

/// A modern inline warning/error banner with expandable long messages.
struct ErrorBanner: View {
    let message: String
    @State private var isExpanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)

            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(isExpanded ? nil : 2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if message.count > 100 {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.orange.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Empty State View

/// macOS 13-compatible empty-state placeholder (replaces `ContentUnavailableView`
/// which requires macOS 14+).
struct EmptyStateView: View {
    let title:       String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(.linearGradient(
                    colors: [.secondary.opacity(0.6), .secondary.opacity(0.3)],
                    startPoint: .top,
                    endPoint: .bottom
                ))

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Card View

/// Modern card container with subtle shadow and border.
struct CardView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                    )
            )
    }
}

// MARK: - Status Dot

/// Styled status indicator dot.
struct StatusDot: View {
    let isActive: Bool
    let activeColor: Color

    init(isActive: Bool, activeColor: Color = .green) {
        self.isActive = isActive
        self.activeColor = activeColor
    }

    var body: some View {
        Circle()
            .fill(isActive ? activeColor : Color.secondary.opacity(0.4))
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .fill(isActive ? activeColor.opacity(0.3) : .clear)
                    .frame(width: 14, height: 14)
            )
    }
}

// MARK: - Tag Badge

/// Modern pill-shaped tag/badge.
struct TagBadge: View {
    let text:  String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
    }
}

// MARK: - Preview

#if DEBUG
struct SharedViews_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            SectionHeader(icon: "gearshape", title: "Module Settings")
            ErrorBanner(message: "Something went wrong. Please check your settings and try again.")
            ErrorBanner(message: "SMC connected but no sensors responded. On Apple Silicon Macs some sensor keys differ from Intel. The app may need updated sensor keys for your hardware.")
            EmptyStateView(
                title: "No Items",
                systemImage: "tray",
                description: "Nothing to show here."
            )
            CardView {
                Text("Card content goes here")
            }
            HStack {
                StatusDot(isActive: true)
                StatusDot(isActive: false)
                TagBadge(text: "Normal", color: .green)
                TagBadge(text: "Hot", color: .orange)
            }
        }
        .padding()
        .frame(width: 400)
    }
}
#endif
