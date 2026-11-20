# Ovis Fit · iPhone uygulaması

SwiftUI (iOS 17+) uygulaması ve analiz sunucusu (Node 22). Görsel referanslar `../Design/Ekranlar`.

```
Prototip/
├─ OvisFit.xcodeproj         Xcode projesi (scheme: OvisFit, paylaşılan)
├─ Config/Base.xcconfig      Bundle ID, sürüm, sunucu adresi; Local.xcconfig'i (git dışı) içe aktarır
├─ iOS/Core/                 Platformdan bağımsız mantık (enerji, plan, tabak, su, hareket, gelişim, kayıt)
├─ iOS/UI/                   SwiftUI ekranları
├─ iOS/Resources/            Assets (Ovi, örnek tabak, uygulama simgesi), foods.json, PrivacyInfo.xcprivacy
├─ Tests/OvisFitCoreTests/   Core birim testleri (swift test)
├─ Package.swift             Core'u test etmek için SwiftPM paketi (Xcode hedefi aynı dosyaları derler)
├─ server/                   Analiz sunucusu, testleri, Dockerfile
└─ scripts/                  simulator.sh, testflight.sh, ExportOptions-TestFlight.plist
```

## Tek komutla derleme ve teslim (Mac)

```bash
TEAM=<Team ID> ./scripts/xcode-build.sh            # testler + simülatör derlemesi + imzalı .ipa
TEAM=<Team ID> ./scripts/xcode-build.sh --upload   # ek olarak TestFlight'a yükler
```

Her adımın günlüğü `build/logs/` altına yazılır; hata olursa ilgili satırlar ekrana basılır.

## Hızlı başlangıç (Mac, Xcode 16+)

```bash
cd Prototip
node --test server/server.test.mjs        # sunucu + besin verisi testleri
swift test                                # Core birim testleri
ANTHROPIC_API_KEY=... ./scripts/dev-server.sh   # analiz sunucusu (Claude Haiku 5.5)
./scripts/simulator.sh                    # derle, iPhone simülatörüne kur, aç
./scripts/simulator.sh screenshots        # Bugün / Analiz / Su görüntüleri → screenshots/
```

Analiz için Anthropic API anahtarı gerekir (https://console.anthropic.com/settings/keys). Anahtar yalnızca sunucu sürecindedir; uygulamada veya xcconfig'de bulunmaz.

Simülatöre tabak fotoğrafı eklemek için fotoğrafı Simülatör penceresine sürükle.

### Başlatma argümanları (yalnızca geliştirme)

| Argüman | Etki |
| --- | --- |
| `-OvisResetData` | Gerçek günlüğü siler, ilk açılış akışını yeniden gösterir |
| `-OvisScreenshotData` | Tasarımdaki örnek değerlerle **ayrı, geçici** bir UserDefaults alanı kullanır. Gerçek günlüğe dokunmaz |
| `-OvisScreen today\|analysis\|water` | `-OvisScreenshotData` ile birlikte ilgili ekranı açar |

## Ekranlar

| Tasarım | Uygulama |
| --- | --- |
| 01 Bugün | İlk açılışta boş günlük. Ad, tarih, hedef, kayıtlı enerji (aralıkların orta noktası, "tahmini" notuyla), su, hareket ve sıradaki öğün gerçek veriden gelir. Halka = tahmini enerji / hedef. |
| 02 Profil | Yaş, boy, kilo, cinsiyet, aktivite ve isim girilir. Ondalık virgül, `cm`/`m`/`kg` birimleri ve alan bazlı hata iletileri desteklenir. Avatar üzerinden düzenlenir. |
| 03 Hedef | Kilo vermek / korumak / almak; öğün saatleri, ara öğün, beslenme tercihi, alerjiler, hareket kısıtları ve ekipman. Hesaplanan hedef gösterilir, profil onayla kaydedilir. |
| 04 Plan | Mifflin-St Jeor × aktivite katsayısı ± hedef farkı (alt sınır: dinlenme enerjisi ve 1.200 kcal). Tarifler hedefe göre ölçeklenir; gram, enerji ve makrolar birlikte değişir. Alerjen ve kaynak her öğünde görünür. ⓘ penceresi yöntemi ve varsayımları açıklar. Klinik plan için elle hedef girilebilir. |
| 05 Hareket | Süre (10/20/30 dk), ekipman ve kısıtlara göre seçenekler. Dinlenme her zaman var. Tamamlama günde bir kez işlenir. |
| 06 Fotoğraf | PhotosPicker, isteğe bağlı kamera (izin metni ve reddedilme durumu), önizleme, yeniden seçme, açık eylemle gönderim. Yükleniyor/iptal, çevrimdışı, servise erişilemiyor, servis yapılandırılmadı ve tabak tanınamadı durumları ele alınır. |
| 07 Analiz | Yemek adı, gram ve enerji aralığı. Gram ve ilave yağ değişince toplamlar yeniden hesaplanır. Silme (önizlemeli onay), yeniden seçme ve besin değeri bilinen öğeyi elle ekleme var. Öneriler alerji ve tercihlerden geçer: süt alerjisi veya vegan tercihte yoğurt önerilmez. Öneri önce önizlenir, kayıt tek onayla yapılır. Art arda Kaydet dokunuşu tek kayıt üretir. |
| 08 Planım değişti | Dışarıdayım / Evdeyim / Vaktim az için 2–3 uygun alternatif. Seçim yalnızca planı değiştirir; "Yedim" ayrı bir eylemdir. |
| 09 Su | Su ve diğer içecekler ayrı kaydedilir, hedef toplamla karşılaştırılır. 150/250/500 ml ve geri al. Başlangıç 1.750 ml (1,5–2 L aralığı), düzenlenebilir. Hekim kısıtlamasında hedef, kalan miktar ve teşvik kapanır. |
| 10 Ödem rehberi | Acil durum (112) ilk sırada. Kaynaklı statik içerik. Sıvı hedefini otomatik değiştirmez. |
| 11 Gelişim | Tarihli kilo kaydı. Haftalık eğri (Swift Charts), öğün ve hareket sayıları gerçek kayıtlardan üretilir. Kayıt yok ve tek ölçüm durumları ele alınır. |

## Veri ve taşıma

- Anahtarlar korunur: `of.meals.v1`, `of.drinks.v1`, `of.fluidTarget`, `of.clinicalFluidLimit`. Yeni anahtarlar: `of.profile.v1`, `of.weights.v1`, `of.activities.v1`, `of.planSwaps.v1`, `of.apiBaseURL`, `of.schemaVersion`.
- `Meal` kaydına isteğe bağlı `slot`, `source`, `title` alanları eklendi. Eski kayıtlar olduğu gibi okunur, yeni kayıtlar eski şemayla da çözümlenebilir.
- `Repository.migrate()` her açılışta çalışır ve tekrar çalıştırılabilir:
  - İlk çalışmada ham veriyi `*.backup` anahtarlarına bir kez kopyalar.
  - Bozuk tekil kayıtları atlar, sıfır gramlık porsiyonları ve boş öğünleri temizler, yinelenen kimlikleri tekilleştirir.
  - Sıvı hedefini aralığa sıkıştırır. Prototipteki `of.goal` değeri ilk profilde varsayılan hedef olur.
- İlk kullanımda hiçbir örnek veri gerçek günlüğe yazılmaz. Sunucunun demo modu yoktur; fotoğraf analizi her zaman gerçek Claude yanıtıdır (uygulama, eski sürümlerden kalmış "Demo" etiketli kayıtları yalnızca okuyup etiketli gösterir).

## Sunucu

| Ortam değişkeni | Varsayılan | Açıklama |
| --- | --- | --- |
| `ANTHROPIC_API_KEY` | — | Claude API anahtarı. Yoksa `/plate` 503 döner |
| `OVIS_MODEL` | `claude-haiku-5-5` | Model (varsayılan: en düşük maliyetli görsel Claude modeli) |
| `OVIS_LOG_USAGE=1` | kapalı | Her analizin token kullanımını konsola yazar (maliyet takibi) |
| `HOST` / `PORT` | `127.0.0.1` / `8787` | Dinleme adresi |
| `OVIS_RATE_PER_HOUR` | `30` | IP başına saatlik analiz sınırı (429) |
| `TRUST_PROXY=1` | kapalı | IP'yi `X-Forwarded-For`'dan al (ters vekil arkasında) |

`GET /health` çalışma modunu döner. Fotoğraf yalnızca bellekte işlenir, saklanmaz. Model: Claude Haiku 5.5 ($0,10 / $0,50 / milyon token), düşük efor ve yapılandırılmış JSON çıktı; bir tabak analizi yaklaşık $0,001 tutar.

## Xcode'dan iPhone'a kurulum (en hızlı yol)

1. Mac'te sunucuyu başlat: `ANTHROPIC_API_KEY=... ./scripts/dev-server.sh` (anahtarı `~/.ovisfit-key` dosyasına da kaydedebilirsin). Aynı Wi‑Fi'deki telefon `http://<mac-adı>.local:8787` adresine bağlanır.
2. iPhone'u kabloyla bağla, telefonda **Ayarlar › Gizlilik ve Güvenlik › Geliştirici Modu**'nu aç.
3. `OvisFit.xcodeproj`'u aç. **OvisFit** ve **OvisFitWidgets** hedeflerinin **Signing & Capabilities** bölümünde **Team** olarak ekibini seç. Bundle ID `com.ovis.fit` olarak gelir; otomatik imzalama HealthKit yetkisini App ID'ye kendisi ekler.
4. Üstteki cihaz listesinden iPhone'unu seçip **Run (⌘R)**.

Debug derlemesinde bir derleme adımı ("Geliştirme sunucusu adresi") Mac'in Bonjour adını uygulama paketindeki `DevServer.txt` dosyasına yazar. Telefon ilk bağlantıda **Yerel Ağ** izni ister. Debug sürümü yerel ağdaki http adreslerini kabul eder; Release/TestFlight sürümü yalnızca HTTPS kabul eder.

Aynı projeden **Product › Archive › Distribute App › App Store Connect** ile TestFlight'a da yükleyebilirsin. Bunun için Release sunucu adresini `Config/Local.xcconfig`'de vermen gerekir.

## Adım, yakılan enerji ve günlük denge

- **Apple Sağlık (HealthKit):** Uygulama adım sayısını ve aktif enerjiyi (iPhone ve Apple Watch) okur. Profil › Bağlantılar'dan açılırsa öğün enerjisi/makroları, su ve kilo Sağlık'a yazılır; silinen kayıtlar ve "Tüm verilerimi sil" Ovis Fit'in yazdığı örnekleri de siler. Veri cihazda kalır.
- **Sistem hedefleri** (`Targets.daily`): Adım ve hareketle yakılacak enerji hedefini aktivite düzeyi, hedef, yaş ve hareket kısıtlarından sistem belirler; kullanıcı girmez. Bugün ekranındaki ⓘ simgesi açıklamayı gösterir.
- **Yakılan enerji:** Dinlenme (Mifflin-St Jeor) + aktif enerji. Aktif enerji için Apple Sağlık değeri varsa o kullanılır. Yoksa adım × kilo × 0,0005 ve tamamlanan hareketin MET değeriyle tahmin edilir; yürüyüş adımlarda sayıldığı için iki kez eklenmez.
- **Tahmini kilo değişimi:** (alınan − yakılan) / 7.700 kcal. Gün sonu varsayımıyla hesaplanır ve "≈ 27 g verme yönünde" gibi gösterilir. Haftalık özette yalnızca öğün kaydı olan günler sayılır ve sonuç tartıdaki değişimle yan yana verilir.

## Ek özellikler

| Özellik | Nerede | Not |
| --- | --- | --- |
| Hatırlatmalar | Bugün kartı, Profil › Bağlantılar › Hatırlatmalar | Öğün saatleri profilden gelir. Su için 1/2/3 saatte bir, belirlenen saatler arasında. Tartı saati ayarlanabilir (varsayılan 21.00). Hekim sıvı kısıtlamasında su bildirimi gönderilmez. Bildirimler cihazda planlanır. |
| Barkod | Bugün › "Paketli ürün · barkod okut" | VisionKit DataScanner ile canlı tarama (A12+ cihaz; simülatörde numarayı elle yazarsın). Veri Open Food Facts'ten gelir, yalnızca barkod numarası gönderilir. Profildeki alerjenle çakışma uyarısı gösterilir; alerjen bilgisi yoksa bu da açıkça belirtilir. |
| Widget | Ana ekran (küçük, orta) ve kilit ekranı (yuvarlak, dikdörtgen, satır) | Kalan kalori, su, adım ve seri. Veri App Group (`group.$(OVIS_BUNDLE_ID)`) üzerinden paylaşılır; gece yarısı sayaçlar sıfırlanır. |
| Apple Sağlık'a yazma | Profil › Bağlantılar | İsteğe bağlı. Öğün enerjisi ve makroları, su ve kilo yazılır. Silinen veya geri alınan kayıtlar Sağlık'tan da silinir (dış kimlik meta verisiyle). |
| Favoriler ve tekrar | Bugün › Hızlı ekle; öğün kaydına basılı tut | "Dünkü kahvaltı/öğle…" tek dokunuşla eklenir. Art arda dokunuş kilitlidir. |
| Alışveriş listesi | Plan › Alışveriş listesi | 3 veya 7 günlük planın malzemeleri toplanır, yukarı yuvarlanır. İşaretler haftalık saklanır, liste paylaşılabilir. |
| Protein, lif, şeker | Bugün › Makro dengesi | Protein 1,0–1,4 g/kg, lif 14 g/1.000 kcal (en az 25 g), toplam şeker üst sınırı 2.000 kcal'de 90 g. Fotoğraf analizi artık makro tahmini de döndürür; makrosu bilinmeyen öğeler toplama katılmaz ve bu belirtilir. |
| Seriler ve rozetler | Bugün (seri), Gelişim › Seriler ve rozetler | Kayıt, su ve adım serileri; 8 rozet. Hepsi mevcut kayıtlardan hesaplanır, ayrıca saklanmaz. |

**İmza notu:** Widget hedefi ve App Group nedeniyle Bundle ID artık `OVIS_BUNDLE_ID` ile verilir (varsayılan `com.ovis.fit`). Xcode'da her iki hedef için de (OvisFit ve OvisFitWidgets) Team seçilmelidir. Otomatik imzalama App Group'u ve `com.ovis.fit.widgets` kimliğini kendisi oluşturur.

## Sunucuyu Hetzner'e kurma (Ovis CRM ile aynı sunucu)

Mac'te, `Prototip` klasöründe (CRM'i canlıya aldığın gibi SSH ile):
```bash
./scripts/deploy-hetzner.sh
```
Varsayılan sunucu `root@178.105.131.113`, adres `https://fit.178.105.131.113.nip.io`. Betik:
- `/opt/ovisfit` klasörüne, `ovisfit` kullanıcısıyla, `ovisfit` systemd servisi olarak kurar (127.0.0.1:8787).
- Nginx'e ayrı bir site dosyası ekler, `nginx -t` geçmezse geri alır; Let's Encrypt sertifikasını yalnızca bu adres için alır.
- CRM'e (`/opt/ovis-crm`, `ovis-crm` servisi, mevcut Nginx siteleri) dokunmaz; Docker kurmaz.
- İlk kurulumda Anthropic API anahtarını sorar (ekranda görünmez); anahtar yalnızca sunucuda `/opt/ovisfit/.env` içinde durur.
- Güncelleme için aynı komut; her güncellemede önceki sürüm `backups/` altına alınır.

Başka bir sunucu için: `./scripts/deploy-hetzner.sh root@IP alan.adi`. Docker kullanan boş bir sunucu için `deploy/hetzner/docker-compose.yml` (Caddy ile otomatik HTTPS) de hazır.

## Fiziksel iPhone ve TestFlight

1. **Sunucu:** `server/Dockerfile` ile HTTPS sağlayan bir platformda (TLS sonlandıran ters vekil arkasında) çalıştır. `ANTHROPIC_API_KEY` platformun gizli değişkeni olarak verilir. `curl https://<adres>/health` ile doğrula.
2. **App Store Connect:** Uygulamayı Bundle ID ile oluştur.
3. **Yerel ayar:** `cp Config/Local.xcconfig.example Config/Local.xcconfig`. İçine `DEVELOPMENT_TEAM`, `PRODUCT_BUNDLE_IDENTIFIER` ve `OVIS_API_BASE_URL = https:/$()/<adres>` yaz.
4. **Kimlik:** Xcode › Settings › Accounts'ta Apple ID oturumu aç ya da App Store Connect API anahtarını ver (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`).
5. **Yükleme:** `BUILD_NUMBER=1 ./scripts/testflight.sh`. Release arşivi oluşturulur, otomatik imzalanır ve App Store Connect'e yüklenir. Her yüklemede `BUILD_NUMBER` artmalı.
6. **TestFlight:**
   - Dahili testçiler (ekip üyeleri) işlemden hemen sonra kurabilir.
   - Harici testçiler için Beta App Review gerekir. Test bilgisi, iletişim e-postası ve gizlilik politikası adresi istenir.

Hazır olanlar:
- `ITSAppUsesNonExemptEncryption = NO` (yalnızca HTTPS kullanılıyor)
- HealthKit yetkisi (`iOS/OvisFit.entitlements`, okuma ve isteğe bağlı yazma), Sağlık okuma ve yazma izin metinleri
- `PrivacyInfo.xcprivacy`: UserDefaults gerekçesi CA92.1 ve analiz için gönderilen fotoğraf
- Kamera izin metni
- Yalnızca dikey yönlendirme, 1024 px uygulama simgesi

Release derlemesinde varsayılan sunucu adresi bilerek boştur. Ya `Local.xcconfig`'de HTTPS adresi verilir ya da testçi adresi Profil › Analiz sunucusu bölümünden girer.

## Kaynaklar

- [Mifflin-St Jeor, Am J Clin Nutr 1990](https://pubmed.ncbi.nlm.nih.gov/2305711/)
- [USDA FoodData Central](https://fdc.nal.usda.gov/)
- [Anthropic Claude API · Görsel ve yapılandırılmış çıktı](https://platform.claude.com/docs/)
- [NHS, sıvı tüketimi](https://www.nhs.uk/live-well/eat-well/food-guidelines-and-food-labels/water-drinks-nutrition/)
- [King’s College Hospital, sıvı miktarı](https://www.kch.nhs.uk/patients-and-visitors/patients/hydration-matters/)
- [NHS, ödem](https://www.nhs.uk/conditions/oedema/)
- [112 Acil Çağrı Merkezi](https://www.112.gov.tr/)
