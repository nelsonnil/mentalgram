import SwiftUI

// MARK: - Limits & Safety Help View

struct LimitsHelpView: View {
    var onClose: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .top) {
            VaultTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                limitsTopBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        whyLimitsSection
                        cooldownTableSection
                        whatIsDetectionSection
                        duringShowSection
                        goldenRuleSection
                        recoverySection
                        reloginSection
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

    private var limitsTopBar: some View {
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
                Text("Límites & Seguridad")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                    .padding(.top, 8)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    // MARK: - Why limits exist

    private var whyLimitsSection: some View {
        limSection(icon: "shield.lefthalf.filled", iconColor: VaultTheme.Colors.success, title: "Por qué existen los límites") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Instagram impone límites de uso en su API para evitar spam y comportamiento automatizado. Es una medida de seguridad normal que aplica a cualquier app conectada a la plataforma.")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                infoBox(
                    icon: "checkmark.seal.fill",
                    iconColor: VaultTheme.Colors.success,
                    text: "Vault está diseñado con tiempos de espera y espaciados automáticos que respetan esos límites. El mago no tiene que hacer nada — la app lo gestiona por él.",
                    bgColor: VaultTheme.Colors.success
                )

                Text("Si pulsas una función y parece que no responde de inmediato, lo más probable es que la app esté esperando el tiempo de seguridad antes de la siguiente acción. Espera unos segundos y vuelve a intentarlo.")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Cooldown table

    private var cooldownTableSection: some View {
        limSection(icon: "timer", iconColor: VaultTheme.Colors.warning, title: "Tiempos de espera de la app") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Estos valores están integrados automáticamente — no requieren ninguna acción por tu parte:")
                    .font(.system(size: 13))
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)

                cooldownRow(action: "Entre fotos de un set al subir",
                            time: "~3 min",
                            detail: "160–220 s aleatorio por foto")
                cooldownDivider
                cooldownRow(action: "Entre reveals consecutivos",
                            time: "90 s",
                            detail: "Mínimo entre un reveal y el siguiente")
                cooldownDivider
                cooldownRow(action: "Entre archivados (Sync & Archive)",
                            time: "1,5–3 s",
                            detail: "Por cada foto archivada")
                cooldownDivider
                cooldownRow(action: "Límite de acciones por hora",
                            time: "55 máx.",
                            detail: "La app deja de actuar si se acerca al límite")
            }
            .padding(12)
            .background(VaultTheme.Colors.cardBackground)
            .cornerRadius(12)
        }
    }

    // MARK: - What is detection

    private var whatIsDetectionSection: some View {
        limSection(icon: "antenna.radiowaves.left.and.right", iconColor: Color(hex: "FF9F0A"), title: "Qué es una detección y cuándo ocurre") {
            VStack(alignment: .leading, spacing: 10) {
                Text("De vez en cuando Instagram puede pedir una verificación de identidad si detecta actividad inusual. Esto es completamente temporal y no supone ningún riesgo real para la cuenta.")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("La app reacciona automáticamente pausando la sesión durante el tiempo necesario:")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    detectionRow(type: "Verificación puntual", duration: "2–3 min", color: Color(hex: "FF9F0A"))
                    detectionRow(type: "Demasiadas peticiones (429)", duration: "5 min", color: Color(hex: "FF9F0A"))
                    detectionRow(type: "Acción bloqueada", duration: "15 min", color: VaultTheme.Colors.error)
                    detectionRow(type: "Spam detectado", duration: "10 min", color: VaultTheme.Colors.error)
                    detectionRow(type: "Sesión expirada", duration: "Re-login necesario", color: VaultTheme.Colors.error)
                }
                .padding(10)
                .background(VaultTheme.Colors.cardBackground)
                .cornerRadius(10)

                Text("En todos los casos excepto la sesión expirada, la app se recupera sola sin intervención.")
                    .font(.system(size: 12))
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - During the show

    private var duringShowSection: some View {
        limSection(icon: "theatermasks.fill", iconColor: Color(hex: "A78BFA"), title: "Durante la actuación") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Si ocurre una detección mientras el espectador está mirando, la app oculta los detalles técnicos y muestra una pantalla genérica de \"Sin conexión a Internet\".")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                infoBox(
                    icon: "wifi.slash",
                    iconColor: Color(hex: "A78BFA"),
                    text: "Es una excusa natural y creíble: \"Ah, la conexión de Instagram falla un momento, no pasa nada.\" Ningún espectador verá nada técnico.",
                    bgColor: Color(hex: "A78BFA")
                )

                Text("Qué hacer en ese momento:")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)

                stepRow(number: "1", text: "Señala la pantalla con naturalidad: \"Ah, Instagram falla un segundo\"")
                stepRow(number: "2", text: "Espera 2–3 minutos — la app se recupera sola en la mayoría de casos")
                stepRow(number: "3", text: "Si el problema persiste, continúa con otra parte de la actuación y retoma después")
            }
        }
    }

    // MARK: - Golden rule

    private var goldenRuleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: "FF9F0A").opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "FF9F0A"))
                }
                Text("Regla de oro")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
            }

            infoBox(
                icon: "arrow.right.circle.fill",
                iconColor: Color(hex: "FF9F0A"),
                text: "Si la app no responde o algo parece bloqueado, ve directamente a la app oficial de Instagram. Instagram puede haber mostrado un aviso de actividad inusual que requiere tu atención. Hasta que no lo resuelvas allí, Vault no podrá continuar.",
                bgColor: Color(hex: "FF9F0A")
            )
        }
    }

    // MARK: - Recovery steps

    private var recoverySection: some View {
        limSection(icon: "arrow.clockwise.circle.fill", iconColor: VaultTheme.Colors.primary, title: "Cómo recuperar la sesión") {
            VStack(alignment: .leading, spacing: 16) {

                // Scenario A
                scenarioBlock(
                    label: "Escenario A",
                    subtitle: "Verificación puntual — el más habitual",
                    color: VaultTheme.Colors.primary,
                    steps: [
                        "La app no responde o muestra un aviso de bloqueo",
                        "Abre la app oficial de Instagram",
                        "Si aparece un aviso de actividad inusual, pulsa \"Dismiss\" o completa el código de verificación (email o SMS)",
                        "Si no aparece nada, espera 2 minutos — la sesión se restablece sola en Vault",
                        "Vuelve a Vault: todo continúa con normalidad"
                    ]
                )

                // Scenario B
                scenarioBlock(
                    label: "Escenario B",
                    subtitle: "Sesión expirada — poco frecuente",
                    color: VaultTheme.Colors.warning,
                    steps: [
                        "Vault muestra la pantalla de re-login",
                        "Ve primero a Instagram real para descartar cualquier aviso pendiente y pulsa \"Dismiss\" si lo hay",
                        "Vuelve a Vault y pulsa \"Connect Account\"",
                        "Entra con tu usuario y contraseña",
                        "Acepta las cookies cuando Instagram lo pida — es indispensable",
                        "La sesión se restaura automáticamente"
                    ]
                )

                // Scroll reminder
                scrollWarningBox
            }
        }
    }

    // MARK: - When to re-login manually

    private var reloginSection: some View {
        limSection(icon: "person.badge.key.fill", iconColor: VaultTheme.Colors.secondary, title: "Cuándo hacer re-login manualmente") {
            VStack(alignment: .leading, spacing: 10) {
                Text("No es necesario hacer logout antes de cada actuación. Una sesión activa puede durar semanas. Haz re-login solo si:")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                limBullet(icon: "exclamationmark.circle.fill", iconColor: VaultTheme.Colors.error,
                          text: "La app lleva más de 24 h sin responder correctamente a ninguna acción")
                limBullet(icon: "exclamationmark.circle.fill", iconColor: VaultTheme.Colors.error,
                          text: "Se producen 3 o más detecciones seguidas en la misma sesión")
                limBullet(icon: "exclamationmark.circle.fill", iconColor: VaultTheme.Colors.error,
                          text: "El botón \"Reconnect\" aparece persistentemente en Settings")

                Text("En el resto de situaciones, la app gestiona la sesión de forma automática.")
                    .font(.system(size: 12))
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Scroll reminder box

    private var scrollWarningBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.primary)
                Text("Aviso importante — scroll hacia abajo")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
            }
            Text("Tras reconectar, si no ves las fotos que esperabas en tu perfil de Instagram, haz scroll hacia abajo para forzar la actualización.")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Instagram muestra a veces la versión en caché hasta que se refresca manualmente con un deslizamiento hacia abajo.")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(VaultTheme.Colors.primary.opacity(0.07))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(VaultTheme.Colors.primary.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Shared helpers

    private func limSection<Content: View>(
        icon: String, iconColor: Color, title: String,
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

    private func limBullet(icon: String, iconColor: Color, text: String) -> some View {
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

    private func infoBox(icon: String, iconColor: Color, text: String, bgColor: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(iconColor)
                .frame(width: 20)
                .padding(.top, 1)
            Text(text)
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(bgColor.opacity(0.07))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(bgColor.opacity(0.25), lineWidth: 1)
        )
    }

    private func cooldownRow(action: String, time: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(action)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(VaultTheme.Colors.textSecondary)
            }
            Spacer()
            Text(time)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(VaultTheme.Colors.warning)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }

    private var cooldownDivider: some View {
        Divider()
            .background(Color.secondary.opacity(0.2))
    }

    private func detectionRow(type: String, duration: String, color: Color) -> some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(type)
                    .font(.system(size: 13))
                    .foregroundColor(VaultTheme.Colors.textSecondary)
            }
            Spacer()
            Text(duration)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
        }
    }

    private func stepRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(hex: "A78BFA").opacity(0.15))
                    .frame(width: 22, height: 22)
                Text(number)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "A78BFA"))
            }
            Text(text)
                .font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    private func scenarioBlock(label: String, subtitle: String, color: Color, steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(color.opacity(0.12))
                    .cornerRadius(20)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(VaultTheme.Colors.textSecondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(color.opacity(0.15))
                                .frame(width: 22, height: 22)
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(color)
                        }
                        Text(step)
                            .font(VaultTheme.Typography.body())
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
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
