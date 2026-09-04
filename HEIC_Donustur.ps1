$root = $PSScriptRoot
if (-not $root) { $root = Split-Path -Parent $MyInvocation.MyCommand.Path }

$logLines = New-Object System.Collections.Generic.List[string]
function Write-Log([string]$msg, [ConsoleColor]$color = 'Gray') {
    Write-Host $msg -ForegroundColor $color
    $logLines.Add($msg)
}

$Version = "1.0"

Write-Host ""
Write-Host "  __  __  ___ ____  ____   " -ForegroundColor Cyan
Write-Host " |  \/  ||_ _/ ___||  _ \  " -ForegroundColor Cyan
Write-Host " | |\/| | | | |    | |_) | " -ForegroundColor Cyan
Write-Host " | |  | | | | |___ |  _ <  " -ForegroundColor Cyan
Write-Host " |_|  |_||___\____||_| \_\ " -ForegroundColor Cyan
Write-Host "      HEIC  ->  JPG        " -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  _  __    _    __  __ ___ _     ____    _    ___ __  __ " -ForegroundColor DarkGray
Write-Host " | |/ /   / \  |  \/  |_ _| |   / ___|  / \  |_ _|  \/  |" -ForegroundColor DarkGray
Write-Host " | ' /   / _ \ | |\/| || || |   \___ \ / _ \  | || |\/| |" -ForegroundColor DarkGray
Write-Host " | . \  / ___ \| |  | || || |___ ___) / ___ \ | || |  | |" -ForegroundColor DarkGray
Write-Host " |_|\_\/_/   \_\_|  |_|___|_____|____/_/   \_\___|_|  |_|" -ForegroundColor DarkGray
Write-Host ""

Write-Log "=============================================" Cyan
Write-Log " HEIC -> JPEG Donusturucu  v$Version" Cyan
Write-Log " Klasor: $root" Cyan
Write-Log "=============================================" Cyan
Write-Log ""
Write-Log "Hakkinda: Bu arac HEIC fotograflari JPEG'e cevirir; ciftlenen" DarkGray
Write-Log "resimleri, AAE dosyalarini ve video/Live Photo dosyalarini" DarkGray
Write-Log "duzenlemenize yardimci olur. Her adim icin ayri onay istenir." DarkGray
Write-Log ""

# --- HEIF/HEVC codec kontrolu ---
$heifOk = [bool](Get-AppxPackage -Name "*HEIFImageExtension*")
$hevcOk = [bool](Get-AppxPackage -Name "*HEVCVideoExtension*")

if (-not ($heifOk -and $hevcOk)) {
    Write-Host "Bu bilgisayarda HEIC fotograflari acmak icin gereken Windows eklentileri kurulu degil." -ForegroundColor Yellow
    Write-Host "Microsoft Store acilacak, asagidaki eklentileri kurup bu programi tekrar calistirin:" -ForegroundColor Yellow
    Write-Host "  1) HEIF Image Extensions" -ForegroundColor Yellow
    Write-Host "  2) HEVC Video Extensions from Device Manufacturer (ucretsiz surum)" -ForegroundColor Yellow
    Write-Host ""
    if (-not $heifOk) { Start-Process "ms-windows-store://pdp/?ProductId=9PMMSR1CGPWG" }
    if (-not $hevcOk) { Start-Process "ms-windows-store://pdp/?ProductId=9N4WGH0Z6VHQ" }
    Read-Host "Eklentileri kurduktan sonra bu programi tekrar calistirin. Kapatmak icin Enter'a basin"
    exit
}

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

# --- WinRT (Windows Imaging) API hazirligi ---
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]
$null = [Windows.Storage.StorageFolder,Windows.Storage,ContentType=WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics.Imaging,ContentType=WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapEncoder,Windows.Graphics.Imaging,ContentType=WindowsRuntime]
$null = [Windows.Storage.Streams.IRandomAccessStream,Windows.Storage.Streams,ContentType=WindowsRuntime]

# Bu script blogu paralel donusturme icin her runspace'de ayri ayri calistirilir,
# bu yuzden WinRT hazirligi ve yardimci fonksiyonlar kendi icinde tekrar tanimlanir.
$ConvertScriptBlock = {
    param($srcPath, $destPath)

    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $null = [Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]
    $null = [Windows.Storage.StorageFolder,Windows.Storage,ContentType=WindowsRuntime]
    $null = [Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics.Imaging,ContentType=WindowsRuntime]
    $null = [Windows.Graphics.Imaging.BitmapEncoder,Windows.Graphics.Imaging,ContentType=WindowsRuntime]
    $null = [Windows.Storage.Streams.IRandomAccessStream,Windows.Storage.Streams,ContentType=WindowsRuntime]

    function Await($WinRtTask, $ResultType) {
        $asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
        $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
        $netTask = $asTask.Invoke($null, @($WinRtTask))
        $netTask.Wait(-1) | Out-Null
        $netTask.Result
    }
    function AwaitAction($WinRtAction) {
        $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' })[0]
        $netTask = $asTask.Invoke($null, @($WinRtAction))
        $netTask.Wait(-1) | Out-Null
    }

    function Convert-HeicToJpg([string]$srcPath, [string]$destPath) {
        $destDir  = Split-Path -Parent $destPath
        $destName = Split-Path -Leaf $destPath

        $file       = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($srcPath)) ([Windows.Storage.StorageFile])
        $srcStream  = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
        $decoder    = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($srcStream)) ([Windows.Graphics.Imaging.BitmapDecoder])

        $transform  = New-Object Windows.Graphics.Imaging.BitmapTransform
        $pixelData  = Await ($decoder.GetPixelDataAsync(
                        $decoder.BitmapPixelFormat,
                        $decoder.BitmapAlphaMode,
                        $transform,
                        [Windows.Graphics.Imaging.ExifOrientationMode]::RespectExifOrientation,
                        [Windows.Graphics.Imaging.ColorManagementMode]::DoNotColorManage
                      )) ([Windows.Graphics.Imaging.PixelDataProvider])

        $destFolder = Await ([Windows.Storage.StorageFolder]::GetFolderFromPathAsync($destDir)) ([Windows.Storage.StorageFolder])
        $destFile   = Await ($destFolder.CreateFileAsync($destName, [Windows.Storage.CreationCollisionOption]::ReplaceExisting)) ([Windows.Storage.StorageFile])
        $destStream = Await ($destFile.OpenAsync([Windows.Storage.FileAccessMode]::ReadWrite)) ([Windows.Storage.Streams.IRandomAccessStream])

        $encoder = Await ([Windows.Graphics.Imaging.BitmapEncoder]::CreateAsync([Windows.Graphics.Imaging.BitmapEncoder]::JpegEncoderId, $destStream)) ([Windows.Graphics.Imaging.BitmapEncoder])
        $bytes = $pixelData.DetachPixelData()
        $encoder.SetPixelData($decoder.BitmapPixelFormat, $decoder.BitmapAlphaMode, [uint32]$decoder.OrientedPixelWidth, [uint32]$decoder.OrientedPixelHeight, $decoder.DpiX, $decoder.DpiY, $bytes)
        AwaitAction ($encoder.FlushAsync())

        $destStream.Dispose()
        $srcStream.Dispose()
    }

    try {
        Convert-HeicToJpg -srcPath $srcPath -destPath $destPath
        [PSCustomObject]@{ Success = $true; Src = $srcPath; Dest = $destPath; Error = $null }
    }
    catch {
        [PSCustomObject]@{ Success = $false; Src = $srcPath; Dest = $destPath; Error = $_.Exception.Message }
    }
}

function Move-ToFolder([System.IO.FileInfo]$f, [string]$folder) {
    $hedefAd = $f.Name
    $hedefYol = Join-Path $folder $hedefAd
    $sayac = 1
    while (Test-Path -LiteralPath $hedefYol) {
        $hedefAd = "{0}_{1}{2}" -f [System.IO.Path]::GetFileNameWithoutExtension($f.Name), $sayac, $f.Extension
        $hedefYol = Join-Path $folder $hedefAd
        $sayac++
    }
    Move-Item -LiteralPath $f.FullName -Destination $hedefYol
}

function Ask-YesNo($soru) {
    while ($true) {
        $cevap = Read-Host "$soru (E/H)"
        if ($cevap -match '^[EeYy]') { return $true }
        if ($cevap -match '^[HhNn]') { return $false }
        Write-Host "Lutfen E ya da H yazin." -ForegroundColor Yellow
    }
}

# Bir foto/video dosyasinin ayni klasordeki esleşen Live Photo videosunu (.MOV) bulur.
function Get-PairedMov([System.IO.FileInfo]$imgFile) {
    $movPath = [System.IO.Path]::ChangeExtension($imgFile.FullName, ".mov")
    if (Test-Path -LiteralPath $movPath) { return Get-Item -LiteralPath $movPath }
    $movPathUpper = [System.IO.Path]::ChangeExtension($imgFile.FullName, ".MOV")
    if (Test-Path -LiteralPath $movPathUpper) { return Get-Item -LiteralPath $movPathUpper }
    return $null
}

$silAae = $false
if ($yapAaeSil) {
    $silAae = Ask-YesNo "AAE dosyalari (duzenleme/efekt bilgisi) silinsin mi?"
}

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

if ($silAae) {
    Write-Log ""
    $aaeFiles = Get-ChildItem -Path $root -Recurse -File -Include *.aae,*.AAE -ErrorAction SilentlyContinue
    if ($aaeFiles.Count -gt 0) {
        $aaeFiles | Remove-Item -Force
        Write-Log "$($aaeFiles.Count) adet AAE dosyasi silindi." Green
    } else {
        Write-Log "Silinecek AAE dosyasi bulunamadi." Yellow
    }
}

Write-Host ""
$tasiCift = Ask-YesNo "Ciftlenen (icerigi ayni olan) resimler 'Ciftlenen_Resimler' klasorune tasinsin mi?"
$duplicatesFolder = Join-Path $root "Ciftlenen_Resimler"
if ($tasiCift) {
    Write-Log ""
    Write-Log "Resimler karsilastiriliyor (icerik/hash bazli)..." Cyan

    $resimUzantilari = @("*.jpg", "*.jpeg", "*.png", "*.heic")
    $resimler = Get-ChildItem -Path $root -Recurse -File -Include $resimUzantilari -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notlike "$duplicatesFolder*" }

    $gruplar = $resimler | Group-Object -Property { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    $ciftGruplar = $gruplar | Where-Object { $_.Count -gt 1 }

    if ($ciftGruplar.Count -eq 0) {
        Write-Log "Ciftlenen resim bulunamadi." Yellow
    } else {
        if (-not (Test-Path -LiteralPath $duplicatesFolder)) {
            New-Item -ItemType Directory -Path $duplicatesFolder | Out-Null
        }

        $tasinan = 0
        $tasinanMov = 0
        foreach ($grup in $ciftGruplar) {
            # ilk dosya oldugu yerde kalir, digerleri tasinir
            $tutulacak = $grup.Group | Sort-Object FullName | Select-Object -First 1
            $tasinacaklar = $grup.Group | Where-Object { $_.FullName -ne $tutulacak.FullName }

            foreach ($f in $tasinacaklar) {
                $pairedMov = Get-PairedMov $f
                Move-ToFolder -f $f -folder $duplicatesFolder
                $tasinan++

                if ($pairedMov) {
                    Move-ToFolder -f $pairedMov -folder $duplicatesFolder
                    $tasinanMov++
                }
            }
        }
        Write-Log "$tasinan adet ciftlenen resim '$duplicatesFolder' klasorune tasindi." Green
        if ($tasinanMov -gt 0) {
            Write-Log "Bunlarla eslesen $tasinanMov adet Live Photo videosu (.MOV) da ayni klasore tasindi." Green
        }
    }
}

# Bir video dosyasinin ayni klasorde, ayni isimde eslesen bir fotografi (Live Photo kaynagi) var mi?
function Test-LivePhotoMov([System.IO.FileInfo]$movFile) {
    $imgUzantilari = @(".jpg", ".jpeg", ".png", ".heic")
    foreach ($ext in $imgUzantilari) {
        $imgPath = [System.IO.Path]::ChangeExtension($movFile.FullName, $ext)
        if (Test-Path -LiteralPath $imgPath) { return $true }
        $imgPathUpper = [System.IO.Path]::ChangeExtension($movFile.FullName, $ext.ToUpper())
        if (Test-Path -LiteralPath $imgPathUpper) { return $true }
    }
    return $false
}

Write-Host ""
$tasiLivePhoto = Ask-YesNo "Fotograflarla eslesen Live Photo videolari (.MOV) 'LivePhoto_Videolari' klasorune tasinsin mi?"
$livePhotoFolder = Join-Path $root "LivePhoto_Videolari"
$tasinanLivePhotoYollari = New-Object System.Collections.Generic.List[string]

if ($tasiLivePhoto) {
    Write-Log ""
    Write-Log "Live Photo videolari araniyor..." Cyan

    $movDosyalari = Get-ChildItem -Path $root -Recurse -File -Include *.mov,*.MOV -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -notlike "$duplicatesFolder*" -and $_.FullName -notlike "$livePhotoFolder*" }
    $livePhotoMovlari = @($movDosyalari | Where-Object { Test-LivePhotoMov $_ })

    if ($livePhotoMovlari.Count -eq 0) {
        Write-Log "Live Photo videosu bulunamadi." Yellow
    } else {
        if (-not (Test-Path -LiteralPath $livePhotoFolder)) {
            New-Item -ItemType Directory -Path $livePhotoFolder | Out-Null
        }
        foreach ($f in $livePhotoMovlari) {
            $tasinanLivePhotoYollari.Add($f.FullName)
            Move-ToFolder -f $f -folder $livePhotoFolder
        }
        Write-Log "$($livePhotoMovlari.Count) adet Live Photo videosu '$livePhotoFolder' klasorune tasindi." Green
    }
}

Write-Host ""
$tasiVideo = Ask-YesNo "Diger video dosyalari (.mp4, .mov, .avi, .mkv, .wmv, .m4v, .3gp) 'Videolar' klasorune tasinsin mi?"
if ($tasiVideo) {
    Write-Log ""
    Write-Log "Video dosyalari araniyor..." Cyan

    $videosFolder = Join-Path $root "Videolar"
    $videoUzantilari = @("*.mp4", "*.mov", "*.avi", "*.mkv", "*.wmv", "*.m4v", "*.3gp")
    $videoDosyalari = Get-ChildItem -Path $root -Recurse -File -Include $videoUzantilari -ErrorAction SilentlyContinue |
                      Where-Object {
                          $_.FullName -notlike "$duplicatesFolder*" -and
                          $_.FullName -notlike "$livePhotoFolder*" -and
                          $_.FullName -notlike "$videosFolder*" -and
                          $tasinanLivePhotoYollari -notcontains $_.FullName
                      }

    if ($videoDosyalari.Count -eq 0) {
        Write-Log "Tasinacak video dosyasi bulunamadi." Yellow
    } else {
        if (-not (Test-Path -LiteralPath $videosFolder)) {
            New-Item -ItemType Directory -Path $videosFolder | Out-Null
        }
        foreach ($f in $videoDosyalari) {
            Move-ToFolder -f $f -folder $videosFolder
        }
        Write-Log "$($videoDosyalari.Count) adet video dosyasi '$videosFolder' klasorune tasindi." Green
    }
}

Write-Log ""
$logPath = Join-Path $root ("HEIC_Donustur_Log_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".txt")
$logLines | Out-File -LiteralPath $logPath -Encoding UTF8
Write-Host "Islem ozeti kaydedildi: $logPath" -ForegroundColor Cyan

Write-Host ""
Write-Host "Islem tamamlandi." -ForegroundColor Cyan
Read-Host "Kapatmak icin Enter'a basin"
