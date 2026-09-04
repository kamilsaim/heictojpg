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
