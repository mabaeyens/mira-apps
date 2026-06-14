# Security Policy

## Supported versions

Mira is a single-maintainer project distributed via TestFlight. Only the **latest
TestFlight build** is supported — please reproduce any issue on the current version before
reporting.

## Reporting a vulnerability

**Please do not open a public issue for security vulnerabilities.**

Report privately through GitHub:

1. Go to the [**Security**](https://github.com/mabaeyens/mira-apps/security) tab of this repo.
2. Click **Report a vulnerability**.
3. Describe the issue.

Helpful details to include:

- A description of the vulnerability and its impact.
- Steps to reproduce (or a proof of concept).
- Affected platform (iOS / iPadOS / macOS) and app version + build.
- The mira-core server version, if relevant.

You'll get a best-effort acknowledgement; as a one-person project, response times vary.
Once a fix ships, the advisory can be published to credit the reporter (let me know if you'd
prefer to stay anonymous).

## Scope

- The apps store no secrets in the repository. Network access to the server is gated by a
  shared bearer token configured **server-side** in
  [mira-core](https://github.com/mabaeyens/mira-core) — see that repo's security policy for
  server-side reports.
- Inference and data stay on the user's own hardware; the apps talk only to the user's own
  Mac server over the LAN (Bonjour) or Tailscale (HTTPS).
