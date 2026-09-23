"""Shared project-scoped xcodebuild discovery for dev-ios hooks and skills."""

from __future__ import annotations

import os
import re
import subprocess


def parse_etime(etime: str) -> int:
    etime = etime.strip()
    if not etime:
        return 0
    if "-" in etime:
        days, rest = etime.split("-", 1)
        day_seconds = int(days) * 86400
    else:
        rest = etime
        day_seconds = 0
    parts = [int(part) for part in rest.split(":")]
    if len(parts) == 1:
        return day_seconds + parts[0]
    if len(parts) == 2:
        return day_seconds + parts[0] * 60 + parts[1]
    return day_seconds + parts[0] * 3600 + parts[1] * 60 + parts[2]


def list_process_rows() -> list[dict]:
    result = subprocess.run(
        ["ps", "-axo", "pid=,pcpu=,pmem=,etime=,comm=,command="],
        capture_output=True,
        text=True,
        check=False,
    )
    rows: list[dict] = []
    for line in result.stdout.splitlines():
        match = re.match(
            r"\s*(\d+)\s+([\d.]+)\s+([\d.]+)\s+(\S+)\s+(\S+)\s+(.*)$",
            line,
        )
        if not match:
            continue
        rows.append(
            {
                "pid": int(match.group(1)),
                "cpu_percent": float(match.group(2)),
                "mem_percent": float(match.group(3)),
                "elapsed_seconds": parse_etime(match.group(4)),
                "elapsed": match.group(4),
                "comm": match.group(5),
                "command": match.group(6),
            }
        )
    return rows


def project_matches(command: str, project_path: str, project_name: str) -> bool:
    return project_path in command or project_name in command


def project_xcodebuild_processes(project_path: str) -> list[dict]:
    project_name = os.path.basename(project_path)
    rows = list_process_rows()
    return [
        row
        for row in rows
        if "xcodebuild" in row["command"]
        and project_matches(row["command"], project_path, project_name)
    ]
