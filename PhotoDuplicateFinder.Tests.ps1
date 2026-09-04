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
