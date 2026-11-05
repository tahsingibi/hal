import SwiftUI

enum ToolPresentation { case settings, menu }
private struct ToolPresentationKey: EnvironmentKey { static let defaultValue = ToolPresentation.settings }
/// Ayarlar sayfası zaten kaydırıyor; içindeki paneller kendi kaydırmalarını bırakır.
private struct SettingsEmbeddedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var toolPresentation: ToolPresentation {
        get { self[ToolPresentationKey.self] }
        set { self[ToolPresentationKey.self] = newValue }
    }

    var settingsEmbedded: Bool {
        get { self[SettingsEmbeddedKey.self] }
        set { self[SettingsEmbeddedKey.self] = newValue }
    }
}

// MARK: - Sayfa

/// Ayarlar penceresinin tek sayfa düzeni: büyük başlık, altında kartlar. Her
/// sayfa aynı genişlikte ve aynı boşluklarla durur; geniş pencerede ortalanır.
struct SettingsPage<Content: View>: View {
    static var maxWidth: CGFloat { 760 }

    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.title2.bold())
                    if let subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                content()
            }
            .frame(maxWidth: Self.maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(22)
        }
        .environment(\.settingsEmbedded, true)
    }
}

/// Menüde kendi kaydıran, ayarlar sayfasına gömülünce kaydırmayı sayfaya bırakan kap.
struct PanelScroll<Content: View>: View {
    @Environment(\.settingsEmbedded) private var embedded
    var showsIndicators = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        if embedded {
            content()
        } else {
            ScrollView(showsIndicators: showsIndicators) { content() }
        }
    }
}

// MARK: - Kart

/// Bir grup ilgili denetimi taşıyan yuvarlak kart; isteğe bağlı başlık ve dipnotla.
struct SettingsCard<Content: View>: View {
    @Environment(\.toolPresentation) private var presentation
    var title: String? = nil
    var symbol: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        if presentation == .menu {
            VStack(alignment: .leading, spacing: 8) {
                if let title { Text(title).font(.system(size: 13, weight: .semibold)) }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 13) {
                if let title {
                    HStack(spacing: 7) {
                        if let symbol { Image(systemName: symbol).foregroundStyle(.tint) }
                        Text(title).font(.headline)
                    }
                }
                content()
                if let footer { SettingsFootnote(footer) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

/// Satırın metin sütununun başladığı yer; alt denetimler buna hizalanır.
let settingsRowTextInset: CGFloat = 26 + 12

// MARK: - Satırlar

/// Simge, başlık, isteğe bağlı açıklama ve sağda denetim.
struct SettingsRow<Accessory: View>: View {
    let symbol: String?
    let title: String
    var caption: String? = nil
    var badge: String? = nil
    @ViewBuilder var accessory: () -> Accessory

    init(symbol: String?, title: String, caption: String? = nil, badge: String? = nil,
         @ViewBuilder accessory: @escaping () -> Accessory) {
        self.symbol = symbol
        self.title = title
        self.caption = caption
        self.badge = badge
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 12) {
            if let symbol { SettingsIconTile(symbol: symbol) }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                    }
                }
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            accessory()
        }
    }
}

extension SettingsRow where Accessory == EmptyView {
    init(symbol: String?, title: String, caption: String? = nil, badge: String? = nil) {
        self.init(symbol: symbol, title: title, caption: caption, badge: badge) { EmptyView() }
    }
}

struct SettingsIconTile: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 26, height: 26)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// Anahtarlı satır. Eski çağrıların sırası (başlık, açıklama, simge) korunur.
struct SettingsToggleRow: View {
    var title: String
    var detail: String? = nil
    var symbol: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(symbol: symbol, title: title, caption: detail?.isEmpty == false ? detail : nil) {
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }
    }
}

/// Birkaç seçenekten birini seçen açılır menü satırı. Yer yetmezse menü başlığın altına iner.
struct SettingsMenuRow<Value: Hashable, Options: View>: View {
    let symbol: String?
    let title: String
    var caption: String? = nil
    @Binding var selection: Value
    @ViewBuilder var options: () -> Options

    var body: some View {
        ViewThatFits(in: .horizontal) {
            SettingsRow(symbol: symbol, title: title, caption: caption) { menu }
            VStack(alignment: .leading, spacing: 8) {
                SettingsRow(symbol: symbol, title: title, caption: caption)
                menu.padding(.leading, symbol == nil ? 0 : settingsRowTextInset)
            }
        }
    }

    private var menu: some View {
        Picker(title, selection: $selection) { options() }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
    }
}

/// Segmentli seçim satırı; sığmazsa segmentler başlığın altına iner.
struct SettingsSegmentRow<Value: Hashable, Options: View>: View {
    let symbol: String?
    let title: String
    @Binding var selection: Value
    @ViewBuilder var options: () -> Options

    var body: some View {
        ViewThatFits(in: .horizontal) {
            SettingsRow(symbol: symbol, title: title) { picker }
            VStack(alignment: .leading, spacing: 8) {
                SettingsRow(symbol: symbol, title: title)
                picker.padding(.leading, symbol == nil ? 0 : settingsRowTextInset)
            }
        }
    }

    private var picker: some View {
        Picker(title, selection: $selection) { options() }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
    }
}

/// Başlığın yanında sabit genişlikte, sola yaslı bir metin alanı.
struct SettingsTextRow: View {
    let symbol: String?
    let title: String
    var caption: String? = nil
    @Binding var text: String
    var prompt: String = ""
    var width: CGFloat = 260

    var body: some View {
        SettingsRow(symbol: symbol, title: title, caption: caption) {
            TextField(title, text: $text, prompt: Text(prompt))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
        }
    }
}

/// Sayı alanı ve birimi: "2000 ml".
struct SettingsNumberRow: View {
    let symbol: String?
    let title: String
    var caption: String? = nil
    @Binding var value: Double
    var unit: String = ""

    var body: some View {
        SettingsRow(symbol: symbol, title: title, caption: caption) {
            HStack(spacing: 6) {
                TextField(title, value: $value, format: .number.locale(Language.locale).grouping(.never))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                if !unit.isEmpty {
                    Text(unit).foregroundStyle(.secondary).frame(minWidth: 22, alignment: .leading)
                }
            }
        }
    }
}

/// Kart içindeki küçük açıklama metni.
struct SettingsFootnote: View {
    let text: String
    var inset: CGFloat = 0

    init(_ text: String, inset: CGFloat = 0) {
        self.text = text
        self.inset = inset
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, inset)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Etiketi solda, anahtarı sağda tutan anahtar biçimi; kendi etiketini taşıyan
/// denetimler de diğer satırlarla aynı hizada durur.
struct TrailingSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 12)
            Toggle(isOn: configuration.$isOn) { EmptyView() }
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

// MARK: - Araç parçaları

struct ToolEmptyState: View {
    var symbol: String
    var title: String
    var detail: String
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity).padding(.vertical, 24)
    }
}

struct ToolBadge: View {
    var title: String
    var color: Color = .secondary
    var body: some View {
        Text(title).font(.system(size: 10, weight: .medium))
            .foregroundStyle(color).padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}
