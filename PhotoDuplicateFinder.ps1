# Farkli cozunurlukte ayni fotograflari bulmak icin saf mantik fonksiyonlari.
# Bu dosya HEIC_Donustur.ps1 tarafindan dot-source edilir ve
# PhotoDuplicateFinder.Tests.ps1 ile Pester uzerinden test edilir.

# Get-DHash, Get-OrientationCorrectedBitmap ve Get-ImageFingerprint fonksiyonlari
# System.Drawing.Bitmap ve ilgili System.Drawing/System.Drawing.Imaging tiplerini
# kullanir. Bu assembly varsayilan olarak yuklu degildir; burada yuklemezsek bu
# dosya taze bir PowerShell surecinde dot-source edildiginde (ornegin
# HEIC_Donustur.ps1 uzerinden) "Cannot find type [System.Drawing.Bitmap]" hatasi
# alinir ve Get-ImageFingerprint bunu sessizce yutup $null donerek her goruntuyu
# "okunamadi" olarak isaretler.
Add-Type -AssemblyName System.Drawing

function Get-ImgKey {
    param([Parameter(Mandatory)][string]$FileName)
    # NOT: Turkce sistem kulturunde (tr-TR) 'i' ve 'I' harfleri varsayilan
    # buyuk/kucuk harf donusumunde birbirine esit degildir (dotless/dotted I
    # sorunu). Bu yuzden -match yerine CultureInvariant + IgnoreCase secenekli
    # .NET Regex kullaniyoruz, aksi halde "img_0021.jpg" gibi kucuk harfli
    # dosya adlari eslesmez.
    $regexOptions = [System.Text.RegularExpressions.RegexOptions]'IgnoreCase, CultureInvariant'
    $match = [System.Text.RegularExpressions.Regex]::Match($FileName, 'IMG_(\d{4,})', $regexOptions)
    if ($match.Success) {
        return "IMG_$($match.Groups[1].Value)"
    }
    return $null
}

function Get-HammingDistance {
    param([Parameter(Mandatory)][uint64]$A, [Parameter(Mandatory)][uint64]$B)
    $xor = $A -bxor $B
    $count = 0
    for ($i = 0; $i -lt 64; $i++) {
        if (($xor -band ([uint64]1 -shl $i)) -ne 0) { $count++ }
    }
    return $count
}

function Get-DHash {
    param([Parameter(Mandatory)][System.Drawing.Bitmap]$Bitmap)

    $small = New-Object System.Drawing.Bitmap($Bitmap, (New-Object System.Drawing.Size(9, 8)))
    try {
        $hash = [uint64]0
        $bit = 0
        for ($y = 0; $y -lt 8; $y++) {
            for ($x = 0; $x -lt 8; $x++) {
                $c1 = $small.GetPixel($x, $y)
                $c2 = $small.GetPixel($x + 1, $y)
                $g1 = 0.299 * $c1.R + 0.587 * $c1.G + 0.114 * $c1.B
                $g2 = 0.299 * $c2.R + 0.587 * $c2.G + 0.114 * $c2.B
                if ($g1 -gt $g2) { $hash = $hash -bor ([uint64]1 -shl $bit) }
                $bit++
            }
        }
        return $hash
    } finally {
        $small.Dispose()
    }
}

$script:ExifOrientationPropertyId = 0x0112

function Get-OrientationCorrectedBitmap {
    param([Parameter(Mandatory)][System.Drawing.Bitmap]$Bitmap)

    if ($Bitmap.PropertyIdList -contains $script:ExifOrientationPropertyId) {
        $prop = $Bitmap.GetPropertyItem($script:ExifOrientationPropertyId)
        $orientation = [int]$prop.Value[0]
        switch ($orientation) {
            2 { $Bitmap.RotateFlip([System.Drawing.RotateFlipType]::RotateNoneFlipX) }
            3 { $Bitmap.RotateFlip([System.Drawing.RotateFlipType]::Rotate180FlipNone) }
            4 { $Bitmap.RotateFlip([System.Drawing.RotateFlipType]::Rotate180FlipX) }
            5 { $Bitmap.RotateFlip([System.Drawing.RotateFlipType]::Rotate90FlipX) }
            6 { $Bitmap.RotateFlip([System.Drawing.RotateFlipType]::Rotate90FlipNone) }
            7 { $Bitmap.RotateFlip([System.Drawing.RotateFlipType]::Rotate270FlipX) }
            8 { $Bitmap.RotateFlip([System.Drawing.RotateFlipType]::Rotate270FlipNone) }
        }
    }
    return $Bitmap
}

function Get-ImageFingerprint {
    param([Parameter(Mandatory)][string]$Path)

    try {
        $bmp = New-Object System.Drawing.Bitmap($Path)
        try {
            $corrected = Get-OrientationCorrectedBitmap -Bitmap $bmp
            $hash = Get-DHash -Bitmap $corrected
            [PSCustomObject]@{
                Path     = $Path
                Hash     = $hash
                Width    = $corrected.Width
                Height   = $corrected.Height
                FileSize = (Get-Item -LiteralPath $Path).Length
            }
        }
        finally {
            $bmp.Dispose()
        }
    }
    catch {
        return $null
    }
}

function Resolve-DuplicateClusters {
    param(
        [Parameter(Mandatory)][object[]]$Fingerprints,
        [Parameter(Mandatory)][int]$Threshold
    )

    $n = $Fingerprints.Count
    $clusterIndex = New-Object 'int[]' $n
    for ($i = 0; $i -lt $n; $i++) { $clusterIndex[$i] = -1 }
    $nextClusterId = 0

    for ($i = 0; $i -lt $n; $i++) {
        for ($j = $i + 1; $j -lt $n; $j++) {
            $distance = Get-HammingDistance -A $Fingerprints[$i].Hash -B $Fingerprints[$j].Hash
            if ($distance -le $Threshold) {
                if ($clusterIndex[$i] -eq -1 -and $clusterIndex[$j] -eq -1) {
                    $clusterIndex[$i] = $nextClusterId
                    $clusterIndex[$j] = $nextClusterId
                    $nextClusterId++
                }
                elseif ($clusterIndex[$i] -ne -1 -and $clusterIndex[$j] -eq -1) {
                    $clusterIndex[$j] = $clusterIndex[$i]
                }
                elseif ($clusterIndex[$j] -ne -1 -and $clusterIndex[$i] -eq -1) {
                    $clusterIndex[$i] = $clusterIndex[$j]
                }
                else {
                    # her ikisi de zaten farkli kumelerde: j'nin kumesini i'ninkiyle birlestir
                    $targetId = $clusterIndex[$i]
                    $sourceId = $clusterIndex[$j]
                    for ($k = 0; $k -lt $n; $k++) {
                        if ($clusterIndex[$k] -eq $sourceId) { $clusterIndex[$k] = $targetId }
                    }
                }
            }
        }
    }

    $clusters = New-Object System.Collections.Generic.List[object]
    $seenClusterIds = @{}
    for ($id = 0; $id -lt $nextClusterId; $id++) {
        if ($seenClusterIds.ContainsKey($id)) { continue }
        $members = for ($k = 0; $k -lt $n; $k++) { if ($clusterIndex[$k] -eq $id) { $Fingerprints[$k] } }
        $members = @($members)
        if ($members.Count -ge 2) {
            $clusters.Add($members)
        }
        $seenClusterIds[$id] = $true
    }
    # Basindaki virgul, PowerShell'in disaridaki diziyi acip elemanlarini teker teker
    # dondurmesini engeller (elemanlarin kendisi de birer dizi oldugu icin bu kritik).
    # Bunu "@($clusters)" olarak sadelestirmeyin: PowerShell 5.1'de $clusters bir
    # List[object] ve elemanlari dizi oldugunda "@($clusters)" ArgumentException firlatiyor.
    # Yalniz "$clusters.ToArray()" da (virgulsuz) pipeline'da yine acilip bozulur.
    return , $clusters.ToArray()
}

function Select-DuplicateWinnerAndLosers {
    param([Parameter(Mandatory)][object[]]$Cluster)

    $sorted = @($Cluster | Sort-Object -Property @{Expression = { $_.Width * $_.Height }; Descending = $true }, @{Expression = { $_.FileSize }; Descending = $true })
    [PSCustomObject]@{
        Winner = $sorted[0]
        Losers = @($sorted | Select-Object -Skip 1)
    }
}
