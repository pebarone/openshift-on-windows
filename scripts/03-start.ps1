$ErrorActionPreference = "Stop"
$env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"

Write-Host "starting docker container for kind cluster"
docker start openshift-local-control-plane | Out-Host
kind.exe export kubeconfig --name openshift-local
oc.exe wait --for=condition=Ready node --all --timeout=180s
oc.exe get nodes
Write-Host "cluster is up"
Write-Host "console: http://console.localtest.me/"
Write-Host "sample:  http://hello.localtest.me/"
