# Tek dosya HEIC_Donustur.exe derleme scripti (ek arac/SDK gerektirmez, Windows csc.exe kullanir).
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
if (-not $root) { $root = Split-Path -Parent $MyInvocation.MyCommand.Path }

$psMain = Join-Path $root "HEIC_Donustur.ps1"
$psDup  = Join-Path $root "PhotoDuplicateFinder.ps1"
$csFile = Join-Path $root "Launcher.cs"
$icoPath = Join-Path $root "assets\icon.ico"
$outExe  = Join-Path $root "HEIC_Donustur.exe"

# assets/icon.svg tasarimini birebir yansitan coklu-cozunurluklu .ico uret
function New-AppIcon([string]$Path) {
    Add-Type -AssemblyName System.Drawing

    function New-RoundedRectPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
        $p = New-Object System.Drawing.Drawing2D.GraphicsPath
        $d = $r * 2
        $p.AddArc($x, $y, $d, $d, 180, 90)
        $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
        $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
        $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
        $p.CloseFigure()
        return $p
    }

    function Render-IconBitmap([int]$size) {
        $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $g.Clear([System.Drawing.Color]::Transparent)

        $s = $size / 512.0
        $g.ScaleTransform([float]$s, [float]$s)

        # Arka plan (mavi -> camgobegi gradyan)
        $bgPath = New-RoundedRectPath 28 28 456 456 108
        $bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            (New-Object System.Drawing.PointF(70, 55)),
            (New-Object System.Drawing.PointF(445, 460)),
            [System.Drawing.Color]::FromArgb(255, 0x25, 0x63, 0xEB),
            [System.Drawing.Color]::FromArgb(255, 0x06, 0xB6, 0xD4)
        )
        $g.FillPath($bgBrush, $bgPath)

        # HEIC karti
        $cardPath = New-RoundedRectPath 104 112 210 250 30
        $g.FillPath([System.Drawing.Brushes]::White, $cardPath)

        # Gokyuzu, gunes, daglar
        $skyPath = New-RoundedRectPath 128 140 162 112 18
        $skyBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 0xE0, 0xF2, 0xFE))
        $g.FillPath($skyBrush, $skyPath)

        $sunBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 0xFB, 0xBF, 0x24))
        $g.FillEllipse($sunBrush, 150, 158, 32, 32)

        $mtnBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 0x22, 0xC5, 0x5E))
        $mtnPts = [System.Drawing.PointF[]]@(
            (New-Object System.Drawing.PointF(140, 232)),
            (New-Object System.Drawing.PointF(184, 190)),
            (New-Object System.Drawing.PointF(216, 218)),
            (New-Object System.Drawing.PointF(244, 190)),
            (New-Object System.Drawing.PointF(280, 232))
        )
        $g.FillPolygon($mtnBrush, $mtnPts)

        # HEIC etiketi
        $heicTagPath = New-RoundedRectPath 128 282 108 42 14
        $heicTagBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 0xDB, 0xEA, 0xFE))
        $g.FillPath($heicTagBrush, $heicTagPath)

        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = [System.Drawing.StringAlignment]::Center
        $sf.LineAlignment = [System.Drawing.StringAlignment]::Center

        $heicFont = New-Object System.Drawing.Font("Arial", 22, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $heicTextBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 0x25, 0x63, 0xEB))
        $g.DrawString("HEIC", $heicFont, $heicTextBrush, (New-Object System.Drawing.RectangleF(128, 282, 108, 42)), $sf)

        # Donusum oku
        $arrowPen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 24)
        $arrowPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $arrowPen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
        $arrowPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
        $g.DrawLine($arrowPen, 274, 316, 373, 316)
        $g.DrawLines($arrowPen, [System.Drawing.PointF[]]@(
            (New-Object System.Drawing.PointF(348, 284)),
            (New-Object System.Drawing.PointF(386, 316)),
            (New-Object System.Drawing.PointF(348, 348))
        ))

        # JPG rozeti
        $jpgPath = New-RoundedRectPath 276 342 146 74 25
        $jpgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 0xF5, 0x9E, 0x0B))
        $g.FillPath($jpgBrush, $jpgPath)

        $jpgFont = New-Object System.Drawing.Font("Arial", 31, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $g.DrawString("JPG", $jpgFont, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF(276, 342, 146, 74)), $sf)

        $g.Dispose()
        return $bmp
    }

    $sizes = @(16, 32, 48, 64, 256)
    $pngBlobs = New-Object System.Collections.Generic.List[byte[]]
    foreach ($sz in $sizes) {
        $bmp = Render-IconBitmap $sz
        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $pngBlobs.Add($ms.ToArray())
        $ms.Dispose()
        $bmp.Dispose()
    }

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }

    $fs = [System.IO.File]::Create($Path)
    $bw = New-Object System.IO.BinaryWriter($fs)
    try {
        # ICONDIR header
        $bw.Write([uint16]0)
        $bw.Write([uint16]1)
        $bw.Write([uint16]$sizes.Count)

        $offset = 6 + (16 * $sizes.Count)
        for ($i = 0; $i -lt $sizes.Count; $i++) {
            $sz = $sizes[$i]
            $b = if ($sz -ge 256) { [byte]0 } else { [byte]$sz }
            $bw.Write($b)            # Width
            $bw.Write($b)            # Height
            $bw.Write([byte]0)       # ColorCount
            $bw.Write([byte]0)       # Reserved
            $bw.Write([uint16]1)     # Planes
            $bw.Write([uint16]32)    # BitCount
            $bw.Write([uint32]$pngBlobs[$i].Length)
            $bw.Write([uint32]$offset)
            $offset += $pngBlobs[$i].Length
        }
        foreach ($blob in $pngBlobs) {
            $bw.Write($blob)
        }
    } finally {
        $bw.Dispose()
        $fs.Dispose()
    }
}

$csc = @(
    "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe"
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if (-not $csc) {
    throw "csc.exe bulunamadi (.NET Framework 4.x gerekli)."
}

Write-Host "Ikon olusturuluyor: $icoPath" -ForegroundColor Cyan
New-AppIcon -Path $icoPath

Write-Host "Derleniyor: $outExe" -ForegroundColor Cyan
& $csc `
    /nologo `
    /target:exe `
    /optimize+ `
    /platform:anycpu `
    /win32icon:$icoPath `
    "/resource:$psMain,HEIC_Donustur.ps1" `
    "/resource:$psDup,PhotoDuplicateFinder.ps1" `
    "/out:$outExe" `
    $csFile

if ($LASTEXITCODE -ne 0) {
    throw "Derleme basarisiz (cikis kodu: $LASTEXITCODE)."
}

$info = Get-Item -LiteralPath $outExe
Write-Host ("Basarili! {0} ({1:N1} KB)" -f $info.FullName, ($info.Length / 1KB)) -ForegroundColor Green
