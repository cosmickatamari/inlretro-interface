$TargetPath = "D:\INL-retro-progdump-master"
$CutoffDate = (Get-Date).AddDays(-30)

$RecentFiles = Get-ChildItem -Path $TargetPath -Recurse -File |
    Where-Object { $_.LastWriteTime -ge $CutoffDate }

$RecentFiles | Select-Object FullName, LastWriteTime | Sort-Object LastWriteTime -Descending