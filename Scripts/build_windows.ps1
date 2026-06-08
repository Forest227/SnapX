param(
    [ValidateSet("x86", "x64", "arm64")]
    [string[]]$Architectures = @("x86", "x64", "arm64"),
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Project = Join-Path $ProjectRoot "Windows/SnapX.Windows/SnapX.Windows.csproj"
$OutputRoot = Join-Path $ProjectRoot "Build/Windows"

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw "dotnet SDK is required. Install .NET 8 SDK and Windows App SDK workload support on Windows."
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

foreach ($Architecture in $Architectures) {
    $Runtime = "win-$Architecture"
    $OutDir = Join-Path $OutputRoot $Runtime

    dotnet publish $Project `
        -c $Configuration `
        -r $Runtime `
        -p:GenerateAppxPackageOnBuild=true `
        -p:AppxBundle=Never `
        -p:AppxPackageDir="$OutDir/" `
        -p:AppxPackageSigningEnabled=false
}

Write-Host "Windows packages written to $OutputRoot"
