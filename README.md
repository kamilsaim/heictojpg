<p align="center">
  <img src="assets/icon.svg" width="120" height="120" alt="HEIC -> JPEG Donusturucu logosu">
</p>

# HEIC -> JPEG Donusturucu

iPhone'dan gelen `.HEIC` fotograflari `.jpg`'ye ceviren, kopya fotograflari ve
Live Photo videolarini duzenleyen bir Windows araci. Tek yapmaniz gereken
`.bat` dosyasini calistirmak; kurulum ya da komut satiri bilgisi gerekmez.

## Kullanim

1. `HEIC_Donustur.bat` dosyasini, icinde HEIC fotograflari olan klasore
   (veya bir ust klasore, alt klasorler de taranir) kopyalayin.
2. Cift tiklayip calistirin.
3. Sirasiyla sorulan sorulara `E` (evet) veya `H` (hayir) ile cevap verin.

> HEIC dosyalarini acabilmek icin Windows'ta **HEIF Image Extensions** ve
> **HEVC Video Extensions** eklentileri kurulu olmalidir. Kurulu degilse
> program bunlari Microsoft Store'dan kurmaniz icin otomatik olarak acar.

## Ne yapar?

Program, calistirildigi klasorde (alt klasorler dahil) sirasiyla:

1. **HEIC -> JPEG donusturur** — bulunan tum `.heic` dosyalarini `.jpg`
   olarak kaydeder, orijinal EXIF yonlendirmesini korur. Birden fazla
   dosyayi ayni anda (paralel) donusturerek hizlandirir.
2. **Donusturulen HEIC dosyalarini siler** (isterseniz) — basariyla
   donusturulen HEIC dosyalarini, onaylarsaniz siler.
3. **Eslesen Live Photo videolarini (.MOV) siler** (isterseniz) — silinen
   her HEIC ile ayni isimde bir `.mov` varsa, onu da silme secenegi sunar.
4. **AAE dosyalarini siler** (isterseniz) — iOS'un duzenleme/efekt bilgisi
   iceren `.aae` dosyalarini temizler.
5. **Ciftlenen (birebir ayni) resimleri tasir** (isterseniz) — icerigi
   (SHA-256 hash) birebir ayni olan fotograflari bulur, bir kopyasini
   yerinde birakip digerlerini `Ciftlenen_Resimler` klasorune tasir.
6. **Live Photo videolarini ayirir** (isterseniz) — bir fotografla ayni
   isimde eslesen `.mov` dosyalarini `LivePhoto_Videolari` klasorune tasir.
7. **Diger video dosyalarini ayirir** (isterseniz) — `.mp4`, `.mov`,
   `.avi`, `.mkv`, `.wmv`, `.m4v`, `.3gp` uzantili (Live Photo eslesmesi
   olmayan) video dosyalarini `Videolar` klasorune tasir.

Islem sonunda, ne yapildigina dair bir ozet `HEIC_Donustur_Log_*.txt`
dosyasina kaydedilir.

## Dosyalar

| Dosya | Aciklama |
|---|---|
| `HEIC_Donustur.bat` | Cift tiklayip calistirilacak baslangic dosyasi. |
| `HEIC_Donustur.ps1` | Asil islemi yapan PowerShell scripti. |

## Gereksinimler

- Windows 10/11
- Windows Store'dan **HEIF Image Extensions** ve **HEVC Video Extensions**
  eklentileri (program ilk calistirmada kontrol eder ve eksikse yonlendirir)

## Notlar

- Hicbir dosya internete gonderilmez; tum islemler bilgisayarinizda,
  yerel olarak yapilir.
- Silme ve tasima islemlerinin tumu opsiyoneldir; her adimda ayri ayri
  onay istenir.
