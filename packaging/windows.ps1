param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = '1.3.0',
    [switch]$Portable,
    [string]$CompilerPath = (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$bundle = Join-Path $root 'build\windows\x64\runner\Release'
$dist = Join-Path $root 'dist'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $visualStudio) { throw 'O toolchain C++ do Visual Studio não foi encontrado.' }
$redistributables = Join-Path $visualStudio 'VC\Redist\MSVC'
$runtime = Get-ChildItem -Path "$redistributables\*\x64\Microsoft.VC*.CRT" -Directory |
    Where-Object { $_.Parent.Parent.Name -match '^\d+\.\d+\.\d+$' } |
    Sort-Object { [version]$_.Parent.Parent.Name } -Descending |
    Select-Object -First 1
if (-not $runtime) { throw 'As DLLs redistribuíveis do Visual C++ não foram encontradas.' }
foreach ($name in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
    Copy-Item -LiteralPath (Join-Path $runtime.FullName $name) -Destination $bundle -Force
}
New-Item -ItemType Directory -Force $dist | Out-Null
if ($Portable) {
    Compress-Archive -Path "$bundle\*" -DestinationPath (Join-Path $dist 'BigEvil-Launcher-windows-x64-portable.zip') -Force
} else {
    & $CompilerPath "/DAppVersion=$Version" (Join-Path $PSScriptRoot 'windows.iss')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
