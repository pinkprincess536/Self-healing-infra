param(
    [int]$PollSeconds = 10,
    [int]$RecoveryTimeoutSeconds = 240,
    [int]$ResolutionTimeoutSeconds = 120,
    [string]$EvidenceFile = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not $EvidenceFile) {
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
    $EvidenceFile = Join-Path $root "journal\evidence\day6-$timestamp.log"
}

$evidenceDirectory = Split-Path -Parent $EvidenceFile
New-Item -ItemType Directory -Force -Path $evidenceDirectory | Out-Null

$prometheusUrl = "http://127.0.0.1:9090"
$alertmanagerUrl = "http://127.0.0.1:9093"
$healthUrl = "http://127.0.0.1:8083/health"
$startedAt = (Get-Date).ToUniversalTime()
$originalRestartPolicy = (docker inspect -f "{{.HostConfig.RestartPolicy.Name}}" nginx).Trim()
$demoPassed = $false

function Write-Evidence([string]$Message = "") {
    Write-Host $Message
    Add-Content -Path $EvidenceFile -Value $Message
}

function Get-MetricValue {
    $response = Invoke-RestMethod "$prometheusUrl/api/v1/query?query=nginx_up"
    if (@($response.data.result).Count -eq 0) { return "missing" }
    return [string]$response.data.result[0].value[1]
}

function Get-RuleState {
    $response = Invoke-RestMethod "$prometheusUrl/api/v1/rules"
    foreach ($group in $response.data.groups) {
        foreach ($rule in $group.rules) {
            if ($rule.name -eq "NginxDown") { return [string]$rule.state }
        }
    }
    return "missing"
}

function Get-PrometheusAlertCount {
    $response = Invoke-RestMethod "$prometheusUrl/api/v1/alerts"
    return @($response.data.alerts).Count
}

function Get-AlertmanagerAlertCount {
    $response = Invoke-RestMethod "$alertmanagerUrl/api/v2/alerts"
    return @($response).Count
}

function Get-NginxRunning {
    return (docker inspect -f "{{.State.Running}}" nginx 2>$null).Trim()
}

function Test-NginxHealth {
    try {
        & curl.exe -fsS --max-time 3 $healthUrl *> $null
        return $LASTEXITCODE -eq 0
    }
    catch {
        # A failed request is the expected observation immediately after the
        # controlled NGINX kill; report false instead of aborting the script.
        return $false
    }
}

function Get-WebhookLogs {
    # Docker writes container logs to stderr even when `docker logs` succeeds.
    # Temporarily avoid turning those normal log lines into PowerShell errors.
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $lines = @(docker logs recovery-webhook --since $startedAt.ToString("o") 2>&1)
        return (($lines | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
}

try {
    Write-Evidence "=== DAY 6 SELF-HEALING DEMO ==="
    Write-Evidence "started_at=$($startedAt.ToString('o'))"
    Write-Evidence "host=$env:COMPUTERNAME"
    Write-Evidence "original_restart_policy=$originalRestartPolicy"
    Write-Evidence

    Write-Evidence "=== PHASE 1: HEALTHY BASELINE ==="
    docker compose ps | ForEach-Object { Write-Evidence $_ }
    & curl.exe -fsS $healthUrl *> $null
    & curl.exe -fsS "$prometheusUrl/-/ready" *> $null
    & curl.exe -fsS "$alertmanagerUrl/-/ready" *> $null

    $metric = Get-MetricValue
    $rule = Get-RuleState
    $prometheusAlerts = Get-PrometheusAlertCount
    $alertmanagerAlerts = Get-AlertmanagerAlertCount
    Write-Evidence "nginx_up=$metric rule=$rule prometheus_alerts=$prometheusAlerts alertmanager_alerts=$alertmanagerAlerts"

    if ($metric -ne "1" -or $rule -ne "inactive" -or $prometheusAlerts -ne 0) {
        throw "Baseline is not clean; refusing to run a destructive demo."
    }

    Write-Evidence
    Write-Evidence "=== PHASE 2: CONTROLLED FAILURE ==="
    docker update --restart=no nginx | Out-Null
    docker kill nginx | Out-Null
    Start-Sleep -Seconds 2
    Write-Evidence "nginx_running=$(Get-NginxRunning) health=$(if (Test-NginxHealth) {'ok'} else {'down'})"

    if ((Get-NginxRunning) -ne "false") {
        throw "NGINX did not stop as expected."
    }

    Write-Evidence
    Write-Evidence "=== PHASE 3: DETECTION AND AUTOMATED RECOVERY ==="
    $recovered = $false
    $sawMetricZero = $false
    $sawPending = $false
    $sawFiring = $false

    for ($elapsed = 0; $elapsed -le $RecoveryTimeoutSeconds; $elapsed += $PollSeconds) {
        if ($elapsed -gt 0) { Start-Sleep -Seconds $PollSeconds }

        $metric = Get-MetricValue
        $rule = Get-RuleState
        $running = Get-NginxRunning
        $health = if (Test-NginxHealth) { "ok" } else { "down" }
        Write-Evidence ("t={0,3}s nginx_up={1} alert={2,-8} running={3} health={4}" -f $elapsed, $metric, $rule, $running, $health)

        if ($metric -eq "0") { $sawMetricZero = $true }
        if ($rule -eq "pending") { $sawPending = $true }
        if ($rule -eq "firing") { $sawFiring = $true }

        if ($running -eq "true" -and $health -eq "ok" -and $sawFiring) {
            $recovered = $true
            break
        }
    }

    if (-not $recovered) {
        throw "Automatic recovery was not verified within $RecoveryTimeoutSeconds seconds."
    }
    if (-not $sawMetricZero -or -not $sawPending -or -not $sawFiring) {
        throw "The complete metric/alert lifecycle was not observed."
    }

    Write-Evidence
    Write-Evidence "=== PHASE 4: DEEP VALIDATION AND ALERT RESOLUTION ==="
    $resolved = $false
    for ($elapsed = 0; $elapsed -le $ResolutionTimeoutSeconds; $elapsed += $PollSeconds) {
        if ($elapsed -gt 0) { Start-Sleep -Seconds $PollSeconds }

        $metric = Get-MetricValue
        $rule = Get-RuleState
        $prometheusAlerts = Get-PrometheusAlertCount
        $alertmanagerAlerts = Get-AlertmanagerAlertCount
        $health = if (Test-NginxHealth) { "ok" } else { "down" }
        Write-Evidence ("resolution_t={0,3}s nginx_up={1} alert={2,-8} prometheus_alerts={3} alertmanager_alerts={4} health={5}" -f $elapsed, $metric, $rule, $prometheusAlerts, $alertmanagerAlerts, $health)

        if ($metric -eq "1" -and $rule -eq "inactive" -and $prometheusAlerts -eq 0 -and $alertmanagerAlerts -eq 0 -and $health -eq "ok") {
            $resolved = $true
            break
        }
    }

    if (-not $resolved) {
        throw "Recovery occurred, but alert resolution was not verified within $ResolutionTimeoutSeconds seconds."
    }

    $webhookLogs = ""
    for ($attempt = 1; $attempt -le 7; $attempt++) {
        $webhookLogs = Get-WebhookLogs
        if ($webhookLogs -match "alert received: status=resolved") { break }
        Start-Sleep -Seconds 10
    }

    $importantLogs = $webhookLogs -split "`r?`n" | Select-String "alert received|running recovery|recovery succeeded|alert resolved"
    $importantLogs | ForEach-Object { Write-Evidence $_.Line }

    if (-not ($webhookLogs -match "alert received: status=firing")) {
        throw "Webhook firing-notification evidence is missing."
    }
    if (-not ($webhookLogs -match "recovery succeeded and passed validation")) {
        throw "Webhook recovery-success evidence is missing."
    }
    if (-not ($webhookLogs -match "alert received: status=resolved")) {
        throw "Webhook resolved-notification evidence is missing."
    }

    Write-Evidence
    Write-Evidence "=== RESULT: PASS ==="
    Write-Evidence "Observed nginx_up 1->0->1, alert inactive->pending->firing->inactive, authenticated Ansible recovery, HTTP health, and resolved notification."
    $demoPassed = $true
}
finally {
    Write-Evidence
    Write-Evidence "=== CLEANUP ==="
    docker update --restart=unless-stopped nginx *> $null

    if ((Get-NginxRunning) -ne "true") {
        Write-Evidence "Automated recovery did not leave NGINX running; starting it manually."
        docker start nginx *> $null
    }

    for ($attempt = 1; $attempt -le 12; $attempt++) {
        if (Test-NginxHealth) { break }
        Start-Sleep -Seconds 1
    }

    Write-Evidence "restored_restart_policy=$((docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' nginx).Trim())"
    Write-Evidence "cleanup_health=$(if (Test-NginxHealth) {'ok'} else {'failed'})"
    Write-Evidence "evidence_file=$EvidenceFile"
}

if (-not $demoPassed) {
    exit 1
}
