#!/usr/bin/env python3
"""Normalize OISD Big into sorted ASCII domain lines for memory-mapped lookup."""
import re
import sys

domain_re = re.compile(r"(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?")
result = set()
for raw in sys.stdin:
    line = raw.strip().lower()
    if not line or line.startswith(("!", "#", "[", "@@")):
        continue
    if line.startswith("||"):
        line = line[2:].split("^", 1)[0].split("$", 1)[0]
    elif line.startswith(("0.0.0.0 ", "127.0.0.1 ")):
        line = line.split()[1]
    elif line.startswith(("address=/", "server=/")):
        line = line.split("/", 2)[1]
    elif any(c.isspace() for c in line):
        continue
    line = line.rstrip(".")
    if domain_re.fullmatch(line):
        result.add(line)
for domain in sorted(result):
    sys.stdout.write(domain + "\n")
