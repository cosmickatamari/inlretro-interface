$bytes = [System.IO.File]::ReadAllBytes('D:\INL-retro-progdump-master\host\games\nes\Mega Man 3_cnrom.nes')
$bytes[6] = 0x41  # Mapper 4
[System.IO.File]::WriteAllBytes('D:\INL-retro-progdump-master\host\games\nes\Mega Man 3_cnrom_mapper4.nes', $bytes)
Write-Host "Header fixed - mapper changed to 4"
