param($filename)
$bytes = Get-Content $filename -AsByteStream -TotalCount 16
for($i=0; $i -lt $bytes.Length; $i++) {
    Write-Host ('{0:X2}' -f $bytes[$i]) -NoNewline
    if($i -lt $bytes.Length-1) {
        Write-Host ' ' -NoNewline
    }
}
Write-Host ""
