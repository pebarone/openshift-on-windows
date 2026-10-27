$ErrorActionPreference = "Stop"
Write-Host "stopping kind cluster container (data is kept)"
docker stop openshift-local-control-plane | Out-Host
Write-Host "stopped. start again with .\scripts\03-start.ps1"
