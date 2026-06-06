#!/usr/bin/env python3
"""Prepend a new <item> to appcast.xml for a Sparkle-enabled release.

Usage: update-appcast.py <version> <build> <ed_signature> <length> <pub_date>

  version      e.g. "0.2.0"
  build        CFBundleVersion integer, e.g. "2"
  ed_signature EdDSA base64 signature from `sign_update`
  length       DMG byte length from `sign_update`
  pub_date     RFC 2822 date, e.g. "Mon, 02 Jun 2025 12:00:00 +0000"
"""

import sys

if len(sys.argv) != 6:
    sys.exit(__doc__)

version, build, sig, length, pub_date = sys.argv[1:]
dmg_url = f"https://github.com/lilmelon77/hey-claude/releases/download/v{version}/HeyClaude.dmg"

new_item = f"""
    <item>
      <title>Version {version}</title>
      <pubDate>{pub_date}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <enclosure
        url="{dmg_url}"
        sparkle:edSignature="{sig}"
        length="{length}"
        type="application/x-apple-diskimage"/>
    </item>"""

with open("appcast.xml", "r", encoding="utf-8") as f:
    content = f.read()

# Insert after the <language> closing tag so newest releases appear first.
marker = "</language>"
if marker not in content:
    sys.exit("ERROR: appcast.xml missing <language> tag — cannot insert item.")

content = content.replace(marker, marker + new_item, 1)

with open("appcast.xml", "w", encoding="utf-8") as f:
    f.write(content)

print(f"appcast.xml updated: v{version} (build {build})")
