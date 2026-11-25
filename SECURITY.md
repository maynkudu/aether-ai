# Security policy

aether.ai is in early development. No stable support window is established; fixes target main and subsequent reviewed releases.

## Private reporting

Use [GitHub private vulnerability reporting](https://github.com/maynkudu/aether-ai/security/advisories/new) if enabled. Otherwise contact the maintainer privately using their published contact information on [GitHub](https://github.com/maynkudu). Do not post secrets or exploitable details in public issues. Include affected commit, impact and minimal sanitized reproduction.

## Trust boundaries

aether queries the native Codex app-server, which may refresh its authentication. Local caches can include account labels and filesystem paths. No hosted inference proxy or telemetry is built in. Optional asset downloads and updates contact documented upstream sources. Native preview builds are unsigned or ad-hoc signed; verify their provenance. Linux updater verifies source ancestry, not signed release provenance yet.

Never attach credentials, auth.json, raw settings or cache dumps to public reports. Rotate or revoke exposed credentials through the provider.
