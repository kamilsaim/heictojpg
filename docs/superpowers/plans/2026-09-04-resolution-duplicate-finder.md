# Farklı Çözünürlükte Aynı Fotoğrafları Bulma - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new menu option to `HEIC_Donustur.ps1` that finds photos which are the same picture saved twice at different resolutions (e.g. an original phone JPEG and a re-encoded HEIC->JPEG copy), and moves the lower-resolution copy to a review folder, keeping the highest-resolution file in place.

**Architecture:** Pure/testable duplicate-detection logic (filename key extraction, perceptual hashing, EXIF orientation correction, Hamming-distance clustering) lives in a new dot-sourced file, `PhotoDuplicateFinder.ps1`, covered by Pester tests. `HEIC_Donustur.ps1` dot-sources it and adds a new menu option that wires the pure logic to the filesystem (scanning, moving files) using the script's existing `Move-ToFolder` / `Get-PairedMov` / `Ask-YesNo` / `Write-Log` helpers.

**Tech Stack:** Windows PowerShell 5.1, `System.Drawing` (GDI+, already available — no new dependencies), Pester 3.4.0 (already installed on this machine, confirmed via `Get-Module -ListAvailable Pester`).

---

## Spec reference

Full design: `docs/superpowers/specs/2026-09-04-resolution-duplicate-finder-design.md`. Key decisions baked into this plan:

- Candidate pairing: filename `IMG_####` key match first (cheap), then perceptual-hash confirmation (accurate) — not full pairwise across the whole library.
- Confirmation: 9x8 grayscale difference hash (dHash), EXIF-orientation-corrected before hashing, Hamming distance threshold `6` (out of 64 bits), defined as a single named variable so it's easy to tune later.
- On confirmed duplicate: keep highest resolution (width × height); tie-break on larger file size (bytes).
- Action: move losers to `Dusuk_Cozunurluklu_Kopyalar` via the existing `Move-ToFolder` (collision-safe renaming already handled there). Also move paired Live Photo `.MOV` via existing `Get-PairedMov`.
- New standalone menu option `6`, own `Ask-YesNo` confirmation, no auto-delete.
- Files/dirs not matching `IMG_####` are out of scope (accepted trade-off).
- Corrupt/unreadable images: skipped with a log line, script does not stop.

## File Structure

- Create: `E:\ksaim\claude programlar\heictojpeg\PhotoDuplicateFinder.ps1` — dot-sourceable file with all pure/testable duplicate-detection functions.
- Create: `E:\ksaim\claude programlar\heictojpeg\PhotoDuplicateFinder.Tests.ps1` — Pester 3.4 tests for every function in the file above.
- Modify: `E:\ksaim\claude programlar\heictojpeg\HEIC_Donustur.ps1` — dot-source the new file, extend `Ask-Menu`, add the new processing block.
- Modify: `E:\ksaim\claude programlar\heictojpeg\README.md` — document the new menu option and new file.

---

### Task 1: `Get-ImgKey` — filename candidate key extraction

**Files:**
- Create: `PhotoDuplicateFinder.ps1`
- Create: `PhotoDuplicateFinder.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `PhotoDuplicateFinder.Tests.ps1` with this content:

```powershell
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path "E:\ksaim\claude programlar\heictojpeg\PhotoDuplicateFinder.Tests.ps1"`
Expected: FAIL — `PhotoDuplicateFinder.ps1` does not exist yet (dot-source error), or `Get-ImgKey` not recognized.

- [ ] **Step 3: Write minimal implementation**

Create `PhotoDuplicateFinder.ps1` with:

```powershell
# Farkli cozunurlukte ayni fotograflari bulmak icin saf mantik fonksiyonlari.
# Bu dosya HEIC_Donustur.ps1 tarafindan dot-source edilir ve
# PhotoDuplicateFinder.Tests.ps1 ile Pester uzerinden test edilir.

function Get-ImgKey {
    param([Parameter(Mandatory)][string]$FileName)
    if ($FileName -match 'IMG_(\d{4,})') {
        return "IMG_$($Matches[1])"
    }
    return $null
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path "E:\ksaim\claude programlar\heictojpeg\PhotoDuplicateFinder.Tests.ps1"`
Expected: PASS (4 tests, 0 failed)

- [ ] **Step 5: Commit**

```bash
git add PhotoDuplicateFinder.ps1 PhotoDuplicateFinder.Tests.ps1
git commit -m "Add Get-ImgKey filename candidate matcher for duplicate finder"
```

---

### Task 2: `Get-HammingDistance` — bit distance between two hashes

**Files:**
- Modify: `PhotoDuplicateFinder.ps1`
- Modify: `PhotoDuplicateFinder.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Append to `PhotoDuplicateFinder.Tests.ps1`:

```powershell
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path "E:\ksaim\claude programlar\heictojpeg\PhotoDuplicateFinder.Tests.ps1"`
Expected: The 3 new tests FAIL with "Get-HammingDistance is not recognized"; the 4 Task 1 tests still PASS.

- [ ] **Step 3: Write minimal implementation**

Append to `PhotoDuplicateFinder.ps1`:

```powershell
function Get-HammingDistance {
    param([Parameter(Mandatory)][uint64]$A, [Parameter(Mandatory)][uint64]$B)
    $xor = $A -bxor $B
    $count = 0
    for ($i = 0; $i -lt 64; $i++) {
        if (($xor -band ([uint64]1 -shl $i)) -ne 0) { $count++ }
    }
    return $count
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path "E:\ksaim\claude programlar\heictojpeg\PhotoDuplicateFinder.Tests.ps1"`
Expected: PASS (7 tests, 0 failed)

- [ ] **Step 5: Commit**

```bash
git add PhotoDuplicateFinder.ps1 PhotoDuplicateFinder.Tests.ps1
git commit -m "Add Get-HammingDistance bit-distance helper for duplicate finder"
```

---

### Task 3: `Get-DHash` — perceptual difference hash of a bitmap

**Files:**
- Modify: `PhotoDuplicateFinder.ps1`
- Modify: `PhotoDuplicateFinder.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Append to `PhotoDuplicateFinder.Tests.ps1`:

```powershell
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path "E:\ksaim\claude programlar\heictojpeg\PhotoDuplicateFinder.Tests.ps1"`
Expected: The 2 new tests FAIL with "Get-DHash is not recognized"; the 7 previous tests still PASS.

- [ ] **Step 3: Write minimal implementation**

Append to `PhotoDuplicateFinder.ps1`:

```powershell
function Get-DHash {
    param([Parameter(Mandatory)][System.Drawing.Bitmap]$Bitmap)

    $small = New-Object System.Drawing.Bitmap($Bitmap, (New-Object System.Drawing.Size(9, 8)))
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
    $small.Dispose()
    return $hash
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path "E:\ksaim\claude programlar\heictojpeg\PhotoDuplicateFinder.Tests.ps1"`
Expected: PASS (9 tests, 0 failed)

- [ ] **Step 5: Commit**

```bash
git add PhotoDuplicateFinder.ps1 PhotoDuplicateFinder.Tests.ps1
git commit -m "Add Get-DHash perceptual hash function for duplicate finder"
```

---

### Task 4: `Get-OrientationCorrectedBitmap` — apply EXIF orientation before hashing

**Files:**
- Modify: `PhotoDuplicateFinder.ps1`
- Modify: `PhotoDuplicateFinder.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Append to `PhotoDuplicateFinder.Tests.ps1`:

```powershell
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path "E:\ksaim\claude programlar\heictojpeg\PhotoDuplicateFinder.Tests.ps1"`
Expected: The 2 new tests FAIL with "Get-OrientationCorrectedBitmap is not recognized"; the 9 previous tests still PASS.

- [ ] **Step 3: Write minimal implementation**

Append to `PhotoDuplicateFinder.ps1`:

```powershell
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path "E:\ksaim\claude programlar\heictojpeg\PhotoDuplicateFinder.Tests.ps1"`
Expected: PASS (11 tests, 0 failed)

- [ ] **Step 5: Commit**

```bash
git add PhotoDuplicateFinder.ps1 PhotoDuplicateFinder.Tests.ps1
git commit -m "Add Get-OrientationCorrectedBitmap EXIF orientation handling"
```

---

### Task 5: `Get-ImageFingerprint` — file-backed fingerprint (hash + dimensions + size)

**Files:**
- Modify: `PhotoDuplicateFinder.ps1`
- Modify: `PhotoDuplicateFinder.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Append to `PhotoDuplicateFinder.Tests.ps1`:

```powershell
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path "E:\ksaim\claude programlar\heictojpeg\PhotoDuplicateFinder.Tests.ps1"`
Expected: The 3 new tests FAIL with "Get-ImageFingerprint is not recognized"; the 11 previous tests still PASS.

- [ ] **Step 3: Write minimal implementation**

Append to `PhotoDuplicateFinder.ps1`:

```powershell
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path "E:\ksaim\claude programlar\heictojpeg\PhotoDuplicateFinder.Tests.ps1"`
Expected: PASS (14 tests, 0 failed)

- [ ] **Step 5: Commit**

```bash
git add PhotoDuplicateFinder.ps1 PhotoDuplicateFinder.Tests.ps1
git commit -m "Add Get-ImageFingerprint file-backed hash+dimensions helper"
```

---

### Task 6: `Resolve-DuplicateClusters` — group fingerprints into confirmed duplicate clusters

**Files:**
- Modify: `PhotoDuplicateFinder.ps1`
- Modify: `PhotoDuplicateFinder.Tests.ps1`

This function takes a flat list of fingerprint objects (as produced by `Get-ImageFingerprint`, but tested here with hand-built fake fingerprint objects so the test doesn't depend on real images) that all share the same `IMG_####` key, and returns an array of clusters (each cluster is an array of 2+ fingerprints confirmed as the same photo by Hamming distance). Fingerprints that don't match anything in their key group are left out of the result entirely.

- [ ] **Step 1: Write the failing test**

Append to `PhotoDuplicateFinder.Tests.ps1`:

```powershell
Describe "Resolve-DuplicateClusters" {
    function New-FakeFingerprint([string]$Path, [uint64]$Hash, [int]$Width, [int]$Height, [long]$FileSize) {
        [PSCustomObject]@{ Path = $Path; Hash = $Hash; Width = $Width; Height = $Height; FileSize = $FileSize }
    }

    It "groups two fingerprints with a small Hamming distance into one cluster" {
        $fps = @(
            (New-FakeFingerprint "a.jpg" ([uint64]0b1010) 100 100 1000),
            (New-FakeFingerprint "b.jpg" ([uint64]0b1011) 200 200 2000)
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
            (New-FakeFingerprint "a.jpg" ([uint64]0b0000) 100 100 1000),
            (New-FakeFingerprint "b.jpg" ([uint64]0b0001) 200 200 2000),
            (New-FakeFingerprint "c.jpg" ([uint64]0b0011) 300 300 3000)
        )
        $clusters = Resolve-DuplicateClusters -Fingerprints $fps -Threshold 2
        $clusters.Count | Should Be 1
        $clusters[0].Count | Should Be 3
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path "E:\ksaim\claude programlar\heictojpeg\PhotoDuplicateFinder.Tests.ps1"`
Expected: The 3 new tests FAIL with "Resolve-DuplicateClusters is not recognized"; the 14 previous tests still PASS.

- [ ] **Step 3: Write minimal implementation**

Append to `PhotoDuplicateFinder.ps1`:

```powershell
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
    return @($clusters)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path "E:\ksaim\claude programlar\heictojpeg\PhotoDuplicateFinder.Tests.ps1"`
Expected: PASS (17 tests, 0 failed)

- [ ] **Step 5: Commit**

```bash
git add PhotoDuplicateFinder.ps1 PhotoDuplicateFinder.Tests.ps1
git commit -m "Add Resolve-DuplicateClusters union-merge clustering for duplicate finder"
```

---

### Task 7: `Select-DuplicateWinnerAndLosers` — pick the file to keep within a cluster

**Files:**
- Modify: `PhotoDuplicateFinder.ps1`
- Modify: `PhotoDuplicateFinder.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Append to `PhotoDuplicateFinder.Tests.ps1`:

```powershell
Describe "Select-DuplicateWinnerAndLosers" {
    function New-FakeFingerprint([string]$Path, [int]$Width, [int]$Height, [long]$FileSize) {
        [PSCustomObject]@{ Path = $Path; Hash = [uint64]0; Width = $Width; Height = $Height; FileSize = $FileSize }
    }

    It "keeps the fingerprint with the higher resolution" {
        $cluster = @(
            (New-FakeFingerprint "low.jpg" 3024 4032 2000000),
            (New-FakeFingerprint "high.jpg" 4032 3024 6000000)
        )
        $result = Select-DuplicateWinnerAndLosers -Cluster $cluster
        $result.Winner.Path | Should Be "high.jpg"
        $result.Losers.Count | Should Be 1
        $result.Losers[0].Path | Should Be "low.jpg"
    }

    It "breaks a resolution tie using the larger file size" {
        $cluster = @(
            (New-FakeFingerprint "small_file.jpg" 1000 1000 1000000),
            (New-FakeFingerprint "big_file.jpg" 1000 1000 3000000)
        )
        $result = Select-DuplicateWinnerAndLosers -Cluster $cluster
        $result.Winner.Path | Should Be "big_file.jpg"
        $result.Losers[0].Path | Should Be "small_file.jpg"
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path "E:\ksaim\claude programlar\heictojpeg\PhotoDuplicateFinder.Tests.ps1"`
Expected: The 2 new tests FAIL with "Select-DuplicateWinnerAndLosers is not recognized"; the 17 previous tests still PASS.

- [ ] **Step 3: Write minimal implementation**

Append to `PhotoDuplicateFinder.ps1`:

```powershell
function Select-DuplicateWinnerAndLosers {
    param([Parameter(Mandatory)][object[]]$Cluster)

    $sorted = $Cluster | Sort-Object -Property @{Expression = { $_.Width * $_.Height }; Descending = $true }, @{Expression = { $_.FileSize }; Descending = $true }
    $sorted = @($sorted)
    [PSCustomObject]@{
        Winner = $sorted[0]
        Losers = @($sorted | Select-Object -Skip 1)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path "E:\ksaim\claude programlar\heictojpeg\PhotoDuplicateFinder.Tests.ps1"`
Expected: PASS (19 tests, 0 failed)

- [ ] **Step 5: Commit**

```bash
git add PhotoDuplicateFinder.ps1 PhotoDuplicateFinder.Tests.ps1
git commit -m "Add Select-DuplicateWinnerAndLosers resolution/size tie-break logic"
```

---

### Task 8: Wire the new menu option into `HEIC_Donustur.ps1`

**Files:**
- Modify: `HEIC_Donustur.ps1:1-2` (dot-source), `HEIC_Donustur.ps1:54-96` (`Ask-Menu`), `HEIC_Donustur.ps1:424-454` (insert new block before the "Bu turdaki islemler tamamlandi" line)

This task has no automated test (it's the integration wiring into a script that reads from the real filesystem and asks the user interactive Y/N questions, matching how every other step in this file is already un-unit-tested — see Task 9 for manual verification instead).

- [ ] **Step 1: Dot-source the new file at the top of the script**

In `HEIC_Donustur.ps1`, after line 2 (`if (-not $root) { $root = Split-Path -Parent $MyInvocation.MyCommand.Path }`), add:

```powershell
. (Join-Path $root "PhotoDuplicateFinder.ps1")
```

- [ ] **Step 2: Add menu option 6 and extend validation range**

In the `Ask-Menu` function (`HEIC_Donustur.ps1:54-96`), change:

```powershell
    $secenekler = [ordered]@{
        1 = "HEIC -> JPEG donustur"
        2 = "AAE dosyalarini sil"
        3 = "Ciftlenen (ayni icerikli) resimleri tasi"
        4 = "Live Photo videolarini (.MOV) tasi"
        5 = "Diger video dosyalarini tasi"
    }
```

to:

```powershell
    $secenekler = [ordered]@{
        1 = "HEIC -> JPEG donustur"
        2 = "AAE dosyalarini sil"
        3 = "Ciftlenen (ayni icerikli) resimleri tasi"
        4 = "Live Photo videolarini (.MOV) tasi"
        5 = "Diger video dosyalarini tasi"
        6 = "Farkli cozunurlukte ayni fotograflari bul (dusuk cozunurluklu kopyayi tasi)"
    }
```

then change the two lines that hard-code the range `1`-`5`:

```powershell
        if ([string]::IsNullOrWhiteSpace($girdi)) {
            return @(1, 2, 3, 4, 5)
        }
```
becomes
```powershell
        if ([string]::IsNullOrWhiteSpace($girdi)) {
            return @(1, 2, 3, 4, 5, 6)
        }
```

and

```powershell
            if (-not [int]::TryParse($t, [ref]$n) -or $n -lt 1 -or $n -gt 5) {
```
becomes
```powershell
            if (-not [int]::TryParse($t, [ref]$n) -or $n -lt 1 -or $n -gt 6) {
```

and the error message line:
```powershell
        Write-Host "Lutfen 1-5 arasinda numaralari virgulle ayirarak girin (veya hepsi icin bos birakin)." -ForegroundColor Yellow
```
becomes
```powershell
        Write-Host "Lutfen 1-6 arasinda numaralari virgulle ayirarak girin (veya hepsi icin bos birakin)." -ForegroundColor Yellow
```

- [ ] **Step 3: Read the new flag from the menu selection**

Near `HEIC_Donustur.ps1:102-106` where the other flags are set:

```powershell
$yapDonustur      = $secilenler -contains 1
$yapAaeSil        = $secilenler -contains 2
$yapCiftTasi      = $secilenler -contains 3
$yapLivePhotoTasi = $secilenler -contains 4
$yapVideoTasi     = $secilenler -contains 5
```

add a sixth line:

```powershell
$yapCozunurlukTasi = $secilenler -contains 6
```

- [ ] **Step 4: Insert the processing block**

Insert this new block in `HEIC_Donustur.ps1` right after the "Diger video dosyalarini tasi" block ends (right before the `Write-Host ""` / `Write-Log "Bu turdaki islemler tamamlandi."` lines that currently follow it, i.e. right before what is currently line 456 `Write-Host ""` preceding `"Bu turdaki islemler tamamlandi."`):

```powershell
Write-Host ""
$resolutionDupFolder = Join-Path $root "Dusuk_Cozunurluklu_Kopyalar"
$tasiCozunurluk = $false
if ($yapCozunurlukTasi) {
    $tasiCozunurluk = Ask-YesNo "Farkli cozunurlukte kaydedilmis ayni fotograflar bulunup dusuk cozunurluklu kopyalari 'Dusuk_Cozunurluklu_Kopyalar' klasorune tasinsin mi?"
}
if ($tasiCozunurluk) {
    Write-Log ""
    Write-Log "Fotograflar isim+gorsel benzerligine gore karsilastiriliyor..." Cyan

    $hammingEsigi = 6

    $resimUzantilariCozunurluk = @("*.jpg", "*.jpeg", "*.png", "*.heic")
    $adayResimler = Get-ChildItem -Path $root -Recurse -File -Include $resimUzantilariCozunurluk -ErrorAction SilentlyContinue |
                    Where-Object {
                        $_.FullName -notlike "$duplicatesFolder*" -and
                        $_.FullName -notlike "$resolutionDupFolder*"
                    }

    $anahtarGruplari = @{}
    foreach ($f in $adayResimler) {
        $anahtar = Get-ImgKey -FileName $f.Name
        if ($anahtar) {
            if (-not $anahtarGruplari.ContainsKey($anahtar)) { $anahtarGruplari[$anahtar] = New-Object System.Collections.Generic.List[object] }
            $anahtarGruplari[$anahtar].Add($f)
        }
    }

    $tasinanCozunurluk = 0
    $tasinanCozunurlukMov = 0
    $okunamayan = 0

    foreach ($anahtar in $anahtarGruplari.Keys) {
        $adayDosyalar = $anahtarGruplari[$anahtar]
        if ($adayDosyalar.Count -lt 2) { continue }

        $parmakIzleri = New-Object System.Collections.Generic.List[object]
        foreach ($f in $adayDosyalar) {
            $fp = Get-ImageFingerprint -Path $f.FullName
            if ($fp) {
                $fp | Add-Member -MemberType NoteProperty -Name FileInfo -Value $f
                $parmakIzleri.Add($fp)
            } else {
                $okunamayan++
                Write-Log "Atlandi (okunamadi): $($f.Name)" DarkYellow
            }
        }
        if ($parmakIzleri.Count -lt 2) { continue }

        $kumeler = Resolve-DuplicateClusters -Fingerprints @($parmakIzleri) -Threshold $hammingEsigi
        foreach ($kume in $kumeler) {
            $sonuc = Select-DuplicateWinnerAndLosers -Cluster $kume
            foreach ($kaybeden in $sonuc.Losers) {
                $pairedMov = Get-PairedMov $kaybeden.FileInfo
                Move-ToFolder -f $kaybeden.FileInfo -folder $resolutionDupFolder
                $tasinanCozunurluk++
                if ($pairedMov) {
                    Move-ToFolder -f $pairedMov -folder $resolutionDupFolder
                    $tasinanCozunurlukMov++
                }
            }
        }
    }

    if ($tasinanCozunurluk -eq 0) {
        Write-Log "Farkli cozunurlukte ayni fotograf bulunamadi." Yellow
    } else {
        if (-not (Test-Path -LiteralPath $resolutionDupFolder)) {
            New-Item -ItemType Directory -Path $resolutionDupFolder | Out-Null
        }
        Write-Log "$tasinanCozunurluk adet dusuk cozunurluklu kopya '$resolutionDupFolder' klasorune tasindi." Green
        if ($tasinanCozunurlukMov -gt 0) {
            Write-Log "Bunlarla eslesen $tasinanCozunurlukMov adet Live Photo videosu (.MOV) da ayni klasore tasindi." Green
        }
    }
    if ($okunamayan -gt 0) {
        Write-Log "$okunamayan adet dosya okunamadigi icin karsilastirmaya dahil edilmedi." Yellow
    }
}
```

Note: this block creates `$resolutionDupFolder` before checking `Test-Path` on it inside the loop (via `Move-ToFolder`) — `Move-ToFolder` itself doesn't create the destination folder, so the folder must exist before any `Move-ToFolder` call runs. Fix this ordering issue in the same step: move the `New-Item -ItemType Directory` call to happen *before* the `foreach ($anahtar in $anahtarGruplari.Keys)` loop instead of after it, guarded by `if (-not (Test-Path -LiteralPath $resolutionDupFolder)) { New-Item -ItemType Directory -Path $resolutionDupFolder | Out-Null }`, mirroring the existing "Ciftlenen resimleri tasi" block's ordering (`HEIC_Donustur.ps1:352-355`) where the folder is created before any `Move-ToFolder` call. Do not create the folder if `$tasinanCozunurluk` ends up 0 — only create it right before the first actual move, i.e. immediately after `$kumeler = Resolve-DuplicateClusters ...` finds at least one non-empty cluster for the first time. Simplest correct implementation: create the folder lazily inside the `foreach ($kaybeden in $sonuc.Losers)` loop, guarded by the existing `Test-Path` check, right before the first `Move-ToFolder` call:

```powershell
            foreach ($kaybeden in $sonuc.Losers) {
                if (-not (Test-Path -LiteralPath $resolutionDupFolder)) {
                    New-Item -ItemType Directory -Path $resolutionDupFolder | Out-Null
                }
                $pairedMov = Get-PairedMov $kaybeden.FileInfo
                Move-ToFolder -f $kaybeden.FileInfo -folder $resolutionDupFolder
                $tasinanCozunurluk++
                if ($pairedMov) {
                    Move-ToFolder -f $pairedMov -folder $resolutionDupFolder
                    $tasinanCozunurlukMov++
                }
            }
```

and remove the now-redundant `if (-not (Test-Path -LiteralPath $resolutionDupFolder)) { New-Item ... }` from the later `if ($tasinanCozunurluk -eq 0) { ... } else { ... }` block (keep only the `Write-Log` lines there).

- [ ] **Step 5: Verify the script still parses**

Run: `powershell -NoProfile -Command "$errors = $null; [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw 'E:\ksaim\claude programlar\heictojpeg\HEIC_Donustur.ps1'), [ref]$errors) | Out-Null; if ($errors.Count -eq 0) { 'OK' } else { $errors }"`
Expected: `OK`

- [ ] **Step 6: Commit**

```bash
git add HEIC_Donustur.ps1
git commit -m "Wire resolution-based duplicate finder into the main menu"
```

---

### Task 9: Manual verification against real files

**Files:** none (verification only)

Automated Pester tests cover all the pure logic (Tasks 1-7). This step manually verifies the wiring in Task 8 actually behaves correctly end-to-end, without risking the user's real photo library.

- [ ] **Step 1: Build a disposable test folder**

Run (PowerShell), creating a throwaway folder with one true duplicate pair (same content, different size) and one false-positive-shaped pair (same `IMG_####` number, different content) so both the "should move" and "should NOT move" paths are exercised:

```powershell
Add-Type -AssemblyName System.Drawing
$testRoot = Join-Path $env:TEMP ("HeicDupManualTest_" + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $testRoot | Out-Null

function New-Solid([string]$Path, [int]$W, [int]$H, [int]$Shade) {
    $bmp = New-Object System.Drawing.Bitmap($W, $H)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::FromArgb($Shade, $Shade, $Shade))
    for ($x = 0; $x -lt $W; $x += [Math]::Max(1,[int]($W/8))) {
        $g.FillRectangle([System.Drawing.Brushes]::Black, $x, 0, 2, $H)
    }
    $g.Dispose()
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Jpeg)
    $bmp.Dispose()
}

# Gercek cift: ayni gorsel, iki farkli boyut/isim deseninde
New-Solid (Join-Path $testRoot "IMG_0100.jpg") 4032 3024 180
New-Solid (Join-Path $testRoot "2020_01_01_IMG_0100.jpg") 1200 900 180

# Yanlis pozitif adayi: ayni IMG numarasi, tamamen farkli goruntu
New-Solid (Join-Path $testRoot "IMG_0200.jpg") 3000 2000 20
New-Solid (Join-Path $testRoot "2021_05_05_IMG_0200.jpg") 3000 2000 220

Copy-Item "E:\ksaim\claude programlar\heictojpeg\HEIC_Donustur.ps1" $testRoot
Copy-Item "E:\ksaim\claude programlar\heictojpeg\PhotoDuplicateFinder.ps1" $testRoot
"Test folder: $testRoot"
```

- [ ] **Step 2: Run the script against the test folder and select only option 6**

In a terminal: `powershell -NoProfile -File "<testRoot>\HEIC_Donustur.ps1"` (substitute the printed `$testRoot`). At the menu prompt, enter `6`. Answer `E` (yes) to the confirmation question.

- [ ] **Step 3: Confirm expected outcome**

Check:
- `Dusuk_Cozunurluklu_Kopyalar` folder was created inside `testRoot`.
- It contains exactly one file: the smaller `2020_01_01_IMG_0100.jpg` (the 1200x900 one).
- `IMG_0100.jpg` (4032x3024, the higher-resolution winner) is still in `testRoot`, not moved.
- Both `IMG_0200.jpg` and `2021_05_05_IMG_0200.jpg` are still in `testRoot` (NOT moved — this is the false-positive candidate that the perceptual-hash check must reject).
- The printed summary / log file mentions moving exactly 1 file.

If any of these don't hold, stop and re-check Task 8's wiring (most likely culprits: the `$hammingEsigi` threshold, or the `Get-OrientationCorrectedBitmap`/`Get-DHash` pipeline) before proceeding — do not adjust the threshold against the user's real library first.

- [ ] **Step 4: Clean up the disposable test folder**

```powershell
Remove-Item -LiteralPath $testRoot -Recurse -Force
```

No commit for this task (verification only, no source changes).

---

### Task 10: Update README

**Files:**
- Modify: `README.md:26-51` (numbered feature list), `README.md:53-58` (Dosyalar table)

- [ ] **Step 1: Add the new step to the numbered feature list**

In `README.md`, after item 6 (`Live Photo videolarini ayirir`) and before item 7 (`Diger video dosyalarini ayirir`), the list currently runs 1-7. Renumber so the new feature becomes item 7 and the existing "Diger video dosyalarini ayirir" becomes item 8:

Replace:
```markdown
6. **Live Photo videolarini ayirir** (isterseniz) — bir fotografla ayni
   isimde eslesen `.mov` dosyalarini `LivePhoto_Videolari` klasorune tasir.
7. **Diger video dosyalarini ayirir** (isterseniz) — `.mp4`, `.mov`,
   `.avi`, `.mkv`, `.wmv`, `.m4v`, `.3gp` uzantili (Live Photo eslesmesi
   olmayan) video dosyalarini `Videolar` klasorune tasir.
```

with:
```markdown
6. **Live Photo videolarini ayirir** (isterseniz) — bir fotografla ayni
   isimde eslesen `.mov` dosyalarini `LivePhoto_Videolari` klasorune tasir.
7. **Diger video dosyalarini ayirir** (isterseniz) — `.mp4`, `.mov`,
   `.avi`, `.mkv`, `.wmv`, `.m4v`, `.3gp` uzantili (Live Photo eslesmesi
   olmayan) video dosyalarini `Videolar` klasorune tasir.
8. **Farkli cozunurlukte ayni fotograflari bulur** (isterseniz) — dosya
   adindaki `IMG_####` numarasi ve gorsel benzerlik (fark hash) ile ayni
   fotografin farkli cozunurluklerde kaydedilmis kopyalarini tespit eder
   (orn. HEIC'ten JPEG'e yeniden encode edilen bir kopya ile telefondan
   gelen orijinal JPEG), dusuk cozunurluklu olani `Dusuk_Cozunurluklu_Kopyalar`
   klasorune tasir, yuksek cozunurluklu olan yerinde kalir.
```

- [ ] **Step 2: Add the new file to the Dosyalar table**

Replace:
```markdown
| Dosya | Aciklama |
|---|---|
| `HEIC_Donustur.bat` | Cift tiklayip calistirilacak baslangic dosyasi. |
| `HEIC_Donustur.ps1` | Asil islemi yapan PowerShell scripti. |
```

with:
```markdown
| Dosya | Aciklama |
|---|---|
| `HEIC_Donustur.bat` | Cift tiklayip calistirilacak baslangic dosyasi. |
| `HEIC_Donustur.ps1` | Asil islemi yapan PowerShell scripti. |
| `PhotoDuplicateFinder.ps1` | Farkli cozunurlukteki ayni fotograflari tespit eden yardimci fonksiyonlar (`HEIC_Donustur.ps1` tarafindan kullanilir). |
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Document the resolution-based duplicate finder in README"
```

---

## Self-review notes

- **Spec coverage:** Candidate pairing (Task 1, Task 8 Step 4), dHash + EXIF correction (Tasks 3-4), threshold-based confirmation (Task 6, wired with `$hammingEsigi = 6` in Task 8), winner/loser selection by resolution then file size (Task 7), move-not-delete with paired MOV (Task 8), corrupt-file handling (Task 5's `try/catch` + Task 8's `$okunamayan` counter), new standalone menu option 6 with its own confirmation (Task 8) — all covered.
- **Folder-creation-before-move bug caught during planning:** the first draft of Task 8's block created `Dusuk_Cozunurluklu_Kopyalar` only after the move loop finished, which would have made every `Move-ToFolder` call fail. Fixed in Task 8 Step 4 by creating the folder lazily right before the first actual move (mirrors how `Move-ToFolder` itself expects a pre-existing destination).
- **Type consistency:** `Get-ImgKey(FileName)`, `Get-HammingDistance(A,B)`, `Get-DHash(Bitmap)`, `Get-OrientationCorrectedBitmap(Bitmap)`, `Get-ImageFingerprint(Path)` returning `{Path,Hash,Width,Height,FileSize}`, `Resolve-DuplicateClusters(Fingerprints,Threshold)`, `Select-DuplicateWinnerAndLosers(Cluster)` returning `{Winner,Losers}` — names and shapes are used identically across Tasks 1-8.
