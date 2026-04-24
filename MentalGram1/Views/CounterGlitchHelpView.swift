import SwiftUI

// MARK: - Counter Glitch Effect Help View

struct CounterGlitchHelpView: View {
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            VaultTheme.Colors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    heroHeader.padding(.bottom, VaultTheme.Spacing.lg)
                    CounterGlitchAnimatedDemo()
                        .padding(.horizontal, VaultTheme.Spacing.lg)
                        .padding(.bottom, VaultTheme.Spacing.xl)
                    Group {
                        CGHSection(icon: "wand.and.stars",          iconColor: Color(hex: "6366F1"), title: "Cómo funciona")      { howItWorks }
                        cghDivider
                        CGHSection(icon: "gearshape.fill",           iconColor: VaultTheme.Colors.success, title: "Preparación") { setupSteps }
                        cghDivider
                        CGHSection(icon: "theatermasks.fill",         iconColor: Color(hex: "E63946"),       title: "Guión")       { scriptSection }
                        cghDivider
                        CGHSection(icon: "arrow.left.arrow.right.circle.fill", iconColor: Color(hex: "F97316"), title: "Modo Transfer") { transferSection }
                        cghDivider
                        CGHSection(icon: "lightbulb.fill",           iconColor: Color(hex: "F472B6"),       title: "Consejos")    { tipsSection }
                    }
                    .padding(.horizontal, VaultTheme.Spacing.lg)
                    Spacer(minLength: 60)
                }
                .padding(.top, 80)
            }
            // Fixed top bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Counter Glitch Effect").font(VaultTheme.Typography.titleSmall()).foregroundColor(VaultTheme.Colors.textPrimary)
                    Text("Performance Guide").font(VaultTheme.Typography.caption()).foregroundColor(VaultTheme.Colors.textSecondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(VaultTheme.Colors.textSecondary)
                        .frame(width: 32, height: 32).background(VaultTheme.Colors.backgroundSecondary).clipShape(Circle())
                }
            }
            .padding(.horizontal, VaultTheme.Spacing.lg).padding(.vertical, VaultTheme.Spacing.md)
            .background(VaultTheme.Colors.background.shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4))
        }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        VStack(spacing: VaultTheme.Spacing.md) {
            ZStack {
                Circle().fill(Color(hex: "6366F1").opacity(0.15)).frame(width: 80, height: 80)
                Text("🎭").font(.system(size: 40))
            }
            Text("Counter Glitch Effect")
                .font(VaultTheme.Typography.title()).foregroundColor(VaultTheme.Colors.textPrimary)
            Text("El espectador dice un número del 1 al 100. El mago lo registra en secreto y abre el perfil de Instagram de un participante: el contador aparece inflado. Al pulsar el botón de volumen, un glitch y cuenta regresiva revelan el número \"robado\".")
                .font(VaultTheme.Typography.body()).foregroundColor(VaultTheme.Colors.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, VaultTheme.Spacing.lg)
        }
        .frame(maxWidth: .infinity).padding(.vertical, VaultTheme.Spacing.xl)
    }

    private var cghDivider: some View {
        Rectangle().fill(VaultTheme.Colors.cardBorder).frame(height: 1).padding(.vertical, VaultTheme.Spacing.xl)
    }

    // MARK: - How it works

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            CGHBody("La app infla silenciosamente el contador real sumándole el número del espectador. Cuando el glitch termina la cuenta regresiva, el contador vuelve al número real — que el espectador reconoce como \"el de siempre\". La ilusión: los números \"desaparecieron\".")
            CGHMetric(icon: "hand.point.left.fill", color: Color(hex: "6366F1"), label: "Dígito secreto vía swipe",
                      desc: "En el grid de posts/reels del perfil, cada swipe izquierda en una celda registra el dígito de esa posición (1–9, luego 0). Igual que Force Reel.")
            CGHMetric(icon: "plus.circle.fill", color: VaultTheme.Colors.primary, label: "Inflado invisible",
                      desc: "El perfil abierto muestra real + número_espectador. Si el real es 500 y el espectador dijo 37, verá 537. En perfiles con 10K+, cada unidad cuenta como 1K (input 6 en 200K → muestra 206K → baja a 200K).")
            CGHMetric(icon: "bolt.fill", color: Color(hex: "F97316"), label: "Glitch + cuenta regresiva",
                      desc: "Al pulsar el botón de volumen: efecto glitch (distorsión de señal) y luego el contador baja de 537 a 500 en ~6 segundos.")
            CGHMetric(icon: "checkmark.seal.fill", color: VaultTheme.Colors.success, label: "La convicción",
                      desc: "Cuando el espectador comprueba su móvil ve 500 — el número de siempre. Confirma sin saberlo que le quitaron exactamente 37.")
            CGHInfoBox("El perfil puede ser del espectador, de un voluntario elegido al azar, o el del propio mago.")
        }
    }

    // MARK: - Setup

    private var setupSteps: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
            CGHStep(n: 1, text: "Activa **Counter Glitch Effect** en Settings. Elige si el contador objetivo es **Followers** o **Following**.")
            CGHStep(n: 2, text: "Opcional: activa **Transfer Effect** si quieres que el número \"robado\" aparezca sumándose a tu propio perfil.")
            CGHStep(n: 3, text: "Configura el **Delay** antes de la cuenta regresiva (0–10 s) para poder hablar antes de que empiecen los números a bajar.")
            CGHStep(n: 4, text: "Memoriza el mapa de dígitos: fila 1 → 1,2,3 · fila 2 → 4,5,6 · fila 3 → 7,8,9 · fila 4 → 0 (cualquier celda).")
            CGHStep(n: 5, text: "En Performance, abre el perfil del participante. **Antes** de abrirlo, entra al grid de posts y registra los dígitos con swipes izquierda.")
        }
    }

    // MARK: - Script

    private var scriptSection: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.xl) {
            CGHBody("Un guión con drama para justificar el efecto y crear convicción.")

            cghScriptBlock(
                tag: "LA PROPUESTA",
                tagColor: Color(hex: "6366F1"),
                icon: "megaphone.fill",
                stage: "Señala a un participante. Sin tocar el móvil todavía.",
                lines: [
                    "«Quiero hacer un pequeño experimento. Algo que nunca ha podido demostrarse de forma pública.»",
                    "«¿Puedes decirme un número del 1 al 100? El que quieras. Sin pensar demasiado.»",
                    "«[El número dicho]. Perfecto. Ese número ahora te pertenece.»",
                ],
                note: "Mientras hablas y el espectador piensa el número, empieza discretamente a navegar el grid de su perfil para registrar los dígitos."
            )

            cghScriptBlock(
                tag: "LA JUSTIFICACIÓN",
                tagColor: Color(hex: "F97316"),
                icon: "person.fill.questionmark",
                stage: "Abre el perfil de Instagram del participante mostrando la pantalla.",
                lines: [
                    "«Instagram lleva un registro de todo. Cada seguidor, cada conexión... tiene un peso.»",
                    "«Mira cuánta gente te sigue. [lee el número inflado]. [Número]. Personas reales que eligieron estar pendientes de ti.»",
                    "«Ahora voy a hacer algo que no debería ser posible.»",
                ]
            )

            cghScriptBlock(
                tag: "EL MOMENTO",
                tagColor: Color(hex: "E63946"),
                icon: "bolt.fill",
                stage: "Pulsa el botón de volumen con naturalidad. El glitch comienza.",
                lines: [
                    "«[Número dicho por el espectador]. Ese es tu número. Voy a tomarlo prestado... por un momento.»",
                ],
                note: "Di esto justo cuando el glitch arranca. El delay que hayas configurado te da margen para hablar antes del conteo."
            )

            cghScriptBlock(
                tag: "LA REVELACIÓN",
                tagColor: VaultTheme.Colors.success,
                icon: "sparkles",
                stage: "El contador termina de bajar. Silencio. Luego:",
                lines: [
                    "«[Número dicho]. Desaparecidos. Echa un vistazo a tu móvil. ¿Cuántos seguidores tienes?»",
                    "«Exactamente los mismos de siempre. Excepto que hace unos segundos había [número] más.»",
                    "«No te preocupes — solo los tomé prestados. [Si Transfer mode]: los tienes en el mío.»",
                ]
            )
        }
    }

    // MARK: - Transfer

    private var transferSection: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            CGHBody("Con **Transfer Effect** activado, el truco tiene una segunda fase: el número \"robado\" del espectador aparece sumándose al perfil del mago.")
            CGHMetric(icon: "1.circle.fill", color: Color(hex: "6366F1"), label: "Fase 1 — Deflación",
                      desc: "El perfil del espectador/voluntario cuenta regresivamente del número inflado al real.")
            CGHMetric(icon: "2.circle.fill", color: Color(hex: "F97316"), label: "Fase 2 — Inflación",
                      desc: "Abre tu propio perfil. Pulsa el botón de volumen de nuevo: el mismo número aparece sumándose a tu contador — como si los seguidores hubieran \"viajado\" de un perfil al otro.")
            CGHInfoBox("Asegúrate de navegar a tu propio perfil antes de pulsar el volumen la segunda vez. La app guarda el offset de la Fase 1 y lo usa en la Fase 2.")
        }
    }

    // MARK: - Tips

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            CGHTip(icon: "hand.point.left.fill", color: Color(hex: "6366F1"),
                   text: "**Registra los dígitos antes de abrir el perfil.** Una vez el número inflado está visible, cualquier swipe accidental lo resetearía.")
            CGHTip(icon: "clock.fill", color: VaultTheme.Colors.primary,
                   text: "**Usa el delay.** 3–5 segundos de pausa entre el botón y la cuenta regresiva te dan tiempo para hablar y construir expectativa.")
            CGHTip(icon: "person.2.fill", color: VaultTheme.Colors.success,
                   text: "**Perfil propio o ajeno.** Con el perfil del espectador el impacto es mayor porque puede verificar inmediatamente. Con el tuyo tienes más control.")
            CGHTip(icon: "eye.slash.fill", color: VaultTheme.Colors.warning,
                   text: "**No enseñes la pantalla hasta tener el número inflado.** Navega el grid con el móvil hacia ti, después gíralo.")
            CGHTip(icon: "arrow.left.arrow.right.circle", color: Color(hex: "F97316"),
                   text: "**Transfer mode** funciona mejor en shows pequeños donde el público puede ver ambos perfiles y el \"viaje\" del número.")
            CGHTip(icon: "k.circle.fill", color: Color(hex: "BF5AF2"),
                   text: "**Perfiles con 10K+.** El offset se multiplica ×1000 automáticamente. Pide un número del 1–10 al espectador y la cuenta regresiva baja en unidades de K (206K → 200K).")
        }
    }

    // MARK: - Script block helper

    private func cghScriptBlock(
        tag: LocalizedStringKey,
        tagColor: Color,
        icon: String,
        stage: LocalizedStringKey? = nil,
        lines: [LocalizedStringKey],
        note: LocalizedStringKey? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(tagColor)
                Text(tag)
                    .font(.system(size: 11, weight: .bold)).foregroundColor(tagColor).tracking(0.8)
            }
            if let stage {
                Text(stage)
                    .font(.system(size: 11, weight: .medium).italic())
                    .foregroundColor(VaultTheme.Colors.textSecondary.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 7) {
                ForEach(lines.indices, id: \.self) { i in
                    let line = lines[i]
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle().fill(tagColor).frame(width: 3).cornerRadius(2).padding(.top, 2)
                        Text(line)
                            .font(.system(size: 12, weight: .medium).italic())
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let note {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle.fill").font(.system(size: 10)).foregroundColor(Color(hex: "0095F6")).padding(.top, 1)
                    Text(note).font(.system(size: 10)).foregroundColor(VaultTheme.Colors.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(8).background(Color(hex: "0095F6").opacity(0.06)).cornerRadius(8)
            }
        }
        .padding(12)
        .background(tagColor.opacity(0.04))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tagColor.opacity(0.15), lineWidth: 1))
    }
}

// MARK: - ── Animated Demo ──────────────────────────────────────────────────────

private struct CounterGlitchAnimatedDemo: View {

    enum Scene { case digits, inflated, glitch, conviction }
    @State private var scene: Scene = .digits
    @State private var sceneAnimDone = false

    // Scene 1 — digit input (adapted from ForceReelHelpView)
    @State private var activeTab:       Int     = 0
    @State private var accumDigits:     [Int]   = []
    @State private var activeSwipeCell: Int?    = nil
    @State private var swipeTrail:      CGFloat = 0
    @State private var showFinger:      Bool    = false
    @State private var fingerOffset:    CGSize  = .zero
    @State private var followingBounce: CGFloat = 1.0
    @State private var confirmFlash:    Bool    = false

    // Scene 2 — inflated profile
    @State private var inflatedGlow: Double = 0
    @State private var showInflatedBadge = false

    // Scene 3 — glitch + countdown
    @State private var glitchPhase: GlitchPhase = .idle
    @State private var countdownValue: Int = 537
    @State private var glitchStrips: [GlitchStrip] = []
    @State private var glitchRGB: CGFloat = 0
    @State private var glitchFlash: Double = 0
    @State private var glitchTimer: Timer? = nil
    @State private var volumePressed = false

    // Scene 4 — conviction
    @State private var spectatorPhoneVisible = false
    @State private var transferArrowVisible  = false
    @State private var magicianPhoneVisible  = false

    @State private var sceneTask: Task<Void, Never>? = nil

    enum GlitchPhase { case idle, glitching, counting, done }

    // ── Fixed example values ───────────────────────────────────────────────
    private let realCount  = 500
    private let secretNum  = 37
    private var inflated: Int { realCount + secretNum }  // 537

    // ── Phone dimensions ───────────────────────────────────────────────────
    private let phoneW: CGFloat = 248
    private let phoneH: CGFloat = 492
    private let cellW:  CGFloat = 82
    private let cellH:  CGFloat = 66
    private var gridCX: CGFloat { phoneW / 2 }
    private var gridCY: CGFloat { 268 / 2 }

    private func cellCenter(_ idx: Int) -> CGSize {
        let col = idx % 3; let row = idx / 3
        return CGSize(
            width:  CGFloat(col) * (cellW + 1) + cellW / 2 - gridCX,
            height: CGFloat(row) * (cellH + 1) + cellH / 2 - gridCY
        )
    }

    private let cellDigits = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 0, 0]

    private let postGradients: [LinearGradient] = [
        LinearGradient(colors: [Color(hex: "1a0f40"), Color(hex: "0d0820")], startPoint: .topLeading,  endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "0f2040"), Color(hex: "081028")], startPoint: .top,         endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "2a1a1a"), Color(hex: "180f0f")], startPoint: .top,         endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "1a2a1a"), Color(hex: "0f180f")], startPoint: .topTrailing, endPoint: .bottom),
        LinearGradient(colors: [Color(hex: "1a1a2a"), Color(hex: "0f0f18")], startPoint: .topLeading,  endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "2e1a2e"), Color(hex: "1a0f18")], startPoint: .top,         endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "1a2e1a"), Color(hex: "0f1a0f")], startPoint: .topLeading,  endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "2e2e1a"), Color(hex: "1a1a0f")], startPoint: .topLeading,  endPoint: .bottomLeading),
        LinearGradient(colors: [Color(hex: "2a1a1a"), Color(hex: "180f0f")], startPoint: .top,         endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "1a1a2a"), Color(hex: "0f0f18")], startPoint: .topLeading,  endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "2e1a2e"), Color(hex: "1a0f18")], startPoint: .top,         endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "1a2e1a"), Color(hex: "0f1a0f")], startPoint: .topLeading,  endPoint: .bottomTrailing),
    ]
    private let postIcons = ["building.2.fill","tree.fill","sun.horizon.fill","figure.run",
                             "star.fill","camera.fill","music.note","flame.fill","heart.fill",
                             "moon.stars.fill","leaf.fill","bolt.fill"]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 14) {
            // Context note
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill").font(.system(size: 13)).foregroundColor(Color(hex: "6366F1"))
                    Text("La ilusión").font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "6366F1"))
                    Spacer()
                }
                Text("La app **suma** el número al contador real. El espectador ve el total inflado y cree que siempre fue así. El glitch lo \"devuelve\" al original — que él reconocerá como el número verdadero.")
                    .font(.system(size: 11)).foregroundColor(VaultTheme.Colors.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(Color(hex: "6366F1").opacity(0.06))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "6366F1").opacity(0.18), lineWidth: 1))

            // Scene pills
            HStack(spacing: 6) {
                scenePill(n: "1", label: "cgdemo.pill.your_profile", active: scene == .digits)
                scenePill(n: "2", label: "cgdemo.pill.spectator",    active: scene == .inflated)
                scenePill(n: "3", label: "Glitch",                   active: scene == .glitch)
                scenePill(n: "4", label: "cgdemo.pill.conviction",   active: scene == .conviction)
            }

            // Phone owner badge — shows whose phone/profile is on screen
            Group {
                switch scene {
                case .digits:
                    phoneOwnerBadge(
                        label: "cgdemo.badge.your_phone",
                        sublabel: "cgdemo.badge.your_phone_sub",
                        icon: "iphone", color: Color(hex: "6366F1")
                    )
                case .inflated:
                    phoneOwnerBadge(
                        label: "cgdemo.badge.spectator_profile",
                        sublabel: "cgdemo.badge.spectator_profile_sub",
                        icon: "person.fill", color: Color(hex: "BF5AF2")
                    )
                case .glitch:
                    phoneOwnerBadge(
                        label: "cgdemo.badge.spectator_glitch",
                        sublabel: "cgdemo.badge.spectator_glitch_sub",
                        icon: "bolt.fill", color: Color(hex: "F97316")
                    )
                case .conviction:
                    phoneOwnerBadge(
                        label: "cgdemo.badge.conviction",
                        sublabel: "cgdemo.badge.conviction_sub",
                        icon: "checkmark.circle.fill", color: VaultTheme.Colors.success
                    )
                }
            }
            .animation(.easeInOut(duration: 0.3), value: scene)

            phoneMockup
                .shadow(color: Color(hex: "6366F1").opacity(glitchPhase == .done ? 0.5 : inflatedGlow * 0.4), radius: 28)

            // Caption
            Group {
                switch scene {
                case .digits:
                    Text("cgdemo.caption.digits")
                case .inflated:
                    Text("cgdemo.caption.inflated")
                case .glitch:
                    Text("cgdemo.caption.glitch")
                case .conviction:
                    Text("cgdemo.caption.conviction")
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(VaultTheme.Colors.textSecondary)
            .multilineTextAlignment(.center)
            .frame(minHeight: 38)
            .animation(.easeInOut(duration: 0.3), value: scene)

            // Next button
            if sceneAnimDone {
                Button(action: nextScene) {
                    HStack(spacing: 6) {
                        Text(scene == .conviction ? "action.restart" : "action.next")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: scene == .conviction ? "arrow.counterclockwise" : "arrow.right")  
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 22).padding(.vertical, 9)
                    .background(LinearGradient(colors: [Color(hex: "6366F1"), Color(hex: "BF5AF2")], startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(20)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(VaultTheme.Spacing.lg)
        .background(VaultTheme.Colors.backgroundSecondary)
        .cornerRadius(VaultTheme.CornerRadius.lg)
        .overlay(RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.lg).stroke(Color(hex: "6366F1").opacity(0.25), lineWidth: 1))
        .onAppear  { startCurrentScene() }
        .onDisappear { sceneTask?.cancel(); glitchTimer?.invalidate() }
    }

    // MARK: - Navigation

    private func nextScene() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            sceneAnimDone = false
            switch scene {
            case .digits:   scene = .inflated
            case .inflated: scene = .glitch
            case .glitch:   scene = .conviction
            case .conviction: scene = .digits
            }
        }
        startCurrentScene()
    }

    private func startCurrentScene() {
        sceneTask?.cancel()
        sceneTask = Task { @MainActor in
            switch scene {
            case .digits:    await animScene1()
            case .inflated:  await animScene2()
            case .glitch:    await animScene3()
            case .conviction: await animScene4()
            }
            if !Task.isCancelled {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { sceneAnimDone = true }
            }
        }
    }

    // MARK: - Phone mockup

    private var phoneMockup: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 38).fill(Color(hex: "111111"))
                .frame(width: phoneW + 16, height: phoneH + 16)
            // Volume buttons (left side)
            RoundedRectangle(cornerRadius: 2).fill(volumePressed ? Color(hex: "6366F1") : Color(hex: "252525"))
                .frame(width: 3, height: 68).offset(x: -(phoneW / 2 + 9), y: -66)
                .animation(.easeInOut(duration: 0.15), value: volumePressed)
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: "252525"))
                .frame(width: 3, height: 44).offset(x: (phoneW / 2 + 9), y: -52)
            Capsule().fill(Color.black).frame(width: 96, height: 30).offset(y: -(phoneH / 2 + 1))
            RoundedRectangle(cornerRadius: 28).fill(Color(hex: "060606")).frame(width: phoneW, height: phoneH)

            Group {
                switch scene {
                case .digits:    digitsScene.transition(.opacity)
                case .inflated:  inflatedScene.transition(.opacity)
                case .glitch:    glitchScene.transition(.opacity)
                case .conviction: convictionScene.transition(.opacity)
                }
            }
            .frame(width: phoneW, height: phoneH)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .animation(.easeInOut(duration: 0.35), value: scene)
        }
    }

    // MARK: - Scene 1: Digit input (magician's own profile during Performance)

    private var digitsScene: some View {
        ZStack {
            Color(hex: "060606")
            VStack(spacing: 0) {
                igNavBar(username: "magician_ig")
                igProfileStats(following: accumDigits.isEmpty ? "68" : accumDigits.map { "\($0)" }.joined(),
                               followingIsAccum: !accumDigits.isEmpty,
                               followingBounce: followingBounce,
                               accentColor: Color(hex: "6366F1"))
                igBioLine(text: "Ilusionista profesional")
                igActionButtonsOwn
                igTabBar
                ZStack {
                    pagedTabContent
                    if showFinger { fingerView.offset(fingerOffset) }
                    if confirmFlash {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(hex: "6366F1").opacity(0.7), lineWidth: 2)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Scene 2: Inflated profile (spectator's profile)

    private var inflatedScene: some View {
        ZStack {
            Color(hex: "060606")
            VStack(spacing: 0) {
                igNavBar(username: "spectator_ig")
                igProfileStats(following: "\(inflated)",
                               followingIsAccum: true,
                               followingBounce: 1.0,
                               accentColor: Color(hex: "BF5AF2"),
                               glowIntensity: inflatedGlow)
                igBioLine(text: "Espectador · 🎭")
                igActionButtons
                igTabBar
                // Mini post grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
                    ForEach(0..<9, id: \.self) { i in
                        ZStack {
                            postGradients[i]
                            Image(systemName: postIcons[i]).font(.system(size: 16)).foregroundColor(.white.opacity(0.15))
                        }
                        .frame(height: cellH)
                    }
                }
                Spacer()
            }
        }
        .overlay(alignment: .bottom) {
            if showInflatedBadge {
                HStack(spacing: 8) {
                    Image(systemName: "eye.fill").font(.system(size: 11)).foregroundColor(Color(hex: "BF5AF2"))
                    Text("El espectador ve \(inflated) · Real: \(realCount) + \(secretNum)")
                        .font(.system(size: 10, weight: .semibold)).foregroundColor(.white)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.ultraThinMaterial)
                .background(Color.black.opacity(0.6))
                .cornerRadius(20)
                .padding(.bottom, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Scene 3: Glitch + countdown (still spectator's profile)

    private var glitchScene: some View {
        ZStack {
            Color(hex: "060606")
            VStack(spacing: 0) {
                igNavBar(username: "spectator_ig")
                igProfileStats(following: "\(countdownValue)",
                               followingIsAccum: glitchPhase != .idle,
                               followingBounce: 1.0,
                               accentColor: glitchPhase == .done ? VaultTheme.Colors.success : Color(hex: "F97316"),
                               glowIntensity: glitchPhase == .counting ? 0.6 : 0)
                igBioLine(text: "Espectador · 🎭")
                igActionButtons
                igTabBar
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
                    ForEach(0..<9, id: \.self) { i in
                        ZStack {
                            postGradients[i]
                            Image(systemName: postIcons[i]).font(.system(size: 16)).foregroundColor(.white.opacity(0.15))
                        }
                        .frame(height: cellH)
                    }
                }
                Spacer()
            }

            // Mini glitch overlay on top of phone content
            if glitchPhase == .glitching {
                miniGlitchOverlay
                    .transition(.opacity)
            }

            // Flash overlay
            if glitchFlash > 0 {
                Color.white.opacity(glitchFlash).ignoresSafeArea()
            }
        }
    }

    private var miniGlitchOverlay: some View {
        ZStack {
            Color.black.opacity(0.15)
            ForEach(glitchStrips) { strip in
                Rectangle()
                    .fill(strip.color.opacity(strip.opacity))
                    .frame(height: strip.height)
                    .frame(maxWidth: .infinity)
                    .offset(x: strip.xOffset, y: strip.yPos - phoneH / 2)
            }
            // RGB split hint
            if abs(glitchRGB) > 1 {
                Color(red: 1, green: 0, blue: 0).opacity(0.12).offset(x: glitchRGB)
                Color(red: 0, green: 0.9, blue: 1).opacity(0.12).offset(x: -glitchRGB * 0.6)
            }
        }
    }

    // MARK: - Scene 4: Conviction

    private var convictionScene: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "0d0820"), Color(hex: "060606")], startPoint: .top, endPoint: .bottom)

            VStack(spacing: 20) {
                Text("cgdemo.pill.conviction")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(Color(white: 0.5))
                    .padding(.top, 24)

                // Spectator phone
                if spectatorPhoneVisible {
                    miniPhoneCard(
                        label: "Espectador",
                        icon: "person.fill",
                        iconColor: Color(hex: "6366F1"),
                        stat: "\(realCount)",
                        statLabel: "ig.stat.followers",
                        note: "El número de siempre ✓",
                        accentColor: VaultTheme.Colors.success
                    )
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }

                // Transfer arrow
                if transferArrowVisible {
                    HStack(spacing: 8) {
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 18)).foregroundColor(Color(hex: "6366F1"))
                            Text("-\(secretNum)").font(.system(size: 10, weight: .bold)).foregroundColor(Color(hex: "6366F1"))
                        }
                        Text("→").font(.system(size: 20, weight: .bold)).foregroundColor(Color(white: 0.4))
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 18)).foregroundColor(Color(hex: "F97316"))
                            Text("+\(secretNum)").font(.system(size: 10, weight: .bold)).foregroundColor(Color(hex: "F97316"))
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                }

                // Magician phone (Transfer mode)
                if magicianPhoneVisible {
                    miniPhoneCard(
                        label: "cgdemo.label.magician_transfer",
                        icon: "wand.and.stars",
                        iconColor: Color(hex: "F97316"),
                        stat: "\(1240 + secretNum)",
                        statLabel: "ig.stat.followers",
                        note: "+\(secretNum) recibidos 🎩",
                        accentColor: Color(hex: "F97316")
                    )
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }

                Spacer()
            }
        }
    }

    private func miniPhoneCard(label: LocalizedStringKey, icon: String, iconColor: Color, stat: String, statLabel: LocalizedStringKey, note: LocalizedStringKey, accentColor: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(iconColor.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: icon).font(.system(size: 16)).foregroundColor(iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 10, weight: .semibold)).foregroundColor(Color(white: 0.6))
                HStack(spacing: 4) {
                    Text(stat).font(.system(size: 22, weight: .black)).foregroundColor(.white).monospacedDigit()
                    Text(statLabel).font(.system(size: 10)).foregroundColor(Color(white: 0.5))
                }
                Text(note).font(.system(size: 10, weight: .medium)).foregroundColor(accentColor)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accentColor.opacity(0.3), lineWidth: 1))
        .padding(.horizontal, 20)
    }

    // MARK: - Shared profile components

    private func igProfileStats(
        following: String,
        followingIsAccum: Bool,
        followingBounce: CGFloat,
        accentColor: Color = Color(hex: "6366F1"),
        glowIntensity: Double = 0
    ) -> some View {
        HStack(spacing: 0) {
            ZStack {
                Circle()
                    .stroke(LinearGradient(colors: [Color(hex: "F97316"), Color(hex: "E91E8C"), Color(hex: "9B59B6")],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.5)
                    .frame(width: 58, height: 58)
                Circle().fill(Color(hex: "1a0f40")).frame(width: 50, height: 50)
                    .overlay(Text("M").font(.system(size: 20, weight: .bold)).foregroundColor(.white))
            }
            .padding(.leading, 16)
            Spacer()
            igStatItem("12", "Posts")
            Spacer()
            igStatItem("847", "Followers")
            Spacer()
            // Following — the magic counter
            VStack(spacing: 2) {
                ZStack {
                    Text(following)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(followingIsAccum ? accentColor : .white)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                        .id(following)
                }
                .scaleEffect(followingBounce)
                .animation(.spring(response: 0.26, dampingFraction: 0.45), value: followingBounce)
                .shadow(color: accentColor.opacity(glowIntensity * 0.8), radius: glowIntensity > 0 ? 8 : 0)

                Text("Following")
                    .font(.system(size: 10, weight: followingIsAccum ? .bold : .regular))
                    .foregroundColor(followingIsAccum ? accentColor : .white.opacity(0.55))
                    .animation(.easeInOut(duration: 0.2), value: followingIsAccum)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(accentColor.opacity(followingIsAccum ? 0.6 : 0), lineWidth: 1.5)
                    .background(RoundedRectangle(cornerRadius: 8).fill(accentColor.opacity(followingIsAccum ? 0.08 : 0)))
            )
            .animation(.easeInOut(duration: 0.25), value: followingIsAccum)
            Spacer()
        }
        .frame(height: 68)
    }

    private func igStatItem(_ n: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(n).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
            Text(label).font(.system(size: 10)).foregroundColor(.white.opacity(0.55))
        }
    }

    // Nav bar – username configurable so Scene 1 shows magician, others show spectator
    private func igNavBar(username: String) -> some View {
        ZStack {
            Color(hex: "060606")
            HStack {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
                Spacer()
                Text(username).font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 17)).foregroundColor(.white)
            }
            .padding(.horizontal, 18)
        }
        .frame(height: 48)
    }

    // Bio line – configurable text (LocalizedStringKey so string literals get translated)
    private func igBioLine(text: LocalizedStringKey) -> some View {
        HStack {
            Text(text).font(.system(size: 11.5)).foregroundColor(.white.opacity(0.65)).padding(.leading, 18)
            Spacer()
        }
        .frame(height: 20)
    }

    // Action buttons for another user's profile (Follow / Message)
    private var igActionButtons: some View {
        HStack(spacing: 8) {
            Text("ig.follow").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                .frame(maxWidth: .infinity).frame(height: 30).background(Color(hex: "6366F1")).cornerRadius(8)
            Text("Message").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                .frame(maxWidth: .infinity).frame(height: 30).background(Color.white.opacity(0.12)).cornerRadius(8)
            Image(systemName: "person.badge.plus").font(.system(size: 13)).foregroundColor(.white)
                .frame(width: 34, height: 30).background(Color.white.opacity(0.12)).cornerRadius(8)
        }
        .padding(.horizontal, 16).frame(height: 48)
    }

    // Action buttons for the magician's OWN profile (Edit Profile / Share Profile)
    private var igActionButtonsOwn: some View {
        HStack(spacing: 8) {
            Text("ig.edit_profile").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                .frame(maxWidth: .infinity).frame(height: 30)
                .background(Color.white.opacity(0.12)).cornerRadius(8)
            Text("ig.share_profile").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                .frame(maxWidth: .infinity).frame(height: 30)
                .background(Color.white.opacity(0.12)).cornerRadius(8)
        }
        .padding(.horizontal, 16).frame(height: 48)
    }

    // Badge shown above the phone to clarify whose screen is visible
    private func phoneOwnerBadge(label: LocalizedStringKey, sublabel: LocalizedStringKey, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(color.opacity(0.15)).frame(width: 28, height: 28)
                Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(color)
                Text(sublabel)
                    .font(.system(size: 9))
                    .foregroundColor(color.opacity(0.75))
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(color.opacity(0.07))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.2), lineWidth: 1))
    }

    private var igTabBar: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                igTabIcon("square.grid.3x3.fill", idx: 0)
                igTabIcon("play.rectangle.fill",  idx: 1)
                igTabIcon("person.crop.square",   idx: 2)
            }
            HStack(spacing: 0) {
                Rectangle().fill(Color.white).frame(width: phoneW / 3, height: 1.5)
                    .offset(x: CGFloat(activeTab) * (phoneW / 3))
                Spacer()
            }
            .animation(.easeInOut(duration: 0.32), value: activeTab)
        }
        .frame(height: 40)
        .overlay(Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1), alignment: .top)
    }

    private func igTabIcon(_ icon: String, idx: Int) -> some View {
        Image(systemName: icon).font(.system(size: 17))
            .foregroundColor(.white.opacity(activeTab == idx ? 1 : 0.28))
            .frame(maxWidth: .infinity).frame(height: 40)
            .animation(.easeInOut(duration: 0.25), value: activeTab)
    }

    private var pagedTabContent: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                postsGrid.frame(width: geo.size.width)
                reelsGrid.frame(width: geo.size.width)
                taggedGrid.frame(width: geo.size.width)
            }
            .offset(x: -CGFloat(activeTab) * geo.size.width)
            .animation(.easeInOut(duration: 0.34), value: activeTab)
        }
        .clipped()
    }

    private var postsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
            ForEach(0..<12) { i in postCell(index: i) }
        }
    }

    private func postCell(index: Int) -> some View {
        let digit   = cellDigits[index]
        let isSwipe = activeSwipeCell == index && activeTab == 0
        return ZStack {
            postGradients[index]
            Image(systemName: postIcons[index]).font(.system(size: 16)).foregroundColor(.white.opacity(0.12))
            if isSwipe { swipeFeedback }
            // Corner digit
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text("\(digit)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                        .padding(3)
                }
            }
        }
        .frame(height: cellH)
        .animation(.easeInOut(duration: 0.12), value: isSwipe)
    }

    private var reelsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
            ForEach(0..<12) { i in
                ZStack {
                    postGradients[(i + 3) % 12]
                    Image(systemName: "play.fill").font(.system(size: 13)).foregroundColor(.white.opacity(0.3))
                }
                .frame(height: cellH)
            }
        }
    }

    private var taggedGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
            ForEach(0..<12) { i in
                ZStack {
                    postGradients[(i + 6) % 12]
                    Image(systemName: "person.crop.square").font(.system(size: 13)).foregroundColor(.white.opacity(0.25))
                }
                .frame(height: cellH)
            }
        }
    }

    private var swipeFeedback: some View {
        HStack(spacing: 4) {
            Capsule().fill(.white.opacity(0.75)).frame(width: max(1, 30 * swipeTrail), height: 3)
            Image(systemName: "arrow.left").font(.system(size: 9, weight: .bold)).foregroundColor(.white.opacity(swipeTrail * 0.85))
        }
        .animation(.easeOut(duration: 0.12), value: swipeTrail)
    }

    private var fingerView: some View {
        Image(systemName: "hand.point.up.left.fill")
            .font(.system(size: 28)).foregroundColor(.white)
            .shadow(color: .black.opacity(0.5), radius: 4)
            .rotationEffect(.degrees(15))
    }

    // MARK: - Scene pill

    private func scenePill(n: String, label: LocalizedStringKey, active: Bool) -> some View {
        HStack(spacing: 4) {
            Text(n).font(.system(size: 10, weight: .bold))
                .foregroundColor(active ? .white : VaultTheme.Colors.textSecondary)
                .frame(width: 16, height: 16)
                .background(active ? Color(hex: "6366F1") : Color.clear)
                .clipShape(Circle())
            Text(label).font(.system(size: 11, weight: active ? .semibold : .regular))
                .foregroundColor(active ? VaultTheme.Colors.textPrimary : VaultTheme.Colors.textSecondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(active ? Color(hex: "6366F1").opacity(0.12) : Color.clear)
        .cornerRadius(20)
        .animation(.easeInOut(duration: 0.25), value: active)
    }

    // MARK: - Helpers

    private func sleep(_ s: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
    }

    // MARK: - Scene 1 animation: digit input

    @MainActor
    private func animScene1() async {
        withAnimation(.none) {
            activeTab = 0; accumDigits = []; activeSwipeCell = nil; swipeTrail = 0
            showFinger = false; fingerOffset = .zero; confirmFlash = false; followingBounce = 1.0
        }
        await sleep(0.6)

        // Digit 3 — swipe on cell index 2 (digit 3)
        await doSwipe(cellIdx: 2, digit: 3, nextTab: 1)
        await sleep(1.8)  // long pause so viewer sees Following="3"

        // Digit 7 — swipe on cell index 6 (digit 7)
        await doSwipe(cellIdx: 6, digit: 7, nextTab: 2)
        await sleep(0.4)

        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { confirmFlash = true }
        withAnimation(.easeOut(duration: 0.25)) { showFinger = false }
        await sleep(2.5)

        withAnimation(.easeOut(duration: 0.3)) { confirmFlash = false }
        await sleep(0.3)
    }

    @MainActor
    private func doSwipe(cellIdx: Int, digit: Int, nextTab: Int) async {
        let c = cellCenter(cellIdx)
        withAnimation(.none) {
            fingerOffset = CGSize(width: c.width + 22, height: c.height)
            activeSwipeCell = cellIdx; swipeTrail = 0
        }
        withAnimation(.easeIn(duration: 0.18)) { showFinger = true }
        await sleep(0.28)

        withAnimation(.easeIn(duration: 0.12)) { swipeTrail = 1 }
        withAnimation(.easeOut(duration: 0.50)) {
            fingerOffset = CGSize(width: c.width - 22, height: c.height)
        }
        await sleep(0.25)
        withAnimation(.easeInOut(duration: 0.34)) { activeTab = nextTab }
        await sleep(0.30)

        withAnimation(.easeOut(duration: 0.14)) { swipeTrail = 0; activeSwipeCell = nil }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.52)) { accumDigits.append(digit) }
        followingBounce = 1.5
        withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) { followingBounce = 1.0 }

        await sleep(0.20)
        withAnimation(.easeOut(duration: 0.14)) { showFinger = false }
        await sleep(0.18)
    }

    // MARK: - Scene 2 animation: inflated profile

    @MainActor
    private func animScene2() async {
        withAnimation(.none) { inflatedGlow = 0; showInflatedBadge = false }
        await sleep(0.6)

        withAnimation(.easeIn(duration: 0.5)) { inflatedGlow = 1 }
        await sleep(0.8)

        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { showInflatedBadge = true }
        await sleep(3.0)

        withAnimation(.easeOut(duration: 0.3)) { inflatedGlow = 0 }
        await sleep(0.3)
    }

    // MARK: - Scene 3 animation: glitch + countdown

    @MainActor
    private func animScene3() async {
        withAnimation(.none) {
            glitchPhase = .idle
            countdownValue = inflated
            glitchStrips = []
            glitchRGB = 0
            glitchFlash = 0
            volumePressed = false
        }
        await sleep(0.8)

        // Volume button press indicator
        withAnimation(.easeInOut(duration: 0.12)) { volumePressed = true }
        await sleep(0.15)
        withAnimation(.easeInOut(duration: 0.2)) { volumePressed = false }
        await sleep(0.1)

        // Start glitch
        withAnimation(.none) { glitchPhase = .glitching }
        await runMiniGlitch()

        // Countdown from inflated to real
        withAnimation(.none) { glitchPhase = .counting; glitchStrips = [] }
        let steps = 18
        let start = inflated
        let end   = realCount
        for s in 0...steps {
            if Task.isCancelled { return }
            let t = Double(s) / Double(steps)
            // Ease-in-out: slow start, fast middle, slow end
            let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            let value = start - Int(Double(start - end) * eased)
            withAnimation(.none) { countdownValue = value }
            let interval = s < 4 ? 0.12 : s > 14 ? 0.18 : 0.06
            await sleep(interval)
        }
        withAnimation(.none) { countdownValue = end; glitchPhase = .done }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        await sleep(2.5)
    }

    private func runMiniGlitch() async {
        let frameInterval = 1.0 / 18.0
        let totalFrames   = Int(1.4 / frameInterval)
        for f in 0..<totalFrames {
            if Task.isCancelled { return }
            let progress  = Double(f) / Double(totalFrames)
            let intensity = progress < 0.1 ? 1.0 : progress < 0.7 ? Double.random(in: 0.55...1.0) : 0.5 * (1 - (progress - 0.7) / 0.3)

            let nStrips = Int.random(in: 2...Int(8 * intensity + 2))
            let neonColors: [Color] = [.cyan, Color(red: 1, green: 0, blue: 0.5), .green, Color(red: 0.3, green: 0.4, blue: 1)]
            glitchStrips = (0..<nStrips).map { _ in
                GlitchStrip(
                    yPos: CGFloat.random(in: 0...phoneH),
                    height: CGFloat.random(in: 3...20),
                    xOffset: CGFloat.random(in: -phoneW * 0.3...phoneW * 0.3) * CGFloat(intensity),
                    color: neonColors.randomElement()!,
                    opacity: Double.random(in: 0.06...0.22)
                )
            }
            glitchRGB = CGFloat.random(in: -16 * intensity...16 * intensity)
            glitchFlash = f < 2 ? 0.85 - Double(f) * 0.42 : 0

            await sleep(frameInterval)
        }
        glitchStrips = []
        glitchRGB    = 0
        glitchFlash  = 0
    }

    // MARK: - Scene 4 animation: conviction

    @MainActor
    private func animScene4() async {
        withAnimation(.none) {
            spectatorPhoneVisible = false
            transferArrowVisible  = false
            magicianPhoneVisible  = false
        }
        await sleep(0.6)

        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { spectatorPhoneVisible = true }
        await sleep(1.4)

        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { transferArrowVisible = true }
        await sleep(0.7)

        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { magicianPhoneVisible = true }
        await sleep(2.5)
    }
}

// MARK: - Glitch strip model

private struct GlitchStrip: Identifiable {
    let id = UUID()
    let yPos:    CGFloat
    let height:  CGFloat
    let xOffset: CGFloat
    let color:   Color
    let opacity: Double
}

// MARK: - ── Reusable helper components (CGH-prefixed) ──────────────────────────

private struct CGHSection<Content: View>: View {
    let icon: String; let iconColor: Color; let title: LocalizedStringKey; let content: Content
    init(icon: String, iconColor: Color, title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.icon = icon; self.iconColor = iconColor; self.title = title; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.lg) {
            HStack(spacing: VaultTheme.Spacing.sm) {
                Image(systemName: icon).foregroundColor(iconColor).font(.system(size: 18))
                Text(title).font(VaultTheme.Typography.titleSmall()).foregroundColor(VaultTheme.Colors.textPrimary)
            }
            content
        }
    }
}

private struct CGHBody: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        Text(text).font(VaultTheme.Typography.body()).foregroundColor(VaultTheme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CGHMetric: View {
    let icon: String; let color: Color; let label: LocalizedStringKey; let desc: LocalizedStringKey
    var body: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.md) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(color).frame(width: 22).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13, weight: .semibold)).foregroundColor(color)
                Text(desc).font(VaultTheme.Typography.caption()).foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CGHStep: View {
    let n: Int; let text: String
    var body: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.md) {
            Text("\(n)").font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Color(hex: "6366F1")).clipShape(Circle())
                .padding(.top, 1)
            Text(LocalizedStringKey(text)).font(VaultTheme.Typography.body()).foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CGHInfoBox: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.sm) {
            Image(systemName: "info.circle.fill").foregroundColor(Color(hex: "6366F1")).font(.system(size: 14)).padding(.top, 1)
            Text(text).font(VaultTheme.Typography.caption()).foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(VaultTheme.Spacing.md)
        .background(Color(hex: "6366F1").opacity(0.07))
        .cornerRadius(VaultTheme.CornerRadius.sm)
    }
}

private struct CGHTip: View {
    let icon: String; let color: Color; let text: String
    var body: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.md) {
            Image(systemName: icon).font(.system(size: 13)).foregroundColor(color).frame(width: 22).padding(.top, 2)
            Text(LocalizedStringKey(text)).font(VaultTheme.Typography.caption()).foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
