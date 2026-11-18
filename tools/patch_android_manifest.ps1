# Run from the hamkalaam folder:  .\tools\patch_android_manifest.ps1
$p = "android\app\src\main\AndroidManifest.xml"
if (-not (Test-Path $p)) { Write-Host "Cannot find $p - are you in the hamkalaam folder?"; exit 1 }
$t = Get-Content $p -Raw
$changed = $false
foreach ($perm in @("android.permission.INTERNET","android.permission.CAMERA","android.permission.MODIFY_AUDIO_SETTINGS")) {
  if ($t -notmatch [regex]::Escape($perm)) {
    $t = $t -replace "(<manifest[^>]*>)", "`$1`r`n    <uses-permission android:name=`"$perm`"/>"
    $changed = $true
  }
}
if ($t -notmatch "usesCleartextTraffic") {
  $t = $t -replace "<application", "<application android:usesCleartextTraffic=`"true`""
  $changed = $true
}
if ($changed) { Set-Content -Path $p -Value $t -Encoding UTF8; Write-Host "Manifest updated." } else { Write-Host "Manifest already OK." }
