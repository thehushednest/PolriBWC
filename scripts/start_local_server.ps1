param(
  [string]$HostAddress = "0.0.0.0",
  [int]$Port = 8787
)

$projectRoot = Split-Path -Parent $PSScriptRoot
$dart = "C:\Users\sprik\flutter-git\bin\cache\dart-sdk\bin\dart.exe"

if (-not (Test-Path $dart)) {
  throw "Dart executable tidak ditemukan di $dart"
}

Write-Host "Menjalankan Polri BWC local server di http://$HostAddress`:$Port/api/v1"
& $dart "$projectRoot\server\bin\polri_bwc_server.dart" --host $HostAddress --port $Port
