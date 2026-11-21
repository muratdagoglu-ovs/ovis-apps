# Ovis Fit · iPhone uygulamasını tamamla

## Bu sürümün teslim kontrolü

OvisFit klasöründe çalış. Prototip/OvisFit.xcodeproj içindeki mevcut uygulamayı Xcode ile bir iPhone simülatöründe derle. Güncel tasarım ve davranış için projedeki SwiftUI ekranlarını esas al. Aşağıdaki önceki ekran tarifleri ürünün geçmiş tasarım referansıdır.

Antrenman sekmesinde Salon ve Ev programlarını aç. Beş hareketin kapaklarını kontrol et. Her birinde detay ve aktif set ekranını açarak yerel MP4 dosyasının çevrimdışı oynadığını, duraklatılabildiğini ve hareket değişince doğru klibin geldiğini doğrula. Hareketi Azalt etkin olduğunda ilk açılışta sabit kapak gösterildiğini kontrol et. Kaynaklar Prototip/iOS/Resources/WorkoutMedia ve Assets.xcassets içindedir. Güncel görsel referans Design/Ovi_Antrenman_Onizleme.jpg dosyasındadır.

Ana ekran, Plan, Su ve Gelişim sekmelerini kontrol et. Gerekli derleme hatalarını gider. Build sonucunu, çalıştırdığın kontrolleri ve simülatör ekran görüntülerini paylaş.


Bu klasörü Mac üzerinde Claude Code ile aç. Görev, Prototip/OvisFit.xcodeproj projesini geliştirip fiziksel iPhone’a kurulabilecek bir SwiftUI uygulaması ve simülatörde doğrulanmış bir Debug derlemesi teslim etmektir. Sadece plan yazmakla kalma; kaynakları düzenle, test et, derle ve sonucu raporla.

## Önce açılacak dosyalar

- Design/Ekranlar içindeki 11 PNG, görsel referanstır (393 × 852 pt, @2x). Ana görsel kararlarında bunları kullan.
- Design/index.html tıklanabilir akış modelidir. Bir tarayıcıda yerel açılır. Alt menüden ekranları, avatardan profili aç. Örnekleri geçici bellekte tutar; sabit değerleri üretim verisine dönüştür.
- Design/Assets içinde özgün Ovi maskotundan hazırlanmış şeffaf PNG ve örnek yemek fotoğrafı vardır. Fotoğrafı yalnızca örnek veya o tarif için kullan. Gerçek analiz ekranına kullanıcının seçtiği görüntüyü getir.
- Prototip/README.md, iOS/ ve server/ mevcut çalışan mantığın başlangıcıdır. Xcode hedef üyeliğini ve projeye eklenen kaynakları güncelle.

## Ekranlar ve davranış

| Görsel | SwiftUI davranışı |
| --- | --- |
| 01 Bugün | İlk kullanıcının günlüğü boş açılır. Kullanıcı adı, bugün, günlük enerji hedefi, kaydedilmiş enerji, su, hareket ve sıradaki öğün doğru kaynaktan gelsin. Halka tüketilen tahmini enerjiyi hedefe böler. Aralıkları günlüğe sakla, özet kartında orta noktanın tahmin olduğunu belirt. |
| 02 Profil | İlk açılışta yaş, boy (cm), kilo (kg), cinsiyet, aktivite ve isim girilebilir. Ondalık virgülü, birimleri ve giriş hatalarını yönet. Profil daha sonra avatar üzerinden düzenlenebilir. |
| 03 Hedef | Kilo verme, koruma, alma. Öğün saatleri, beslenme tercihi, alerjiler ve hareket kısıtları düzenlenir. Kişinin onayladığı profil kaydedilir. |
| 04 Günlük plan | Yetişkin profilinden belgelenmiş bir yöntemle tahmini enerji ihtiyacı oluştur. Aktivite ve seçili hedefi hesaba kat. Miktar, öğün ve yemekler birlikte güncellensin. Gerçek tarif, porsiyon, besin değeri ve alerjen verisini kaynaklandır. Hedef yöntemini ve varsayımlarını pratik bir bilgi penceresinde açıkla. Uygun veri yoksa veya kişinin klinik bir planı varsa manuel hedefe izin ver. |
| 05 Hareket | Süreyi, ekipmanı, fiziksel kısıtları ve kullanıcının zamanını gözeten hareket veya dinlenme seçeneği sun. Tamamlama aynı günün etkinlik raporuna bir kez işlenir. |
| 06 Fotoğraf | PhotosPicker, isteğe bağlı kamera, doğru izin metni, önizleme, yeniden seçme, açık kullanıcı eylemiyle gönderim. Yükleniyor, iptal, çevrimdışı, servis erişilemiyor ve tabak tanınamadı durumlarını tasarla. |
| 07 Analiz | Backend’den gelen yemek adları, gram ve enerji aralığını göster. Yanlış tanıma için silme, yeniden seçme ve besin değeri bilinen öğeyi elle ekleme sağla. Gram veya ilave yağ güncellenince alt ve üst toplamları yeniden hesapla. Üretimde öneriyi kullanıcının alerjileri ve tercihlerinden geçir. Önemli örnek: süt alerjisi varsa yoğurt önerilmez. Ekleme/çıkarma önce önizlenir, kayıt tek onayla yapılır. |
| 08 Planım değişti | Ev, dışarı, az zaman bağlamına göre 2–3 alternatif sun. Önerileri tercihlere, alerjilere ve uygun porsiyonlara göre seç. Seçim planlanan öğünü değiştirir; tüketilmiş öğün kaydı ayrı bir eylemdir. |
| 09 Su | Su ve diğer içecekleri ayrı kaydet. Sıvı hedefini ikisinin toplamıyla karşılaştır. 150, 250, 500 ml ve geri al. Mevcut yetişkin başlangıç aralığı ve düzenleme seçeneği korunsun. Hekim sıvı kısıtlaması varsa otomatik hedef, kalan miktar ve tamamlama teşviki kapanır. |
| 10 Ödem rehberi | Prototipteki kaynaklı statik içeriği kullan. Acil belirtilere yönelik açıklama ekranda ilk sırada. Sıvı hedefini ödem bildirimiyle otomatik değiştirme. |
| 11 Gelişim | Tarihli kilo kaydı eklenebilsin. Gerçek kayıtlardan haftalık eğri, öğün ve hareket sayısı üretilsin. Hiç kayıt ve tek ölçüm durumunu ele al. |

## Tasarımın iOS karşılığı

- Zemin #F8F8F1, ana yazı #192F28, koyu yeşil #163E35, açık yeşil vurgu #DEEFA1, su kartı #DCEEF2, bölücü #DBE2D3. Ovi’nin orijinal renklerini koru.
- Sistem yazı tipi, büyük başlıklarda SF sistem serif italik vurgusu, sayılarda monospacedDigit. Tasarım kelime imidir: “Ovis Fit”. Ekranlarda gerçek iOS durum çubuğu, güvenli alanlar ve doğal geri hareketi kullanılsın.
- Ana sekmeler Bugün, Plan, Su, Gelişim. Tabağım ana ekranda belirgin eylem. Ödem rehberine Su sekmesinden erişilir. İkincil ekranlarda bağlama uygun geri dönüş.
- Ana yatay kenar 20 pt, bölümler arası 20–24 pt, kart köşeleri 16–22 pt, eylem 48–50 pt. Dokunma alanları en az 44 pt. Görseli SwiftUI içinde yeniden oluştur, ekran görüntüsünü arayüz yerine kullanma. Küçük ekranda metnin tamamı kaydırılarak okunabilsin. Dynamic Type ve VoiceOver’da iyileştir. Fotoğraf sonucu ve su hedefi sayısal metinle de ifade edilsin.
- Ekranlardaki örnek profil, değerler ve tarih temsili verilerdir. İlk kullanımda örnek veriyi gerçek günlüğe yazma. Önizleme aracı ile native uygulamanın veri saklama davranışını ayır.

## Teknik teslim

- Mevcut günlüklerin Codable formatını ve of.meals.v1 / of.drinks.v1 anahtarlarını dikkate al. Veri modelini değiştirirsen mevcut örnek günlükleri güvenli ve tekrar çalıştırılabilir biçimde taşı. Aynı öğünde art arda Kaydet dokunuşlarını engelle.
- API anahtarı yalnızca Node sunucusunda. Simülatör localhost, fiziksel iPhone ise yapılandırılabilir erişilebilir HTTPS adresi kullanır. Ayar örneği sağla. Gerçek fotoğrafı, kullanıcı onayından sonra ve yalnızca analiz için gönder. Yeni anahtar veya canlı servis yoksa demo yanıtını etiketleyip gerçek analizden ayır.
- Kendi hesap bilgileri gerektiren imza ve dağıtım dışında, yerelde yapılabilen geliştirme ve derlemeyi tamamla. İmzalı dağıtım veya mağazaya gönderim yapma.

## Derleme ve kabul

1. Uygun Mac’te Xcode, SDK ve mevcut simülatörleri tespit et. Proje ve scheme listesini xcodebuild -list ile doğrula. Bir iPhone simülatörünü açıp gerçek UDID’sini kullan.
2. node --test Prototip/server/server.test.mjs ile başla. Günlük hesap, porsiyon, hedef ve kayıt mantığına yönelik testleri ekle.
3. xcodebuild -project Prototip/OvisFit.xcodeproj -scheme OvisFit -configuration Debug -destination "platform=iOS Simulator,id=<UDID>" -derivedDataPath build build komutunu doğru scheme ve UDID ile çalıştır. Derleme hatalarını düzelt. Uygulamayı simctl install ve launch ile aç.
4. İlk profil → üç ayrı hedef → günlük plan kontrolü. Öğle alternatifi günlüğe kendiliğinden eklenmemeli. Fotoğrafta porsiyonu azaltınca toplam da azalsın; onay, iptal ve mükerrer dokunmayı sınayın. Su ekle, geri al, sıvı kısıtlaması, ödem rehberi, kilo kaydı ve yeniden açılışta kalıcılığı kontrol et. Kaynak anahtarı varsa ayrıca gerçek tabakla test et.
5. Ana ekran, analiz ve su ekranından gerçek simülatör görüntüsü alıp tasarım referanslarıyla karşılaştır. Tamamlanan ekranları, build sonucunu, testleri, üretilen .app konumunu ve fiziksel iPhone için gereken imza/sunucu ayarlarını bildir. Çalıştırılmamış kontrolleri açıkça belirt.
