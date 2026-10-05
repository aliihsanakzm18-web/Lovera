$ErrorActionPreference = 'Stop'
Write-Host "Fetching Flutter release info..."
$releases = (Invoke-RestMethod -Uri 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json').releases
$stable = $releases | Where-Object { $_.channel -eq 'stable' } | Select-Object -First 1

$downloadUrl = "https://storage.googleapis.com/flutter_infra_release/releases/$($stable.archive)"
Write-Host "Found URL: $downloadUrl"

$targetDir = "C:\src"
if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

$zipPath = "$targetDir\flutter.zip"

Write-Host "Downloading Flutter SDK to $zipPath (bu işlem birkaç dakika sürebilir)..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$webClient = New-Object System.Net.WebClient
$webClient.DownloadFile($downloadUrl, $zipPath)

Write-Host "Extracting Flutter SDK to $targetDir..."
Expand-Archive -Path $zipPath -DestinationPath $targetDir -Force

Write-Host "Cleaning up zip file..."
Remove-Item -Path $zipPath -Force

Write-Host "Adding Flutter to User PATH..."
$flutterBin = "C:\src\flutter\bin"
$userPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::User)
if ($userPath -notlike "*$flutterBin*") {
    $newPath = "$userPath;$flutterBin"
    [Environment]::SetEnvironmentVariable("Path", $newPath, [EnvironmentVariableTarget]::User)
    Write-Host "PATH updated successfully!"
}

Write-Host "Flutter installation complete!"
