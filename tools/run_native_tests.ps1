param([string]$Classes='', [string]$Report='android-instrumentation')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$env:JAVA_HOME='C:\Program Files\Microsoft\jdk-17.0.20.8-hotspot'
Push-Location (Join-Path $root 'android')
try {
    & .\gradlew.bat :app:assembleDebug :app:assembleDebugAndroidTest -Pdart-defines=WU9NQV9JTlRFR1JBVElPTl9RQT10cnVl *> (Join-Path $root 'docs/yoma/native-build.log')
    if($LASTEXITCODE) { throw 'Falló la compilación de integración' }
    $sdk=Join-Path $env:LOCALAPPDATA 'Android/Sdk'
    $aapt=Join-Path $sdk 'build-tools/36.0.0/aapt.exe'
    $adb=Join-Path $sdk 'platform-tools/adb.exe'
    $apk=Join-Path $root 'build/app/outputs/apk/debug/app-debug.apk'
    $test=Join-Path $root 'build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk'
    $appInfo=& $aapt dump badging $apk
    $testInfo=& $aapt dump badging $test
    if(!($appInfo -match "^package: name='app.yoma.integration.qa'")) { throw 'No se instalará: paquete distinto del aislado' }
    if(!($testInfo -match "^package: name='app.yoma.integration.qa.test'")) { throw 'Paquete de instrumentación inesperado' }
    & $adb -s emulator-5554 install -r $apk
    if($LASTEXITCODE) { throw 'Falló instalar app aislada' }
    & $adb -s emulator-5554 install -r $test
    if($LASTEXITCODE) { throw 'Falló instalar instrumentación' }
    if($Classes) { & $adb -s emulator-5554 shell am instrument -w -r -e class $Classes app.yoma.integration.qa.test/androidx.test.runner.AndroidJUnitRunner *> (Join-Path $root "docs/yoma/$Report.txt") }
    else { & $adb -s emulator-5554 shell am instrument -w -r app.yoma.integration.qa.test/androidx.test.runner.AndroidJUnitRunner *> (Join-Path $root "docs/yoma/$Report.txt") }
    & $adb -s emulator-5554 logcat -d -s YomaAnimeBridge:D '*:S' *> (Join-Path $root 'docs/yoma/bridge-origin-log.txt')
    $reportText=Get-Content -Raw (Join-Path $root "docs/yoma/$Report.txt")
    if ($reportText -match 'FAILURES!!!|INSTRUMENTATION_FAILED|INSTRUMENTATION_ABORTED|INSTRUMENTATION_STATUS_CODE: -2' -or $reportText -notmatch 'OK \(') { throw 'La instrumentación falló o quedó incompleta; consulta su informe' }
    Get-Content (Join-Path $root "docs/yoma/$Report.txt") -Tail 8
} finally { Pop-Location }
