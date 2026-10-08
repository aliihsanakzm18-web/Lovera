$source = (Get-Item -LiteralPath ".").FullName
$destinationZip = Join-Path (Split-Path $source -Parent) "Lovera_Backup_20261009.zip"
$tempFolder = Join-Path (Split-Path $source -Parent) "Lovera_Temp_Backup"

if (Test-Path $destinationZip) {
    Remove-Item $destinationZip -Force
}
if (Test-Path $tempFolder) {
    Remove-Item $tempFolder -Recurse -Force
}

New-Item -ItemType Directory -Path $tempFolder | Out-Null

Write-Host "Kaynak kodlar gecici dizine kopyalaniyor..."
& robocopy $source $tempFolder /E /XD build .dart_tool .git .idea /XF *.png /NFL /NDL /NJH /NJS

Write-Host "ZIP arsivi olusturuluyor..."
Compress-Archive -Path "$tempFolder\*" -DestinationPath $destinationZip -CompressionLevel Optimal

Remove-Item $tempFolder -Recurse -Force

if (Test-Path $destinationZip) {
    $item = Get-Item $destinationZip
    $mb = [math]::Round($item.Length / 1MB, 2)
    Write-Host "Yedekleme BASARIYLA tamamlandi!"
    Write-Host "Konum: $destinationZip"
    Write-Host "Boyut: $mb MB"
} else {
    Write-Error "Yedek olusturulamadi!"
}
