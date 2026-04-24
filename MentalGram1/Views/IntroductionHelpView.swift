import SwiftUI

// MARK: - Introduction Help View

struct IntroductionHelpView: View {
    var onClose: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .top) {
            VaultTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                introTopBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        heroBlock
                        howItWorksSection
                        whyItMattersSection
                        threePillarsSection
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    // MARK: - Top bar

    private var introTopBar: some View {
        ZStack {
            HStack {
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                    }
                    .padding(.trailing, 20)
                }
            }
            VStack(spacing: 2) {
                Capsule()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 36, height: 4)
                Text("What is Vault?")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                    .padding(.top, 8)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    // MARK: - Hero

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(hex: "A78BFA").opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 26))
                        .foregroundColor(Color(hex: "A78BFA"))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Vault — Instagram Magic")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Text("Hybrid app · Real account · Real results")
                        .font(.system(size: 13))
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                }
            }

            Text("Vault se conecta directamente a tu cuenta de Instagram real sin necesitar un perfil separado, un público especial ni ninguna configuración visible.")
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Todo lo que ejecutas ocurre en la misma cuenta que tus espectadores ya siguen — y lo que ven ellos es Instagram, no la app.")
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color(hex: "A78BFA").opacity(0.06))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "A78BFA").opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - How it works

    private var howItWorksSection: some View {
        introSection(icon: "bolt.fill", iconColor: VaultTheme.Colors.primary, title: "Cómo funciona") {
            VStack(alignment: .leading, spacing: 10) {
                introBullet(icon: "photo.stack.fill", iconColor: VaultTheme.Colors.success,
                            text: "Sube, archiva y desarchiva fotos en el momento exacto que eliges")
                introBullet(icon: "person.crop.circle.fill", iconColor: Color(hex: "A78BFA"),
                            text: "Cambia tu foto de perfil al instante desde la app")
                introBullet(icon: "bubble.left.fill", iconColor: VaultTheme.Colors.warning,
                            text: "Publica o actualiza tu nota e Instagram en tiempo real")
                introBullet(icon: "text.alignleft", iconColor: VaultTheme.Colors.secondary,
                            text: "Edita tu biografía para que coincida con lo que el espectador está pensando")
                introBullet(icon: "person.2.fill", iconColor: Color(hex: "34D399"),
                            text: "Consulta seguidores y seguidos para efectos de counter glitch")
                introBullet(icon: "calendar", iconColor: Color(hex: "F472B6"),
                            text: "Recupera metadatos — fechas, posición en grid, subtítulos — para forzajes de fecha")
            }
        }
    }

    // MARK: - Why it matters

    private var whyItMattersSection: some View {
        introSection(icon: "eye.fill", iconColor: Color(hex: "F472B6"), title: "Por qué importa en magia") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cuando el espectador abre Instagram en su propio móvil ve el resultado real — no una captura de pantalla, no una simulación.")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                quoteBox(
                    text: "La predicción estaba ahí desde el principio, archivada e invisible hasta que tú decidiste revelarla. El forzaje lo confirmó el algoritmo de Instagram. La fecha estaba grabada en una publicación de hace meses.",
                    color: Color(hex: "F472B6")
                )

                Text("Vault te da el control de una capa de Instagram que ningún espectador puede cuestionar — porque no es la app, es Instagram mismo.")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Three pillars

    private var threePillarsSection: some View {
        introSection(icon: "square.3.layers.3d.fill", iconColor: VaultTheme.Colors.secondary, title: "Tres pilares") {
            VStack(alignment: .leading, spacing: 12) {
                pillarCard(
                    icon: "shuffle",
                    color: VaultTheme.Colors.primary,
                    title: "Forzajes",
                    body: "Dirige al espectador hacia un número, fecha o post que ya conoces.",
                    tags: ["Force Post", "Force Reel", "Date Force", "Counter Glitch"]
                )
                pillarCard(
                    icon: "archivebox.fill",
                    color: VaultTheme.Colors.success,
                    title: "Predicciones",
                    body: "Pre-sube una foto que coincide con la elección del espectador, archívala, y desarchívala en el clímax.",
                    tags: ["Post Prediction"]
                )
                pillarCard(
                    icon: "person.crop.circle.badge.checkmark",
                    color: Color(hex: "A78BFA"),
                    title: "Reveals de perfil",
                    body: "Cambia tu foto, nota o biografía en tiempo real para que coincida con lo que el espectador está pensando.",
                    tags: ["Profile Picture", "Note", "Biography"]
                )
            }
        }
    }

    // MARK: - Shared helpers

    private func introSection<Content: View>(
        icon: String, iconColor: Color, title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
            }
            content()
        }
    }

    private func introBullet(icon: String, iconColor: Color, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 20)
                .padding(.top, 2)
            Text(text)
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func quoteBox(text: LocalizedStringKey, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(color.opacity(0.6))
                .frame(width: 3)
                .cornerRadius(2)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .italic()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func pillarCard(icon: String, color: Color, title: LocalizedStringKey, body: LocalizedStringKey, tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
            }
            Text(body)
                .font(.system(size: 13))
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(color.opacity(0.12))
                        .cornerRadius(20)
                }
            }
        }
        .padding(12)
        .background(color.opacity(0.05))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}
