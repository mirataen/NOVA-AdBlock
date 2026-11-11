# NOVA AdBlock — DNS Profile Edition

**This edition is designed for installation on iPhone using ESign or Feather with an ordinary valid signing certificate. It requires no VPN/Network Extension entitlement.**

NOVA is a **companion app** for installing encrypted DNS configuration profiles. DNS filtering occurs **at the DNS provider**, not inside the app. There is no packet tunnel and no remote VPN. The app never pretends it can check whether a profile is active.

## DNS profiles

- [NOVA OISD Big (Public RDNS Lite)](profiles/NOVA-OISD-Big.mobileconfig): DoH `https://lite.public-rdns.com/dns-query`. The provider advertises OISD Big filtering. [Provider details](https://public-rdns.com/lite.html).
- [NOVA OISD Full alternative (Control D Free DNS)](profiles/NOVA-OISD-Full-Alternative.mobileconfig): DoH `https://freedns.controld.com/x-oisd`. Control D's free OISD Full preset. [OISD's setup guide](https://oisd.nl/setup/controld).

The two profile choices are **alternatives**. Do not install both at once. Other DNS profiles, VPNs and Apple privacy features can override the chosen DNS resolver.

### How to install on iPhone (no Mac or Xcode)

1. In Safari, open the raw `.mobileconfig` download:
   - [OISD Big DNS profile](https://raw.githubusercontent.com/mirataen/NOVA-AdBlock/main/profiles/NOVA-OISD-Big.mobileconfig)
   - [Control D alternative](https://raw.githubusercontent.com/mirataen/NOVA-AdBlock/main/profiles/NOVA-OISD-Full-Alternative.mobileconfig)
2. Approve the profile download when iOS asks.
3. Open **Settings → General → VPN & Device Management → Profile Downloaded**, review the DNS endpoint shown, then tap **Install**.
4. If iOS offers a DNS selector, select the installed profile. If an old NOVA VPN is present, remove it from VPN settings; the DNS edition does not need it.
5. To disable NOVA DNS, remove the configuration profile in Settings.

**iOS 27:** Apple has deprecated the legacy `com.apple.dnsSettings.managed` configuration payload in favor of declarative DNS settings. Manual installation may still be offered, but operation must be verified on the actual iOS 27 device. If iOS refuses installation, check the DNS provider's own iOS profile instructions.

**Trust and privacy:** You are trusting the selected third-party provider to process your DNS queries. NOVA's code does not collect your DNS traffic, but it cannot independently audit the provider. If another VPN handles DNS, the profile might be ignored. DoH encrypts DNS traffic; it does not hide IP traffic or change your public IP. Domain-based filtering does not remove all advertisements, trackers or in-page cosmetic elements.

## Download the unsigned IPA

Go to [GitHub Actions](https://github.com/mirataen/NOVA-AdBlock/actions/workflows/build-ipa.yml), select the most recent successful run named **Build NOVA DNS Edition unsigned IPA and profiles** and download `NOVA-DNS-Edition-unsigned-IPA` under Artifacts. Unzip, then sign the IPA with ESign or Feather. This new version has no embedded network extension.

No .p12 certificate, mobile provisioning file, password, access token or private key belongs in this public repository.
