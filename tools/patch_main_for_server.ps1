# Makes the app read the saved server address when it starts.
# Run from the hamkalaam folder:  powershell -ExecutionPolicy Bypass -File .\tools\patch_main_for_server.ps1
$f = "lib\main.dart"
if (-not (Test-Path $f)) { Write-Host "Cannot find $f - run this from the hamkalaam folder."; exit 1 }
$enc = New-Object System.Text.UTF8Encoding($false)
$t = [System.IO.File]::ReadAllText((Resolve-Path $f), $enc)
if ($t -match "AppConfig\.load") { Write-Host "main.dart is already patched."; exit 0 }

$import = "import 'package:hamkalaam/config/app_config.dart';"
$init = "  WidgetsFlutterBinding.ensureInitialized();`r`n  await AppConfig.load();"

if ($t -match "(?m)^(Future<void>|void)\s+main\(\)\s*async\s*\{") {
  $t = [regex]::Replace($t, "(?m)^((?:Future<void>|void)\s+main\(\)\s*async\s*\{)", "`$1`r`n$init", 1)
} elseif ($t -match "(?m)^void\s+main\(\)\s*\{") {
  $t = [regex]::Replace($t, "(?m)^void\s+main\(\)\s*\{", "Future<void> main() async {`r`n$init", 1)
} else {
  Write-Host "Could not find main() in lib\main.dart - send me that file."; exit 2
}
$t = [regex]::Replace($t, "(?m)^(import [^\r\n]+;)", "`$1`r`n$import", 1)
[System.IO.File]::WriteAllText((Resolve-Path $f), $t, $enc)
Write-Host "main.dart patched."
Select-String -Path $f -Pattern "AppConfig|void main|Future<void> main|ensureInitialized"
