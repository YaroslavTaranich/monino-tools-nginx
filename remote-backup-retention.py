#!/usr/bin/env python3
"""Build a deterministic retention plan for Monino Tools remote backups."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone


BACKUP_RE = re.compile(
    r"^monino-tools-backup-(?P<timestamp>\d{8}T\d{6}Z)\.tar\.gz$"
)


@dataclass(frozen=True)
class Backup:
    name: str
    created_at: datetime


def parse_now(value: str | None) -> datetime:
    if value is None:
        return datetime.now(timezone.utc)
    parsed = datetime.strptime(value, "%Y%m%dT%H%M%SZ")
    return parsed.replace(tzinfo=timezone.utc)


def previous_months(now: datetime, count: int) -> set[tuple[int, int]]:
    result: set[tuple[int, int]] = set()
    year = now.year
    month = now.month
    for _ in range(count):
        result.add((year, month))
        month -= 1
        if month == 0:
            month = 12
            year -= 1
    return result


def newest_per_bucket(
    backups: list[Backup],
    allowed_buckets: set[object],
    bucket_for,
) -> set[str]:
    kept: set[str] = set()
    seen: set[object] = set()
    for backup in backups:
        bucket = bucket_for(backup.created_at)
        if bucket in allowed_buckets and bucket not in seen:
            kept.add(backup.name)
            seen.add(bucket)
    return kept


def build_plan(backups: list[Backup], now: datetime) -> list[tuple[str, Backup, str]]:
    backups = sorted(backups, key=lambda item: item.created_at, reverse=True)
    reasons: dict[str, set[str]] = {backup.name: set() for backup in backups}

    protected_after = now - timedelta(hours=48)
    for backup in backups:
        if backup.created_at >= protected_after:
            reasons[backup.name].add("protected-48h")

    daily_dates = {(now - timedelta(days=offset)).date() for offset in range(7)}
    for name in newest_per_bucket(backups, daily_dates, lambda value: value.date()):
        reasons[name].add("daily")

    current_week = now.date() - timedelta(days=now.weekday())
    weekly_dates = {current_week - timedelta(weeks=offset) for offset in range(4)}
    for name in newest_per_bucket(
        backups,
        weekly_dates,
        lambda value: value.date() - timedelta(days=value.weekday()),
    ):
        reasons[name].add("weekly")

    monthly_keys = previous_months(now, 6)
    for name in newest_per_bucket(
        backups, monthly_keys, lambda value: (value.year, value.month)
    ):
        reasons[name].add("monthly")

    plan: list[tuple[str, Backup, str]] = []
    for backup in backups:
        backup_reasons = reasons[backup.name]
        if backup_reasons:
            plan.append(("KEEP", backup, ",".join(sorted(backup_reasons))))
        else:
            plan.append(("DELETE", backup, "expired"))
    return plan


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--now", help="UTC timestamp used for deterministic planning")
    args = parser.parse_args()
    now = parse_now(args.now)

    backups: list[Backup] = []
    seen: set[str] = set()
    for raw_line in sys.stdin:
        name = raw_line.strip()
        if not name:
            continue
        match = BACKUP_RE.fullmatch(name)
        if match is None:
            print(f"Invalid backup name: {name}", file=sys.stderr)
            return 2
        if name in seen:
            print(f"Duplicate backup name: {name}", file=sys.stderr)
            return 2
        seen.add(name)
        created_at = datetime.strptime(
            match.group("timestamp"), "%Y%m%dT%H%M%SZ"
        ).replace(tzinfo=timezone.utc)
        if created_at > now + timedelta(minutes=5):
            print(f"Backup timestamp is in the future: {name}", file=sys.stderr)
            return 2
        backups.append(Backup(name=name, created_at=created_at))

    for action, backup, reason in build_plan(backups, now):
        print(f"{action}\t{backup.name}\t{reason}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
