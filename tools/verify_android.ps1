param(
    [string]$Device,
    [ValidateSet('debug','profile')][string]$Mode='profile'
)
$ErrorActionPreference='Stop'
Set-Location (Join-Path $PSScriptRoot '..')
flutter analyze
if($LASTEXITCODE) { throw 'Falló el análisis' }
flutter test
if($LASTEXITCODE) { throw 'Fallaron las pruebas' }
if(!$Device) { throw 'Indica -Device con el identificador de un teléfono o emulador de pruebas' }
flutter build apk "--$Mode" --target=integration_test/device_test.dart --dart-define=YOMASHI_QA=true
if($LASTEXITCODE) { throw 'Falló la compilación QA' }
$sdk=if($env:ANDROID_HOME) {$env:ANDROID_HOME} elseif($env:ANDROID_SDK_ROOT) {$env:ANDROID_SDK_ROOT} else {Join-Path $env:LOCALAPPDATA 'Android\Sdk'}
$binary=if($IsWindows) {'aapt.exe'} else {'aapt'}
$aapt=Get-ChildItem (Join-Path (Join-Path $sdk 'build-tools') "*/$binary") | Sort-Object FullName -Descending | Select-Object -First 1
if(!$aapt) { throw 'No se encontró aapt para verificar el APK antes de instalar' }
$apk="build/app/outputs/flutter-apk/app-$Mode.apk"
$badging=& $aapt.FullName dump badging $apk
if(($badging | Select-String "^package: name='app.yomashi.reader.qa'").Count -ne 1) {
    throw 'Bloqueado: el APK no tiene el identificador aislado de pruebas'
}
# Instalar únicamente el binario ya verificado, sin reconstruirlo durante drive.
flutter drive "--$Mode" --no-dds --driver=test_driver/integration_test.dart --target=integration_test/device_test.dart "--use-application-binary=$apk" -d $Device
if($LASTEXITCODE) { throw 'Falló la prueba Android; revisar el informe de Flutter' }
