# Jalankan script ini sebagai Administrator (klik kanan → Run as administrator)
# Script ini membuka port 8787 (HTTP API) dan 8788 (PTT audio relay) di Windows Firewall
# agar HP di jaringan WiFi yang sama bisa terhubung ke server.

$ruleName8787 = "Polri BWC Server HTTP"
$ruleName8788 = "Polri BWC Server PTT"

function Add-IfNotExists($name, $port) {
    $existing = netsh advfirewall firewall show rule name=$name 2>$null
    if ($LASTEXITCODE -ne 0) {
        netsh advfirewall firewall add rule `
            name=$name `
            dir=in `
            action=allow `
            protocol=TCP `
            localport=$port `
            profile=private,domain
        Write-Host "✓ Rule '$name' (port $port) berhasil ditambahkan." -ForegroundColor Green
    } else {
        Write-Host "→ Rule '$name' (port $port) sudah ada, dilewati." -ForegroundColor Yellow
    }
}

Add-IfNotExists $ruleName8787 8787
Add-IfNotExists $ruleName8788 8788

Write-Host ""
Write-Host "Selesai. Server sekarang bisa diakses dari HP melalui WiFi yang sama." -ForegroundColor Cyan
Write-Host "IP laptop  : 192.168.1.39"
Write-Host "Endpoint   : http://192.168.1.39:8787/api/v1"
Write-Host ""
Write-Host "Tekan Enter untuk keluar..."
Read-Host
