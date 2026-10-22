# Open the local KwVPS preview with Git Bash and a UTF-8 console.
# This script does not run administrative commands or connect to a VPS.
[CmdletBinding()]
param(
  [ValidateSet('preview', 'help')]
  [string] $Mode = 'preview'
)

$ErrorActionPreference = 'Stop'

$gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue |
  Where-Object { $_.Source -match '[\\/]cmd[\\/]git\.exe$' } |
  Select-Object -First 1

if (-not $gitCommand) {
  Write-Error 'Không tìm thấy Git for Windows. Hãy cài Git for Windows rồi chạy lại.'
  exit 2
}

$gitRoot = Split-Path -Parent (Split-Path -Parent $gitCommand.Source)
$gitBash = Join-Path $gitRoot 'bin\bash.exe'
if (-not (Test-Path -LiteralPath $gitBash -PathType Leaf)) {
  Write-Error "Không tìm thấy Git Bash tại $gitBash"
  exit 2
}

$utf8 = [System.Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
$env:LANG = 'C.UTF-8'
$env:LC_CTYPE = 'C.UTF-8'

$entry = Join-Path (Split-Path -Parent $PSScriptRoot) 'kwvps'
if ($Mode -eq 'help') {
  & $gitBash $entry --help
} else {
  & $gitBash $entry --preview
}
exit $LASTEXITCODE
