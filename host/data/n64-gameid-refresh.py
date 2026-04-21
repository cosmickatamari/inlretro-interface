"""Regenerate n64-gameid.tsv from n64_roms_complete.xlsx (run when the sheet changes)."""
from __future__ import annotations

import openpyxl
from pathlib import Path

HERE = Path(__file__).resolve().parent
XLSX = HERE / "n64-roms-complete.xlsx"
OUT = HERE / "n64-gameid.tsv"


def main() -> None:
    wb = openpyxl.load_workbook(XLSX, read_only=True, data_only=True)
    ws = wb["N64 ROM List"]
    by_id: dict[str, int] = {}
    for row in ws.iter_rows(min_row=2, values_only=True):
        if not row or all(c is None for c in row):
            continue
        rom_id = str(row[1]).strip().upper()
        mb = float(row[3])
        kib = int(round(mb * 1024))
        by_id[rom_id] = kib
    lines = [
        "# N64 retail ROM size by ROM ID (4-char game code at cartridge header offset 0x3B).",
        "# KiB = spreadsheet ROM Size (MB) column times 1024 (MiB). Source: n64_roms_complete.xlsx.",
        "# Output file: n64-gameid.tsv (ROM_ID<TAB>KIB)",
    ]
    for rid in sorted(by_id.keys()):
        lines.append(f"{rid}\t{by_id[rid]}")
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {OUT} ({len(by_id)} entries)")


if __name__ == "__main__":
    main()
