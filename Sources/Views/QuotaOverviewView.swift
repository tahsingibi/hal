import AppKit
import SwiftUI

/// Bütün kota sağlayıcıları tek sayfada. Her sağlayıcı bir bölüm: planı, her
/// pencerenin kullanımı, yenilenmeye kalan süre ve pencere süresinin ne kadarının
/// geçtiğini gösteren işaret. Codex'in biriken sıfırlama hakları da burada.
struct QuotaOverviewView: View {
    @EnvironmentObject private var store: AppStore
    var onSettings: (SettingsTab) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(store.quotas.enumerated()), id: \.element.id) { index, group in
                if index > 0 {
                    Divider().opacity(0.4).padding(.vertical, 12)
                }
                QuotaProviderSection(group: group, now: store.now, onSettings: onSettings)
            }
        }
    }
}

private struct QuotaProviderSection: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var colorScheme
    let group: QuotaGroup
    let now: Date
    var onSettings: (SettingsTab) -> Void
    @State private var loginHint: String?

    private var accent: Color { Color(hex: group.accentHex) }

    /// Okumadan bu yana yenilenen pencereler sıfırdan başlar.
    private var windows: [QuotaWindow] { group.windows.map { $0.current(at: now) } }

    /// Başka yerde yapılan kullanımı kaçırmış olabilecek kadar eski bir okuma.
    private var stale: Bool {
        guard let observed = group.observedAt else { return false }
        return now.timeIntervalSince(observed) > 10 * 60
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            switch group.status {
            case .ready:
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(windows) { window in
                        if window.hasLimit { meter(window) } else { infoRow(window) }
                    }
                }
                .opacity(stale ? 0.6 : 1)
                if let credits = group.resetCredits {
                    CodexResetCreditsView(credits: credits, now: now, accent: accent)
                }
                caption
            case .loading:
                ProgressView().controlSize(.small)
            case .missingAuth, .error:
                QuotaSetupView(group: group, loginHint: $loginHint, onSettings: onSettings)
            }
        }
    }

    // MARK: Başlık

    private var header: some View {
        HStack(spacing: 7) {
            Image(nsImage: BrandIcon.from(id: group.id).image(dark: colorScheme == .dark, size: 14))
                .resizable()
                .interpolation(.high)
                .frame(width: 14, height: 14)
            Text(group.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            if let plan = group.plan {
                QuotaChip(text: plan, tint: accent)
            }
            Spacer(minLength: 4)
            if store.refreshing && group.status != .ready {
                ProgressView().controlSize(.mini)
            }
        }
    }

    // MARK: Satırlar

    private func meter(_ window: QuotaWindow) -> some View {
        let reset = window.resetsAt.flatMap { $0 > now ? $0 : nil }
        let tint = window.clampedPercent >= 0.7 ? Theme.barColor(percent: window.clampedPercent) : Color.primary
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(window.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let reset {
                    Label(TimeFormatters.remaining(reset.timeIntervalSince(now)), systemImage: "arrow.clockwise")
                        .labelStyle(QuotaInlineLabel())
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
                Spacer(minLength: 4)
                Text(window.percentText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
                    .fixedSize()
            }
            QuotaMeter(value: window.clampedPercent, pace: window.elapsedFraction(at: now),
                       tint: Theme.barColor(percent: window.clampedPercent))
            if let detail = window.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !window.usedText.isEmpty {
                Text(window.usedText)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .help(help(window, reset: reset))
    }

    /// Sınırı olmayan satır: yüzde uydurmak yerine ham değer.
    private func infoRow(_ window: QuotaWindow) -> some View {
        HStack {
            Text(window.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(window.usedText.isEmpty ? L("Kota sınırı yok", "No quota limit") : window.usedText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func help(_ window: QuotaWindow, reset: Date?) -> String {
        let remaining = Int(((1 - window.clampedPercent) * 100).rounded())
        var parts = [
            window.title,
            Lf("%1$@ kullanıldı", "%1$@ used", window.percentText),
            Lf("%%%1$d kaldı", "%1$d%% left", remaining)
        ]
        if let reset {
            parts.append(Lf("Yenilenme: %1$@", "Renews: %1$@",
                            reset.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Language.locale))))
        }
        if let elapsed = window.elapsedFraction(at: now) {
            parts.append(Lf("Sürenin %%%1$d geçti", "%1$d%% of the window elapsed", Int((elapsed * 100).rounded())))
        }
        return parts.joined(separator: " · ")
    }

    /// Okumanın kaynağı ya da yaşı; ancak bir şey söylüyorsa.
    @ViewBuilder private var caption: some View {
        let age = stale ? group.observedAt.map {
            Lf("%1$@ önce güncellendi", "Updated %1$@ ago", TimeFormatters.remaining(now.timeIntervalSince($0)))
        } : nil
        let parts = [group.note, age].compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.system(size: 10.5))
                .foregroundStyle(stale ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tertiary))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Codex sıfırlama hakları

/// Hesapta kaç hak olduğu, sıradakinin ne zaman sona ereceği ve önce soran bir
/// kullanım düğmesi. Onay sorusu düğmenin yerini alır; çift tık bir hak harcamaz.
private struct CodexResetCreditsView: View {
    @EnvironmentObject private var store: AppStore
    let credits: QuotaResetCredits
    let now: Date
    let accent: Color
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise.circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(L("Sıfırlama hakları", "Resets"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if credits.available > 0 {
                    QuotaChip(text: "\(credits.available)", tint: accent)
                }
            }
            content
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.04)))
        .help(L(
            "Bir sıfırlama hakkı Codex’in oturum ve haftalık limitini birlikte yeniler. Haklar Codex’in kendi oturumuyla okunur; Hâl o oturumu hiç okumaz.",
            "A reset renews the Codex session and weekly limits at once. Codex reads your resets with its own sign-in, which Hâl never reads."
        ))
        .onChange(of: credits.available) { _, _ in confirming = false }
    }

    /// Bir kullanımın sonucu bir dakika kartta kalır.
    private var finished: (outcome: CodexAppServer.Outcome?, date: Date)? {
        guard case .finished(let outcome, let date) = store.codexResetActivity,
              now.timeIntervalSince(date) < 60 else { return nil }
        return (outcome, date)
    }

    @ViewBuilder private var content: some View {
        if store.codexResetActivity == .redeeming {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                line(L("Sıfırlanıyor…", "Resetting…"))
            }
        } else if confirming, credits.available > 0 {
            VStack(alignment: .leading, spacing: 7) {
                Text(L("Oturum ve haftalık limit şimdi sıfırlansın mı?", "Reset the session and weekly limits now?"))
                    .font(.system(size: 11.5, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    pill(L("Vazgeç", "Cancel"), prominent: false) { confirming = false }
                    pill(L("Sıfırla", "Reset")) {
                        confirming = false
                        store.redeemCodexReset()
                    }
                }
            }
        } else if let finished {
            if finished.outcome == nil, credits.available > 0 {
                // Tekrar denemek aynı kullanımı yineler; ikinci bir hak harcanmaz.
                VStack(alignment: .leading, spacing: 7) {
                    outcome(nil)
                    useButton
                }
            } else {
                outcome(finished.outcome)
            }
        } else if credits.available > 0 {
            HStack(spacing: 8) {
                if let expiry = credits.nextExpiry {
                    // Bir günden az kalan hak, yakında kullanılmaya değer.
                    let soon = expiry.timeIntervalSince(now) < 86_400
                    Text(Lf("Sıradaki %1$@ içinde sona erer", "Next expires in %1$@",
                            TimeFormatters.remaining(expiry.timeIntervalSince(now))))
                        .font(.system(size: 11))
                        .foregroundStyle(soon ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tertiary))
                        .lineLimit(2)
                        .help(expiry.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened)
                            .locale(Language.locale)))
                }
                Spacer(minLength: 4)
                useButton
            }
        } else {
            line(L("Kullanılabilir hak yok", "No resets available"))
        }
    }

    private var useButton: some View {
        pill(L("Hakkı kullan", "Use a reset"), symbol: "arrow.counterclockwise") { confirming = true }
    }

    @ViewBuilder private func outcome(_ outcome: CodexAppServer.Outcome?) -> some View {
        switch outcome {
        case .reset?:
            line(L("Limitler sıfırlandı", "Limits reset"), symbol: "checkmark.circle.fill", tint: .green)
        case .nothingToReset?:
            line(L("Kullanımın henüz sıfırlama gerektirmiyor", "Your usage doesn’t need a reset yet"),
                 symbol: "info.circle.fill", tint: .secondary)
        case .alreadyRedeemed?:
            line(L("Bu hak zaten kullanılmış", "That reset was already used"),
                 symbol: "info.circle.fill", tint: .secondary)
        case .noCredit?:
            line(L("Kullanılabilir hak yok", "No resets available"))
        case nil:
            line(L("Hak kullanılamadı", "Couldn’t use the reset"),
                 symbol: "exclamationmark.circle.fill", tint: .orange)
        }
    }

    private func line(_ text: String, symbol: String? = nil, tint: Color = .secondary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let symbol { Image(systemName: symbol).foregroundStyle(tint) }
            Text(text).foregroundStyle(symbol == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
        .font(.system(size: 11.5, weight: .medium))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func pill(_ title: String, symbol: String? = nil, prominent: Bool = true,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let symbol { Image(systemName: symbol).imageScale(.small) }
                Text(title).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(prominent ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(prominent ? accent.opacity(0.18) : Color.primary.opacity(0.08), in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Parçalar

/// Kullanım çubuğu. `pace`, pencere süresinin geçen kısmını ince bir çizgiyle
/// işaretler: dolgu çizgiyi geçmişse kullanım zamandan hızlı gidiyor demektir.
private struct QuotaMeter: View {
    let value: Double
    let pace: Double?
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: value > 0 ? max(5, geo.size.width * value) : 0)
                if let pace {
                    Rectangle()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: 1.5, height: 9)
                        .offset(x: min(geo.size.width - 1.5, max(0, geo.size.width * pace - 0.75)))
                }
            }
            .frame(height: 5)
            .frame(maxHeight: .infinity)
        }
        .frame(height: 9)
        .animation(.easeOut(duration: 0.25), value: value)
    }
}

private struct QuotaChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(tint.opacity(0.15), in: Capsule(style: .continuous))
            .lineLimit(1)
            .fixedSize()
    }
}

private struct QuotaInlineLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

// MARK: - Kurulum / hata

/// Oturum yok ya da okunamadı: gerçek nedeni ve atılacak adımı gösterir.
private struct QuotaSetupView: View {
    @EnvironmentObject private var store: AppStore
    let group: QuotaGroup
    @Binding var loginHint: String?
    var onSettings: (SettingsTab) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ForEach(actions, id: \.title) { action in
                    Button(action.title, action: action.run)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            if let loginHint {
                Text(loginHint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var title: String {
        if group.status == .missingAuth {
            switch group.kind {
            case .claude: return L("Claude oturumu yok", "No Claude session")
            case .codex: return L("Codex oturumu yok", "No Codex session")
            case .grok: return L("Grok henüz bağlı değil", "Grok is not connected yet")
            case .custom: return Lf("%1$@ için kaynak yok", "No source for %1$@", group.name)
            }
        }
        return Lf("%1$@ kotası okunamadı", "Could not read %1$@ quota", group.name)
    }

    private var detail: String {
        // Tahmin yürütmek yerine CLI'den/sunucudan gelen gerçek nedeni göster.
        if let message = group.message, !message.isEmpty {
            return message + "\n\n" + hint
        }
        return hint
    }

    private var hint: String {
        switch group.kind {
        case .claude:
            return L(
                "Kota Claude Code’a sorulur; oturumu Claude Code kendisi yönetir, Hâl anahtar zincirini okumaz. Terminal’de claude /login çalıştır, sonra Yenile’ye bas.",
                "Quota is asked of Claude Code, which manages its own sign-in; Hâl never reads the Keychain. Run claude /login in Terminal, then tap Refresh."
            )
        case .codex:
            return L(
                "Kota Codex’in kendi sunucusuna (codex app-server) sorulur; oturumu Codex yönetir. Terminal’de codex login çalıştır ya da Codex uygulamasında giriş yap, sonra Yenile’ye bas.",
                "Quota is asked of Codex’s own server (codex app-server), which manages its sign-in. Run codex login in Terminal or sign in to the Codex app, then tap Refresh."
            )
        case .grok:
            return L(
                "Haftalık sınır grok’un kendi fatura ucundan okunur. Oturum ~/.grok/auth.json dosyasıdır. Terminalde grok login çalıştır, sonra Yenile.",
                "The weekly limit is read from grok’s own billing endpoint. The session is ~/.grok/auth.json. Run grok login in Terminal, then Refresh."
            )
        case .custom:
            return L(
                "Bu kaynağın JSON çıktısında kota alanı bulunamadı. Ayarlar’dan komutu veya URL’yi kontrol et.",
                "No quota field found in this source’s JSON output. Check the command or URL in Settings."
            )
        }
    }

    private struct Action {
        var title: String
        var run: () -> Void
    }

    private var actions: [Action] {
        var actions: [Action] = []
        let openedHint = L("Terminal açıldı. Giriş bittikten sonra Yenile’ye bas.",
                           "Terminal opened. After you finish signing in, tap Refresh.")
        switch group.kind {
        case .claude:
            actions.append(Action(title: L("Terminalde giriş", "Sign in via Terminal")) {
                loginHint = ClaudeAuth.openLogin() ?? openedHint
            })
        case .grok:
            actions.append(Action(title: L("Terminalde giriş", "Sign in via Terminal")) {
                loginHint = GrokAuth.openLogin() ?? openedHint
            })
        case .codex, .custom:
            break
        }
        actions.append(Action(title: L("Yenile", "Refresh")) {
            loginHint = nil
            Task {
                await AgentQuotaMemory.shared.invalidate(group.id)
                await store.refresh()
            }
        })
        if group.kind != .grok {
            actions.append(Action(title: L("Ayarlar", "Settings")) { onSettings(.quota) })
        }
        return actions
    }
}
