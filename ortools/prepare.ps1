# Check out OR-Tools (latest release tag) and HiGHS (latest branch) side by
# side, ready to build OR-Tools against that HiGHS with CMake or Bazel.
# PowerShell twin of prepare.sh; see there for details.
#
#   .\ortools\prepare.ps1 [-WorkDir <dir>] [-OrtoolsRef <ref>] [-HighsRef <ref>]
param(
  [string]$WorkDir = (Join-Path $PWD 'ortools-work'),
  [string]$OrtoolsRef = $env:ORTOOLS_REF,
  [string]$HighsRef = $(if ($env:HIGHS_REF) { $env:HIGHS_REF } else { 'latest' })
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$OrtoolsUrl = 'https://github.com/google/or-tools.git'
$HighsUrl = 'https://github.com/ERGO-Code/HiGHS.git'
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$WorkDir = (Resolve-Path $WorkDir).Path

if (-not $OrtoolsRef) {
  # Release tags only: skip release candidates and anything non-numeric.
  $OrtoolsRef = git ls-remote --tags --refs $OrtoolsUrl 'v*' |
    ForEach-Object { ($_ -split 'refs/tags/')[1] } |
    Where-Object { $_ -match '^v\d+\.\d+(\.\d+)?$' } |
    Sort-Object { [version]$_.Substring(1) } |
    Select-Object -Last 1
  if (-not $OrtoolsRef) { throw 'could not resolve an OR-Tools release tag' }
}

function Checkout($Url, $Ref, $Dir) {
  if (-not (Test-Path (Join-Path $Dir '.git'))) {
    git init -q $Dir
    git -C $Dir remote add origin $Url
  }
  git -C $Dir fetch -q --depth 1 origin $Ref
  git -C $Dir checkout -q -f FETCH_HEAD
  git -C $Dir clean -q -fdx -e build/ -e 'bazel-*'
}

$Ortools = Join-Path $WorkDir 'or-tools'
$Highs = Join-Path $WorkDir 'HiGHS'
Checkout $OrtoolsUrl $OrtoolsRef $Ortools
Checkout $HighsUrl $HighsRef $Highs

$OrtoolsSha = git -C $Ortools rev-parse HEAD
$HighsSha = git -C $Highs rev-parse HEAD
$HighsVersion = (Select-String -Path (Join-Path $Highs 'Version.txt') -Pattern '^HIGHS_(MAJOR|MINOR|PATCH)=(\d+)' |
  ForEach-Object { $_.Matches[0].Groups[2].Value }) -join '.'

# OR-Tools must still fetch HiGHS under the name "highs", otherwise
# FETCHCONTENT_SOURCE_DIR_HIGHS is silently ignored.
$Deps = Get-Content (Join-Path $Ortools 'cmake/dependencies/CMakeLists.txt') -Raw
if ($Deps -notmatch 'FetchContent_Declare\(\s*highs\s') {
  throw "OR-Tools no longer declares FetchContent 'highs'; update prepare.ps1"
}

$HighsPath = $Highs -replace '\\', '/'
Add-Content (Join-Path $Ortools 'MODULE.bazel') @"

# Added by highs-tests/ortools/prepare.ps1: HiGHS $HighsRef ($HighsSha).
local_path_override(
    module_name = "highs",
    path = "$HighsPath",
)
"@
# Flags such as --@rules_cuda//cuda:archs resolve from the root module, so
# OR-Tools needs to see rules_cuda for the GPU build. Same version as HiGHS.
$RulesCuda = Select-String -Path (Join-Path $Highs 'MODULE.bazel') -Pattern '^bazel_dep\(name = "rules_cuda".*\)' |
  Select-Object -First 1
if ($RulesCuda) {
  Add-Content (Join-Path $Ortools 'MODULE.bazel') ($RulesCuda.Line -replace '\)\s*$', ', dev_dependency = True)')
}
$Check = Join-Path $Ortools 'highs_check'
if (Test-Path $Check) { Remove-Item -Recurse -Force $Check }
Copy-Item -Recurse (Join-Path $PSScriptRoot 'highs_check') $Check

"OR-Tools $OrtoolsRef ($OrtoolsSha), HiGHS $HighsRef $HighsVersion ($HighsSha)"
"  OR-Tools: $Ortools"
"  HiGHS:    $Highs"
