$bytes = [System.IO.File]::ReadAllBytes('D:\INL-retro-progdump-master\host\games\nes\Mega Man 3_unrom.nes')
$bytes[6] = 0x41  # Mapper 4
$bytes[5] = 0x10  # CHR-ROM size (128KB)
[System.IO.File]::WriteAllBytes('D:\INL-retro-progdump-master\host\games\nes\Mega Man 3_unrom_mapper4.nes', $bytes)
Write-Host "Header fixed - mapper changed to 4, CHR-ROM added"
