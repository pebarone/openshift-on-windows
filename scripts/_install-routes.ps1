$ErrorActionPreference = "Stop"
$env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

function Invoke-Oc {
    & oc.exe @args
    if ($LASTEXITCODE -ne 0) { throw "oc failed: $args" }
}

Write-Host "installing OpenShift Route API"
Invoke-Oc apply -f (Join-Path $Root "cluster\route-crd.yaml")
Invoke-Oc apply -f (Join-Path $Root "cluster\route-sync.yaml")

Write-Host "loading route-sync controller"
$cm = Join-Path $Root "cluster\route-sync.py"
oc.exe create configmap route-sync -n openshift-ingress --from-file=route-sync.py=$cm --dry-run=client -o yaml | oc.exe apply -f -
if ($LASTEXITCODE -ne 0) { throw "configmap apply failed" }

$ErrorActionPreference = "Continue"
oc.exe rollout restart deployment/route-sync -n openshift-ingress 2>$null | Out-Host
$ErrorActionPreference = "Stop"
Invoke-Oc rollout status deployment/route-sync -n openshift-ingress --timeout=180s

Write-Host "creating demo and console routes"
Invoke-Oc apply -f (Join-Path $Root "cluster\demo-route.yaml")

Write-Host "waiting for routes to be admitted"
$deadline = (Get-Date).AddMinutes(2)
do {
    $hello = oc.exe get route hello -n demo -o jsonpath="{.status.ingress[0].host}" 2>$null
    if ($hello) { break }
    Start-Sleep -Seconds 3
} while ((Get-Date) -lt $deadline)

Invoke-Oc get route -A
Write-Host "Route domain: *.apps.localtest.me"
