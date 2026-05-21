import SwiftUI

// MARK: - Date Force Help View

struct DateForceHelpView: View {
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            VaultTheme.Colors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    heroHeader.padding(.bottom, VaultTheme.Spacing.lg)
                    DateForceAnimatedDemo()
                        .padding(.horizontal, VaultTheme.Spacing.lg)
                        .padding(.bottom, VaultTheme.Spacing.xl)
                    Group {
                        DFHSection(icon: "wand.and.stars",       iconColor: Color(hex: "BF5AF2"), title: "Cómo funciona") { howItWorks }
                        dfhDivider
                        DFHSection(icon: "gearshape.fill",        iconColor: VaultTheme.Colors.success, title: "Preparación") { setupSteps }
                        dfhDivider
                        DFHSection(icon: "theatermasks.fill",      iconColor: Color(hex: "E63946"),       title: "Presentación y guión") { presentationScript }
                        dfhDivider
                        DFHSection(icon: "mic.fill",              iconColor: VaultTheme.Colors.warning,  title: "Durante el show") { duringShow }
                        dfhDivider
                        DFHSection(icon: "lightbulb.fill",        iconColor: Color(hex: "F472B6"),       title: "Consejos") { tipsSection }
                    }
                    .padding(.horizontal, VaultTheme.Spacing.lg)
                    Spacer(minLength: 60)
                }
                .padding(.top, 80)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Date Force").font(VaultTheme.Typography.titleSmall()).foregroundColor(VaultTheme.Colors.textPrimary)
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

    private var heroHeader: some View {
        VStack(spacing: VaultTheme.Spacing.md) {
            ZStack {
                Circle().fill(Color(hex: "BF5AF2").opacity(0.15)).frame(width: 80, height: 80)
                Text("📅").font(.system(size: 40))
            }
            Text("Date Force").font(VaultTheme.Typography.title()).foregroundColor(VaultTheme.Colors.textPrimary)
            Text("Seleccionas espectadores del público que te han seguido. Sus seguidores y seguidos se usan para \"codificar\" la fecha y la hora de hoy. El resultado aparece en el perfil de cualquier reel de Explore — el espectador lo descifra restando sus propios números.")
                .font(VaultTheme.Typography.body()).foregroundColor(VaultTheme.Colors.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, VaultTheme.Spacing.lg)
        }
        .frame(maxWidth: .infinity).padding(.vertical, VaultTheme.Spacing.xl)
    }

    private var dfhDivider: some View {
        Rectangle().fill(VaultTheme.Colors.cardBorder).frame(height: 1).padding(.vertical, VaultTheme.Spacing.xl)
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            DFHBody("El mago pide a unos espectadores que le sigan en Instagram durante el show. Abre la lista de seguidores y toca la foto de perfil de cada espectador: aparece un aro Stories como marca secreta. Al salir, la app calcula el resultado automáticamente.")
            DFHMetric(icon: "person.2.fill", color: Color(hex: "BF5AF2"), label: "Dos grupos secretos",
                      desc: "Los primeros N espectadores seleccionados son el grupo FECHA (usan sus seguidores). Los últimos N son el grupo HORA (usan sus seguidos).")
            DFHMetric(icon: "plus.circle.fill", color: VaultTheme.Colors.primary, label: "Suma camuflada",
                      desc: "La app suma internamente los conteos de cada grupo y los añade a la fecha/hora actual, generando los números \"mágicos\".")
            DFHMetric(icon: "play.rectangle.fill", color: VaultTheme.Colors.success, label: "Aparece en Explore",
                      desc: "Abre cualquier reel en Explore. El perfil de ese usuario muestra los seguidores/seguidos ya modificados con el resultado del truco.")
            DFHMetric(icon: "minus.circle.fill", color: VaultTheme.Colors.warning, label: "El espectador lo descifra",
                      desc: "Al restar los números de su grupo, el espectador obtiene la fecha y la hora exactas — sin saber que el mago los incluyó de antemano.")
            DFHInfoBox("El aro en la foto es completamente invisible para los espectadores — parece una notificación normal de Instagram.")
        }
    }

    private var setupSteps: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
            DFHStep(n: 1, text: "**Antes del show**, activa **Date Force** en Settings y configura el formato de fecha (DD/MM o MM/DD) y el offset de minutos si lo necesitas.")
            DFHStep(n: 2, text: "En Performance, abre la lista de seguidores (**\"Followers\"**) y espera a que los espectadores te sigan durante el show.")
            DFHStep(n: 3, text: "Toca la **foto de perfil** de cada espectador en la lista — aparece el aro Stories de colores. Los primeros seleccionados → grupo 📅 fecha. Los últimos → grupo 🕐 hora.")
            DFHStep(n: 4, text: "Pulsa la **flecha atrás** para cerrar. La app carga sus perfiles automáticamente en segundo plano.")
            DFHStep(n: 5, text: "Ve a Explore, abre cualquier reel y muestra los números al público. ¡Ya están listos!")
        }
    }

    private var duringShow: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.xl) {
            DFHShowStep(label: "PEDIR QUE TE SIGAN", color: Color(hex: "BF5AF2"),
                        action: "Pide a los espectadores elegidos que te sigan en Instagram ahora mismo. Abre la lista de seguidores en Performance.",
                        dialogue: "\"Voy a necesitar tu ayuda. ¿Puedes seguirme en Instagram ahora mismo? Todos vosotros.\"")
            DFHShowStep(label: "SELECCIÓN SECRETA", color: VaultTheme.Colors.primary,
                        action: "Toca discretamente la foto de cada espectador — el aro aparece solo en tu pantalla como marca interna. Nadie más lo ve.",
                        dialogue: nil)
            DFHShowStep(label: "CIERRA Y ESPERA", color: VaultTheme.Colors.success,
                        action: "Pulsa la flecha atrás. La app carga los perfiles en background. En 2-3 segundos todo está calculado.",
                        dialogue: "\"Vamos a Explore. Abre cualquier reel que quieras — tú eliges.\"")
            DFHShowStep(label: "EL REVEAL", color: VaultTheme.Colors.warning,
                        action: "El reel muestra los seguidores y seguidos modificados. Pide al espectador que reste el número de su grupo — obtendrá la fecha y la hora de hoy.",
                        dialogue: "\"Resta tus seguidores de ese número. ¿Qué obtienes? Exactamente: la fecha de hoy.\"")
        }
    }

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            DFHTip(icon: "person.crop.circle.badge.checkmark", color: Color(hex: "BF5AF2"),
                   text: "**Toca la foto, no la fila.** El aro se activa pulsando el avatar. Pulsar el nombre abre el perfil.")
            DFHTip(icon: "arrow.uturn.backward.circle", color: VaultTheme.Colors.primary,
                   text: "**Si te equivocas**, toca la foto de nuevo — el aro desaparece y el espectador queda deseleccionado.")
            DFHTip(icon: "2.circle.fill", color: VaultTheme.Colors.success,
                   text: "**Número par de espectadores.** Con 2 espectadores: 1 grupo fecha + 1 grupo hora. Con 4: 2+2. Con 6: 3+3.")
            DFHTip(icon: "clock.badge.exclamationmark", color: VaultTheme.Colors.warning,
                   text: "**Usa el offset de minutos** en Settings si necesitas ajustar la hora para que el truco funcione con la hora exacta del show.")
            DFHTip(icon: "lock.iphone", color: Color(hex: "F472B6"),
                   text: "**Cuentas privadas.** Si un espectador tiene la cuenta privada y no te sigue de vuelta, es posible que sus conteos no estén disponibles.")
        }
    }

    // MARK: - Presentation & Script

    private var presentationScript: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.xl) {

            DFHBody("Un guión completo para construir suspense y justificar el uso de seguidores y seguidos. Adapta las palabras a tu estilo.")

            // ── THE HOOK ────────────────────────────────────────────────────
            scriptBlock(
                tag: "EL GANCHO",
                tagColor: Color(hex: "E63946"),
                icon: "megaphone.fill",
                stage: "Empieza sin tocar el teléfono. De pie, en silencio. Deja que la sala se calme.",
                lines: [
                    "«Quiero hablar de algo que todos hacemos cada día sin pensarlo. Seguir a personas.»",
                    "«No en la calle. En Instagram. Esa pequeña decisión — pulsar ese botón — significa algo. Significa que elegiste a esa persona. Dijiste: esta persona me importa.»",
                    "«Y la gente que te sigue a ti hizo lo mismo contigo. Miró tu vida y decidió que merecía la pena. Eso no es nada. Es una forma silenciosa de confianza.»",
                    "«Lo que creo — y lo que quiero mostraros esta noche — es que esas elecciones tienen peso real. Y cuando las sumas todas en una sala llena de gente... nos dicen algo extraordinario.»",
                ]
            )

            // ── THE INVITATION ───────────────────────────────────────────────
            scriptBlock(
                tag: "LA INVITACIÓN",
                tagColor: Color(hex: "0095F6"),
                icon: "person.badge.plus",
                stage: "Saca el móvil. Sostenlo visible pero sin abrirlo todavía.",
                lines: [
                    "«Voy a necesitar vuestra ayuda. Todos sacad el móvil y abrid Instagram.»",
                    "«Buscadme. [di tu usuario claramente] Y seguidme. Ahora mismo, en esta sala. Vais a ser parte de esto.»",
                    "«Bien. No cerréis Instagram — lo vais a necesitar. Quedaos en vuestro propio perfil.»",
                ],
                note: "Una vez la mayoría te haya seguido, pulsa discretamente en el área de seguidores — la app empieza a capturar en background. Los próximos 10–20 segundos de carga los usas para la presentación."
            )

            // ── THE JUSTIFICATION ────────────────────────────────────────────
            scriptBlock(
                tag: "LA JUSTIFICACIÓN",
                tagColor: Color(hex: "BF5AF2"),
                icon: "arrow.left.arrow.right",
                stage: "Divide la sala visualmente. Señala izquierda, luego derecha.",
                lines: [
                    "«Quiero separaros en dos grupos. Los de mi izquierda — y los de mi derecha.»",
                    "«Los de la izquierda representan una cara de la ecuación: las personas que os eligieron a vosotros. Vuestros seguidores. Ese número mide vuestra presencia en el mundo.»",
                    "«Los de la derecha representáis la otra cara. Las personas que vosotros elegisteis. A quiénes seguís. El número que mide vuestra curiosidad. Lo que os importa.»",
                    "«Dos direcciones de la misma conexión. Quién viene a ti. Y a quién vas tú. Y creo — de verdad lo creo — que juntos, en esta sala, en este momento exacto... esos dos números saben algo que nosotros no.»",
                ]
            )

            // ── COLLECTING THE NUMBERS ───────────────────────────────────────
            scriptBlock(
                tag: "EL RITUAL DE LOS NÚMEROS",
                tagColor: VaultTheme.Colors.success,
                icon: "plus.forwardslash.minus",
                stage: "El grupo izquierdo mira su perfil. Instagram ya está abierto en cada móvil.",
                lines: [
                    "«Los de la izquierda — mirad vuestro perfil. No a quién seguís. El otro número. ¿Cuánta gente os sigue a vosotros? Decidlo en voz alta.»",
                    "[Nombre]: 1.240. [Nombre]: 873. ¿Y tú? 512. Perfecto.",
                    "«1.240 más 873 más 512. Juntos... 2.625. Esa es la suma de todos los que os eligieron. Recordad ese número.»",
                    "«Y el otro lado. Los de la derecha — pregunta diferente. ¿A cuánta gente seguís vosotros? Las personas que elegisteis.»",
                    "«347 más 512 más 190. Juntos... 1.049. El alcance colectivo de vuestra curiosidad. Guardad ese número también.»",
                ],
                note: "Apunta los números en un bloc o pizarra mientras los dicen. Hazlo teatral y deliberado — cada número tiene peso."
            )

            // ── THE STRANGER ─────────────────────────────────────────────────
            scriptBlock(
                tag: "EL DESCONOCIDO",
                tagColor: VaultTheme.Colors.warning,
                icon: "person.fill.questionmark",
                stage: "Entrega el móvil a alguien que no haya participado todavía.",
                lines: [
                    "«Ahora bien. Si yo elijo el perfil — sospecharíais. Si lo elige alguien que conocéis — no sería justo. Lo que necesitamos es alguien completamente fuera de esta sala. Alguien que el algoritmo encontró para nosotros.»",
                    "«Tú no has participado todavía. Quiero que abras el Explore de Instagram — la lupa. Verás publicaciones de personas que nunca has conocido, elegidas por el algoritmo. Desplázate todo el tiempo que quieras. Cuando uno te llame la atención — para. Sin pensar. Solo para.»",
                ],
                note: "Deja que se desplace libremente. No digas nada. El silencio trabaja por ti. Cuando toque una publicación, recupera el móvil de forma natural."
            )

            // ── THE REVELATION ───────────────────────────────────────────────
            scriptBlock(
                tag: "LA REVELACIÓN",
                tagColor: Color(hex: "F97316"),
                icon: "sparkles",
                stage: "Ralentiza todo. Mira entre la pantalla y el público.",
                lines: [
                    "«¿Recordáis el primer número? La suma de todos los que siguen a vuestro grupo — 2.625. Ahora mirad este desconocido. Tiene... [lee el número de seguidores forzado]. 5.227 seguidores.»",
                    "«5.227... menos 2.625... eso nos da... 2.602. Cuatro dígitos. 26 — 02. El 26 de febrero. Alguien mire su móvil. ¿Qué fecha es hoy?»",
                ],
                note: "Pausa. No sonrías. Deja que reaccionen primero."
            )

            scriptBlock(
                tag: "",
                tagColor: Color(hex: "F97316"),
                icon: "clock.fill",
                stage: nil,
                lines: [
                    "«Y el segundo número — 1.049. Las personas a las que sigue vuestro grupo. Este desconocido sigue a... [lee el número de seguidos forzado]. 2.349 personas. 2.349 menos 1.049... 1.300. Las trece horas. Alguien dígame la hora exacta ahora mismo.»",
                    "«La fecha y la hora de hoy. Codificadas en los números de un desconocido en internet — por las personas de esta sala, con sus propias elecciones, hechas a lo largo de años. Eso no es magia. Eso es conexión.»",
                ]
            )
        }
    }

    private func scriptBlock(
        tag: String,
        tagColor: Color,
        icon: String,
        stage: String?,
        lines: [String],
        note: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !tag.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(tagColor)
                    Text(tag)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(tagColor)
                        .tracking(0.8)
                }
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
                    let isDialogue = line.hasPrefix("«") || line.hasPrefix("\"")
                    HStack(alignment: .top, spacing: 8) {
                        if isDialogue {
                            Rectangle()
                                .fill(tagColor)
                                .frame(width: 3)
                                .cornerRadius(2)
                                .padding(.top, 2)
                        }
                        Text(line)
                            .font(isDialogue
                                  ? .system(size: 12, weight: .medium).italic()
                                  : .system(size: 11))
                            .foregroundColor(isDialogue
                                             ? VaultTheme.Colors.textPrimary
                                             : VaultTheme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let note {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "0095F6"))
                        .padding(.top, 1)
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(Color(hex: "0095F6").opacity(0.06))
                .cornerRadius(8)
            }
        }
        .padding(12)
        .background(tag.isEmpty
                    ? Color(hex: "F97316").opacity(0.04)
                    : tagColor.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tag.isEmpty
                        ? Color(hex: "F97316").opacity(0.15)
                        : tagColor.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - ── Animated Demo ─────────────────────────────────────────────────────

private struct DateForceAnimatedDemo: View {

    enum Scene { case select, math, explore, reveal }
    @State private var scene: Scene = .select
    @State private var sceneAnimDone = false   // true when current scene's anim has finished

    // Scene 1 — two sub-phases: profile view → followers list
    enum SelectPhase { case profile, list }
    @State private var selectPhase: SelectPhase = .profile
    @State private var followerStatGlow = false
    @State private var selectedRanks: [Int: Int] = [:]
    @State private var fingerVisible  = false
    @State private var fingerPos      = CGPoint(x: 124, y: 80)
    @State private var fingerTapScale: CGFloat = 1.0

    // Scene 2 — math
    @State private var dateRowsVisible: [Bool] = [false, false]
    @State private var timeRowsVisible: [Bool] = [false, false]
    @State private var dateSumVisible   = false
    @State private var timeSumVisible   = false
    @State private var dateSumValue: CGFloat = 0
    @State private var timeSumValue: CGFloat = 0

    // Scene 3 — explore (two sub-phases: grid → full reel)
    enum ExplorePhase { case grid, reel }
    @State private var explorePhase: ExplorePhase = .grid
    @State private var tappedReelIndex: Int? = nil   // highlighted cell in grid
    @State private var followerResult: CGFloat = 0
    @State private var followingResult: CGFloat = 0
    @State private var resultGlow: Double = 0
    @State private var exploreProfileVisible = false

    // Scene 4 — reveal
    @State private var dateStrike  = false
    @State private var timeStrike  = false
    @State private var dateRevealed = false
    @State private var timeRevealed = false
    @State private var revealGlow: Double = 0

    @State private var sceneTask: Task<Void, Never>? = nil

    // ── Fixed example values ──────────────────────────────────────────────────
    private let spectators: [(name: String, followers: Int, following: Int)] = [
        ("@carlos",  500, 320),
        ("@laura",   400, 210),
        ("@marcos",  780, 480),
        ("@sofia",   750, 340),
    ]
    private let todayDate = 2802   // 28/02
    private let todayTime = 1530   // 15:30
    private var dateSum: Int { spectators[0].followers + spectators[1].followers }   // 900
    private var timeSum: Int { spectators[2].following + spectators[3].following }   // 820 (wait — let me use following correctly)
    // Actually let me recompute: group time uses seguidos (following)
    // spectators[2].following = 480, spectators[3].following = 340 → sum = 820
    private var followerShown: Int { todayDate + dateSum }   // 2802 + 900 = 3702
    private var followingShown: Int { todayTime + timeSum }  // 1530 + 820 = 2350

    // ── Phone dimensions ─────────────────────────────────────────────────────
    private let phoneW: CGFloat = 248
    private let phoneH: CGFloat = 492

    var body: some View {
        VStack(spacing: 14) {

            // ── Context note (always visible) ───────────────────────────────
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "0095F6"))
                    Text("Antes de empezar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "0095F6"))
                    Spacer()
                }
                Text("El mago pide a los espectadores que le sigan en Instagram durante la actuación. Una vez lo hayan hecho, abre su lista de seguidores y selecciona quiénes participan.")
                    .font(.system(size: 11))
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "BF5AF2"))
                    Text("Funciona con **2, 4, 6, 8** o más espectadores (siempre número par)")
                        .font(.system(size: 11))
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(Color(hex: "0095F6").opacity(0.06))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "0095F6").opacity(0.18), lineWidth: 1))

            // ── Scene pills ─────────────────────────────────────────────────
            HStack(spacing: 6) {
                scenePill(n: "1", label: "Selección",  active: scene == .select)
                scenePill(n: "2", label: "Suma",       active: scene == .math)
                scenePill(n: "3", label: "Explore",    active: scene == .explore)
                scenePill(n: "4", label: "Reveal",     active: scene == .reveal)
            }

            phoneMockup
                .shadow(color: Color(hex: "BF5AF2").opacity(resultGlow * 0.55), radius: 32)
                .animation(.easeInOut(duration: 0.4), value: resultGlow)

            // ── Caption ─────────────────────────────────────────────────────
            Group {
                switch scene {
                case .select:
                    Text("El mago abre **Seguidores** y toca el avatar de cada espectador — el **aro** confirma la selección")
                case .math:
                    Text("Grupo 1 (📅 fecha): suma sus **seguidores** · Grupo 2 (🕐 hora): suma sus **seguidos**")
                case .explore:
                    Text("En Explore, el reel muestra **fecha + suma** como seguidores y **hora + suma** como seguidos")
                case .reveal:
                    Text("El espectador resta su grupo al número del reel… y aparece la **fecha y hora exacta** ✓")
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(VaultTheme.Colors.textSecondary)
            .multilineTextAlignment(.center)
            .frame(minHeight: 38)
            .animation(.easeInOut(duration: 0.3), value: scene)

            // ── Navigation button ────────────────────────────────────────────
            if sceneAnimDone {
                Button(action: nextScene) {
                    HStack(spacing: 6) {
                        Text(scene == .reveal ? "Reiniciar" : "Siguiente")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: scene == .reveal ? "arrow.counterclockwise" : "arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 22).padding(.vertical, 9)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "BF5AF2"), Color(hex: "0095F6")],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .cornerRadius(20)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(VaultTheme.Spacing.lg)
        .background(VaultTheme.Colors.backgroundSecondary)
        .cornerRadius(VaultTheme.CornerRadius.lg)
        .overlay(RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.lg)
            .stroke(Color(hex: "BF5AF2").opacity(0.25), lineWidth: 1))
        .onAppear  { startCurrentScene() }
        .onDisappear { sceneTask?.cancel() }
    }

    // ── Scene navigation ─────────────────────────────────────────────────────

    private func nextScene() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            sceneAnimDone = false
            switch scene {
            case .select:  scene = .math
            case .math:    scene = .explore
            case .explore: scene = .reveal
            case .reveal:  scene = .select
            }
        }
        startCurrentScene()
    }

    private func startCurrentScene() {
        sceneTask?.cancel()
        sceneTask = Task { @MainActor in
            switch scene {
            case .select:  await animScene1()
            case .math:    await animScene2()
            case .explore: await animScene3()
            case .reveal:  await animScene4()
            }
            if !Task.isCancelled {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    sceneAnimDone = true
                }
            }
        }
    }

    // MARK: - Phone mockup

    private var phoneMockup: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 38).fill(Color(hex: "111111"))
                .frame(width: phoneW + 16, height: phoneH + 16)
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: "252525"))
                .frame(width: 3, height: 68).offset(x: -(phoneW / 2 + 9), y: -66)
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: "252525"))
                .frame(width: 3, height: 44).offset(x: (phoneW / 2 + 9), y: -52)
            Capsule().fill(Color.black).frame(width: 96, height: 30)
                .offset(y: -(phoneH / 2 + 1))
            RoundedRectangle(cornerRadius: 28).fill(Color.white).frame(width: phoneW, height: phoneH)

            Group {
                switch scene {
                case .select:  selectScene.transition(.opacity)
                case .math:    mathScene.transition(.opacity)
                case .explore: exploreScene.transition(.opacity)
                case .reveal:  revealScene.transition(.opacity)
                }
            }
            .frame(width: phoneW, height: phoneH)
            .clipped()
        }
    }

    // MARK: - Scene 1: Profile → tap Followers → list with rings

    private var selectScene: some View {
        ZStack {
            if selectPhase == .profile {
                profileSubScene.transition(.opacity)
            } else {
                followersListSubScene.transition(.opacity)
            }

            // Animated finger (shown in both sub-phases)
            if fingerVisible {
                fingerView
                    .position(fingerPos)
                    .scaleEffect(fingerTapScale)
                    .animation(.spring(response: 0.2, dampingFraction: 0.55), value: fingerTapScale)
                    .allowsHitTesting(false)
            }
        }
    }

    // Sub-scene A: Instagram profile
    private var profileSubScene: some View {
        ZStack(alignment: .top) {
            Color.white

            VStack(spacing: 0) {
                // Nav bar
                HStack {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.black).padding(.leading, 12)
                    Spacer()
                    Text("magician_ig")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.black)
                    Spacer()
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14)).foregroundColor(.black).padding(.trailing, 14)
                }
                .frame(height: 42)

                // Profile header
                HStack(alignment: .top, spacing: 0) {
                    // Avatar
                    Circle()
                        .fill(LinearGradient(colors: [Color(hex: "BF5AF2"), Color(hex: "0095F6")],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 62, height: 62)
                        .overlay(Image(systemName: "person.fill").font(.system(size: 24)).foregroundColor(.white))
                        .padding(.leading, 14)

                    Spacer()

                    // Stats
                    HStack(spacing: 0) {
                        profileStat(value: "24", label: "posts")
                        profileStat(value: "1.247", label: "seguidores", highlight: followerStatGlow)
                        profileStat(value: "318", label: "seguidos")
                    }
                    .padding(.trailing, 10)
                }
                .padding(.top, 10)

                // Name + bio
                VStack(alignment: .leading, spacing: 2) {
                    Text("El Mago 🎩")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                    Text("Ilusionista profesional")
                        .font(.system(size: 11)).foregroundColor(Color(white: 0.4))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 8)

                // Action buttons
                HStack(spacing: 6) {
                    roundedBtn("Editar perfil")
                    roundedBtn("Compartir")
                    Image(systemName: "person.badge.plus").font(.system(size: 13))
                        .foregroundColor(.black)
                        .frame(height: 28)
                        .padding(.horizontal, 10)
                        .background(Color(white: 0.92))
                        .cornerRadius(7)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                // Story highlights
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(["Show", "Trucos", "Fan"], id: \.self) { title in
                            VStack(spacing: 4) {
                                Circle()
                                    .stroke(Color(white: 0.8), lineWidth: 1)
                                    .frame(width: 46, height: 46)
                                    .overlay(Circle().fill(Color(white: 0.94)))
                                Text(title).font(.system(size: 9)).foregroundColor(.black)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }

                Divider()

                // Post grid (3×3 placeholder)
                LazyVGrid(columns: Array(repeating: .init(.flexible(), spacing: 1), count: 3), spacing: 1) {
                    ForEach(0..<9, id: \.self) { i in
                        Rectangle()
                            .fill(Color(white: i % 2 == 0 ? 0.85 : 0.78))
                            .aspectRatio(1, contentMode: .fill)
                    }
                }
            }
        }
    }

    private func profileStat(value: String, label: String, highlight: Bool = false) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.black)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(highlight ? Color(hex: "0095F6") : Color(white: 0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(highlight ? Color(hex: "0095F6").opacity(0.08) : Color.clear)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(hex: "0095F6").opacity(highlight ? 0.4 : 0), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.3), value: highlight)
    }

    private func roundedBtn(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(Color(white: 0.92))
            .cornerRadius(7)
    }

    // Sub-scene B: followers list with rings
    private var followersListSubScene: some View {
        ZStack {
            Color.white
            VStack(spacing: 0) {
                // Nav bar
                HStack {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(.black).padding(.leading, 12)
                    Spacer()
                    Text("magician_ig")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.black)
                    Spacer()
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 14)).foregroundColor(.black).padding(.trailing, 12)
                }
                .frame(height: 42)

                // Tab row
                HStack(spacing: 0) {
                    followersTab(title: "1.247 seguidores", selected: true)
                    followersTab(title: "318 seguidos", selected: false)
                }
                Divider()

                // Search bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundColor(Color(white: 0.5))
                    Text("Buscar").font(.system(size: 12)).foregroundColor(Color(white: 0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color(white: 0.93)).cornerRadius(8)
                .padding(.horizontal, 12).padding(.vertical, 6)
                Divider()

                // Follower rows
                ForEach(0..<4, id: \.self) { i in
                    selectRow(index: i)
                    if i < 3 { Divider().padding(.leading, 70) }
                }
                Spacer()
            }
        }
    }

    private func followersTab(title: String, selected: Bool) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? .black : Color(white: 0.5))
                .padding(.horizontal, 10).padding(.vertical, 9)
            Rectangle()
                .fill(selected ? Color.black : Color.clear)
                .frame(height: 1.5)
        }
        .frame(maxWidth: .infinity)
    }

    private func selectRow(index i: Int) -> some View {
        let rank = selectedRanks[i]
        let isSelected = rank != nil
        return HStack(spacing: 10) {
            // Avatar with optional story ring
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    if isSelected {
                        Circle()
                            .stroke(storyGradient, lineWidth: 2.5)
                            .frame(width: 50, height: 50)
                        Circle().fill(Color.white).frame(width: 46, height: 46)
                    }
                    Circle()
                        .fill(Color(white: 0.88))
                        .frame(width: isSelected ? 42 : 44, height: isSelected ? 42 : 44)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 18))
                                .foregroundColor(Color(white: 0.65))
                        )
                }
                .frame(width: 50, height: 50)
                .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isSelected)

                if let r = rank {
                    Text("\(r)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: 15, height: 15)
                        .background(Circle().fill(Color(hex: "0095F6")))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 2) {
                Text(spectators[i].name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)
                Text("\(spectators[i].followers) seg.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.5))
            }
            Spacer()
            Text("Quitar")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(white: 0.93))
                .cornerRadius(6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Scene 2: Math visualization

    private var mathScene: some View {
        ZStack {
            Color.white
            VStack(spacing: 0) {
                // Mini header
                Text("Cálculo interno")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(white: 0.4))
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                HStack(alignment: .top, spacing: 0) {
                    // DATE group
                    VStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Text("📅").font(.system(size: 12))
                            Text("FECHA").font(.system(size: 10, weight: .bold)).foregroundColor(Color(hex: "0095F6"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)

                        ForEach(0..<2, id: \.self) { i in
                            if dateRowsVisible[i] {
                                VStack(spacing: 2) {
                                    Text(spectators[i].name)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.black)
                                    HStack(spacing: 3) {
                                        Image(systemName: "person.2.fill")
                                            .font(.system(size: 9))
                                            .foregroundColor(Color(hex: "0095F6"))
                                        Text("\(spectators[i].followers)")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(Color(hex: "0095F6"))
                                    }
                                }
                                .padding(.vertical, 7)
                                .frame(maxWidth: .infinity)
                                .background(Color(hex: "0095F6").opacity(0.07))
                                .cornerRadius(8)
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }

                        if dateSumVisible {
                            Divider().padding(.horizontal, 8)
                            VStack(spacing: 2) {
                                Text("Suma")
                                    .font(.system(size: 9))
                                    .foregroundColor(Color(white: 0.5))
                                Text("\(Int(dateSumValue))")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(Color(hex: "0095F6"))
                                    .monospacedDigit()
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)

                    // Divider
                    Rectangle()
                        .fill(Color(white: 0.88))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)

                    // TIME group
                    VStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Text("🕐").font(.system(size: 12))
                            Text("HORA").font(.system(size: 10, weight: .bold)).foregroundColor(Color(hex: "F97316"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)

                        ForEach(0..<2, id: \.self) { i in
                            let sp = spectators[i + 2]
                            if timeRowsVisible[i] {
                                VStack(spacing: 2) {
                                    Text(sp.name)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.black)
                                    HStack(spacing: 3) {
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 9))
                                            .foregroundColor(Color(hex: "F97316"))
                                        Text("\(sp.following)")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(Color(hex: "F97316"))
                                    }
                                }
                                .padding(.vertical, 7)
                                .frame(maxWidth: .infinity)
                                .background(Color(hex: "F97316").opacity(0.07))
                                .cornerRadius(8)
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }

                        if timeSumVisible {
                            Divider().padding(.horizontal, 8)
                            VStack(spacing: 2) {
                                Text("Suma")
                                    .font(.system(size: 9))
                                    .foregroundColor(Color(white: 0.5))
                                Text("\(Int(timeSumValue))")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(Color(hex: "F97316"))
                                    .monospacedDigit()
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)

                Spacer()
            }
        }
    }

    // MARK: - Scene 3: Explore (grid → full reel)

    private var exploreScene: some View {
        ZStack {
            if explorePhase == .grid {
                exploreGridView
                    .transition(.opacity)
            } else {
                exploreReelView
                    .transition(.opacity)
            }

            // Finger is shared across both sub-phases
            if fingerVisible {
                fingerView
                    .position(fingerPos)
                    .scaleEffect(fingerTapScale)
                    .animation(.spring(response: 0.2, dampingFraction: 0.55), value: fingerTapScale)
                    .allowsHitTesting(false)
            }
        }
    }

    // Sub-scene A: Instagram Explore grid
    private var exploreGridView: some View {
        ZStack(alignment: .top) {
            Color.white

            VStack(spacing: 0) {
                // Nav bar
                HStack {
                    Text("Explorar")
                        .font(.system(size: 16, weight: .bold)).foregroundColor(.black)
                        .padding(.leading, 14)
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15)).foregroundColor(.black).padding(.trailing, 14)
                }
                .frame(height: 42)

                // Search bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundColor(Color(white: 0.5))
                    Text("Buscar").font(.system(size: 12)).foregroundColor(Color(white: 0.55))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Color(white: 0.93)).cornerRadius(8)
                .padding(.horizontal, 10).padding(.bottom, 6)

                // Reel grid — 3 columns
                let cols = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
                LazyVGrid(columns: cols, spacing: 2) {
                    ForEach(0..<12, id: \.self) { i in
                        let isTarget = i == 4
                        let isTapped = tappedReelIndex == i
                        ZStack {
                            Rectangle()
                                .fill(reelColor(index: i))
                                .frame(height: 96)
                            // Reel icon
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.6))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                                .padding(5)
                            // Highlight for target reel
                            if isTarget {
                                Rectangle()
                                    .stroke(Color(hex: "BF5AF2"), lineWidth: isTapped ? 3 : 1.5)
                                    .opacity(isTapped ? 1 : 0.5)
                                    .animation(.easeInOut(duration: 0.2), value: isTapped)
                            }
                            if isTapped {
                                Color.white.opacity(0.3)
                                    .transition(.opacity)
                            }
                        }
                        .clipped()
                    }
                }
            }
        }
    }

    private func reelColor(index: Int) -> Color {
        let colors: [Color] = [
            Color(hex: "2d3561"), Color(hex: "1e4d6b"), Color(hex: "3d2b56"),
            Color(hex: "1a3a4a"), Color(hex: "4a1e6b"), Color(hex: "1e3d2b"),
            Color(hex: "5c2d1e"), Color(hex: "1e2d5c"), Color(hex: "2d5c1e"),
            Color(hex: "5c1e3d"), Color(hex: "1e5c4a"), Color(hex: "3d4a1e"),
        ]
        return colors[index % colors.count]
    }

    // Sub-scene B: full-screen reel (existing explore reel view)
    private var exploreReelView: some View {
        ZStack(alignment: .bottom) {
            // Video background — dark cinematic gradient
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "0d1117"), Color(hex: "1c2a3a"), Color(hex: "0d2137")],
                    startPoint: .top, endPoint: .bottom
                )
                // Simulated blurry content shapes
                Circle()
                    .fill(Color(hex: "1a4a6e").opacity(0.4))
                    .frame(width: 160, height: 160)
                    .blur(radius: 40)
                    .offset(x: -40, y: -60)
                Circle()
                    .fill(Color(hex: "2d1b4e").opacity(0.5))
                    .frame(width: 120, height: 120)
                    .blur(radius: 30)
                    .offset(x: 60, y: 80)
            }

            // Top bar
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                Spacer()
                Text("Reels")
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                Spacer()
                Image(systemName: "camera.fill")
                    .font(.system(size: 14)).foregroundColor(.white)
            }
            .padding(.horizontal, 16).padding(.top, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Right-side action buttons
            VStack(spacing: 20) {
                reelActionBtn(icon: "heart.fill",       color: .white,   count: "12K")
                reelActionBtn(icon: "bubble.right.fill", color: .white,  count: "843")
                reelActionBtn(icon: "paperplane.fill",  color: .white,   count: "")
                reelActionBtn(icon: "bookmark.fill",    color: .white,   count: "")
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
            }
            .padding(.trailing, 14)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

            // Bottom bar (username, caption, music)
            VStack(alignment: .leading, spacing: 0) {
                // Stats card with magic numbers
                if exploreProfileVisible {
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(followerResult > 0 ? "\(Int(followerResult))" : "—")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .monospacedDigit()
                            HStack(spacing: 4) {
                                Text("seguidores")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Color(white: 0.75))
                                if followerResult >= Double(followerShown) {
                                    Image(systemName: "calendar.badge.checkmark")
                                        .font(.system(size: 9))
                                        .foregroundColor(Color(hex: "BF5AF2"))
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Rectangle().fill(Color.white.opacity(0.3)).frame(width: 1, height: 36).padding(.horizontal, 8)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(followingResult > 0 ? "\(Int(followingResult))" : "—")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .monospacedDigit()
                            HStack(spacing: 4) {
                                Text("seguidos")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Color(white: 0.75))
                                if followingResult >= Double(followingShown) {
                                    Image(systemName: "clock.badge.checkmark")
                                        .font(.system(size: 9))
                                        .foregroundColor(Color(hex: "F97316"))
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                LinearGradient(colors: [Color(hex: "BF5AF2"), Color(hex: "F97316")],
                                               startPoint: .leading, endPoint: .trailing)
                                    .opacity(resultGlow * 0.9),
                                lineWidth: 1.5
                            )
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                HStack(spacing: 8) {
                    // Avatar with story ring
                    ZStack {
                        Circle()
                            .stroke(storyGradient, lineWidth: 2)
                            .frame(width: 34, height: 34)
                        Circle().fill(Color(white: 0.3)).frame(width: 28, height: 28)
                            .overlay(Image(systemName: "person.fill").font(.system(size: 12)).foregroundColor(Color(white: 0.75)))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text("explore_user")
                                .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                            Text("Seguir")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10).padding(.vertical, 3)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(5)
                        }
                        Text("¡Elige un número del 1 al 31 🎩")
                            .font(.system(size: 11)).foregroundColor(Color(white: 0.85))
                    }
                    Spacer()
                }

                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.system(size: 10)).foregroundColor(.white)
                    Text("Magic Show • Instrumental")
                        .font(.system(size: 10)).foregroundColor(Color(white: 0.8))
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 18)
        }
    }

    private func reelActionBtn(icon: String, color: Color, count: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(color)
                .shadow(color: .black.opacity(0.4), radius: 2)
            if !count.isEmpty {
                Text(count)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: - Scene 4: Reveal (subtraction)

    private var revealScene: some View {
        ZStack {
            // Background shifts to dark purple when both are revealed
            (dateRevealed && timeRevealed ? Color(hex: "130d1e") : Color(hex: "f8f8f8"))
                .animation(.easeInOut(duration: 0.6), value: dateRevealed && timeRevealed)

            VStack(spacing: 14) {
                Text("El espectador hace la resta:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(white: dateRevealed && timeRevealed ? 0.6 : 0.45))
                    .padding(.top, 20)

                // ── DATE row ──────────────────────────────────────────────
                revealRow(
                    emoji: "📅",
                    label: "Fecha",
                    shown: followerShown,
                    sum: dateSum,
                    strike: dateStrike,
                    revealed: dateRevealed,
                    resultText: "28/02",
                    accentColor: Color(hex: "BF5AF2")
                )
                .padding(.horizontal, 14)

                // ── TIME row ──────────────────────────────────────────────
                revealRow(
                    emoji: "🕐",
                    label: "Hora",
                    shown: followingShown,
                    sum: timeSum,
                    strike: timeStrike,
                    revealed: timeRevealed,
                    resultText: "15:30",
                    accentColor: Color(hex: "F97316")
                )
                .padding(.horizontal, 14)

                // ── Big result banner ─────────────────────────────────────
                if dateRevealed && timeRevealed {
                    VStack(spacing: 8) {
                        Text("🎩")
                            .font(.system(size: 32))
                        VStack(spacing: 4) {
                            Text("28 / 02")
                                .font(.system(size: 30, weight: .black))
                                .foregroundColor(Color(hex: "BF5AF2"))
                                .shadow(color: Color(hex: "BF5AF2").opacity(revealGlow * 0.8), radius: 12)
                            Text("15 : 30")
                                .font(.system(size: 30, weight: .black))
                                .foregroundColor(Color(hex: "F97316"))
                                .shadow(color: Color(hex: "F97316").opacity(revealGlow * 0.8), radius: 12)
                        }
                        Text("¡Fecha y hora de hoy!")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(white: 0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(14)
                    .padding(.horizontal, 14)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }

                Spacer()
            }
        }
        .animation(.easeInOut(duration: 0.4), value: dateRevealed && timeRevealed)
    }

    private func revealRow(
        emoji: String,
        label: String,
        shown: Int,
        sum: Int,
        strike: Bool,
        revealed: Bool,
        resultText: String,
        accentColor: Color
    ) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Text(emoji).font(.system(size: 12))
                Text("Grupo \(label)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accentColor)
                Spacer()
            }

            HStack(alignment: .center, spacing: 4) {
                // Shown value
                Text("\(shown)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(dateRevealed && timeRevealed ? .white : .black)
                    .monospacedDigit()

                Text("−")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(white: 0.5))

                // Sum with strike
                ZStack {
                    Text("\(sum)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(accentColor)
                        .monospacedDigit()
                    if strike {
                        Rectangle()
                            .fill(Color.red.opacity(0.85))
                            .frame(height: 2.5)
                            .transition(.scale(scale: 0, anchor: .leading))
                    }
                }

                Text("=")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(white: 0.5))

                // Result
                if revealed {
                    VStack(spacing: 0) {
                        Text(resultText)
                            .font(.system(size: 20, weight: .black))
                            .foregroundColor(accentColor)
                            .monospacedDigit()
                            .shadow(color: accentColor.opacity(revealGlow * 0.7), radius: 8)
                    }
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                } else {
                    Text("?")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(white: 0.4))
                        .frame(minWidth: 30)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(revealed
            ? accentColor.opacity(0.12)
            : Color(white: dateRevealed && timeRevealed ? 0.12 : 0.96))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(accentColor.opacity(revealed ? 0.4 : 0.15), lineWidth: 1))
        .animation(.easeInOut(duration: 0.35), value: revealed)
    }

    // MARK: - Finger view

    private var fingerView: some View {
        Image(systemName: "hand.point.up.left.fill")
            .font(.system(size: 28))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.5), radius: 4)
            .rotationEffect(.degrees(15))
    }

    // MARK: - Scene pill

    private func scenePill(n: String, label: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Text(n)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(active ? .white : VaultTheme.Colors.textSecondary)
                .frame(width: 16, height: 16)
                .background(active ? Color(hex: "BF5AF2") : Color.clear)
                .clipShape(Circle())
            Text(label)
                .font(.system(size: 11, weight: active ? .semibold : .regular))
                .foregroundColor(active ? VaultTheme.Colors.textPrimary : VaultTheme.Colors.textSecondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(active ? Color(hex: "BF5AF2").opacity(0.12) : Color.clear)
        .cornerRadius(20)
        .animation(.easeInOut(duration: 0.25), value: active)
    }

    // MARK: - Story gradient

    private var storyGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [
                Color(hex: "F58529"), Color(hex: "FEDA77"),
                Color(hex: "DD2A7B"), Color(hex: "8134AF"),
                Color(hex: "515BD4"), Color(hex: "F58529")
            ]),
            center: .center
        )
    }

    // MARK: - Helpers

    private func formatK(_ n: Int) -> String {
        if n >= 1000 { return String(format: "%.1fK", Double(n) / 1000) }
        return "\(n)"
    }

    private func sleep(_ s: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
    }

    // ── Scene 1: tap each spectator ──────────────────────────────────────────
    @MainActor
    private func animScene1() async {
        // ── Phase A: show profile ──
        withAnimation(.none) {
            selectPhase = .profile
            selectedRanks = [:]
            followerStatGlow = false
            fingerVisible = false
            fingerPos = CGPoint(x: 35, y: 80)
        }
        await sleep(0.7)

        // Finger appears and moves toward "seguidores" stat
        // The stat column is roughly center-right at (x≈148, y≈110) in the phone canvas
        withAnimation(.easeInOut(duration: 0.4)) {
            fingerPos = CGPoint(x: 148, y: 110)
            fingerVisible = true
        }
        await sleep(0.5)

        // Glow highlights the stat
        withAnimation(.easeInOut(duration: 0.25)) { followerStatGlow = true }
        await sleep(0.3)

        // Tap animation
        withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) { fingerTapScale = 0.75 }
        await sleep(0.12)
        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { fingerTapScale = 1.0 }
        await sleep(0.25)

        // Transition to followers list
        withAnimation(.easeInOut(duration: 0.35)) {
            selectPhase = .list
            followerStatGlow = false
        }
        await sleep(0.5)

        // Move finger to the left (avatar column) for selections
        withAnimation(.easeInOut(duration: 0.3)) {
            fingerPos = CGPoint(x: 35, y: 110)
        }
        await sleep(0.3)

        // ── Phase B: tap each follower to add ring ──
        // y positions for rows inside the list: nav(42) + tab(32) + search(40) + divider → first row ~130
        let tapTargets: [(row: Int, y: CGFloat)] = [(0, 132), (1, 198), (2, 264), (3, 330)]

        for (rank, target) in tapTargets.enumerated() {
            if Task.isCancelled { return }

            withAnimation(.easeInOut(duration: 0.35)) {
                fingerPos = CGPoint(x: 35, y: target.y)
            }
            await sleep(0.45)

            withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) { fingerTapScale = 0.75 }
            await sleep(0.12)
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { fingerTapScale = 1.0 }

            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                selectedRanks[target.row] = rank + 1
            }
            await sleep(0.75)
        }

        withAnimation(.easeOut(duration: 0.2)) { fingerVisible = false }
        await sleep(1.5)
    }

    // ── Scene 2: math visualization ──────────────────────────────────────────
    @MainActor
    private func animScene2() async {
        withAnimation(.none) {
            dateRowsVisible = [false, false]
            timeRowsVisible = [false, false]
            dateSumVisible = false
            timeSumVisible = false
            dateSumValue = 0
            timeSumValue = 0
        }
        await sleep(0.6)

        // Show date rows
        for i in 0..<2 {
            if Task.isCancelled { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { dateRowsVisible[i] = true }
            await sleep(0.4)
        }

        // Show time rows simultaneously
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            timeRowsVisible[0] = true; timeRowsVisible[1] = true
        }
        await sleep(0.6)

        // Animate sums counting up
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            dateSumVisible = true; timeSumVisible = true
        }
        let targetDate = Double(dateSum)
        let targetTime = Double(timeSum)
        let steps = 20
        for s in 1...steps {
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.06)) {
                dateSumValue = targetDate * Double(s) / Double(steps)
                timeSumValue = targetTime * Double(s) / Double(steps)
            }
            await sleep(0.04)
        }
        withAnimation(.none) {
            dateSumValue = targetDate
            timeSumValue = targetTime
        }
        await sleep(2.0)
    }

    // ── Scene 3: explore result ───────────────────────────────────────────────
    @MainActor
    private func animScene3() async {
        withAnimation(.none) {
            explorePhase = .grid
            tappedReelIndex = nil
            followerResult = 0; followingResult = 0; resultGlow = 0
            exploreProfileVisible = false
            fingerVisible = false
            fingerPos = CGPoint(x: 124, y: 300)
        }
        await sleep(0.6)

        // ── Phase A: grid — finger moves to target reel and taps it ──
        // Target reel index 4 (row 1, col 1 = center cell)
        // Grid starts below nav(42)+explore-tabs(36) ≈ y=78. Each cell ≈ 82×98 + 2px gap.
        // Center of cell[4]: x = 82+41 = 123, y = 78 + 98 + 2 + 49 ≈ 227
        let targetCellX: CGFloat = 123
        let targetCellY: CGFloat = 224

        withAnimation(.easeInOut(duration: 0.4)) {
            fingerPos = CGPoint(x: targetCellX, y: targetCellY)
            fingerVisible = true
        }
        await sleep(0.55)

        // Tap — highlight cell
        withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) { fingerTapScale = 0.75 }
        await sleep(0.1)
        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { fingerTapScale = 1.0 }
        withAnimation(.easeInOut(duration: 0.2)) { tappedReelIndex = 4 }
        await sleep(0.35)

        withAnimation(.easeOut(duration: 0.2)) { fingerVisible = false }
        await sleep(0.2)

        // ── Phase B: open reel full-screen ──
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            explorePhase = .reel
            tappedReelIndex = nil
        }
        await sleep(0.7)

        // Slide in stats card
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { exploreProfileVisible = true }
        await sleep(0.4)

        // Count up follower/following
        let fTarget = Double(followerShown)
        let tTarget = Double(followingShown)
        let steps = 30
        for s in 1...steps {
            if Task.isCancelled { return }
            let t = Double(s) / Double(steps)
            withAnimation(.easeOut(duration: 0.05)) {
                followerResult = fTarget * t
                followingResult = tTarget * t
            }
            await sleep(0.03)
        }
        withAnimation(.none) { followerResult = fTarget; followingResult = tTarget }

        withAnimation(.easeIn(duration: 0.4)) { resultGlow = 1 }
        await sleep(2.5)
        withAnimation(.easeOut(duration: 0.4)) { resultGlow = 0 }
        await sleep(0.3)
    }

    // ── Scene 4: reveal / subtraction ────────────────────────────────────────
    @MainActor
    private func animScene4() async {
        withAnimation(.none) {
            dateStrike = false; timeStrike = false
            dateRevealed = false; timeRevealed = false
            revealGlow = 0
        }
        await sleep(0.8)

        // Strike through date sum
        withAnimation(.easeInOut(duration: 0.3)) { dateStrike = true }
        await sleep(0.5)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) { dateRevealed = true }
        await sleep(0.7)

        // Strike through time sum
        withAnimation(.easeInOut(duration: 0.3)) { timeStrike = true }
        await sleep(0.5)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) { timeRevealed = true }
        await sleep(0.4)
        withAnimation(.easeIn(duration: 0.5)) { revealGlow = 1 }
        await sleep(2.5)
        withAnimation(.easeOut(duration: 0.4)) { revealGlow = 0 }
        await sleep(0.3)
    }
}

// MARK: - ── Reusable helpers (DFH-prefixed) ──────────────────────────────────

private struct DFHSection<Content: View>: View {
    let icon: String; let iconColor: Color; let title: String; let content: Content
    init(icon: String, iconColor: Color, title: String, @ViewBuilder content: () -> Content) {
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

private struct DFHBody: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(VaultTheme.Typography.body()).foregroundColor(VaultTheme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct DFHMetric: View {
    let icon: String; let color: Color; let label: String; let desc: String
    var body: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.md) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(color).frame(width: 22).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13, weight: .semibold)).foregroundColor(color)
                Text(desc).font(VaultTheme.Typography.caption()).foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(VaultTheme.Spacing.sm).background(color.opacity(0.06)).cornerRadius(VaultTheme.CornerRadius.sm)
    }
}

private struct DFHInfoBox: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.sm) {
            Image(systemName: "info.circle.fill").foregroundColor(VaultTheme.Colors.info).font(.system(size: 14)).padding(.top, 1)
            Text(text).font(VaultTheme.Typography.caption()).foregroundColor(VaultTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(VaultTheme.Spacing.md).background(VaultTheme.Colors.info.opacity(0.08)).cornerRadius(VaultTheme.CornerRadius.sm)
        .overlay(RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.sm).stroke(VaultTheme.Colors.info.opacity(0.25), lineWidth: 1))
    }
}

private struct DFHStep: View {
    let n: Int; let text: String
    var body: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.md) {
            Text("\(n)").font(.system(size: 12, weight: .bold)).foregroundColor(Color(hex: "BF5AF2"))
                .frame(width: 22, height: 22).background(Color(hex: "BF5AF2").opacity(0.15)).clipShape(Circle())
            Text(LocalizedStringKey(text)).font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DFHShowStep: View {
    let label: String; let color: Color; let action: String; let dialogue: String?
    var body: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            Text(label).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(color).tracking(1.5)
            VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                HStack(alignment: .top, spacing: VaultTheme.Spacing.sm) {
                    Circle().fill(color.opacity(0.5)).frame(width: 4, height: 4).padding(.top, 8)
                    Text(action).font(VaultTheme.Typography.body()).foregroundColor(VaultTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let d = dialogue {
                    HStack(alignment: .top, spacing: VaultTheme.Spacing.sm) {
                        Rectangle().fill(color).frame(width: 2).cornerRadius(1)
                        Text(d).font(.system(size: 13)).italic().foregroundColor(VaultTheme.Colors.textPrimary.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, VaultTheme.Spacing.md)
                }
            }
        }
        .padding(VaultTheme.Spacing.md).background(VaultTheme.Colors.backgroundSecondary)
        .cornerRadius(VaultTheme.CornerRadius.md)
        .overlay(RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.md).stroke(color.opacity(0.2), lineWidth: 1))
    }
}

private struct DFHTip: View {
    let icon: String; let color: Color; let text: String
    var body: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.md) {
            Image(systemName: icon).foregroundColor(color).font(.system(size: 16)).frame(width: 22).padding(.top, 1)
            Text(LocalizedStringKey(text)).font(VaultTheme.Typography.body())
                .foregroundColor(VaultTheme.Colors.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
