import SwiftUI

// MARK: - Section Header

/// Reusable styled header used at the top of each module view.
struct SectionHeader: View {
    let icon:  String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Error Banner

/// A dismissable inline error/warning banner.
struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
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
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#if DEBUG
struct SharedViews_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            SectionHeader(icon: "gearshape", title: "Module Settings")
            ErrorBanner(message: "Something went wrong. Please check your settings.")
            EmptyStateView(
                title: "No Items",
                systemImage: "tray",
                description: "Nothing to show here."
            )
        }
        .padding()
        .frame(width: 400)
    }
}
#endif
