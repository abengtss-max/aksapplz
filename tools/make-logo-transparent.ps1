# Restore transparency on logo assets whose alpha was flattened onto a near-white
# background. Uses a fast LockBits scan and keys out pixels within tolerance of the
# background color, preserving the colored cube artwork.

Add-Type -AssemblyName System.Drawing

$Files = @('logo-mark.png', 'favicon.png')
$BgR = 250; $BgG = 250; $BgB = 251
$Tolerance = 24

foreach ($f in $Files) {
    $path = Join-Path (Join-Path $PWD 'docs/assets') $f
    $srcBytes = [System.IO.File]::ReadAllBytes($path)
    $ms = [System.IO.MemoryStream]::new($srcBytes)
    $src = [System.Drawing.Bitmap]::FromStream($ms)
    $w = $src.Width; $h = $src.Height

    $bmp = [System.Drawing.Bitmap]::new($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.DrawImage($src, 0, 0, $w, $h)
    $g.Dispose()
    $src.Dispose()
    $ms.Dispose()

    $rect = [System.Drawing.Rectangle]::new(0, 0, $w, $h)
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadWrite, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $bytes = $w * $h * 4
    $buf = New-Object byte[] $bytes
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $buf, 0, $bytes)

    for ($i = 0; $i -lt $bytes; $i += 4) {
        # BGRA order
        $b = $buf[$i]; $gr = $buf[$i + 1]; $r = $buf[$i + 2]
        $dr = [math]::Abs($r - $BgR); $dg = [math]::Abs($gr - $BgG); $db = [math]::Abs($b - $BgB)
        $maxd = [math]::Max($dr, [math]::Max($dg, $db))
        if ($maxd -le $Tolerance) { $buf[$i + 3] = 0 }
    }

    [System.Runtime.InteropServices.Marshal]::Copy($buf, 0, $data.Scan0, $bytes)
    $bmp.UnlockBits($data)
    $tmp = "$path.tmp"
    $bmp.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Move-Item -Force $tmp $path
    Write-Output "$f -> transparent PNG written ($w x $h)"
}
