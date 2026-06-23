import SwiftUI

/// Full-screen "Restoring your data…" overlay shown while a fresh-install restore is
/// actively downloading from iCloud. Makes the wait read as intentional progress.
struct RestoreProgressOverlay: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Image(systemName: "icloud.and.arrow.down.fill")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundColor(.accentColor)

                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.2)

                VStack(spacing: 6) {
                    Text("restore.progress.title")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                    Text("restore.progress.subtitle")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
            }
        }
    }
}

/// Small non-intrusive banner shown once after a successful iCloud restore.
struct RestoreBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "icloud.and.arrow.down.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 1) {
                Text("settings.restore_settings")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text("settings.icloud_applied")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.88))
        )
        .padding(.horizontal, 16)
    }
}
