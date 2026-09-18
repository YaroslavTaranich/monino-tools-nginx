#!/usr/bin/env python3
"""Print direct child names from a WebDAV PROPFIND response."""

from __future__ import annotations

import sys
import urllib.parse
import xml.etree.ElementTree as ET


def main() -> int:
    try:
        root = ET.parse(sys.stdin).getroot()
    except ET.ParseError as error:
        print(f"Invalid WebDAV XML: {error}", file=sys.stderr)
        return 2

    names: set[str] = set()
    for element in root.iter():
        if element.tag.rsplit("}", 1)[-1] != "href" or not element.text:
            continue
        path = urllib.parse.unquote(urllib.parse.urlparse(element.text).path)
        name = path.rstrip("/").rsplit("/", 1)[-1]
        if name and name not in {"backups", "Monino Tools"}:
            names.add(name)

    for name in sorted(names):
        print(name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
