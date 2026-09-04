# Başlangıç Menüsü Tasarımı

## Amaç

`HEIC_Donustur.ps1` şu anda 5 ana işlemi (HEIC->JPEG dönüştürme, AAE silme, çift resim taşıma, Live Photo video taşıma, diğer video taşıma) sırayla, her biri için ayrı bir Evet/Hayır sorusuyla çalıştırıyor. Kullanıcı yalnızca belirli işlemleri çalıştırmak istese bile tüm sorular sırayla karşısına çıkıyor. Bu tasarım, script başında hangi ana işlemlerin çalışacağını tek seferde seçtiren bir menü ekliyor.

## Kapsam

- Script başına (Windows eklenti kontrolünden sonra, HEIC arama başlamadan önce) bir seçim menüsü eklenir.
- Menü sadece **hangi ana adımların çalışacağını** belirler; her adımın kendi ince ayar soruları (silinsin mi, taşınsın mı gibi) olduğu gibi kalır ve sadece o adım seçiliyse sorulur.
- Dönüştürme mantığı, dosya işlemleri, loglama gibi diğer her şey değişmeden kalır.

## Menü Tasarımı

Gösterilecek metin:

```
Hangi islemleri yapmak istiyorsunuz? (birden fazlasini virgulle ayirarak secin, bos = hepsi)

  1) HEIC -> JPEG donustur
  2) AAE dosyalarini sil
  3) Ciftlenen (ayni icerikli) resimleri tasi
  4) Live Photo videolarini (.MOV) tasi
  5) Diger video dosyalarini tasi

Seciminiz (orn: 1,3,4) [Enter = hepsi]:
```

### Davranış

- Kullanıcı `1,3,4` gibi numaraları virgülle ayırarak girer.
- Boş bırakıp Enter'a basarsa **tüm 5 işlem** seçilmiş sayılır (mevcut davranışla birebir aynı — geriye dönük uyumlu varsayılan).
- Girilen değer boşluk/virgül temizlendikten sonra 1-5 aralığı dışında bir sayı içeriyorsa veya sayısal olmayan bir token varsa, hata mesajı gösterilip soru tekrar sorulur (geçerli bir giriş alınana kadar).
- Aynı numara birden fazla kez girilirse tekilleştirilir (basit hata toleransı, ekstra uyarı gerekmez).

### Seçimlerin scripte etkisi

Menüden 5 boole bayrak elde edilir:

- `$yapDonustur` (1)
- `$yapAaeSil` (2)
- `$yapCiftTasi` (3)
- `$yapLivePhotoTasi` (4)
- `$yapVideoTasi` (5)

Script içinde her ana bloğun en dışına bu bayrak eklenir:

- HEIC arama + dönüştürme bloğu (satır ~155-253) → `if ($yapDonustur) { ... }` içine alınır. Seçilmemişse bu blok, içindeki "silinsin mi" sorusu dahil, hiç çalışmaz.
- AAE silme bloğu (satır ~255-264) → mevcut `if ($silAae)` bloğunun dışına `$yapAaeSil` eklenir: `if ($yapAaeSil) { $silAae = Ask-YesNo ...; if ($silAae) { ... } }`. Yani "AAE silinsin mi?" sorusu sadece 2 seçiliyse sorulur.
- Çift resim taşıma bloğu (satır ~267-310) → `$tasiCift = Ask-YesNo ...` çağrısı `if ($yapCiftTasi)` içine alınır; seçilmemişse hem soru sorulmaz hem blok atlanır.
- Live Photo taşıma bloğu (satır ~325-349) → aynı şekilde `if ($yapLivePhotoTasi)` içine alınır.
- Diğer video taşıma bloğu (satır ~352-378) → aynı şekilde `if ($yapVideoTasi)` içine alınır.

Not: `$duplicatesFolder` ve `$livePhotoFolder` değişkenleri sonraki bloklarda (video taşımada hariç tutma filtresi için) kullanılıyor; bu değişkenler menüde ilgili adım seçilmese bile tanımlı kalmalı (yol string'i olarak), çünkü sonraki `Where-Object` filtreleri bu değişkenlere referans veriyor. Bu yüzden `$duplicatesFolder` ve `$livePhotoFolder` atamaları `if` bloklarının **dışında**, mevcut yerlerinde kalır — sadece içindeki asıl işlem mantığı `if ($yapCiftTasi)` / `if ($yapLivePhotoTasi)` ile sarmalanır.

## Hata Yönetimi

- Menü girişi ayrıştırılamazsa (regex ile 1-5 dışı sayı veya sayısal olmayan token tespit edilirse) sarı renkte "Lutfen 1-5 arasinda numaralari virgulle ayirarak girin (veya hepsi icin bos birakin)." mesajı gösterilip döngüyle tekrar sorulur.

## Test Planı

- Script `pwsh -File HEIC_Donustur.ps1` ile örnek bir test klasöründe manuel çalıştırılarak:
  - Boş Enter → tüm adımların çalıştığı (mevcut davranış) doğrulanır.
  - `1,3` gibi kısmi seçim → sadece dönüştürme ve çift resim taşıma adımlarının sorulduğu, AAE/Live Photo/video adımlarının hiç sorulmadığı doğrulanır.
  - Geçersiz giriş (`abc`, `9`) → hata mesajı ve tekrar sorma doğrulanır.
