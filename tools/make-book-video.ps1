#Requires -Version 7.0
[CmdletBinding()]
param(
    [string] $FfmpegPath = 'ffmpeg',
    [string] $OutputPath,
    # Retained for compatibility; the open-book layout is now the default.
    [switch] $V2
)

$ErrorActionPreference = 'Stop'
if (-not $OutputPath) {
    $OutputPath = Join-Path $PSScriptRoot '..\figures\book-chapters-4k.mp4'
}
$generator = Join-Path $PSScriptRoot 'make-book-chapters.py'
if (-not (Get-Command $FfmpegPath -ErrorAction SilentlyContinue)) {
    throw "FFmpeg not found: $FfmpegPath. Install FFmpeg or pass -FfmpegPath."
}
if (Test-Path -LiteralPath $OutputPath) {
    throw "Output already exists: $OutputPath. Choose another -OutputPath or remove it explicitly."
}

$frameDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("book-video-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $frameDirectory | Out-Null
try {
    $renderArguments = @($generator, '--landscape', '--frames-dir', $frameDirectory)
    & python @renderArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Landscape page rendering failed with exit code $LASTEXITCODE."
    }
    $duration = (Get-Content -LiteralPath (Join-Path $frameDirectory 'duration.txt') -Raw).Trim()
    & $FfmpegPath -hide_banner -loglevel warning -nostdin -n `
        -f concat -safe 0 -i (Join-Path $frameDirectory 'frames.ffconcat') `
        -map 0:v:0 -an -t $duration `
        -vf 'fps=25,scale=3840:2160:flags=lanczos,setsar=1' `
        -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p -profile:v high -level:v 5.1 `
        -movflags +faststart $OutputPath
    if ($LASTEXITCODE -ne 0) {
        throw "FFmpeg encoding failed with exit code $LASTEXITCODE."
    }
}
finally {
    Get-ChildItem -LiteralPath $frameDirectory -File | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName
    }
    Remove-Item -LiteralPath $frameDirectory
}

& $FfmpegPath -hide_banner -nostdin -v error -xerror -i $OutputPath -map 0:v:0 -f null -
if ($LASTEXITCODE -ne 0) {
    throw "MP4 decode validation failed with exit code $LASTEXITCODE."
}
Write-Output "Created and decode-validated silent 3840 x 2160 MP4 at 25 fps: $OutputPath"
