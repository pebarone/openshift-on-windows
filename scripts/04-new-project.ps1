param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Name
)

$ErrorActionPreference = "Stop"
$env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"

$existing = oc.exe get namespace $Name --ignore-not-found -o name
if (-not $existing) {
    oc.exe create namespace $Name
    if ($LASTEXITCODE -ne 0) { throw "failed to create namespace $Name" }
}

oc label namespace $Name `
    "pod-security.kubernetes.io/enforce=restricted" `
    "pod-security.kubernetes.io/audit=restricted" `
    "pod-security.kubernetes.io/warn=restricted" `
    "pod-security.kubernetes.io/enforce-version=latest" `
    --overwrite | Out-Host

oc annotate namespace $Name `
    "openshift.io/display-name=$Name" `
    "openshift.io/requester=$env:USERNAME" `
    --overwrite | Out-Host

$ErrorActionPreference = "Continue"
oc create rolebinding "$Name-admin" --clusterrole=admin --user=kubernetes-admin -n $Name 2>$null | Out-Host
$ErrorActionPreference = "Stop"

oc config set-context --current --namespace=$Name | Out-Host
Write-Host "project '$Name' is ready (restricted SCC/PSA)."
Write-Host "root images: .\scripts\05-grant-anyuid.ps1 $Name"
