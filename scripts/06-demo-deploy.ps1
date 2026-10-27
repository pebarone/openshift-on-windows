$ErrorActionPreference = "Stop"
$env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

Write-Host "== 1. project (oc new-project equivalent, restricted SCC) =="
& (Join-Path $Root "scripts\04-new-project.ps1") -Name complete-demo

Write-Host "`n== 2. apply Deployment + Service =="
oc.exe apply -f (Join-Path $Root "cluster\complete-app.yaml")
if ($LASTEXITCODE -ne 0) { throw "apply app failed" }

Write-Host "`n== 3. oc expose svc (creates a Route) =="
$ErrorActionPreference = "Continue"
oc.exe expose svc/web -n complete-demo --hostname=web-complete-demo.apps.localtest.me 2>&1 | Out-Host
$ErrorActionPreference = "Stop"
if ($LASTEXITCODE -ne 0) {
    oc.exe get route web -n complete-demo | Out-Host
}

Write-Host "`n== 4. wait for rollout and Route =="
oc.exe rollout status deployment/web -n complete-demo --timeout=180s
$deadline = (Get-Date).AddMinutes(2)
do {
    $admitted = oc.exe get route web -n complete-demo -o jsonpath="{.status.ingress[0].conditions[?(@.type=='Admitted')].status}" 2>$null
    if ($admitted -eq "True") { break }
    Start-Sleep -Seconds 3
} while ((Get-Date) -lt $deadline)

Write-Host "`n== 5. resources =="
oc.exe get all,route,ingress -n complete-demo

Write-Host "`n== 6. HTTP via Route =="
$code = curl.exe -sS -o NUL -w "%{http_code}" --max-time 20 http://web-complete-demo.apps.localtest.me/
Write-Host "http://web-complete-demo.apps.localtest.me/ -> $code"

if ($code -ne "200") {
    throw "complete deploy did not return HTTP 200"
}

Write-Host "`nDeploy completo ok."
Write-Host "Console: http://console.localtest.me/  (namespace complete-demo)"
Write-Host "Route:   http://web-complete-demo.apps.localtest.me/"
