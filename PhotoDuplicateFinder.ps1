# Farkli cozunurlukte ayni fotograflari bulmak icin saf mantik fonksiyonlari.
# Bu dosya HEIC_Donustur.ps1 tarafindan dot-source edilir ve
# PhotoDuplicateFinder.Tests.ps1 ile Pester uzerinden test edilir.

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
