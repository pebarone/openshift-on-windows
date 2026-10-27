$ErrorActionPreference = "Stop"
$env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

function Invoke-Oc {
    & oc.exe @args
    if ($LASTEXITCODE -ne 0) { throw "oc failed: $args" }
}

Write-Host "installing metrics-server"
Invoke-Oc apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
$patchFile = Join-Path $Root "cluster\metrics-server-patch.json"
$ErrorActionPreference = "Continue"
& oc.exe patch deployment metrics-server -n kube-system --type=json --patch-file $patchFile
$ErrorActionPreference = "Stop"

Write-Host "installing OpenShift Console (quay.io/openshift/origin-console:4.22)"
Invoke-Oc apply -f (Join-Path $Root "cluster\console.yaml")
Invoke-Oc wait --namespace openshift-console --for=condition=available deployment/console --timeout=300s
Invoke-Oc wait --namespace openshift-console --for=condition=ready pod --selector=app=console --timeout=180s

Write-Host ""
Write-Host "console ready"
Invoke-Oc get pods -n openshift-console
Invoke-Oc get ingress -n openshift-console
Write-Host "Open in the browser: http://console.localtest.me/"
Write-Host "Auth is disabled for local lab use. Bind this only to localhost."
