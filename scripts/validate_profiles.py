#!/usr/bin/env python3
"""Validate the portable encrypted DNS configuration profiles in the release."""
import glob
import plistlib
from pathlib import Path

expected = {
    "NOVA-OISD-Big.mobileconfig": "https://lite.public-rdns.com/dns-query",
    "NOVA-OISD-Full-Alternative.mobileconfig": "https://freedns.controld.com/x-oisd",
}
for name, endpoint in expected.items():
    path = Path("profiles") / name
    p = plistlib.loads(path.read_bytes())
    assert p["PayloadType"] == "Configuration"
    assert p["PayloadRemovalDisallowed"] is False
    assert len(p["PayloadContent"]) == 1
    payload = p["PayloadContent"][0]
    assert payload["PayloadType"] == "com.apple.dnsSettings.managed"
    assert payload["DNSSettings"]["DNSProtocol"] == "HTTPS"
    assert payload["DNSSettings"]["ServerURL"] == endpoint
    assert payload["DNSSettings"]["AllowFailover"] is False
    assert not any("networkextension" in k.lower() for k in payload)
    print(f"Valid DNS profile: {name} => {endpoint}")
print("Both profiles validated; no Network Extension or VPN payload present.")
