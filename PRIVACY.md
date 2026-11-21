# Privacy Policy — Mira

_Last updated: 2026-06-21_

Mira is built privacy-first, and this policy is short because there honestly isn't much to
say.

## The short version

- No account. No sign-up. No tracking. No analytics. No ads.
- No servers of ours. Mira talks only to the server *you* run and point it at. There is no
  "Mira cloud" to send anything to.
- Your conversations stay yours. They live on your own device and, if you want, on your own
  self-hosted Mira server. They never pass through us.
- It's open source, so you can check every word of this for yourself:
  <https://github.com/mabaeyens/mira-apps>

## What data Mira collects

None. The app does not collect, transmit, or sell any personal data to us. We couldn't even
if we wanted to: there's no server of ours, and no analytics SDK baked in. That's why the
App Store privacy label says **Data Not Collected**.

## How Mira works

Mira is just a client for a Mira server (the open-source `mira-core` backend) that *you*
run, usually on your own Mac, reachable over localhost, your local network, or your own
Tailscale. By default it connects to `http://127.0.0.1:8000`.

Whatever you type goes to that server for the model to answer, and the reply streams back to
the app. Where it ends up is your call:

- If your server runs a local model (say Ollama or MLX on your own machine), nothing leaves
  your hardware.
- If you've pointed your server at a third-party model provider, your messages travel from
  your server to that provider under whatever arrangement you have with them. That link is
  between you and them. It never goes through us.

## Data that stays on your device (and your own iCloud)

Your conversations are cached locally as a file in the app's container. If iCloud is
available, that file lives in the app's iCloud container and syncs across your devices under
your own Apple ID, never to us.

The text of your most recent conversations (the newest 80) is also kept as plain files in the
app's local cache folder on that device, so a conversation opens at once while the server
refreshes it. It is not in iCloud, is not backed up, and is removed when you delete the
conversation.

Saved server connections (the name and URL you add) are kept in iCloud's key-value store, so
they sync across your devices under your Apple ID, and nowhere else. The access token for a
connection is not stored there: it is kept in the Keychain. On iPhone and iPad that item is
synchronizable, so it travels through iCloud Keychain, which is end-to-end encrypted, and the
app never sends it anywhere except to the server it belongs to. If iCloud Keychain is off, the
token stays on that device and another device needs the connection paired again. On macOS the
local server's token is also kept in the Keychain, on that Mac only.

The smaller stuff (sidebar state, cached memory entries, last-used settings) sits in the
app's local settings. All of it stays on your device and syncs only through *your* iCloud,
under your Apple ID.

## Dictation

When you dictate, the audio is turned into text by Apple's speech recognition. It runs on your device when your language supports that. If it does not, iOS may send the audio to Apple to be recognised, under Apple's own privacy terms. Mira never receives the audio, only the text you then choose to send.

## The only network activity

Mira makes no network calls of its own except to the server you configure. No phone-home, no
telemetry, nothing reaching out in the background.

## Children's privacy

Mira collects no data from anyone, children included.

## Changes

If this policy ever changes, the update lands in this file in the public repository, with the
date above.

## Contact

Questions or concerns? Open an issue or discussion at
<https://github.com/mabaeyens/mira-apps>.
