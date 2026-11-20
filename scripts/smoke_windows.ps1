# Pre-release smoke test on Windows (MSVC). Mirrors smoke_unix.sh.
#
#   .\smoke_windows.ps1 -Ref latest [-Variants default,hipo,hipo-shared,hipo-vcpkg,hipo-vcpkg-clang,gpu]
#   -Ref: any commit of ERGO-Code/HiGHS: a branch, a tag, a SHA on any branch, or pull/<n>/head.
#
# hipo builds OpenBLAS in-tree (BUILD_OPENBLAS=ON) with clang-cl and
# HIGHS_OPENBLAS_REQUIRE_OPTIMIZED=ON, as release-cpack and the highspy-extras wheels do
# (needs clang-cl + ninja on PATH; configure fails rather than using generic kernels).
# hipo-shared: same with BUILD_SHARED_LIBS=ON (OpenBLAS linked statically into highs.dll).
# hipo-vcpkg needs:  vcpkg install openblas[threads]:x64-windows-static
# hipo-vcpkg-clang: OpenBLAS + zlib built with clang-cl by vcpkg, using the triplet documented in
#   docs/src/installation.md ("Windows: OpenBLAS from vcpkg, built with clang-cl"; x64, dynamic, all ports),
#   written by HiGHS' .github/scripts/vcpkg_clang_cl_triplet.py and installed into $Work\vcpkg-clang-installed
#   (does not touch $Vcpkg\installed). First run builds OpenBLAS, ~15 min.
# Every hipo variant also fails if HiPO hands an LP over to IPX (non-thread-safe OpenBLAS).
# gpu needs the CUDA toolkit (CUPDLP_GPU=ON).
# Logs and summary go to $env:USERPROFILE\release-smoke\results\<sha>\. Never pushes or commits.

param(
  [Parameter(Mandatory)] [string] $Ref,
  [string[]] $Variants = @("default", "hipo"),
  [string] $Work = "$env:USERPROFILE\release-smoke",
  [string] $Vcpkg = "C:\Users\galab\code\repos\vcpkg"
)
$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Force $Work | Out-Null
Set-Location $Work
if (-not (Test-Path HiGHS)) { git clone -q https://github.com/ERGO-Code/HiGHS.git }
Set-Location HiGHS
git fetch -q --tags origin
# Any commit works: a branch, a tag, a SHA on any branch, or pull/<n>/head (fetched on demand).
git checkout -q --detach "origin/$Ref" 2>$null
if ($LASTEXITCODE -ne 0) { git checkout -q --detach $Ref 2>$null }
if ($LASTEXITCODE -ne 0) { git fetch -q origin $Ref; if ($LASTEXITCODE -eq 0) { git checkout -q --detach FETCH_HEAD } }
if ($LASTEXITCODE -ne 0) { "unknown ref $Ref"; exit 1 }
$sha = git rev-parse HEAD
$out = "$Work\results\$sha"; New-Item -ItemType Directory -Force $out | Out-Null
$summary = "$out\summary.txt"
# Keep an earlier run's summary on the same SHA (e.g. other variants).
if (Test-Path $summary) { Move-Item $summary "$out\summary-$((Get-Item $summary).LastWriteTime.ToString('yyyyMMddTHHmmss')).txt" }
"ref $Ref sha $sha host $env:COMPUTERNAME $(Get-Date -Format o)" | Tee-Object $summary
$inst = "check\instances"

function Pass($m) { "PASS $m" | Tee-Object -Append $summary }
function Fail($m) { "FAIL $m" | Tee-Object -Append $summary }
# First capture group of the first matching line, or $null (MIP logs have no LP-style lines).
function Capture($text, $pattern) {
  $m = $text | Select-String $pattern | Select-Object -First 1
  if ($m) { $m.Matches[0].Groups[1].Value.Trim() }
}

function Solve($bin, $v, $file, [double]$exp, [double]$tol, [string[]]$opts) {
  $optsFile = "$out\$v.opts"; $opts | Set-Content $optsFile
  $log = "$out\$v-$([IO.Path]::GetFileNameWithoutExtension($file))-$(($opts -join '_') -replace '=','-').log"
  & $bin --options_file $optsFile "$inst\$file" *> $log
  $text = Get-Content $log
  $st = Capture $text "Model status\s*:\s*(.*)"
  if (-not $st) { $st = Capture $text "^  Status\s+(\S+)" }
  $obj = Capture $text "Objective value\s*:\s*(\S+)"
  if (-not $obj) { $obj = Capture $text "^  Primal bound\s+(\S+)" }
  # A silent fallback to another solver must not pass.
  if ($opts -contains "solver=hipo" -and -not ($text | Select-String "Running HiPO")) { $st = "no-HiPO-in-log" }
  # With a non-thread-safe OpenBLAS HiPO gets wrong results and hands over to IPX.
  if ($opts -contains "solver=hipo" -and ($text | Select-String "IPX iterations:\s+[1-9]")) { $st = "HiPO-handed-over-to-IPX" }
  if ($opts -contains "solver=ipx" -and -not ($text | Select-String "IPX")) { $st = "no-IPX-in-log" }
  $ok = $st -eq "Optimal" -and $obj -and ([math]::Abs([double]$obj - $exp) -le $tol * [math]::Max(1, [math]::Abs($exp)))
  if ($ok) { Pass "$v $file $opts obj=$obj" } else { Fail "$v $file $opts status='$st' obj='$obj' (expected $exp) log=$log" }
}

foreach ($v in $Variants) {
  $b = "build-$v"; $flags = @("-DALL_TESTS=ON")
  # (`continue` inside a switch only leaves the switch, so check first.)
  if ($v -notin @("default", "hipo", "hipo-shared", "hipo-vcpkg", "hipo-vcpkg-clang", "gpu")) { Fail "unknown variant $v"; continue }
  if ($v -in @("hipo", "hipo-shared")) { $flags += @("-DHIPO=ON", "-DBUILD_OPENBLAS=ON", "-DHIGHS_OPENBLAS_REQUIRE_OPTIMIZED=ON") }
  if ($v -eq "hipo-shared") { $flags += "-DBUILD_SHARED_LIBS=ON" }
  if ($v -eq "hipo-vcpkg-clang") {
    $trip = "$Work\vcpkg-clang-triplets"; $vinst = "$Work\vcpkg-clang-installed"
    python -I .github\scripts\vcpkg_clang_cl_triplet.py x64 dynamic all-ports $trip *> "$out\$v-triplet.log"
    if ($LASTEXITCODE) { Fail "$v triplet from docs log=$out\$v-triplet.log"; continue }
    & "$Vcpkg\vcpkg.exe" install "openblas[threads]:x64-windows-clang" "zlib:x64-windows-clang" --overlay-triplets=$trip `
      --host-triplet=x64-windows-clang --x-install-root=$vinst *> "$out\$v-vcpkg.log"
    if ($LASTEXITCODE) { Fail "$v vcpkg install log=$out\$v-vcpkg.log"; continue }
    # vcpkg keeps each port's configure output, which names the compiler.
    foreach ($port in "openblas", "zlib") {
      $cl = Get-ChildItem "$Vcpkg\buildtrees\$port" -Filter "config-x64-windows-clang-out.log" -ErrorAction SilentlyContinue | Select-Object -First 1
      $id = if ($cl) { Capture (Get-Content $cl.FullName) "The C compiler identification is (.*)$" }
      if ($id -match "^Clang") { Pass "$v $port built with $id" } else { Fail "$v $port compiler '$id' (expected clang-cl)" }
    }
    $flags += @("-DHIPO=ON", "-DCMAKE_TOOLCHAIN_FILE=$Vcpkg\scripts\buildsystems\vcpkg.cmake", "-DVCPKG_TARGET_TRIPLET=x64-windows-clang",
                "-DVCPKG_OVERLAY_TRIPLETS=$trip", "-DVCPKG_INSTALLED_DIR=$vinst", "-DVCPKG_MANIFEST_MODE=OFF")
  }
  if ($v -eq "hipo-vcpkg") { $flags += @("-DHIPO=ON", "-DCMAKE_TOOLCHAIN_FILE=$Vcpkg\scripts\buildsystems\vcpkg.cmake", "-DVCPKG_TARGET_TRIPLET=x64-windows-static", "-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded") }
  if ($v -eq "gpu")  { $flags += @("-DCUPDLP_GPU=ON") }
  if (Test-Path $b) { Remove-Item -Recurse -Force $b }
  cmake -S . -B $b @flags *> "$out\$v-configure.log"; if ($LASTEXITCODE) { Fail "$v configure log=$out\$v-configure.log"; continue }
  $cfg = Get-Content "$out\$v-configure.log"
  if ($v -in @("hipo", "hipo-shared")) {
    if ($cfg | Select-String "Building OpenBLAS .* with .*clang-cl") { Pass "$v OpenBLAS built with clang-cl" } else { Fail "$v OpenBLAS not built with clang-cl" }
  }
  if ($v -eq "hipo-vcpkg-clang") {
    if ($cfg | Select-String "OpenBLAS CMake config path: .*x64-windows-clang") { Pass "$v uses vcpkg x64-windows-clang OpenBLAS" } else { Fail "$v did not use OpenBLAS from x64-windows-clang" }
  }
  cmake --build $b --parallel --config Release *> "$out\$v-build.log"; if ($LASTEXITCODE) { Fail "$v build"; continue }
  # In-tree OpenBLAS (hipo) emits ~1.6k warnings; count them apart so HiGHS ones stay visible.
  $warn = Select-String 'warning' "$out\$v-build.log"; $blas = @($warn | Where-Object Line -match 'openblas').Count
  "INFO $v compiler warnings: $(@($warn).Count - $blas) (+ $blas from OpenBLAS)" | Tee-Object -Append $summary
  if (Select-String -Path "$out\$v-build.log" -Pattern "warning LNK4098" -Quiet) { Fail "$v crt-mismatch (LNK4098: mixed /MD and /MT runtimes)" } else { Pass "$v crt-consistent" }
  Push-Location $b; ctest -C Release --parallel 8 --timeout 1200 --output-on-failure *> "$out\$v-ctest.log"; $rc = $LASTEXITCODE; Pop-Location
  if ($rc) { Fail "$v ctest" } else { Pass "$v ctest" }
  $bin = (Get-ChildItem -Recurse $b -Filter highs.exe | Where-Object FullName -match "Release" | Select-Object -First 1).FullName
  if (-not $bin) { Fail "$v highs.exe not found"; continue }
  $lp = @("simplex", "ipx", "pdlp"); $mip = @("simplex", "ipx")
  if ($v -like "hipo*") { $lp += "hipo"; $mip += "hipo" }
  if ($v -eq "hipo-shared" -and -not (Test-Path (Join-Path (Split-Path $bin) "highs.dll"))) { Fail "$v highs.dll not next to highs.exe" }
  if ($v -eq "gpu") { $lp = @("pdlp") }
  foreach ($s in $lp) {
    $tol = if ($s -eq "pdlp") { 1e-4 } else { 1e-6 }
    Solve $bin $v "afiro.mps" -464.7531428571 $tol @("solver=$s")
    if ($s -ne "pdlp") { Solve $bin $v "25fv47.mps" 5501.845888 1e-6 @("solver=$s") }
  }
  foreach ($s in $mip) {
    $ipm = if ($s -eq "simplex") { "choose" } else { $s }
    Solve $bin $v "egout.mps" 568.1007 1e-6 @("mip_lp_solver=$s", "mip_ipm_solver=$ipm")
    Solve $bin $v "flugpl.mps" 1201500 1e-6 @("mip_lp_solver=$s", "mip_ipm_solver=$ipm")
  }
}
"---"
$f = Select-String "^FAIL" $summary
if ($f) { $f; exit 1 } else { "ALL PASS ($summary)" }
