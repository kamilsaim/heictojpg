# Başlangıç Menüsü Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `HEIC_Donustur.ps1` script başında, kullanıcının çalıştırmak istediği ana işlemleri (HEIC->JPEG dönüştür, AAE sil, çift resim taşı, Live Photo taşı, diğer video taşı) numaralı bir menüden tek seferde seçmesini sağlamak; seçilmeyen işlemler için hiçbir soru sorulmadan tamamen atlanmasını sağlamak.

**Architecture:** Script başına (Windows eklenti kontrolünden hemen sonra) bir `Ask-Menu` fonksiyonu eklenir; bu fonksiyon 5 boole bayrak (`$yapDonustur`, `$yapAaeSil`, `$yapCiftTasi`, `$yapLivePhotoTasi`, `$yapVideoTasi`) üretecek şekilde `$secilenler` dizisini döndürür. Script'in geri kalanındaki 5 ana blok, ilgili bayrakla sarmalanır — hem "yapılsın mı?" sorusu hem de işlemin kendisi bayrak false ise tamamen atlanır. Diğer her şey (dönüştürme mantığı, dosya taşıma, loglama) değişmeden kalır.

**Tech Stack:** Windows PowerShell 5.1 (tek dosyalık script, `HEIC_Donustur.ps1`). Otomatik test çerçevesi yok; her adımdan sonra `System.Management.Automation.Language.Parser` ile sözdizimi doğrulaması (parse-check) yapılır, son adımda manuel interaktif test yapılır.

**Referans spec:** `docs/superpowers/specs/2026-09-04-baslangic-menusu-design.md`

---

## Ortak Doğrulama Komutu

Her kod değişikliğinden sonra script'in hâlâ geçerli PowerShell sözdizimine sahip olduğunu doğrulamak için şu komut kullanılacak (hatasız ise `OK` yazdırır):

```powershell
powershell -NoProfile -Command "$errs = $null; [System.Management.Automation.Language.Parser]::ParseFile('C:\Users\ksaim\Desktop\heictojpeg\HEIC_Donustur.ps1', [ref]$null, [ref]$errs) | Out-Null; if ($errs.Count -gt 0) { $errs | ForEach-Object { $_.Message } } else { 'OK' }"
```

Bu plandaki her "parse-check" adımında bu komut çalıştırılacak ve çıktının `OK` olması beklenecek.

---

### Task 1: Menü fonksiyonunu ve seçim bayraklarını ekle

**Files:**
- Modify: `HEIC_Donustur.ps1:51-52` (codec kontrol bloğunun bitişi ile WinRT hazırlığının başlangıcı arası)

- [ ] **Step 1: Menü kodunu ekle**

`HEIC_Donustur.ps1` içinde satır 51-52 şu haldedir:

```powershell
    Read-Host "Eklentileri kurduktan sonra bu programi tekrar calistirin. Kapatmak icin Enter'a basin"
    exit
}

# --- WinRT (Windows Imaging) API hazirligi ---
```

Bu iki satır arasına (yani `}` ile `# --- WinRT (Windows Imaging) API hazirligi ---` satırı arasına) aşağıdaki bloğu ekleyin:

```powershell

# --- Islem secim menusu ---
function Ask-Menu {
    $secenekler = [ordered]@{
        1 = "HEIC -> JPEG donustur"
        2 = "AAE dosyalarini sil"
        3 = "Ciftlenen (ayni icerikli) resimleri tasi"
        4 = "Live Photo videolarini (.MOV) tasi"
        5 = "Diger video dosyalarini tasi"
    }

    while ($true) {
        Write-Host ""
        Write-Host "Hangi islemleri yapmak istiyorsunuz? (birden fazlasini virgulle ayirarak secin, bos = hepsi)" -ForegroundColor Cyan
        Write-Host ""
        foreach ($k in $secenekler.Keys) {
            Write-Host ("  {0}) {1}" -f $k, $secenekler[$k])
        }
        Write-Host ""
        $girdi = Read-Host "Seciminiz (orn: 1,3,4) [Enter = hepsi]"

        if ([string]::IsNullOrWhiteSpace($girdi)) {
            return @(1, 2, 3, 4, 5)
        }

        $tokenlar = $girdi -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        $sayilar = New-Object System.Collections.Generic.List[int]
        $gecerli = $true

        foreach ($t in $tokenlar) {
            $n = 0
            if (-not [int]::TryParse($t, [ref]$n) -or $n -lt 1 -or $n -gt 5) {
                $gecerli = $false
                break
            }
            if (-not $sayilar.Contains($n)) { $sayilar.Add($n) }
        }

        if ($gecerli -and $sayilar.Count -gt 0) {
            return $sayilar
        }

        Write-Host "Lutfen 1-5 arasinda numaralari virgulle ayirarak girin (veya hepsi icin bos birakin)." -ForegroundColor Yellow
    }
}

$secilenler = Ask-Menu
$yapDonustur      = $secilenler -contains 1
$yapAaeSil        = $secilenler -contains 2
$yapCiftTasi      = $secilenler -contains 3
$yapLivePhotoTasi = $secilenler -contains 4
$yapVideoTasi     = $secilenler -contains 5

```

- [ ] **Step 2: Parse-check çalıştır**

Ortak doğrulama komutunu çalıştırın (yukarıdaki "Ortak Doğrulama Komutu" bölümüne bakın).
Beklenen çıktı: `OK`

- [ ] **Step 3: Commit**

```bash
git add HEIC_Donustur.ps1
git commit -m "$(cat <<'EOF'
Add startup menu to select which operations to run

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01P1bapytphRsj7zgG9HfuqP
EOF
)"
```

---

### Task 2: AAE silme sorusunu `$yapAaeSil` ile sınırla

**Files:**
- Modify: `HEIC_Donustur.ps1` (Task 1 sonrası satır numaraları ~30 satır kayacaktır; aşağıdaki eski/yeni metinle arayın)

- [ ] **Step 1: `$silAae` atamasını guard'la**

Script içinde şu satırı bulun:

```powershell
$silAae = Ask-YesNo "AAE dosyalari (duzenleme/efekt bilgisi) silinsin mi?"
```

Bunu şununla değiştirin:

```powershell
$silAae = $false
if ($yapAaeSil) {
    $silAae = Ask-YesNo "AAE dosyalari (duzenleme/efekt bilgisi) silinsin mi?"
}
```

(Bu satırdan sonra gelen ve `if ($silAae) { ... }` ile AAE dosyalarını silen blok — script'in daha altında, `$tasiCift` sorusundan hemen önce yer alır — değişmeden kalır; zaten `$silAae` `$false` olduğunda otomatik atlanacaktır.)

- [ ] **Step 2: Parse-check çalıştır**

Ortak doğrulama komutunu çalıştırın. Beklenen çıktı: `OK`

- [ ] **Step 3: Commit**

```bash
git add HEIC_Donustur.ps1
git commit -m "$(cat <<'EOF'
Skip AAE deletion prompt when not selected in menu

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01P1bapytphRsj7zgG9HfuqP
EOF
)"
```

---

### Task 3: HEIC->JPEG dönüştürme bloğunu `$yapDonustur` ile sarmala

**Files:**
- Modify: `HEIC_Donustur.ps1` (dönüştürme bloğu — "HEIC dosyalari araniyor" log satırından, o bölümü kapatan `}` satırına kadar)

- [ ] **Step 1: Bloğu sarmala**

Script içinde, Task 2'de eklenen guard'dan hemen sonra başlayan şu bloğu bulun (bu blok `Write-Log ""` ile başlar ve `if ($toplam -eq 0) { ... } else { ... }` yapısının kapanış `}` parantezi ile biter):

```powershell
Write-Log ""
Write-Log "HEIC dosyalari araniyor (alt klasorler dahil)..." Cyan
$heicFiles = Get-ChildItem -Path $root -Recurse -File -Include *.heic,*.HEIC -ErrorAction SilentlyContinue
$toplam = $heicFiles.Count
Write-Log "$toplam adet HEIC dosyasi bulundu."
Write-Log ""

if ($toplam -eq 0) {
    Write-Log "Donusturulecek HEIC dosyasi yok." Yellow
} else {
    $donusturulecekler = New-Object System.Collections.Generic.List[object]
    foreach ($f in $heicFiles) {
        $hedef = [System.IO.Path]::ChangeExtension($f.FullName, ".jpg")
        if (Test-Path -LiteralPath $hedef) {
            Write-Log "Atlandi (zaten var): $($f.Name)" DarkYellow
        } else {
            $donusturulecekler.Add([PSCustomObject]@{ File = $f; Dest = $hedef })
        }
    }

    $basarili = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    $hatali   = 0

    if ($donusturulecekler.Count -gt 0) {
        $maxThrottle = [Math]::Max(1, [Math]::Min(4, [Environment]::ProcessorCount))
        Write-Log "$($donusturulecekler.Count) dosya donusturulecek. Es zamanli islem sayisi: $maxThrottle" Cyan

        $pool = [runspacefactory]::CreateRunspacePool(1, $maxThrottle)
        $pool.ApartmentState = 'STA'
        $pool.Open()

        $jobs = New-Object System.Collections.Generic.List[object]
        foreach ($item in $donusturulecekler) {
            $ps = [powershell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript($ConvertScriptBlock).AddArgument($item.File.FullName).AddArgument($item.Dest)
            $jobs.Add([PSCustomObject]@{ Pipe = $ps; Handle = $ps.BeginInvoke(); File = $item.File; Dest = $item.Dest })
        }

        $i = 0
        foreach ($job in $jobs) {
            $i++
            try {
                $result = $job.Pipe.EndInvoke($job.Handle)
                if ($result.Success) {
                    Write-Log "[$i/$($jobs.Count)] OK: $($job.File.Name) -> $(Split-Path -Leaf $job.Dest)" Green
                    $basarili.Add($job.File)
                } else {
                    $hatali++
                    Write-Log "[$i/$($jobs.Count)] HATA: $($job.File.Name) - $($result.Error)" Red
                }
            }
            catch {
                $hatali++
                Write-Log "[$i/$($jobs.Count)] HATA: $($job.File.Name) - $($_.Exception.Message)" Red
            }
            finally {
                $job.Pipe.Dispose()
            }
        }

        $pool.Close()
        $pool.Dispose()
    }

    Write-Log ""
    Write-Log "Donusturme tamamlandi. Basarili: $($basarili.Count)  Hatali: $hatali" Cyan

    if ($hatali -gt 0) {
        Write-Log "Not: Hatali dosyalar icin Windows'ta 'HEIF Image Extensions' ve 'HEVC Video Extensions' uygulamalarinin (Microsoft Store) kurulu oldugundan emin olun." Yellow
    }

    if ($basarili.Count -gt 0) {
        Write-Host ""
        $silHeic = Ask-YesNo "Basariyla donusturulen $($basarili.Count) adet HEIC dosyasi silinsin mi?"
        if ($silHeic) {
            foreach ($f in $basarili) {
                Remove-Item -LiteralPath $f.FullName -Force
            }
            Write-Log "$($basarili.Count) adet HEIC dosyasi silindi." Green

            $pairedMovs = @($basarili | ForEach-Object { Get-PairedMov $_ } | Where-Object { $_ })
            if ($pairedMovs.Count -gt 0) {
                Write-Host ""
                $silMov = Ask-YesNo "Silinen HEIC dosyalarina ait $($pairedMovs.Count) adet Live Photo videosu (.MOV) bulundu. Bunlar da silinsin mi?"
                if ($silMov) {
                    $pairedMovs | Remove-Item -Force
                    Write-Log "$($pairedMovs.Count) adet MOV dosyasi silindi." Green
                } else {
                    Write-Log "MOV dosyalari silinmedi." Yellow
                }
            }
        } else {
            Write-Log "HEIC dosyalari silinmedi." Yellow
        }
    }
}
```

Bu bloğun tamamını, her satırı 4 boşluk içeri kaydırılmış hâliyle `if ($yapDonustur) { ... }` içine alacak şekilde değiştirin:

```powershell
if ($yapDonustur) {
    Write-Log ""
    Write-Log "HEIC dosyalari araniyor (alt klasorler dahil)..." Cyan
    $heicFiles = Get-ChildItem -Path $root -Recurse -File -Include *.heic,*.HEIC -ErrorAction SilentlyContinue
    $toplam = $heicFiles.Count
    Write-Log "$toplam adet HEIC dosyasi bulundu."
    Write-Log ""

    if ($toplam -eq 0) {
        Write-Log "Donusturulecek HEIC dosyasi yok." Yellow
    } else {
        $donusturulecekler = New-Object System.Collections.Generic.List[object]
        foreach ($f in $heicFiles) {
            $hedef = [System.IO.Path]::ChangeExtension($f.FullName, ".jpg")
            if (Test-Path -LiteralPath $hedef) {
                Write-Log "Atlandi (zaten var): $($f.Name)" DarkYellow
            } else {
                $donusturulecekler.Add([PSCustomObject]@{ File = $f; Dest = $hedef })
            }
        }

        $basarili = New-Object System.Collections.Generic.List[System.IO.FileInfo]
        $hatali   = 0

        if ($donusturulecekler.Count -gt 0) {
            $maxThrottle = [Math]::Max(1, [Math]::Min(4, [Environment]::ProcessorCount))
            Write-Log "$($donusturulecekler.Count) dosya donusturulecek. Es zamanli islem sayisi: $maxThrottle" Cyan

            $pool = [runspacefactory]::CreateRunspacePool(1, $maxThrottle)
            $pool.ApartmentState = 'STA'
            $pool.Open()

            $jobs = New-Object System.Collections.Generic.List[object]
            foreach ($item in $donusturulecekler) {
                $ps = [powershell]::Create()
                $ps.RunspacePool = $pool
                [void]$ps.AddScript($ConvertScriptBlock).AddArgument($item.File.FullName).AddArgument($item.Dest)
                $jobs.Add([PSCustomObject]@{ Pipe = $ps; Handle = $ps.BeginInvoke(); File = $item.File; Dest = $item.Dest })
            }

            $i = 0
            foreach ($job in $jobs) {
                $i++
                try {
                    $result = $job.Pipe.EndInvoke($job.Handle)
                    if ($result.Success) {
                        Write-Log "[$i/$($jobs.Count)] OK: $($job.File.Name) -> $(Split-Path -Leaf $job.Dest)" Green
                        $basarili.Add($job.File)
                    } else {
                        $hatali++
                        Write-Log "[$i/$($jobs.Count)] HATA: $($job.File.Name) - $($result.Error)" Red
                    }
                }
                catch {
                    $hatali++
                    Write-Log "[$i/$($jobs.Count)] HATA: $($job.File.Name) - $($_.Exception.Message)" Red
                }
                finally {
                    $job.Pipe.Dispose()
                }
            }

            $pool.Close()
            $pool.Dispose()
        }

        Write-Log ""
        Write-Log "Donusturme tamamlandi. Basarili: $($basarili.Count)  Hatali: $hatali" Cyan

        if ($hatali -gt 0) {
            Write-Log "Not: Hatali dosyalar icin Windows'ta 'HEIF Image Extensions' ve 'HEVC Video Extensions' uygulamalarinin (Microsoft Store) kurulu oldugundan emin olun." Yellow
        }

        if ($basarili.Count -gt 0) {
            Write-Host ""
            $silHeic = Ask-YesNo "Basariyla donusturulen $($basarili.Count) adet HEIC dosyasi silinsin mi?"
            if ($silHeic) {
                foreach ($f in $basarili) {
                    Remove-Item -LiteralPath $f.FullName -Force
                }
                Write-Log "$($basarili.Count) adet HEIC dosyasi silindi." Green

                $pairedMovs = @($basarili | ForEach-Object { Get-PairedMov $_ } | Where-Object { $_ })
                if ($pairedMovs.Count -gt 0) {
                    Write-Host ""
                    $silMov = Ask-YesNo "Silinen HEIC dosyalarina ait $($pairedMovs.Count) adet Live Photo videosu (.MOV) bulundu. Bunlar da silinsin mi?"
                    if ($silMov) {
                        $pairedMovs | Remove-Item -Force
                        Write-Log "$($pairedMovs.Count) adet MOV dosyasi silindi." Green
                    } else {
                        Write-Log "MOV dosyalari silinmedi." Yellow
                    }
                }
            } else {
                Write-Log "HEIC dosyalari silinmedi." Yellow
            }
        }
    }
}
```

- [ ] **Step 2: Parse-check çalıştır**

Ortak doğrulama komutunu çalıştırın. Beklenen çıktı: `OK`

- [ ] **Step 3: Commit**

```bash
git add HEIC_Donustur.ps1
git commit -m "$(cat <<'EOF'
Skip HEIC to JPEG conversion when not selected in menu

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01P1bapytphRsj7zgG9HfuqP
EOF
)"
```

---

### Task 4: Çift resim taşıma bloğunu `$yapCiftTasi` ile sarmala

**Files:**
- Modify: `HEIC_Donustur.ps1` (çift resim taşıma bölümü)

- [ ] **Step 1: Bloğu guard'la**

Şu bloğu bulun:

```powershell
Write-Host ""
$tasiCift = Ask-YesNo "Ciftlenen (icerigi ayni olan) resimler 'Ciftlenen_Resimler' klasorune tasinsin mi?"
$duplicatesFolder = Join-Path $root "Ciftlenen_Resimler"
if ($tasiCift) {
```

Bunu şununla değiştirin (yalnızca bu ilk 4 satır; `if ($tasiCift) {` sonrası ve kapanış `}` değişmeden kalır):

```powershell
Write-Host ""
$duplicatesFolder = Join-Path $root "Ciftlenen_Resimler"
$tasiCift = $false
if ($yapCiftTasi) {
    $tasiCift = Ask-YesNo "Ciftlenen (icerigi ayni olan) resimler 'Ciftlenen_Resimler' klasorune tasinsin mi?"
}
if ($tasiCift) {
```

(`$duplicatesFolder` değişkeninin script'in geri kalanında — özellikle video taşıma bölümündeki filtrelerde — kullanıldığını, bu yüzden `if ($yapCiftTasi)` bloğunun dışında, koşulsuz atandığını unutmayın.)

- [ ] **Step 2: Parse-check çalıştır**

Ortak doğrulama komutunu çalıştırın. Beklenen çıktı: `OK`

- [ ] **Step 3: Commit**

```bash
git add HEIC_Donustur.ps1
git commit -m "$(cat <<'EOF'
Skip duplicate photo move when not selected in menu

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01P1bapytphRsj7zgG9HfuqP
EOF
)"
```

---

### Task 5: Live Photo video taşıma bloğunu `$yapLivePhotoTasi` ile sarmala

**Files:**
- Modify: `HEIC_Donustur.ps1` (Live Photo taşıma bölümü)

- [ ] **Step 1: Bloğu guard'la**

Şu bloğu bulun:

```powershell
Write-Host ""
$tasiLivePhoto = Ask-YesNo "Fotograflarla eslesen Live Photo videolari (.MOV) 'LivePhoto_Videolari' klasorune tasinsin mi?"
$livePhotoFolder = Join-Path $root "LivePhoto_Videolari"
$tasinanLivePhotoYollari = New-Object System.Collections.Generic.List[string]

if ($tasiLivePhoto) {
```

Bunu şununla değiştirin:

```powershell
Write-Host ""
$livePhotoFolder = Join-Path $root "LivePhoto_Videolari"
$tasinanLivePhotoYollari = New-Object System.Collections.Generic.List[string]
$tasiLivePhoto = $false
if ($yapLivePhotoTasi) {
    $tasiLivePhoto = Ask-YesNo "Fotograflarla eslesen Live Photo videolari (.MOV) 'LivePhoto_Videolari' klasorune tasinsin mi?"
}

if ($tasiLivePhoto) {
```

(`$livePhotoFolder` ve `$tasinanLivePhotoYollari` değişkenleri sonraki video taşıma bölümünde koşulsuz kullanıldığı için `if ($yapLivePhotoTasi)` bloğunun dışında kalır.)

- [ ] **Step 2: Parse-check çalıştır**

Ortak doğrulama komutunu çalıştırın. Beklenen çıktı: `OK`

- [ ] **Step 3: Commit**

```bash
git add HEIC_Donustur.ps1
git commit -m "$(cat <<'EOF'
Skip Live Photo video move when not selected in menu

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01P1bapytphRsj7zgG9HfuqP
EOF
)"
```

---

### Task 6: Diğer video taşıma bloğunu `$yapVideoTasi` ile sarmala

**Files:**
- Modify: `HEIC_Donustur.ps1` (diğer video taşıma bölümü)

- [ ] **Step 1: Bloğu guard'la**

Şu bloğu bulun:

```powershell
Write-Host ""
$tasiVideo = Ask-YesNo "Diger video dosyalari (.mp4, .mov, .avi, .mkv, .wmv, .m4v, .3gp) 'Videolar' klasorune tasinsin mi?"
if ($tasiVideo) {
```

Bunu şununla değiştirin:

```powershell
Write-Host ""
$tasiVideo = $false
if ($yapVideoTasi) {
    $tasiVideo = Ask-YesNo "Diger video dosyalari (.mp4, .mov, .avi, .mkv, .wmv, .m4v, .3gp) 'Videolar' klasorune tasinsin mi?"
}
if ($tasiVideo) {
```

- [ ] **Step 2: Parse-check çalıştır**

Ortak doğrulama komutunu çalıştırın. Beklenen çıktı: `OK`

- [ ] **Step 3: Commit**

```bash
git add HEIC_Donustur.ps1
git commit -m "$(cat <<'EOF'
Skip other video move when not selected in menu

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01P1bapytphRsj7zgG9HfuqP
EOF
)"
```

---

### Task 7: Manuel uçtan uca test

**Files:**
- No file changes — verification only.

- [ ] **Step 1: Test klasörü hazırla**

Boş bir test klasörü oluşturun ve içine birkaç örnek dosya koyun (gerçek `.heic`/`.mov`/`.aae` dosyanız yoksa boş placeholder dosyalar yeterli, script'in menü/atlama davranışını görmek için):

```powershell
New-Item -ItemType Directory -Force -Path "$env:TEMP\heic_test" | Out-Null
Set-Content -Path "$env:TEMP\heic_test\ornek.aae" -Value "test"
```

- [ ] **Step 2: Boş Enter senaryosu (hepsi seçili)**

```powershell
& "C:\Users\ksaim\Desktop\heictojpeg\HEIC_Donustur.ps1"
```

Script'i `$env:TEMP\heic_test` klasörüne kopyalayıp oradan çalıştırın (script kendi bulunduğu klasörü tarar). Menüde Enter'a basın.
Beklenen: Tüm 5 sorunun (AAE, çift resim, Live Photo, video) sırayla sorulduğu, mevcut (değişiklik öncesi) davranışla aynı akış.

- [ ] **Step 3: Kısmi seçim senaryosu**

Script'i tekrar çalıştırın, menüde `2` girin (sadece AAE sil).
Beklenen: AAE silme sorusu sorulur ve `ornek.aae` silinir; HEIC dönüştürme, çift resim, Live Photo, video taşıma adımlarına ait HİÇBİR soru sorulmadan script sona erer.

- [ ] **Step 4: Geçersiz giriş senaryosu**

Script'i tekrar çalıştırın, menüde `abc` girin.
Beklenen: Sarı "Lutfen 1-5 arasinda..." uyarısı gösterilir ve menü tekrar sorulur. Ardından `9` girin — yine aynı uyarı ile tekrar sorulmalı. Son olarak `1` girip devam edin, dönüştürme adımının çalıştığını doğrulayın.

- [ ] **Step 5: Test klasörünü temizle**

```powershell
Remove-Item -Recurse -Force "$env:TEMP\heic_test"
```

- [ ] **Step 6: Sonucu not al**

Bu adımda kod değişikliği yok; bu görevin amacı doğrulamadır. Test sırasında beklenmeyen bir davranış görülürse ilgili Task'a dönüp düzeltme yapılmalı ve yeniden test edilmelidir.
