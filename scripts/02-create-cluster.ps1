$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Bin = Join-Path $env:USERPROFILE ".local\bin"
$env:PATH = "$Bin;$env:PATH"

$ClusterName = "openshift-local"
$OlmVersion = "v0.46.0"
$IngressUrl = "https://kind.sigs.k8s.io/examples/ingress/deploy-ingress-nginx.yaml"
$OlmCrdsUrl = "https://github.com/operator-framework/operator-lifecycle-manager/releases/download/$OlmVersion/crds.yaml"
$OlmUrl = "https://github.com/operator-framework/operator-lifecycle-manager/releases/download/$OlmVersion/olm.yaml"

function Invoke-Oc {
    & oc.exe @args
    if ($LASTEXITCODE -ne 0) { throw "oc failed: $args" }
}

function Invoke-Kind {
    & kind.exe @args
    if ($LASTEXITCODE -ne 0) { throw "kind failed: $args" }
}

if (-not (Get-Command oc.exe -ErrorAction SilentlyContinue) -or -not (Get-Command kind.exe -ErrorAction SilentlyContinue)) {
    throw "oc/kind missing. run .\scripts\01-install-tools.ps1 first"
}

Write-Host "checking docker"
docker info --format "Server={{.ServerVersion}}" | Out-Host

$prev = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$existing = @(& kind.exe get clusters 2>$null)
$ErrorActionPreference = $prev
if ($existing -contains $ClusterName) {
    Write-Host "cluster $ClusterName already exists"
} else {
    Write-Host "creating kind cluster $ClusterName"
    Invoke-Kind create cluster --config (Join-Path $Root "cluster\kind-config.yaml")
}

Invoke-Kind export kubeconfig --name $ClusterName
$kubeDir = Join-Path $Root ".kube"
New-Item -ItemType Directory -Force -Path $kubeDir, (Join-Path $env:USERPROFILE ".kube") | Out-Null
Copy-Item (Join-Path $env:USERPROFILE ".kube\config") (Join-Path $kubeDir "config") -Force

Write-Host "waiting for API"
Invoke-Oc wait --for=condition=Ready node --all --timeout=180s

Write-Host "installing ingress-nginx"
Invoke-Oc apply -f $IngressUrl
Invoke-Oc wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s

Write-Host "installing OLM $OlmVersion"
Invoke-Oc apply --server-side --force-conflicts -f $OlmCrdsUrl
Start-Sleep -Seconds 5
Invoke-Oc apply --server-side --force-conflicts -f $OlmUrl
try {
    Invoke-Oc wait --namespace olm --for=condition=ready pod --all --timeout=300s
} catch {
    Write-Host "OLM pods still settling; continuing"
}

Write-Host "deploying sample app"
Invoke-Oc apply -f (Join-Path $Root "cluster\sample-app.yaml")
Invoke-Oc wait --namespace demo --for=condition=available deployment/hello --timeout=180s

Write-Host ""
Write-Host "cluster ready"
Invoke-Oc get nodes -o wide
Write-Host ""
Invoke-Oc get pods -A
Write-Host ""
Write-Host "sample app: http://hello.localtest.me/"
Write-Host "kubeconfig: $env:USERPROFILE\.kube\config"

& (Join-Path $Root "scripts\_install-console.ps1")
& (Join-Path $Root "scripts\_install-routes.ps1")

Write-Host ""
Write-Host "console: http://console.localtest.me/"
Write-Host "next: .\scripts\03-start.ps1 (after reboot) or .\scripts\04-new-project.ps1 meuprojeto"
