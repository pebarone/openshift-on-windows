$ErrorActionPreference = "Stop"
$env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"

Write-Host "This deletes the local cluster and all deployed apps."
kind.exe delete cluster --name openshift-local
Write-Host "deleted. recreate with .\scripts\02-create-cluster.ps1"
