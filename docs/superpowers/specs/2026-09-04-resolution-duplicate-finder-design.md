# Farklı Çözünürlükte Aynı Fotoğrafları Bulma — Tasarım

## Problem

`HEIC_Donustur.ps1` içindeki mevcut "Ciftlenen (ayni icerikli) resimleri tasi" adımı, dosyaları SHA256 içerik hash'ine göre karşılaştırıyor. Bu, byte-for-byte aynı dosyaları bulur ama aynı fotoğrafın farklı encode edilmiş kopyalarını (örn. HEIC'ten JPEG'e dönüştürülmüş bir kopya ile telefondan gelen orijinal JPEG) yakalamaz, çünkü yeniden encode işlemi byte'ları tamamen değiştirir.

Kullanıcının gerçek klasöründe (`FOTO` vs `heic`) doğrulandı: SHA256 karşılaştırması 0 eşleşme buldu, ama dosya adındaki `IMG_####` numarasına göre 500 dosyadan 480'i diğer klasörde aynı numaralı bir dosyayla eşleşti. Örnekler (`IMG_0019`, `IMG_0114`) aynı fotoğrafın döndürülmüş/yeniden sıkıştırılmış hali olduğunu doğruladı (genişlik/yükseklik yer değiştirmiş, dosya boyutu çok farklı). Ancak isim eşleşmesi tek başına güvenilir değil: `IMG_0055` örneğinde iki klasördeki dosyalar farklı en/boy oranına sahip tamamen farklı fotoğraflardı (iPhone'un dosya sayacı tekrar kullanılmış).

## Çözüm

Yeni bir menü seçeneği: **"Farkli cozunurlukte ayni fotograflari bul"**. İsim bazlı aday eşleştirme + görsel benzerlik doğrulaması kullanarak gerçek çiftleri bulur, düşük çözünürlüklü kopyayı ayrı bir klasöre taşır.

### Akış

1. `$root` altında, mevcut özel klasörler (`Ciftlenen_Resimler`, `LivePhoto_Videolari`, `Videolar`, yeni `Dusuk_Cozunurluklu_Kopyalar`) hariç tüm resimler (`*.jpg`, `*.jpeg`, `*.png`, `*.heic`) recursive taranır.
2. Dosya adından regex ile `IMG_(\d{4,})` deseni çıkarılır. Bu deseni taşımayan dosyalar bu özellik kapsamı dışında kalır (kapsam dışı bırakma bilinçli bir tercih — bkz. Alternatifler).
3. Aynı `IMG_####` anahtarını taşıyan dosyalar aday grup olarak toplanır. Tek elemanlı gruplar atlanır.
4. Her aday grup içindeki her dosya için:
   - `System.Drawing.Bitmap` ile açılır.
   - EXIF `Orientation` tag'i (PropertyId `0x0112`) okunur ve varsa görsele uygulanır (döndür/aynala) — böylece "aynı fotoğraf, farklı EXIF-baked durumu" senaryosunda yanlış negatif oluşmaz.
   - Yönü düzeltilmiş görsel 9x8 piksel gri tonlamaya küçültülür, komşu piksel parlaklık farklarından 64-bit'lik bir dHash (difference hash) hesaplanır.
   - Orijinal piksel genişlik/yükseklik (EXIF düzeltmesi sonrası) ve dosya boyutu (byte) da saklanır.
5. Grup içindeki dosyalar ikili (pairwise) karşılaştırılır — gruplar küçük olduğundan (tipik olarak 2, nadiren birkaç) bu ucuzdur. İki dosyanın dHash'i arasındaki Hamming mesafesi ≤ **6** (64 bit üzerinden, sabit eşik — kod içinde tek bir değişken, ileride ayarlanabilir) ise gerçek çift kabul edilir.
6. Doğrulanan çift/gruplarda:
   - Çözünürlük (genişlik × yükseklik) en yüksek olan dosya yerinde kalır.
   - Çözünürlük eşitse, dosya boyutu (byte) büyük olan tutulur.
   - Kalanlar mevcut `Move-ToFolder` fonksiyonu ile `Dusuk_Cozunurluklu_Kopyalar` klasörüne taşınır (isim çakışmasında otomatik `_1`, `_2` eklenir — mevcut davranış).
   - Taşınan her dosya için mevcut `Get-PairedMov` ile eşleşen Live Photo `.MOV`'u varsa o da aynı klasöre taşınır.
7. Menüye `6` numaralı seçenek olarak eklenir (`Ask-Menu` fonksiyonundaki `$secenekler` OrderedDictionary'sine, geçerli aralık kontrolü 1-6'ya güncellenir, boş girişte "hepsi" artık 1-6'yı kapsar).
8. Diğer adımlarla tutarlı olacak şekilde işlem öncesi `Ask-YesNo` ile onay istenir, sonuçlar `Write-Log` ile loglanır.

### Veri akışı / bileşenler

- `Get-ImgKey([string]$name)` — dosya adından `IMG_####` anahtarını çıkarır (regex, `$null` dönebilir).
- `Get-ExifCorrectedDHash([System.Drawing.Bitmap]$normalizedBmp)` — 9x8 gri tonlama + fark hash hesaplar, `[uint64]` döner.
- `Get-ImageFingerprint([System.IO.FileInfo]$f)` — dosyayı açar, EXIF orientation'ı uygular, hash + düzeltilmiş genişlik/yükseklik + dosya boyutunu içeren bir `PSCustomObject` döner. Hata durumunda (bozuk dosya, desteklenmeyen format) `$null` döner ve o dosya "hatalı" olarak loglanıp atlanır (script durmaz).
- `Get-HammingDistance([uint64]$a, [uint64]$b)` — XOR + bit sayımı.
- Ana akış bu yardımcı fonksiyonları kullanarak grupları işler; mevcut `Move-ToFolder` ve `Get-PairedMov` fonksiyonları aynen tekrar kullanılır.

### Hata yönetimi

- Bozuk/okunamayan görsel dosyaları: `try/catch` ile yakalanır, `Write-Log` ile "Atlandi (okunamadi): <dosya>" uyarısı verilir, işlem durmaz.
- Grup içinde 3+ dosya varsa (aynı IMG numarası 2'den fazla kez kullanılmışsa): her dosya diğerleriyle karşılaştırılır, birbirine Hamming eşiğinin altında olan dosyalar aynı "gerçek çift kümesi" sayılır (basit union: bir dosya zaten bir kümedeyse ve yeni dosyayla eşleşiyorsa aynı kümeye eklenir); her kümede en yüksek çözünürlüklü olan tutulur.

## Kapsam dışı (bilinçli olarak)

- `IMG_####` deseni taşımayan dosya adları arasındaki gerçek çiftler bu sürümde yakalanmaz (kullanıcı onayladı — performans/karmaşıklık dengesi).
- Doğrudan silme yok; sadece taşıma (mevcut dedupe deseniyle tutarlı, geri alınabilir).
- Eşik değeri (6) kullanıcı arayüzünden ayarlanabilir değil; kod içinde sabit bir değişken olarak tutulur.

## Alternatifler ve neden reddedildi

- **Tüm fotoğraflar arasında tam pairwise görsel karşılaştırma** (isim ön-filtresi olmadan): Kullanıcının gerçek kütüphanesinde (~4400 dosya) çok daha kapsamlı olurdu ama hash hesaplama + karşılaştırma süresi saatler mertebesinde olabilirdi. Kullanıcı hız/kapsam ödünleşiminde isim-bazlı ön filtreyi tercih etti.
- **Mevcut "Ciftlenen resimleri tasi" adımına entegre etmek**: Tek menü seçeneği daha az karmaşa sağlardı ama kesin (byte-identical) ve olasılıksal (görsel benzerlik) sonuçları aynı klasörde karıştırırdı. Kullanıcı ayrı bir menü seçeneği ve ayrı bir hedef klasör istedi, böylece güven seviyeleri net kalır.
