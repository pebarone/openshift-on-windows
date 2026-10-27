$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Bin = Join-Path $env:USERPROFILE ".local\bin"
$Cache = Join-Path $Root ".cache\downloads"
New-Item -ItemType Directory -Force -Path $Bin, $Cache | Out-Null

$OcUrl = "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-windows.zip"
$OcSha = "c1eb272133e5c44d1de88c3ce1df9cd7ea4d9a2f3897bc9e974ba480d80244b8"
$KindUrl = "https://github.com/kubernetes-sigs/kind/releases/download/v0.33.0/kind-windows-amd64"
$KindSha = "4b22adaa135368c5a465d56bbd8e520cbea87272a06ca00b6078e7b81515c9fc"

function Get-FileSha256([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
}

function Download-Verified([string]$Url, [string]$Dest, [string]$Sha) {
    if ((Test-Path $Dest) -and ((Get-FileSha256 $Dest) -eq $Sha)) {
        Write-Host "already present: $(Split-Path $Dest -Leaf)"
        return
    }
    Write-Host "downloading $Url"
    $partial = "$Dest.partial"
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $partial
    $got = Get-FileSha256 $partial
    if ($got -ne $Sha) {
        Remove-Item $partial -Force
        throw "checksum mismatch for $Dest expected $Sha got $got"
    }
    Move-Item $partial $Dest -Force
    Write-Host "checksum ok: $(Split-Path $Dest -Leaf)"
}

Download-Verified $OcUrl (Join-Path $Cache "openshift-client-windows.zip") $OcSha
Download-Verified $KindUrl (Join-Path $Cache "kind-windows-amd64") $KindSha

$tmp = Join-Path $env:TEMP ("oc-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
Expand-Archive -Path (Join-Path $Cache "openshift-client-windows.zip") -DestinationPath $tmp -Force
Copy-Item (Join-Path $tmp "oc.exe") (Join-Path $Bin "oc.exe") -Force
Remove-Item $tmp -Recurse -Force
Copy-Item (Join-Path $Cache "kind-windows-amd64") (Join-Path $Bin "kind.exe") -Force

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$Bin*") {
    [Environment]::SetEnvironmentVariable("Path", "$Bin;$userPath", "User")
    Write-Host "added $Bin to your user PATH (open a new terminal to pick it up)"
}
$env:PATH = "$Bin;$env:PATH"

Write-Host ""
& (Join-Path $Bin "oc.exe") version --client
& (Join-Path $Bin "kind.exe") version
Write-Host ""
Write-Host "installed oc.exe and kind.exe in $Bin"
Write-Host "next: .\scripts\02-create-cluster.ps1"
