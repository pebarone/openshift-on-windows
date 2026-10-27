param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Name
)

$ErrorActionPreference = "Stop"
$env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"

# ROSA equivalent of: oc adm policy add-scc-to-user anyuid -z default
oc label namespace $Name `
    "pod-security.kubernetes.io/enforce=baseline" `
    "pod-security.kubernetes.io/audit=baseline" `
    "pod-security.kubernetes.io/warn=baseline" `
    --overwrite | Out-Host

Write-Host "namespace $Name can run images as a numeric UID (anyuid/baseline)."
