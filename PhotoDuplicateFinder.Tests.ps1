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
