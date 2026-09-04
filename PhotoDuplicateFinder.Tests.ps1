$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here "PhotoDuplicateFinder.ps1")

Describe "Get-ImgKey" {
    It "extracts the IMG_#### key from a plain filename" {
        Get-ImgKey -FileName "IMG_0019.jpg" | Should Be "IMG_0019"
    }

    It "extracts the IMG_#### key when the filename has a date prefix" {
        Get-ImgKey -FileName "2019_06_07_IMG_0055.JPG" | Should Be "IMG_0055"
    }

    It "returns null when there is no IMG_#### pattern" {
        Get-ImgKey -FileName "vacation_photo.jpg" | Should Be $null
    }

    It "matches case-insensitively" {
        Get-ImgKey -FileName "img_0021.jpg" | Should Be "IMG_0021"
    }
}

Describe "Get-HammingDistance" {
    It "returns 0 for two identical values" {
        Get-HammingDistance -A ([uint64]12345) -B ([uint64]12345) | Should Be 0
    }

    It "returns 64 for exact opposites" {
        Get-HammingDistance -A ([uint64]0) -B ([uint64]::MaxValue) | Should Be 64
    }

    It "counts differing bits correctly" {
        # 0b1010 = 10, 0b0010 = 2, xor = 0b1000 -> 1 differing bit
        Get-HammingDistance -A ([uint64]10) -B ([uint64]2) | Should Be 1
    }
}

Describe "Get-DHash" {
    BeforeEach {
        Add-Type -AssemblyName System.Drawing
    }

    It "returns the same hash for two identical gradient images" {
        $bmp1 = New-Object System.Drawing.Bitmap(32, 32)
        $bmp2 = New-Object System.Drawing.Bitmap(32, 32)
        for ($x = 0; $x -lt 32; $x++) {
            $shade = $x * 8
            for ($y = 0; $y -lt 32; $y++) {
                $color = [System.Drawing.Color]::FromArgb($shade, $shade, $shade)
                $bmp1.SetPixel($x, $y, $color)
                $bmp2.SetPixel($x, $y, $color)
            }
        }
        $hash1 = Get-DHash -Bitmap $bmp1
        $hash2 = Get-DHash -Bitmap $bmp2
        $bmp1.Dispose(); $bmp2.Dispose()
        $hash1 | Should Be $hash2
    }

    It "returns a very different hash for a left-to-right vs right-to-left gradient" {
        $bmpAsc = New-Object System.Drawing.Bitmap(32, 32)
        $bmpDesc = New-Object System.Drawing.Bitmap(32, 32)
        for ($x = 0; $x -lt 32; $x++) {
            for ($y = 0; $y -lt 32; $y++) {
                $bmpAsc.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($x * 8, $x * 8, $x * 8))
                $bmpDesc.SetPixel($x, $y, [System.Drawing.Color]::FromArgb((31 - $x) * 8, (31 - $x) * 8, (31 - $x) * 8))
            }
        }
        $hashAsc = Get-DHash -Bitmap $bmpAsc
        $hashDesc = Get-DHash -Bitmap $bmpDesc
        $bmpAsc.Dispose(); $bmpDesc.Dispose()
        (Get-HammingDistance -A $hashAsc -B $hashDesc) | Should BeGreaterThan 40
    }
}

Describe "Get-OrientationCorrectedBitmap" {
    BeforeEach {
        Add-Type -AssemblyName System.Drawing
    }

    function New-FakeExifPropertyItem([int]$Id, [int]$Type, [byte[]]$Value) {
        $item = [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject([System.Drawing.Imaging.PropertyItem])
        $item.Id = $Id
        $item.Type = $Type
        $item.Len = $Value.Length
        $item.Value = $Value
        return $item
    }

    It "leaves a bitmap without an orientation tag unchanged" {
        $bmp = New-Object System.Drawing.Bitmap(6, 4)
        $result = Get-OrientationCorrectedBitmap -Bitmap $bmp
        $result.Width | Should Be 6
        $result.Height | Should Be 4
        $bmp.Dispose()
    }

    It "swaps width and height for a 90-degree orientation tag (value 6)" {
        $bmp = New-Object System.Drawing.Bitmap(6, 4)
        $orientationItem = New-FakeExifPropertyItem -Id 0x0112 -Type 3 -Value ([BitConverter]::GetBytes([uint16]6))
        $bmp.SetPropertyItem($orientationItem)

        $result = Get-OrientationCorrectedBitmap -Bitmap $bmp
        $result.Width | Should Be 4
        $result.Height | Should Be 6
        $bmp.Dispose()
    }
}

Describe "Get-ImageFingerprint" {
    BeforeEach {
        Add-Type -AssemblyName System.Drawing
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("PhotoDupTest_" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:tempDir | Out-Null
    }

    AfterEach {
        Remove-Item -LiteralPath $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    function New-TestJpeg([string]$Path, [int]$Width, [int]$Height) {
        $bmp = New-Object System.Drawing.Bitmap($Width, $Height)
        for ($x = 0; $x -lt $Width; $x++) {
            $shade = [int](($x / [double]$Width) * 255)
            for ($y = 0; $y -lt $Height; $y++) {
                $bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($shade, $shade, $shade))
            }
        }
        $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Jpeg)
        $bmp.Dispose()
    }

    It "reads width, height and file size for a valid image" {
        $path = Join-Path $script:tempDir "big.jpg"
        New-TestJpeg -Path $path -Width 64 -Height 32
        $fp = Get-ImageFingerprint -Path $path
        $fp | Should Not Be $null
        $fp.Width | Should Be 64
        $fp.Height | Should Be 32
        $fp.FileSize | Should Be (Get-Item -LiteralPath $path).Length
    }

    It "produces a low Hamming distance between the same image saved at two sizes" {
        $bigPath = Join-Path $script:tempDir "same_big.jpg"
        $smallPath = Join-Path $script:tempDir "same_small.jpg"
        New-TestJpeg -Path $bigPath -Width 64 -Height 32
        New-TestJpeg -Path $smallPath -Width 16 -Height 8

        $fpBig = Get-ImageFingerprint -Path $bigPath
        $fpSmall = Get-ImageFingerprint -Path $smallPath

        (Get-HammingDistance -A $fpBig.Hash -B $fpSmall.Hash) | Should BeLessThan 6
    }

    It "returns null for a corrupt or unreadable file instead of throwing" {
        $badPath = Join-Path $script:tempDir "corrupt.jpg"
        Set-Content -LiteralPath $badPath -Value "this is not a real jpeg" -Encoding Ascii
        { Get-ImageFingerprint -Path $badPath } | Should Not Throw
        Get-ImageFingerprint -Path $badPath | Should Be $null
    }
}

Describe "Resolve-DuplicateClusters" {
    function New-FakeFingerprint([string]$Path, [uint64]$Hash, [int]$Width, [int]$Height, [long]$FileSize) {
        [PSCustomObject]@{ Path = $Path; Hash = $Hash; Width = $Width; Height = $Height; FileSize = $FileSize }
    }

    It "groups two fingerprints with a small Hamming distance into one cluster" {
        $fps = @(
            (New-FakeFingerprint "a.jpg" ([uint64]10) 100 100 1000),  # 0b1010
            (New-FakeFingerprint "b.jpg" ([uint64]11) 200 200 2000)   # 0b1011
        )
        $clusters = Resolve-DuplicateClusters -Fingerprints $fps -Threshold 6
        $clusters.Count | Should Be 1
        $clusters[0].Count | Should Be 2
    }

    It "does not cluster fingerprints with a large Hamming distance" {
        $fps = @(
            (New-FakeFingerprint "a.jpg" ([uint64]0) 100 100 1000),
            (New-FakeFingerprint "b.jpg" ([uint64]::MaxValue) 200 200 2000)
        )
        $clusters = Resolve-DuplicateClusters -Fingerprints $fps -Threshold 6
        $clusters.Count | Should Be 0
    }

    It "merges three mutually close fingerprints into a single cluster" {
        $fps = @(
            (New-FakeFingerprint "a.jpg" ([uint64]0) 100 100 1000),  # 0b0000
            (New-FakeFingerprint "b.jpg" ([uint64]1) 200 200 2000),  # 0b0001
            (New-FakeFingerprint "c.jpg" ([uint64]3) 300 300 3000)   # 0b0011
        )
        $clusters = Resolve-DuplicateClusters -Fingerprints $fps -Threshold 2
        $clusters.Count | Should Be 1
        $clusters[0].Count | Should Be 3
    }
}
