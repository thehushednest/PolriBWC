param(
  [string]$BaseUrl = "http://127.0.0.1:8787/api/v1",
  [string]$ChannelId = ""
)

$endpoint = if ([string]::IsNullOrWhiteSpace($ChannelId)) {
  "$BaseUrl/presence"
} else {
  "$BaseUrl/presence?channelId=$ChannelId"
}

try {
  $response = Invoke-WebRequest -UseBasicParsing $endpoint -TimeoutSec 5
  $items = $response.Content | ConvertFrom-Json

  if (-not $items) {
    Write-Host "Belum ada user online."
    exit 0
  }

  $items |
    Sort-Object resolvedStatus, lastSeenIso -Descending |
    Select-Object username, resolvedStatus, isTalking, activeChannelId, lastSeenIso, deviceId |
    Format-Table -AutoSize
} catch {
  Write-Error "Gagal mengambil presence dari $endpoint. $($_.Exception.Message)"
  exit 1
}
