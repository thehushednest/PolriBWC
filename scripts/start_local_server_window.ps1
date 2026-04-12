param(
  [string]$HostAddress = "0.0.0.0",
  [int]$Port = 8787
)

$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $PSScriptRoot 'start_local_server.ps1'

Start-Process `
  -FilePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
  -WorkingDirectory $projectRoot `
  -ArgumentList @(
    '-NoLogo',
    '-NoProfile',
    '-NoExit',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    $scriptPath,
    '-HostAddress',
    $HostAddress,
    '-Port',
    $Port
  )
