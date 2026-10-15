# Hâl

macOS menü çubuğu uygulaması: kişisel durum panosu. "Hâl" = an itibarıyla durumun —
kotan, vaktin, odağın, ödemen. Arayüz Türkçe. macOS 14 ve sonrası.

Marka: sağa açılan gösterge halkası ve içindeki konum noktası. Hem ölçüm hem hilal-yıldız
mirası. `Resources/Icons/hal.svg`, menü çubuğunda `BrandIcons.swift` içindeki yollarla çizilir.

Yazan: Tahsin Sungur · [sungur.dev](https://sungur.dev) · [@tahsingibi](https://x.com/tahsingibi).
Lisans: MIT.

> **Bundle kimliği bilerek `dev.sungur.Hilal` kaldı.** Değişseydi tüm ayarlar, bildirim
> izni, Erişilebilirlik izni ve açılışta başlatma kaydı sıfırlanırdı. Görünen ad, uygulama
> dosyası ve veri klasörü `Hal`; eski `~/Library/Application Support/Hilal` klasörü ilk
> açılışta `Hal` olarak taşınır.

## Özellikler

- Menü çubuğu: isteğe bağlı Claude, Codex, Grok ve namaz. Kota anahtarları ilk kurulumda kapalıdır; CLI makinede olsa bile sen açarsın
- Detay kutusu modül sekmeleri, yatay kaydırma. Kotalar altında açık olan sağlayıcılar
- Grok: haftalık sınır ve Grok Build, grok CLI’nin fatura yanıtından okunur. `/rest/rate-limits` haftalık limit değildir ve kullanılmaz. Ön ödemeli bakiye ve yönetim anahtarı bu sayıya karışmaz. Yüzde yoksa uydurulmaz
- Menü çubuğuna tıklayınca varsayılan olarak **Bugün panosu** açılır
  (Ayarlar > Görünüm > Tıklama). "Tıklanan öğenin detayı" seçilirse ikon ne
  gösteriyorsa onun sayfası açılır. Özet ikon ve genel ikon her koşulda panoya
  gider — ikisi de tek bir şeyi değil genel durumu temsil eder. Pano modülü
  kapalıysa herkes temsil ettiği sayfaya düşer
- Açıkken başka bir ikona tıklamak pencereyi oraya taşır
- Popover son sekmeyi hatırlar; yenileme seçili sekmeyi değiştirmez
- Başlıktaki raptiye: detay penceresini sabitler, dışarı tıklayınca kapanmaz (tercih kalıcıdır). Esc kapatır
- Kota kaynakları: Claude `api.anthropic.com/api/oauth/usage` (Keychain “Claude Code-credentials”), Codex `chatgpt.com/backend-api/wham/usage` (`~/.codex/auth.json`), Grok CLI faturası (`~/.grok/auth.json`, süresi dolunca dosyadaki oturum yenilenir)
- Oturum yoksa `–`, okuma hatasında `!` görünür; sayı uydurulmaz
- Claude veya Grok oturumu yoksa pencereden Terminalde giriş
- İlk açılışta menü çubuğunda yalnızca Hâl ikonu durur. Kota ve namaz ikonları Ayarlar > Görünüm’den açılır
- Ayarlar > Görünüm > “Kotaları tek ikonda topla”: kota ikonları tek ikona iner ve **en boş** kullanılabilir kotayı gösterir. Namaz saati ayrı ikon kalır
- Bildirimler (Ayarlar > Bildirimler): vakit bildirimi (vakit girince veya 5/10/15/30 dk
  önce), kota sıfırlanınca, kota eşiği aşılınca, gün sonu hatırlatması (varsayılan 12:00,
  kapatılabilir). Diğerleri kapalı gelir. İzin ancak bir bildirim açıkken istenir. Her
  olay bir kez bildirilir
- Bildirim katmanı modülden bağımsız: modüller yalnızca `Alert` üretir
  (`ModuleAlerts.swift`), zamanlama ve tekrar engelleme `NotificationService`'te
- Namaz: konum seçilmeden vakit istenmez. Bugün satırı ve Namaz sayfası “konum seç” der. Şehir Ayarlar > İbadet’ten seçilir. 0,0 koordinatı konum sayılmaz
- Namaz ikonu, açıksa, bir sonraki vaktin saatini gösterir; Güneş de sıradaki vakit olabilir
- Hakkında: Tahsin Sungur, sungur.dev, @tahsingibi
- Tıklayınca detay penceresi açılır; hover açmaz
- İkinci ekran kopyası isteğe bağlı
- Temizlik modu: ekran kalkanı izin olmadan da çalışır. Sistem kısayollarının da kilitlenmesi için Erişilebilirlik + Giriş İzleme izni gerekir; izin Ayarlar’dan açıkça istenir, her açılışta sistem ayarlarına yönlendirmez
- Always Wake

## Popover yüksekliği

Sayfalar yatay bir `SwipePager` içinde durur. Her sayfa kendi `ScrollView`'ında;
popover yüksekliği seçili sayfanın doğal yüksekliğine göre ayarlanır ve
`MenuBarLayout.popoverMaxContentHeight` ile sınırlanır (ekran yüksekliğine göre,
en fazla 440pt). Sınırı aşan sayfa kendi içinde kayar, kırpılmaz; kısa sayfa da
boş alan bırakmaz.

Ölçüm `PageHeightKey` ile yapılır. Ölçüm henüz gelmediyse yükseklik sabitlenmez,
yalnızca tavan uygulanır — en kötü durumda doğal yüksekliğe düşer, kırpılmış bir
pencereye değil.

Popover'ın bu yüksekliğe uyması için `NSHostingController.sizingOptions` **şart**:
`[.preferredContentSize]` verilmezse popover sabit boyutta kalır ve içerik üst üste biner.

Ayarlar penceresi sekme şeridi yerine kenar çubuğu (`NavigationSplitView`) kullanır;
sekme sayısı arttıkça başlıklar kırpılmasın diye. Sekme şeridi sekiz bölüm için
828pt istiyordu, pencereye 660pt sığıyordu. Kenar çubuğu dört grupta toplanır:
**Uygulama** (Genel, Görünüm, Bildirimler), **Modüller**, **Araçlar** (İndirici, Portlar)
ve **Hakkında**.

> Detay sütununu `ScrollView`'a sarmayın: `Form` zaten kendi içinde kayar, iç içe
> kaydırma alan tıklamalarını ve metin girişini engelliyor.

> `ImageRenderer` `ScrollView`, `TabView` ve `NavigationSplitView` içeriğini çizmez;
> bu yüzden bu görünümleri ekran görüntüsüyle değil `NSHostingView.fittingSize` /
> `preferredContentSize` ile doğrulamak gerekir.

## Bugün panosu

Satırlar sade tutulur: ikon, başlık, değer, gerekirse tek satır açıklama.
**İlerleme çubuğu bilerek yok** — değerlerin kendisi zaten oranı söylüyor
("3 / 5 sayfa", "2/5", "1.4 / 3.0 L"), altına bir de çubuk koymak aynı bilgiyi
ikinci kez ve renkli biçimde tekrarlıyordu. Çubuklar modül sayfalarında duruyor;
orada tek bir şeye odaklanıldığı için yerleri var.


İlk sekme. Açık modüllerin panoya verdiği satırları toplar: derin çalışma, en boş kota,
dolu/okunamayan kotalar, sıradaki vakit, kılınan namaz + seri, su/protein. Satıra
tıklayınca ilgili sekmeye gider.

**Hangi satırların görüneceği tek tek seçilir** (Ayarlar > Görünüm > Bugün panosunda
göster). Modülü kapatmakla aynı şey değil: satır panodan kalkar ama modülün sekmesi,
ölçümü ve bildirimleri yerinde kalır. Gizlenen satır akşam gün özetinde de yer almaz —
"panoda istemiyorum" demek "akşam da okumak istemiyorum" demektir.

Ayarlardaki liste sabit değil, **görülen satırlardan** türetilir: satırlar koşullu
üretiliyor (dolu kota, sıradaki olay, bugünün dozu), yalnızca o an ekranda olanı
listeleseydik çoğu satırı gizleme şansı hiç doğmazdı. Bu yüzden bir kez görülen satır
`hilal.summaryCatalog` kaydında kalır; modül kapatılınca satırları listeden düşer.
Başlığı gün içinde değişen satırlar listede sabit adla durur ("Sıradaki vakit",
"Sonraki olay") — akşam "Akşam" yazan bir anahtarı kapatmış olmayasın.

- **Derin çalışma** kendiliğinden ölçülür: öndeki uygulama `focusApps` listesindeyse ve
  makine 2 dakikadır boşta değilse 30 saniyelik dilimler eklenir. Hiçbir girdi gerekmez.
- **Namaz takibi**: Namaz sekmesinde vakit girdikten sonra işaretlenir; pano gün içi
  sayıyı ve kesintisiz gün serisini gösterir. Seri, bugün henüz tamamlanmadıysa dünden
  geriye sayar — gün ortasında seriyi sıfır göstermek yanıltıcı olurdu. Bilgisayara
  geçilmeyen gün **Gün Sonu** sayfasından tamamlanır.
- **Su / protein** isteğe bağlı, tek dokunuşluk artırma düğmeleriyle.
- **Gün özeti** bildirimi (Ayarlar > Bildirimler) akşam seçtiğin saatte panoyu bildirir.
- **Gün sonu hatırlatması** (Ayarlar > Bildirimler, varsayılan 12:00, kapatılabilir)
  seçtiğin saatte gelir; tıklayınca Gün Sonu sayfası açılır ve kaçırılan işaretler
  oradan düzeltilir.

Günlük kayıtlar `~/Library/Application Support/Hal/daily.json` içinde, gün → metrik
sözlüğü olarak, 400 günlük geçmişle tutulur.

İkinci **Hafta** sayfası son yedi günün odak, antrenman, ibadet ve beslenme
özetini gösterir. Yeni veri toplamaz; aynı günlük kaydı okunabilir hâle getirir.

Üçüncü **Gün Sonu** sayfası son dört günün namaz, ilaç/takviye, dua ve antrenman
işaretlerini tek listede toplar. Kendi verisi yoktur; mevcut günlük kayda yazar.
Bilgisayara geçilmeyen gün burada tamamlanır. Dünden açık işaret varsa pano
satırı da oraya götürür; bugünün eksiği ancak akşam görünür. Pencere bilerek
kısadır — seriyi sonsuza dek geriye doldurmak ölçümü bozar.

## Modüller

Yedi pano modülü var: **Bugün**, **Odak**, **Kotalar**, **İbadet**
(Vakitler + Kur'an + Dua), **Takvim**, **Sağlık** ve **Ödemeler**. Bugün uygulamanın
merkezi olduğu için kapanmaz; diğerleri Ayarlar > Görünüm’den kapatılabilir. Kapanan
modül yalnızca gizlenmez, veri kaynağı ve bildirimleri de durur.
Dörtten fazla modül açıkken sekme şeridinde başlık yalnızca seçili sekmede kalır.

- **Odak**: çalışma uygulaması öndeyken derin çalışma süresini otomatik ölçer; günlük
  hedefi, şu anda sayılan uygulamayı, son yedi günü, haftalık toplamı ve en iyi günü gösterir.

  **Web sitesi / URL takibi bilerek yok.** Ölçüt yalnızca öndeki uygulamanın adına bakar;
  hiçbir izin istemez. Tarayıcıyı listeye eklemek YouTube'u da derin çalışma sayardı, yani
  ölçümün dürüstlüğünü bozardı. `localhost:3000` gibi adresleri ayırt etmenin iki yolu var,
  ikisi de bir bedelle geliyor: sekme URL'sini okumak taşıyıcı başına AppleScript
  (Automation) izni ister ve Firefox URL vermez; pencere başlığından okumak ise sayfa
  başlığını verir, URL'yi değil — bir Vite sunucusu "Vite + React" görünür, `localhost`
  hiç geçmez. İkisi de eklenmedi: uygulama izinsiz ölçüyor kalsın.

- **İbadet > Kur'an**: günlük sayfa hedefi, tek dokunuşluk artırma, 7 günlük çubuk
  grafik ve kesintisiz gün serisi.
- **İbadet > Dua**: günlük okunacakların listesi. Metin uygulamayla gelmez — listeyi
  sen tanımlarsın, uygulama yalnızca "bugün okundu mu" bilgisini tutar. Liste boşken
  sayfa görünmez.
- **Takvim**: bugünün kalan olayları ve panoda "sonraki olay". **İzin kendiliğinden
  istenmez** — yalnızca Ayarlar’daki ya da sayfadaki düğmeye bastığında sorulur.
  İzin yokken modül sessizce boş kalır, EventKit’e hiç istek gitmez.
- **Araçlar > Video indir**: `yt-dlp` sarmalayıcısı — kalıcı bir durum olmadığı için
  pano modülü değildir. Ayarlar > Araçlar > İndirici sayfasından indirilir; menü
  çubuğu ikonuna sağ tıklayıp Araçlar > Video indir ile de açılır. Bağlantı yapıştır,
  MP3/MP4 seç, klasör seç (seçmezsen masaüstü), indir.
  İlerleme canlı okunur, iptal edilebilir, hata yt-dlp'nin kendi mesajıdır.
  `yt-dlp` ya da `ffmpeg` yoksa kurulum komutunu gösterir; kurulumu yapmaz.
- **Araçlar > Açık portlar**: dinleyen TCP portları, hangi programın tuttuğu ve
  (yalnızca senin sürecinse) durdurma. Sistem ve başka kullanıcının süreçleri
  “sistem” diye durur, düğme yoktur. Durdurma önce sorar, SIGTERM gönderir; süreç
  dinlemeye devam ederse sonraki onay SIGKILL’dir. “Yalnızca benim süreçlerim”
  varsayılan açıktır. “Geliştirici” kapsülü varsayılan kapalıdır; açılınca yalnızca
  geliştirici sunucuları listelenir. Sağ tık menüsünden de açılır.

  **Kendi kendini onarır.** Günde bir kez, ilk indirmeden önce yt-dlp güncellenir.
  Ayrıca indirme *çıkarıcı* hatasıyla düşerse (`Unable to extract`, `nsig extraction
  failed`, `HTTP Error 403`) zorla güncelleyip bir kez daha dener — YouTube tarafı
  değiştiğinde takılıp kalmazsın. "Video unavailable" gibi gerçek hatalarda
  güncelleme denenmez, boşuna beklemezsin. Güncelleme yöntemi kuruluma göre
  seçilir: tek dosya derleme → `yt-dlp -U`, Homebrew → `brew upgrade`,
  Python betiği → `pipx upgrade` / `pip install -U`.
- **Sağlık**: Genel, Antrenman, İlaç & Takviye ve Beslenme sayfaları vardır. Su/protein artık
  yalnızca Bugün satırı değil, kendi hızlı giriş ve ilerleme sayfasına da sahiptir.
- **Sağlık > İlaç & Takviye**: her ilaç veya takviyeye birden çok doz saati verilir; her saat ayrı bir kayıt,
  yani sabah dozunu işaretlemek akşam dozunu işaretlemiş saymaz. Saati geçmiş ve
  işaretlenmemiş dozlar "geçti" olarak vurgulanır. Doz saatinde bildirim gönderilir,
  alınmış doz için gönderilmez.
- **Sağlık > Antrenman**: haftanın her gününe bir plan etiketi, tek dokunuşla "yapıldı",
  haftalık ilerleme ve kesintisiz antrenman serisi. Boş ya da "Dinlenme" yazan günler
  antrenman sayılmaz, seriyi de kırmaz. Set/tekrar/ağırlık kaydı bilerek yok: menü
  çubuğu penceresi bunun için dar ve her seti girmek sürdürülemez.
- **Ödemeler**: abonelik, fatura, taksit. Yenileme tarihi bir kez girilir, sonraki
  yenilemeler kayıt değiştirilmeden hesaplanır — uygulama günlerce kapalı kalsa da
  tarih doğru kalır. Yıllık ödemeler aylık toplama 12’ye bölünerek girer. Yenilemeden
  N gün önce sabah 09:00’da bildirim. Tek seferlik harcama takibi bilerek yok:
  Türkiye’de banka API’si olmadığı için elle girilen harcama kaydı sürdürülemez.


Popover sekmeleri ve menü çubuğu ikonları `Sources/Modules.swift` içindeki `ModuleKind`
kaydından türetilir; sabit liste yoktur. `today` kapatılamaz. İndirici bu kaydın
dışındadır: Ayarlar > Araçlar’da durur, sağ tık menüsünden de açılır.

Yeni modül eklemek için dokunulacak dört yer:

1. `Sources/Modules.swift` → `ModuleKind`’a bir `case` ve `title` / `symbol`
2. `AppStore.pages(for:)` → modülün sayfaları (`ModulePage`)
3. `AppStore.summaryLines(for:)` → panoya verdiği satırlar (`SummaryLine`)
4. `DetailPopoverView.body(for:)` → sayfanın görünümü
5. Modülün kendi veri kaynağı; bildirim istiyorsa `ModuleAlerts.swift` içinde `Alert` üretimi

Üçü de `switch` olduğu için bir `case` eklediğinde derleyici eksik kalanları söyler;
çalışma zamanında sessizce kaybolan modül olmaz. Pano tarafında ayrıca kod yazılmaz.

Seçim `DetailTarget(module:item:)` ile taşınır ve `"usage/claude"` biçiminde saklanır.
Eski kayıtlar (`"prayer"`, düz kota kimliği) hâlâ çözülür. Her modülün en son bakılan
sayfası ayrı hatırlanır; sekmeye dönünce oradan devam eder.

## Ne okur, ne istemez

Uygulama sandbox’lı değildir. Port listesi `lsof` kullanır, durdurma `kill` gönderir.

- Claude kotası: Keychain’deki “Claude Code-credentials”. Sohbet okunmaz.
- Codex kotası: `~/.codex/auth.json`. Oturum dizini ve sohbet gövdesi okunmaz.
- Grok kotası: `~/.grok/auth.json`. Erişim belirtecinin süresi dolmak üzereyse aynı dosyadaki yenileme belirteciyle sessizce uzatılır ve dosyaya geri yazılır. Sohbet okunmaz. Tarayıcı çerezi istenmez, Chrome Safe Storage sorulmaz, console.x.ai yönetim anahtarı istenmez.
- Namaz: konum seçilince `api.aladhan.com`. Konum izni kendiliğinden istenmez; şehir listeden seçilir.
- Takvim: izin, Ayarlar’daki ya da sayfadaki düğmeye basılınca istenir. İzin yokken EventKit’e gidilmez.
- Temizlik modunun kısayol kilidi: Erişilebilirlik ve Giriş İzleme, yalnızca Ayarlar’daki düğmeyle.
- Günlük kayıtlar `~/Library/Application Support/Hal/` altındadır. Eski `secrets.json` kota yolunun parçası değildir; kota bu dosyadan okunmaz.

## Çalıştırma

Depodan derlemek dağıtım yoludur. İmzalı bir DMG yoktur. İndirilen imzasız bir ikiliyi Gatekeeper açmaz; kaynak derlemesi çalışır.

```bash
./build.sh
open Hal.app
```

`Hal.app` ve `.build` derleme çıktısıdır, depoya girmez.

## İmza

`build.sh` anahtar zincirindeki ilk Apple Development / Developer ID sertifikasıyla imzalar
(`HILAL_SIGN_IDENTITY` ile değiştirilebilir). Sertifika yoksa ad-hoc imzalar (`codesign --sign -`).
Ad-hoc imzada her derleme yeni bir kod kimliği üretir; macOS anahtar zinciri iznini ve
Erişilebilirlik iznini her seferinde sıfırlar. Sabit bir geliştirici sertifikasıyla izinler bir kez verilir.

İmza kimliği ilk kez değiştiğinde macOS bir defalığına:
- anahtar zinciri erişimi sorar → **Her Zaman İzin Ver**
- Erişilebilirlik listesindeki eski kaydı geçersizleştirir → kaydı silip yeniden ekle

Tık: detay. Sağ tık: yenile, ayarlar, araçlar, modlar, çıkış.

Temizlik modunun kısayol kilidi için: Sistem Ayarları > Gizlilik ve Güvenlik > Erişilebilirlik ve Giriş İzleme.
