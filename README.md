# Chiron ADE — distribution

The installer and the release artifacts for the Chiron ADE. **No source here**;
the app lives in Azure DevOps. This repo exists so a person can install and
update the app without an account, a token or a VPN.

## Install

Three channels, three apps that live side by side. Each talks to its own
Engineers and keeps its own sessions, so a dev build can never answer for a
production one.

```bash
# production
curl -fsSL https://raw.githubusercontent.com/Chiron-Team-G/chiron-ade-releases/main/install.sh | bash

# prod-beta
curl -fsSL https://raw.githubusercontent.com/Chiron-Team-G/chiron-ade-releases/main/install.sh | bash -s -- --channel beta

# the team's build
curl -fsSL https://raw.githubusercontent.com/Chiron-Team-G/chiron-ade-releases/main/install.sh | bash -s -- --channel dev
```

macOS, Apple Silicon and Intel. The script picks the architecture, verifies the
download against the release's checksums, closes a running copy the polite way,
installs into `/Applications` (or your home folder if that is not writable —
never `sudo`) and opens it.

### Why a script and not "download the DMG"

A file a **browser** downloads carries macOS's quarantine flag, and an app that
Apple has not notarised dies there with *"the app is damaged"*. `curl` sets no
such flag, so an app installed this way opens on the first double click with no
Gatekeeper dance. The DMG is published too, for whoever prefers dragging and
does not mind the first-open warning.

When the Developer ID certificate exists, notarised builds make both paths
silent and the DMG becomes the recommended one. Nothing else changes.

## Where the versions come from

| Channel | Version | Where it is published |
|---|---|---|
| production | `0.2.0` | a normal release; `releases/latest` resolves to it |
| prod-beta | `0.2.0-beta.N` | the rolling `beta` tag, replaced by every build |
| dev | `0.2.0-dev.N` | the rolling `dev` tag, replaced by every build |

A rolling tag means there is exactly one build of that channel alive at a time
and its download URL never moves — which is what lets an installed app check
one fixed address for its next version.

## Updating

The app checks its own channel and offers the update; you decide when to
restart, because a restart closes the terminals its agents are working in.
Re-running the install command above does the same thing by hand.
