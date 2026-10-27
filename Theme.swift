import SwiftUI

// MARK: - Фон

/// Статичный «северный» фон. Растеризуется один раз (drawingGroup) — никаких лагов при скролле.
struct AuroraBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.05, blue: 0.13), Color(red: 0.07, green: 0.03, blue: 0.16)],
                startPoint: .top, endPoint: .bottom
            )
            Circle().fill(Color.indigo.opacity(0.60)).frame(width: 340)
                .blur(radius: 90).offset(x: -140, y: -290)
            Circle().fill(Color.cyan.opacity(0.36)).frame(width: 290)
                .blur(radius: 90).offset(x: 160, y: -110)
            Circle().fill(Color.pink.opacity(0.34)).frame(width: 320)
                .blur(radius: 100).offset(x: -130, y: 270)
            Circle().fill(Color.mint.opacity(0.24)).frame(width: 270)
                .blur(radius: 90).offset(x: 160, y: 340)
        }
        .drawingGroup()
        .ignoresSafeArea()
    }
}

// MARK: - Liquid Glass (iOS 26) с аккуратным запасным вариантом для iOS 17–25

#if compiler(>=6.2)
@available(iOS 26.0, *)
private func makeGlass(tint: Color?, interactive: Bool) -> Glass {
    var g = Glass.regular
    if let tint { g = g.tint(tint) }
    if interactive { g = g.interactive() }
    return g
}
#endif

extension View {
    /// Настоящее стекло Liquid Glass на iOS 26, материал — на более старых версиях
    @ViewBuilder
    func glassCard(radius: CGFloat = 28, tint: Color? = nil, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(makeGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            self.fallbackGlass(shape: shape, tint: tint)
        }
        #else
        self.fallbackGlass(shape: shape, tint: tint)
        #endif
    }

    fileprivate func fallbackGlass(shape: RoundedRectangle, tint: Color?) -> some View {
        self
            .background(.ultraThinMaterial, in: shape)
            .overlay { shape.fill((tint ?? Color.clear).opacity(0.22)) }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.38), Color.white.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
            }
    }

    /// Лёгкая карточка для длинных списков: без настоящего стекла, чтобы скролл был идеально плавным
    func softCard(radius: CGFloat = 20) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(Color.white.opacity(0.07), in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7))
    }
}

/// Группа стеклянных элементов (на iOS 26 — GlassEffectContainer: быстрее и красивее)
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Кольцо прогресса

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 14
    var colors: [Color]

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.10), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    AngularGradient(colors: colors, center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(360)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: (colors.last ?? .white).opacity(0.45), radius: 8)
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
    }
}

// MARK: - Мелкие компоненты

struct StatusPill: View {
    let status: LeadStatus

    var body: some View {
        Text(status.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(status.color.opacity(0.18), in: Capsule())
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var color: Color = .white

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .softCard(radius: 18)
    }
}
