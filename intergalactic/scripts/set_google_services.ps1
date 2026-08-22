param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("enable", "disable")]
    [string] $Mode
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$appRoot = Split-Path -Parent $scriptDir
$enable = $Mode -eq "enable"

function Update-TextFile {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [Parameter(Mandatory = $true)]
        [scriptblock] $Updater
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing file: $Path"
    }

    $old = [System.IO.File]::ReadAllText($Path)
    $new = & $Updater $old

    if ($new -ne $old) {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($Path, $new, $utf8NoBom)
        Write-Host "[google-services] Updated $Path"
    }
}

function Replace-Line {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text,
        [Parameter(Mandatory = $true)]
        [string] $Pattern,
        [Parameter(Mandatory = $true)]
        [string] $Replacement,
        [Parameter(Mandatory = $true)]
        [string] $Description
    )

    if ($Text -notmatch $Pattern) {
        throw "Could not find $Description"
    }

    return [regex]::Replace($Text, $Pattern, $Replacement)
}

$pubspec = Join-Path $appRoot "pubspec.yaml"
$appGradle = Join-Path $appRoot "android\app\build.gradle"
$settingsGradle = Join-Path $appRoot "android\settings.gradle"
$firebaseNotifier = Join-Path $appRoot "lib\client\components\push_notification\android\firebase_push_notifier.dart"
$firebaseOptions = Join-Path $appRoot "lib\firebase_options.dart"

Update-TextFile $pubspec {
    param($text)

    $coreLine = if ($enable) { "  firebase_core: 2.32.0" } else { "  # firebase_core: 2.32.0" }
    $messagingLine = if ($enable) { "  firebase_messaging: 14.7.10" } else { "  # firebase_messaging: 14.7.10" }

    $text = Replace-Line $text "(?m)^\s*#?\s*firebase_core:\s*.*$" $coreLine "firebase_core dependency line"
    $text = Replace-Line $text "(?m)^\s*#?\s*firebase_messaging:\s*.*$" $messagingLine "firebase_messaging dependency line"
    return $text
}

Update-TextFile $appGradle {
    param($text)

    $line = if ($enable) {
        "    id 'com.google.gms.google-services'"
    } else {
        "    // id 'com.google.gms.google-services'"
    }

    return Replace-Line $text "(?m)^\s*(//\s*)?id 'com\.google\.gms\.google-services'\s*$" $line "Android Google Services Gradle plugin"
}

Update-TextFile $settingsGradle {
    param($text)

    $line = if ($enable) {
        '    id "com.google.gms.google-services" version "4.4.4" apply false'
    } else {
        '    // id "com.google.gms.google-services" version "4.4.4" apply false'
    }

    return Replace-Line $text '(?m)^\s*(//\s*)?id "com\.google\.gms\.google-services" version "[^"]+" apply false\s*$' $line "settings Google Services Gradle plugin"
}

Update-TextFile $firebaseNotifier {
    param($text)

    $coreImport = if ($enable) {
        "import 'package:firebase_core/firebase_core.dart';"
    } else {
        "// import 'package:firebase_core/firebase_core.dart';"
    }

    $messagingImport = if ($enable) {
        "import 'package:firebase_messaging/firebase_messaging.dart';"
    } else {
        "// import 'package:firebase_messaging/firebase_messaging.dart';"
    }

    $firebaseDynamic = if ($enable) { "// dynamic Firebase;" } else { "dynamic Firebase;" }
    $messagingDynamic = if ($enable) { "// dynamic FirebaseMessaging;" } else { "dynamic FirebaseMessaging;" }
    $optionsDynamic = if ($enable) { "// dynamic DefaultFirebaseOptions;" } else { "dynamic DefaultFirebaseOptions;" }

    $text = Replace-Line $text "(?m)^(//\s*)?import 'package:firebase_core/firebase_core\.dart';\s*$" $coreImport "firebase_core import"
    $text = Replace-Line $text "(?m)^(//\s*)?import 'package:firebase_messaging/firebase_messaging\.dart';\s*$" $messagingImport "firebase_messaging import"
    $text = Replace-Line $text "(?m)^(//\s*)?dynamic Firebase;\s*$" $firebaseDynamic "Firebase placeholder"
    $text = Replace-Line $text "(?m)^(//\s*)?dynamic FirebaseMessaging;\s*$" $messagingDynamic "FirebaseMessaging placeholder"
    $text = Replace-Line $text "(?m)^(//\s*)?dynamic DefaultFirebaseOptions;\s*$" $optionsDynamic "DefaultFirebaseOptions placeholder"
    return $text
}

Update-TextFile $firebaseOptions {
    param($text)

    if ($enable) {
        if ($text -match "// \[google-services-disabled\]") {
            $text = [regex]::Replace(
                $text,
                "(?s)(// ignore_for_file: type=lint\r?\n)// \[google-services-disabled\]\r?\n/\*\r?\n",
                '$1'
            )
            $text = [regex]::Replace($text, "\r?\n\*/\s*$", "")
        } elseif ($text -match "(?s)// ignore_for_file: type=lint\r?\n/\*\r?\n") {
            $text = [regex]::Replace(
                $text,
                "(?s)(// ignore_for_file: type=lint\r?\n)/\*\r?\n",
                '$1'
            )
            $text = [regex]::Replace($text, "\r?\n\*/\s*$", "")
        }
    } elseif ($text -notmatch "// \[google-services-disabled\]" -and
        $text -notmatch "(?s)// ignore_for_file: type=lint\r?\n/\*\r?\n") {
        $text = [regex]::Replace(
            $text,
            "(?s)(// ignore_for_file: type=lint\r?\n)(.*)$",
            '$1// [google-services-disabled]' + "`r`n/*`r`n" + '$2' + "`r`n*/"
        )
    }

    return $text
}

Write-Host "[google-services] Google Services source state: $Mode"
