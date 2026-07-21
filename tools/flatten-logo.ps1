# Flatten a PNG's alpha onto a solid background, producing an opaque image.
# Used to revert logo-mark.png to its original opaque (white-card) look.

Add-Type -AssemblyName System.Drawing

$Files = @('logo-mark.png')
$BgR = 250; $BgG = 250; $BgB = 251

foreach ($f in $Files) {
    $path = Join-Path (Join-Path $PWD 'docs/assets') $f
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $ms = [System.IO.MemoryStream]::new($bytes)
    $src = [System.Drawing.Bitmap]::FromStream($ms)
    $w = $src.Width; $h = $src.Height

    $bmp = [System.Drawing.Bitmap]::new($w, $h, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::FromArgb(255, $BgR, $BgG, $BgB))
    $g.DrawImage($src, 0, 0, $w, $h)
    $g.Dispose()
    $src.Dispose()
    $ms.Dispose()

    $tmp = "$path.tmp"
    $bmp.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Move-Item -Force $tmp $path
    Write-Output "$f -> flattened opaque PNG written ($w x $h)"
}
