---
name: Bug report
about: Something in the Mira iOS or macOS app is broken
title: ''
labels: ''
assignees: ''

---

<!--
Thanks for filing an issue! Fill in the sections that apply and delete the rest.

SECURITY VULNERABILITIES: do not file them here — see SECURITY.md and use the
repo's Security tab → "Report a vulnerability".

This repo is the SwiftUI client. If the server is the thing misbehaving (bad
answers, hangs during generation, tool calls failing), it probably belongs in
mira-core: https://github.com/mabaeyens/mira-core/issues
When in doubt, file it here and it can be moved.
-->

### Summary

<!-- One or two sentences describing what went wrong. -->

### Steps to reproduce

1.
2.
3.

### Expected vs. actual

- **Expected:**
- **Actual:**

### Environment

- **Platform:** <!-- iOS / iPadOS / macOS -->
- **OS version:** <!-- e.g. iOS 26.0, macOS 26.5.1 -->
- **Device:** <!-- e.g. iPhone 17 Pro, M5 MacBook Pro -->
- **Mira app version:** <!-- the About screen shows it; TestFlight shows the build number beside it -->
- **mira-core server version:** <!-- the release tag the server is on, if you know it -->

### Connection

<!--
Worth filling in even when the bug looks unrelated — most "cannot reach server"
reports come down to one of these.
-->

- **Connecting via:** <!-- localhost / Tailscale MagicDNS name / plain LAN IP -->
- **Reaching the server at all?** <!-- does the chat load, or does it fail at connect? -->

### Screenshots or recording

<!-- For anything visual, layout, or streaming-related, a short screen recording says more than a description. -->

### Logs

<!--
Server side: /tmp/com.mab.mira.log if mira-core runs as a LaunchAgent.
Please skim for your auth token before pasting.
-->

```
```

### Anything else

<!-- What you had already tried, whether it used to work, how often it happens. -->
