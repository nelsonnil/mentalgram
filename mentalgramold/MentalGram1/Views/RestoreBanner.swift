import SwiftUI

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
