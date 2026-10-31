<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Resources/Icons/hal-white.svg">
  <img alt="Hâl" src="Resources/Icons/hal.svg" width="96">
</picture>

# Hâl

**macOS menü çubuğunda duran kişisel durum panosu.**

Kotanı, namaz vaktini, odağını, takvimini, sağlığını ve ödemelerini tek pencerede topla. Dock'ta ikon bırakmaz.

[English](README_EN.md) · Türkçe

macOS 14+ · MIT Lisansı

</div>

---

## İçindekiler

- [Öne çıkanlar](#öne-çıkanlar)
- [Hızlı başlangıç](#hızlı-başlangıç)
- [Menü çubuğu](#menü-çubuğu)
- [Modüller](#modüller)
- [Araçlar](#araçlar)
- [Bildirimler](#bildirimler)
- [Gizlilik: uygulama ne okur?](#gizlilik-uygulama-ne-okur)
- [Güncelleme ve yayın](#güncelleme-ve-yayın)
- [Kod imzası](#kod-imzası)
- [Sürüm notları](#sürüm-notları)
- [Geliştirme](#geliştirme)
- [Hakkında](#hakkında)

## Öne çıkanlar

- **Tek pencere, yedi sekme:** Bugün, Odak, Kotalar, İbadet, Takvim, Sağlık, Ödemeler.
- **Modüler:** Kapattığın modülün veri kaynağı ve bildirimleri de durur.
- **Kotalar:** Claude, Codex ve Grok kullanımını menü çubuğundan izle.
- **Namaz vakitleri ve takibi:** Sıradaki vakit, günlük sayı ve kesintisiz seri.
- **Otomatik odak ölçümü:** Tarayıcı adresi okunmaz, izin istemez.
- **Araçlar:** İndirici, Portlar, Homebrew, ses mikseri ve güncellemeler.
- **Türkçe ve İngilizce arayüz;** dil anında değişir.
- **Sandbox'sız, yerel çalışır;** veriler Mac'inde kalır.

## Hızlı başlangıç

Hazır kurulum [Releases](https://github.com/tahsingibi/hal/releases/latest) üzerindeki DMG dosyasıdır. Yayındaki sürüm **1.1.0** (31 Ekim 2026).

1. DMG'yi aç, **Hal**'i **Applications** klasörüne sürükle.
2. İlk açılış: Sistem Ayarları → Gizlilik ve Güvenlik → **Yine de Aç**.

macOS 14+ · Apple Silicon ve Intel. Paket ad-hoc imzalıdır, notarize değildir.

Depodan derlemek geliştirme yoludur:

```bash
./build.sh
open Hal.app
```

`./build.sh --dmg` aynı derlemeyi `dist/Hal-<sürüm>.dmg` olarak paketler ve yanına SHA-256 yazar. Projedeki `Hal.app` geliştirme sertifikasıyla imzalı kalır. `Hal.app`, `.build` ve `dist/` depoya girmez.

**Adlandırma:** Görünen ad **Hâl**'dir. Dosya adı, bundle kimliği ve veri klasörü Türkçe karaktersiz **Hal** kullanır:

| Ne             | Değer                               |
| -------------- | ----------------------------------- |
| Uygulama       | `Hal.app`                           |
| Bundle kimliği | `dev.sungur.Hal`                    |
| Veri klasörü   | `~/Library/Application Support/Hal` |

**Marka:** Sağa açılan bir gösterge halkası ve içindeki konum noktası. Kaynak: `Resources/Icons/hal.svg`. Menü çubuğundaki çizim: `Sources/BrandIcons.swift`.

### Dil

İlk açılışta Mac'in dili kullanılır: sistem dili Türkçe ise Türkçe, değilse İngilizce. Ayarlar › Genel › Dil'den _Sistem_, _Türkçe_ veya _English_ seçilebilir; seçim hemen uygulanır, yeniden açmak gerekmez.

- Tarih ve gün adları seçilen dile uyar. Saat 24 saat biçimindedir.
- Dosyaya ve ağa giden tarih anahtarları POSIX biçimindedir.
- Arayüz metinleri `Resources/tr.lproj` ve `Resources/en.lproj` içinde düzenlenebilir. Sistem izin açıklamaları da yerelleştirilmiştir; bu pencerelerde macOS’un dil seçimi geçerlidir.
- Çeviri kapsamını ve biçim argümanlarını `python3 scripts/localize.py --check` doğrular. Yeni metinleri `--write` ile eklersin; mevcut çevirmen düzenlemeleri korunur.
- Marka adları (Claude, Codex, Grok, Hâl, Always Wake) çevrilmez.

## Özellikler ve ayarlar

Ayarlar penceresi dört başlıkta toplanır:

- **Uygulama:** Genel, Özellikler, İzinler, Menü çubuğu ve Bildirimler.
- **Kişisel:** Odak, İbadet, Sağlık ve Ödemeler.
- **Araçlar:** Kotalar, Takvim, Uyanık tutma, Pencere değiştirici, Ekranlar, Ses, Video indirici, Portlar, Homebrew ve Güncellemeler.
- **Bilgi:** Hakkında ve Yenilikler.

Özellikler sayfasından modülleri tek tek açabilir veya hazır grupları uygulayabilirsin. Kapalı modüller panelden ve ayar kenar çubuğundan kaldırılır; kayıtları korunur. Bugün her zaman açıktır.

Menü panelinin üstünde tek satıra sığan ikon sekmeleri vardır: Kişisel (Bugün, Odak, İbadet, Sağlık, Ödemeler), Kotalar, Takvim, Video indirici, Uyanık tut, Ekranlar, Ses, Güç, Araçlar ve Kontroller. Sekmelerin sırası ve görünürlüğü **Menü çubuğu › Panel sekmeleri** bölümünden değiştirilir. Panelin altında Ayarlar, Uyanık tut ve Çık düğmeleri durur. İzinler sayfası erişimin amacını ve ilgili ayarlara bağlantıları gösterir; kendiliğinden izin istemez.

Uygulamayı yeniden açmak Özellikler penceresini öne getirir. `./build.sh` çıktıyı bu klasördeki `Hal.app` içine yazar; Applications’a kopyalamaz.

## Menü çubuğu

İlk açılışta yalnızca Hâl ikonu durur. Kota ve namaz ikonları Ayarlar › Görünüm'den tek tek açılır.

- **Açma:** Tıklayınca detay penceresi açılır; üzerine gelmek açmaz.
- **Hedef:** Varsayılan hedef _Bugün_ panosudur. Ayarlar › Görünüm › Tıklama'dan "Tıklanan öğenin detayı" seçilirse ikon kendi sayfasını açar. Genel Hâl ikonu her durumda panoya gider. Pano kapalıysa her ikon temsil ettiği sayfaya düşer.
- **Gezinme:** Pencere açıkken başka bir ikona tıklamak onu oraya taşır. Son bakılan sekme hatırlanır; yenileme seçimi değiştirmez.
- **Sabitleme:** Başlıktaki raptiye pencereyi sabitler, dışarı tıklayınca kapanmaz. `Esc` kapatır.
- **Sağ tık menüsü:** Yenile, ayarlar, araçlar, modlar, çıkış. İkinci ekran kopyası isteğe bağlıdır.
- **Tek ikonda toplama:** "Kotaları tek ikonda topla" varsayılan olarak açıktır. Seçili sağlayıcıların marka ve kota değerleri 3,5 saniyede bir yerel SwiftUI geçişiyle sırayla gösterilir. Namaz saati ayrı ikon olarak kalır.
- **Durum işaretleri:** Oturum yoksa `–`, okuma hatasında `!` görünür. Yüzde yoksa sayı üretilmez.

## Modüller

Yedi sekme vardır. _Bugün_ kapatılamaz; diğerleri Ayarlar › Özellikler'den kapatılabilir. Kapanan modül yalnızca gizlenmez, veri kaynağı ve bildirimleri de durur. Sekmeler yatay kayar. Dörtten fazla modül açıkken başlık yalnızca seçili sekmede görünür.

### Bugün

Açık modüllerin panoya verdiği satırları toplar: derin çalışma, en boş kota, dolu veya okunamayan kotalar, sıradaki vakit, kılınan namaz ve seri, su ve protein. Satır; ikon, başlık, değer ve gerekirse tek satır açıklamadan oluşur. İlerleme çubuğu yoktur, oran değerin kendisindedir (çubuklar modül sayfalarındadır). Satıra tıklayınca ilgili sekmeye gidilir.

- Hangi satırların görüneceği Ayarlar › Görünüm › _Bugün panosunda göster_ altından seçilir. Satırı gizlemek modülü kapatmaz; sekme, ölçüm ve bildirimler yerinde kalır. Gizlenen satır akşam gün özetinde de yer almaz.
- Liste, o an ekranda olanlarla sınırlı değildir. Bir kez görülen satır `hal.summaryCatalog` kaydında kalır; modül kapanınca satırları listeden düşer. Başlığı gün içinde değişen satırlar sabit adla durur ("Sıradaki vakit", "Sonraki olay").
- **Hafta:** Son yedi günün odak, antrenman, namaz ve beslenme özetini gösterir. Yeni veri toplamaz.
- **Gün Sonu:** Son dört günün namaz, ilaç ve antrenman işaretlerini tek listede toplar. Bilgisayara geçilmeyen gün buradan tamamlanır. Dünden açık işaret varsa pano satırı da oraya götürür. Bugünün eksiği akşam görünür. Pencere bilerek kısa tutulur; seriyi sonsuza dek geriye doldurmak ölçümü bozar.
- Günlük kayıtlar `~/Library/Application Support/Hal/daily.json` içindedir. Yapı gün → metrik sözlüğüdür ve 400 günlük geçmiş tutulur.

### Odak

Öndeki uygulamanın adı `focusApps` listesindeyse ve Mac iki dakikadır boşta değilse süre kendiliğinden sayılır. Dilimler 30 saniyedir. Günlük hedef, o an sayılan uygulama, son yedi gün, haftalık toplam ve en iyi gün gösterilir. Tarayıcı adresi okunmaz; ölçüm izin istemez.

### Kotalar

Claude, Codex ve Grok. Anahtarlar ilk kurulumda kapalıdır; CLI makinede olsa bile kotayı sen açarsın.

|        | Kaynak                               | Oturum                                     |
| ------ | ------------------------------------ | ------------------------------------------ |
| Claude | `api.anthropic.com/api/oauth/usage`  | Anahtar Zinciri, "Claude Code-credentials" |
| Codex  | `chatgpt.com/backend-api/wham/usage` | `~/.codex/auth.json`                       |
| Grok   | grok CLI fatura yanıtı               | `~/.grok/auth.json`                        |

- **Grok:** Haftalık sınır ve Grok Build bu faturadan okunur. Süre dolmak üzereyse aynı dosyadaki yenileme belirteciyle uzatılır ve dosyaya geri yazılır. Ön ödemeli bakiye ve yönetim anahtarı bu sayıya karışmaz.
- **Oturum yoksa:** Claude veya Grok için pencereden Terminalde giriş açılır. Sohbet, oturum dizini ve tarayıcı çerezi okunmaz; Chrome Safe Storage sorulmaz.
- **Özel kaynak:** Ayarlar'dan elle, komutla veya URL ile özel kota kaynağı eklenebilir.
- Yüzde yoksa uydurulmaz.

### İbadet

Vakitler ve namaz takibi. Konum, hesap yöntemi ve namaz takibi anahtarı Ayarlar › İbadet altında, aynı başlıktadır.

- Şehir listeden seçilir. Konum izni kendiliğinden istenmez. Koordinat seçilmeden vakit istenmez; `0,0` konum sayılmaz.
- Vakitler `api.aladhan.com` üzerinden gelir. Türkiye'de Diyanet ikindi için erken (Şafii) hesabı kullanır; Hanefi yaklaşık bir saat sonradır.
- Namaz sekmesinde vakit işaretlenir. Pano gün içi sayıyı ve kesintisiz gün serisini gösterir. Seri, bugün henüz tamamlanmadıysa dünden geriye sayar.
- Menü çubuğu ikonu, açıksa, sıradaki vaktin saatini gösterir. Güneş de sıradaki vakit olabilir.

### Takvim

Bugünün kalan olayları ve panoda sonraki olay. İzin yalnızca Ayarlar'daki veya sayfadaki düğmeyle istenir. İzin yokken EventKit'e gidilmez ve sayfa boş kalır.

### Sağlık

Dört bölüm: Genel, Antrenman, İlaç ve Takviye, Beslenme.

- **Su ve protein** isteğe bağlıdır. Hızlı giriş hem Bugün satırında hem kendi sayfasındadır.
- **Antrenman:** Haftanın her gününe bir plan etiketi, tek dokunuşla "yapıldı", haftalık ilerleme ve kesintisiz seri. Boş veya "Dinlenme" günleri antrenman sayılmaz, seriyi de kırmaz. Set, tekrar ve ağırlık kaydı yoktur.
- **İlaç ve takviye:** Her öğeye birden çok doz saati verilir; her saat ayrı kayıttır. Saati geçmiş ve işaretlenmemiş doz "geçti" diye vurgulanır. Bildirim doz saatinde gider, alınmış doza gitmez.

### Ödemeler

Abonelik, fatura ve taksit. Yenileme tarihi bir kez girilir; sonraki tarihler kayıt değiştirilmeden hesaplanır, uygulama günlerce kapalı kalsa da tarih doğru kalır. Yıllık ödemeler aylık toplama on ikiye bölünerek girer. Yenilemeden seçilen gün sayısı kadar önce, sabah 09:00'da bildirim gider. Tek seferlik harcama takibi yoktur.

## Araçlar

Pano modülü değildirler. Ayarlar › Araçlar'dan ve menü çubuğu ikonuna sağ tıklayınca açılırlar.

### İndirici

`yt-dlp` sarmalayıcısı. Bağlantıyı yapıştır, MP3 veya MP4 seç, klasör seç (seçilmezse masaüstü kullanılır). İlerleme canlı okunur ve iptal edilebilir. Hata, `yt-dlp`'nin kendi mesajıdır. `yt-dlp` veya `ffmpeg` yoksa kurulum komutu gösterilir; kurulum yapılmaz.

**Otomatik güncelleme:** Günde bir kez, ilk indirmeden önce `yt-dlp` güncellenir. İndirme çıkarıcı hatasıyla düşerse (`Unable to extract`, `nsig extraction failed`, `HTTP Error 403`) bir kez zorla güncellenip yeniden denenir. "Video unavailable" gibi hatalarda güncelleme denenmez. Yöntem kuruluma göredir:

| Kurulum           | Komut                                |
| ----------------- | ------------------------------------ |
| Tek dosya derleme | `yt-dlp -U`                          |
| Homebrew          | `brew upgrade`                       |
| Python betiği     | `pipx upgrade` veya `pip install -U` |

### Portlar

Dinleyen TCP portlarını ve tutan programı listeler (`lsof`).

- "Yalnızca benim süreçlerim" varsayılan açıktır.
- "Geliştirici" kapsülü varsayılan kapalıdır; açılınca yalnızca geliştirici sunucuları kalır.
- Durdurma (`kill`): süreç seninse önce sorar ve `SIGTERM` gönderir. Süreç dinlemeye devam ederse sonraki onay `SIGKILL`'dir.
- Sistem ve başka kullanıcının süreçleri "sistem" diye durur, düğme yoktur.

### Homebrew

Bu Mac’teki Homebrew. Formül ve cask aranır, kurulur, kaldırılır ve yükseltilir. `brew services` kayıtları başlatılır veya durdurulur. Kaldırma ve durdurma önce sorar. Homebrew yoksa kurulum yapılmaz; `brew.sh` gösterilir.

### Ses

Çıkış sesi ve sessize alma. Ses çıkaran her uygulamanın kendi seviyesi vardır; üst sınır 150%’dir. 100% iken ses doğrudan gider. Seviye değişince o uygulamanın sesi süreç tap’i ile okunur ve seçilen kazançla çalınır. Kayıt tutulmaz. Ayrı seviye için sistem sesi kaydı izni gerekir.

### Güncellemeler

Tek listede macOS (`softwareupdate`), Homebrew (`brew outdated`) ve Sparkle beslemesi olan uygulamalar. App Store uygulamaları, `mas` kuruluysa ondan, değilse App Store sayfasından açılır. Hiçbiri kendiliğinden kurulmaz. Sistem güncellemesi Mac’i yeniden başlatabilir.

## Bildirimler

Ayarlar › Bildirimler. İzin, bir bildirim açıkken istenir. Her olay bir kez bildirilir.

- **Vakit:** vakit girince veya 5, 10, 15, 30 dakika önce
- **Kota sıfırlanınca**
- **Kota eşiği aşılınca**
- **Gün sonu hatırlatması:** varsayılan 12:00, kapatılabilir; tıklayınca Gün Sonu açılır
- **Gün özeti:** seçilen saatte panoyu bildirir
- **İlaç dozu ve abonelik yenilemesi:** ilgili kayıt varken

Diğer bildirimler kapalı gelir. Modüller `ModuleAlerts.swift` içinde `Alert` üretir; zamanlama ve tekrar engelleme `NotificationService` içindedir.

### Diğer özellikler

- **Temizlik modu:** Ekranı kalkanla kapatır; bu kısım izinsiz de çalışır. Sistem kısayollarının da kilitlenmesi için Erişilebilirlik ve Giriş İzleme gerekir. İzin Ayarlar'daki düğmeyle istenir; her açılışta Sistem Ayarları'na yönlendirmez.
- **Uyanık tutma:** Sürekli açıkken Mac boşta uyku ve ekran uykusuna geçmez. İsteğe bağlı sayaç, Odak listesindeki uygulamalar öndeyken, prizde veya harici ekrandayken, kapak kapalıyken. Kapak kuralı boşta uykuyu keser; macOS, harici güç ve ekran yoksa kapağı kapatınca yine uyuyabilir.
- **Açılışta başlat:** Yalnızca Ayarlar'daki anahtar değişince güncellenir.

## Gizlilik: uygulama ne okur?

Uygulama sandbox'lı **değildir**. Okuduğu her şey burada:

| Ne                      | Nereden / ne zaman                         | Not                                                                                        |
| ----------------------- | ------------------------------------------ | ------------------------------------------------------------------------------------------ |
| Claude kotası           | Anahtar Zinciri, "Claude Code-credentials" | Sohbet okunmaz                                                                             |
| Codex kotası            | `~/.codex/auth.json`                       | Oturum dizini ve sohbet gövdesi okunmaz                                                    |
| Grok kotası             | `~/.grok/auth.json`                        | Belirteç yenilenince aynı dosyaya yazılır. Çerez ve console.x.ai yönetim anahtarı istenmez |
| Namaz vakitleri         | Şehir seçilince `api.aladhan.com`          | Koordinat seçilmeden istek yapılmaz                                                        |
| Takvim                  | Düğmeye basılınca EventKit                 | İzin yokken erişilmez                                                                      |
| Temizlik kısayol kilidi | Erişilebilirlik ve Giriş İzleme            | Yalnızca Ayarlar'daki düğmeyle                                                             |
| Günlük kayıtlar         | `~/Library/Application Support/Hal/`       | Eski `secrets.json` kota yolunun parçası değildir                                          |
| Uyanık tutma            | Öndeki uygulama, güç kaynağı, ekranlar, kapak | Ağ yok                                                                                  |
| Homebrew                | Bu Mac’teki `brew`                         | Ağ, yalnızca `brew` kendi isterse                                                          |
| Ses mikseri             | Çalan süreçler; seviye değişince süreç tap’i | Kayıt tutulmaz                                                                           |
| Güncellemeler           | `softwareupdate`, `brew`, `SUFeedURL`      | App Store paketleri indirilmez                                                             |

## Güncelleme ve yayın

İndirilen kopya yeni sürümü kendisi sorar; kurulum kendiliğinden yapılmaz. Denetleme günde bir kez yapılır; Ayarlar › Hakkında › _Güncellemeleri denetle_ ile de istenir.

- **Kanal:** `https://raw.githubusercontent.com/tahsingibi/hal/main/appcast.xml`. Uygulama repodaki bu dosyaya bakar. Zip, GitHub Release’e konur; indirme adresi `appcast.xml` içindeki `enclosure` satırındadır. Kanalda **1.1.0** (derleme 3) var.
- **Sparkle:** Paket Sparkle 2.10.0 ile gelir. `build.sh` arşivi indirir ve SHA-256 ile doğrular.
- **Anahtarlar:** Açık anahtar `SUPublicEDKey` içindedir. Gizli anahtar login anahtarlığındadır (hesap adı `Hal`) ve repoya girmez. Anahtar silinirse bu sürümden sonrakilere güncelleme imzalanamaz.
- **Bu sürüm:** GitHub Release üzerindeki DMG ve Sparkle zip’i. Uygulama içi denetleme 1.1.0’ı görür.
- **Sonraki uygulama içi güncelleme:** `scripts/publish-update.sh` yalnızca **Developer ID Application** sertifikası varken zip üretir. Zip GitHub Release'e konur, adresi `appcast.xml` içindeki `enclosure` satırına yazılır. Noter için `NOTARY_KEYCHAIN_PROFILE` gerekir. `CFBundleVersion` katı biçimde artar.
- **Sürekliliği korumak:** Bundle kimliği değişmez; `~/Library/Application Support/Hal` ve tercihler yerinde kalır.

> **Not:** Uygulama içi güncellemeyi taşıyan ilk zip, Sparkle'ı içeren sürüm olmalıdır. `CFBundleVersion` her yayında katı biçimde artar.

## Kod imzası

`build.sh`, anahtar zincirindeki ilk Apple Development veya Developer ID sertifikasıyla imzalar. Kimlik `HAL_SIGN_IDENTITY` ile değiştirilebilir.

- Sertifika yoksa **ad-hoc** imzalanır. Ad-hoc imzada her derleme yeni bir kod kimliği üretir; Anahtar Zinciri ve Erişilebilirlik izinleri her seferinde sıfırlanır. Sabit bir geliştirici sertifikasıyla izin bir kez verilir.
- `./build.sh --dmg` uygulamayı `dist` altına kopyalar, bu kopyayı ad-hoc imzalar ve `dist/Hal-<sürüm>.dmg` yazar. Projedeki `Hal.app` geliştirme sertifikasıyla kalır.
- İmza kimliği ilk kez değişince macOS bir defalığına Anahtar Zinciri erişimi sorar; **Her Zaman İzin Ver** seçilir. Erişilebilirlik listesindeki eski kayıt da geçersizleşir; kayıt silinip yeniden eklenir.

## Geliştirme

Sekmeler ve menü çubuğu ikonları `Sources/Modules.swift` içindeki `ModuleKind` kaydından türer. `today` kapatılamaz. İndirici, Portlar, Homebrew, Ses ve Güncellemeler bu kaydın dışındadır.

**Yeni modül eklemek için:**

1. `ModuleKind` içine bir `case`, `title` ve `symbol`
2. `AppStore.pages(for:)` içinde sayfalar
3. `AppStore.summaryLines(for:)` içinde pano satırları
4. `DetailPopoverView` içinde sayfanın görünümü
5. Veri kaynağı ve gerekirse `ModuleAlerts.swift` içinde `Alert`

**Notlar:**

- Seçim `DetailTarget` ile taşınır ve `"usage/claude"` biçiminde saklanır. Eski kayıtlar (`"prayer"`, düz kota kimliği) hâlâ çözülür. Her modülün son bakılan sayfası ayrı hatırlanır.
- Ayarlar penceresi kenar çubuğu ve arama kullanır: Uygulama (Genel, Görünüm, Bildirimler, Uyanık tutma), Modüller, Araçlar (İndirici, Portlar, Homebrew, Ses, Güncellemeler), Hakkında ve Yenilikler.
- Detay penceresinin yüksekliği seçili sayfanın doğal boyundan gelir ve ekrana göre en fazla 440 pt ile sınırlanır. Sınırı aşan sayfa kendi içinde kayar.
- Paketin geliştirme bölgesi `tr` olarak işaretlidir; bu, çalışma anındaki dili kilitlemez.

## Sürüm notları

Uygulamadaki Hakkında sayfası aynı listeyi gösterir.

### 1.1.0 — 31 Ekim 2026

- Kompakt güç paneli: pil ve sistem grafikleri, adaptör gücü, sıcaklık, sağlık, döngü ve kapasite ayrıntıları
- Hakkında sayfasından açılabilen tanıtım ekranı
- Pencere değiştiricide izin durumu, izin sonrası otomatik kısayol bağlantısı ve basılı tut / bırak geçişi

- Uyanık tutma: sayaç, seçili uygulamalar öndeyken, prizde veya harici ekrandayken, kapak kapalıyken
- Homebrew: arama, kurma, kaldırma, yükseltme, servisi başlatma ve durdurma
- Ses mikseri: çıkış sesi ve uygulama başına seviye
- Güncellemeler: macOS, Homebrew ve yüklü uygulamalar
- Menü çubuğu paneli: simge şeridi, uyanık tutma süreleri, ses mikseri ve araçlar
- Yenilikler kendi sayfasında

### 1.0.0 — 16 Ekim 2026

- Bugün panosu, hafta özeti ve gün sonu
- Odak ölçümü
- Kotalar: Claude, Codex, Grok ve özel kaynak
- İbadet ve namaz takibi
- Takvim
- Sağlık: su, protein, antrenman, ilaç ve takviye
- Ödemeler
- İndirici (yt-dlp)
- Portlar
- Temizlik modu
- Uyanık tutma: sürekli
- Bildirimler, Türkçe ve İngilizce, Sparkle ile sürüm sorusu

## Hakkında

Yazan: **Tahsin Sungur** · [sungur.dev](https://sungur.dev) · [@tahsingibi](https://x.com/tahsingibi)

Lisans: [MIT](LICENSE)

### Yerelleştirme ve ayar doğrulaması

```bash
python3 scripts/localize.py --check
./scripts/verify-settings.sh
```

Doğrulama eski ayarların açılmasını, sıralama ve kompakt görünümün kayıt döngüsünü, tekrar eden/eski modül kimliklerini ve kaynak paketinden anlık dil değişimini kapsar. Kişisel ayarları okumaz veya değiştirmez. Yeni dinamik metinlerde Swift interpolasyonu yerine `Lf` ve konumlu `%1$@` / `%1$d` kullan. Aynı İngilizce metnin farklı Türkçe karşılıkları katalogda `English | Türkçe` bağlam anahtarlarıyla ayrılır.

## Pencere değiştirici ve ekranlar

**Ayarlar › Çalışma ve enerji › Pencere değiştirici** bölümünden etkinleştirilir. Varsayılan uygulama kısayolu **⌥Tab**, pencere kısayolu **⌥`**. Kısayol alanına tıkla ve istediğin birleşimi basarak kaydet; sabit seçenek listesi yoktur. Eski kısayol tercihleri yeni kayıt biçimine taşınır.

- Değiştirici tuşunu basılı tut; Tab/Shift-Tab, oklar veya fareyle gezin; tuşu bırakınca seçilen pencere açılır. Hızlı basış görünme gecikmesini beklemeden geçiş yapar. Esc iptal eder. Elle açılan deneme panelinde Enter ile seçim yapılır.
- Uygulamalar, öndeki/seçili uygulamanın pencereleri ve tüm pencereler için ayrı kısayollar vardır. ⌘Tab / ⌘` kaydedildiğinde ilgili macOS kısayolu geçici olarak devralınır. Özellik kapanınca, güvenli girişte ve uygulama çıkışında geri verilir; açılışta yarım kalmış kayıtlar onarılır.
- Üç görünüm: yatay pencere önizleme şeridi, büyük simgeler ve basit liste. Boyut, sütun sayısı, ekran yerleşimi, görünme gecikmesi ve animasyon tercihleri ayarlanır.
- Küçültülmüş pencereler normal sırada, sonda veya gizli tutulabilir. Tam ekran, geçerli ekran/masaüstü, uygulama başına bir giriş, penceresiz uygulamalar ve uygulamaya göre dışlama seçenekleri vardır.
- W pencereyi normal şekilde kapatır, Q uygulamadan çıkmasını ister; kaydedilmemiş içerik varsa uygulamanın kendi penceresi karar verir. Orta tık yalnızca üzerine gelinen pencereyi kapatır. İsteğe bağlı S ile arama sabitlenir.
- Erişilebilirlik olmadan özel kısayollarla uygulama görünümü kullanılır. Ekran Kaydı izni olmadan gerçek önizleme yerine uygulama simgesi gösterilir. Önizlemeler pencere kimliğiyle eşlenir; küçültülmüş pencerelerin yakalanması denenir. Küçük resimler yalnızca bellekte, en çok 48 adet tutulur; özellik kapatılınca veya bellek baskısında temizlenir. Dosyaya veya ağa yazılmaz. Uygulamaya göre yakalama duraklatılabilir.

**Ekranlar** bölümünde parlaklık kontrolü ayrıca etkinleştirilir. Desteklenen ekranlarda donanım parlaklığı ayarlanır; diğer ekranlarda tıklamaları engellemeyen yazılımsal karartma uygulanır. Yazılımsal karartma ekranın güç tüketimini azaltmaz. Değişiklikler Mac uyuyunca, özellik kapatılınca veya Hâl normal şekilde kapanınca geri alınır. Donanım parlaklığı sonradan başka yerden değiştirilmişse bu değişiklik korunur. Karartma açılışta yeniden uygulanmaz.

Ses aygıtları belirgin **Değiştir** menülerinden seçilir; uygulama seviyeleri ayrı kartlarda gösterilir. Homebrew’da Yüklü / Paket bul / Servisler ayrılır; bağımlılıklar gizlenebilir, ayrıntılar paket adına tıklayarak açılır. Yalnızca güncel olmayan paketlere güncelleme sunulur. Güncellemeler kaynak kartlarında toplanır; günlük veya haftalık arka plan denetimi isteğe bağlıdır ve kendiliğinden kurulum yapmaz. Ayar kenar çubuğu grupları açılıp kapanır; geri/ileri gezinme desteklenir.
