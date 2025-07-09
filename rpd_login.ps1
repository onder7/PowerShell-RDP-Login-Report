
param(
    [int]$Days = 60,
    [string]$OutputPath = $null,
    [switch]$ShowDisconnects
)

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Bu script yönetici yetkisi ile çalıştırılmalıdır."
    exit 1
}

try {
    Write-Host "RDP giriş kayıtları analiz ediliyor..." -ForegroundColor Green
    
    $startTime = (Get-Date).AddDays(-$Days)
    

    $loginEvents = Get-WinEvent -FilterHashtable @{ 
        LogName = 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational'
        Id = 21
        StartTime = $startTime
    } -ErrorAction SilentlyContinue
    
    $logoutEvents = @()
    if ($ShowDisconnects) {
        $logoutEvents = Get-WinEvent -FilterHashtable @{ 
            LogName = 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational'
            Id = 23
            StartTime = $startTime
        } -ErrorAction SilentlyContinue
    }
    
    function Parse-RDPEvent {
        param($event, $eventType)
        
        $lines = $event.Message -split "`n"
        $user = ($lines | Where-Object { $_ -like "User:*" }) -replace "User:\s*", ""
        $ip = ($lines | Where-Object { $_ -like "Source Network Address:*" }) -replace "Source Network Address:\s*", ""
        $sessionId = ($lines | Where-Object { $_ -like "Session ID:*" }) -replace "Session ID:\s*", ""
        
        if ($user -and $ip) {
            return [PSCustomObject]@{
                Zaman = $event.TimeCreated.ToString("dd/MM/yyyy HH:mm:ss")
                Kullanici = $user.Trim()
                IPAdres = $ip.Trim()
                SessionID = if ($sessionId) { $sessionId.Trim() } else { "N/A" }
                EventType = $eventType
                MachineName = $event.MachineName
                EventID = $event.Id
            }
        }
    }
    
    $allData = @()
    
    foreach ($event in $loginEvents) {
        $parsed = Parse-RDPEvent -event $event -eventType "Giriş"
        if ($parsed) { $allData += $parsed }
    }
    
    if ($ShowDisconnects) {
        foreach ($event in $logoutEvents) {
            $parsed = Parse-RDPEvent -event $event -eventType "Çıkış"
            if ($parsed) { $allData += $parsed }
        }
    }
    
    if ($allData) {
        $sortedData = $allData | Sort-Object Zaman -Descending
        
        $totalLogins = ($sortedData | Where-Object { $_.EventType -eq "Giriş" }).Count
        $uniqueUsers = ($sortedData | Where-Object { $_.EventType -eq "Giriş" } | Select-Object -Unique Kullanici).Count
        $uniqueIPs = ($sortedData | Where-Object { $_.EventType -eq "Giriş" } | Select-Object -Unique IPAdres).Count
        
        Write-Host "`n=== RDP Giriş İstatistikleri ===" -ForegroundColor Yellow
        Write-Host "Son $Days gün içinde:" -ForegroundColor Cyan
        Write-Host "- Toplam giriş: $totalLogins" -ForegroundColor White
        Write-Host "- Benzersiz kullanıcı: $uniqueUsers" -ForegroundColor White
        Write-Host "- Benzersiz IP adresi: $uniqueIPs" -ForegroundColor White
        
        $topUsers = $sortedData | Where-Object { $_.EventType -eq "Giriş" } | 
                   Group-Object Kullanici | 
                   Sort-Object Count -Descending | 
                   Select-Object -First 5
        
        if ($topUsers) {
            Write-Host "`n=== En Aktif Kullanıcılar ===" -ForegroundColor Yellow
            foreach ($user in $topUsers) {
                Write-Host "- $($user.Name): $($user.Count) giriş" -ForegroundColor White
            }
        }
        
        if ($OutputPath) {
            $sortedData | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
            Write-Host "`nVeriler şu dosyaya kaydedildi: $OutputPath" -ForegroundColor Green
        }
        
        $sortedData | Out-GridView -Title "RDP Giriş Kayıtları - Son $Days Gün"
        
    } else {
        Write-Warning "Son $Days gün içinde RDP giriş kaydı bulunamadı."
    }
    
} catch {
    Write-Error "Hata oluştu: $($_.Exception.Message)"
    Write-Host "Muhtemel sebepler:" -ForegroundColor Yellow
    Write-Host "1. Yönetici yetkisi gerekiyor" -ForegroundColor White
    Write-Host "2. Event log servisi çalışmıyor" -ForegroundColor White
    Write-Host "3. RDP servisi etkin değil" -ForegroundColor White
}

# Örnek kullanım:
# .\script.ps1                                    # Varsayılan 60 gün
# .\script.ps1 -Days 30                          # Son 30 gün
# .\script.ps1 -Days 7 -OutputPath "rdp.csv"    # 7 gün + CSV dosyasına kaydet
# .\script.ps1 -ShowDisconnects                  # Çıkış kayıtlarını da göster
