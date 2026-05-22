# Mira Apps — Development Workflow

Reference for Claude Code sessions working on mira-apps (iOS + macOS). See `MIRA_WORKFLOW.md` (root) for the complete workflow guide and practices.

---

## Session Checklist

Before starting work on mira-apps:

- [ ] Have you written a 5-bullet spec? (Do this outside Claude Code)
- [ ] Have you checked the sibling app (`mira-core`) for patterns? (API client, state management, etc.)
- [ ] Is this a follow-up to recent work? If yes, skip `/mira-status`.

---

## Project Structure

### iOS Entry Points

- `OllamaSearch/App.swift` — main app, scene setup
- `OllamaSearch/iOSRootView.swift` — NavigationStack for iPhone, NavigationSplitView for iPad

### macOS Entry Points

- `OllamaSearchApp.swift` — main app, menu bar, window management
- `OllamaSearchApp/MacRootView.swift` — NavigationSplitView with pinned sidebar (pattern: proven, do not change)

### Shared Components

- `ConversationListView.swift` — conversation list UI, around 480 lines
- `ChatView.swift` — message rendering
- `APIClient.swift` — API calls to mira-core backend

---

## Key Patterns (Do Not Reinvent)

### Sidebar visibility binding

**Pattern:** NavigationSplitView with pinned `columnVisibility` binding

**Where it works:**
- macOS: Sidebar always visible by default
- iPad: Two-column layout
- iPhone: Full-screen detail view (columnVisibility set to `.detailOnly` on load)

**Files:**
- `MacRootView.swift` (lines 468–490) — the proven pattern
- `iOSRootView.swift` — check here first before making sidebar changes on iPad

**Why this matters:** macOS 26 beta broke HSplitView and collapsed HStack to one pane. NavigationSplitView + pinned binding is the solution that works across all platforms.

### Observable state

Use `@Observable @MainActor` for view models. Example:

```swift
@Observable @MainActor
class ChatViewModel {
    var conversations: [Conversation] = []
    var currentConvId: UUID?
    // ...
}
```

**Where:** All view models in this project.

### Connection resilience

The backend may be sleeping (dev machine was closed, Tailscale was down). Handle gracefully:

- Quick optimistic probe first (APIClient.swift)
- If probe fails, show a transient banner
- Auto-reconnect in the background

Check `mira-core` APIClient for the latest patterns.

---

## Validation Workflow

Before any release:

1. **Run `/mira-validate`**
   - Builds for iOS simulator and macOS
   - Sideloads to iPhone Miguel (development build, no TestFlight delay)
   - Reports success/failure

2. **Manual smoke check (2 minutes)**
   - [ ] App launches and connects to backend
   - [ ] Can open an existing conversation
   - [ ] Can send a message and receive a response
   - [ ] The specific feature you changed works as intended
   - [ ] No visual regressions in sidebar, chat area, icons

3. **Asset check (if icons changed)**
   - Open `Assets.xcassets` → `AppIcon`
   - Check 16×16 and 32×32 previews for JPEG compression artifacts (white border at crop edge)
   - Catch before archiving

See `MIRA_WORKFLOW.md` section 5 for full validation details.

---

## Release Cadence

**Target:** One release per week (Friday or Monday).

**Why one per week?** Each TestFlight build notifies testers. Too many builds confuse the testing story. 

**What happened in the intensive weekend:** 4 releases in one day (0.1.9 → 0.1.11 → 0.1.12 → 0.1.13). This was unsustainable and made it hard to track which build had which fix.

**Process:**
1. Ensure all changes are committed and pushed
2. Run `/mira-validate` and manual smoke check
3. Run `/mira-release` to bump version, archive both iOS and macOS, and upload to TestFlight
4. Done. Next release is a week away.

See `MIRA_WORKFLOW.md` section 7 for full details and commit discipline advice.

---

## Bug Tracking

Open bugs are tracked in the root `BUGS.md` file (if it exists) or in the "Known bugs" section of `BACKLOG.md` (optional).

Completed work lives in `git log`. Don't archive completed bugs into a Done section — once fixed, they're deleted after 90 days.

---

## Monthly Security Audit

Last weekend of each month, run `/security-review` on this repo. Fix HIGH and MEDIUM issues before the next release.

**What to audit:**
- ATS (App Transport Security) settings — ensure no unencrypted endpoints
- Keychain vs UserDefaults — sensitive data must use Keychain, not UserDefaults
- Entitlement scope — network access, file access, camera, etc. must be justified
- Third-party package versions — any outdated pods with CVEs?

---

## Token Efficiency Tips

- Compact at 50% context, not 95% (use `/compact`)
- Write a 5-bullet spec before opening Claude Code
- One deliverable per session — note scope creep for next time
- Use `grep` before `Read` to find the exact line number in large files
- Check the sibling app first before re-solving any UI pattern

**Benefit observed:** With specs + planning, sessions cost 30% fewer tokens for the same work.

See `MIRA_WORKFLOW.md` section 1 and 8 for full details.

---

## Sibling App Reference (mira-core)

When solving a problem, check `mira-core` first for patterns:

- API client logic → `APIClient.swift` (probes, timeouts, retry strategies)
- Connection resilience → check how backend handles server sleep and recovery
- State management → Observable patterns

Borrowed patterns should be noted in commit messages.

---

## Xcode and Build Details

### Schemes

- `OllamaSearch` — the main app (iOS + macOS)
- Make sure you're building the right target (iOS vs macOS)

### Destinations

- iOS Simulator: `platform=iOS Simulator,name=iPhone 16 Pro`
- macOS: `platform=macOS`
- iPhone Miguel (sideload): `id=68256925-7395-58B9-BC9C-7A403153C7CB`

### Build Settings

- Configuration: Debug for development, Release for archive
- Code signing: Automatic (XCode manages provisioning profiles)

---

## Git and GitHub

- Always `git pull origin main` before any commit or push
- Commits should be coherent (one feature/fix per commit, not trial-and-error reversals)
- Use `git rebase -i` to squash commits before pushing if you have many small changes
- Release commits are tagged with version: `git tag v0.1.25 && git push origin v0.1.25`

Commit discipline advice: Normal pace is 5–10 commits per day (coherent changes). Sprint pace is 20–30 per day. More than 30 in a day signals trial-and-error coding — use upfront specs to prevent this.

---

## File Size and Large Components

**Watch out for large files that consume context:**

- `OllamaSearchApp.swift` — ~580 lines
- `ConversationListView.swift` — ~480 lines

**Before reading:** Use `grep` to find the exact line number of the function you need. Example:

```bash
grep -n "func handleMessageSend" OllamaSearchApp.swift
# Output: 245:    func handleMessageSend(text: String) {
# Then Read with offset: 245–260 (just the function, not the whole file)
```

This saves context for the actual work.

---

## macOS-Specific Notes

### HSplitView vs NavigationSplitView

**macOS 26 beta broke HSplitView** — it collapses to a single pane and ignores width constraints. Solution: Use `NavigationSplitView` with a pinned `columnVisibility` binding instead.

**Pattern is in `MacRootView.swift`.** Do not change it unless you have a specific reason and have tested on macOS 26 beta.

### Window and Scene Management

- `OllamaSearchApp.swift` handles WindowGroup and menu bar setup
- Scene modifiers handle window persistence and menu actions

---

## iOS-Specific Notes

### iPad vs iPhone

- **iPhone (compact width):** Full-screen detail view. Sidebar hidden by default.
- **iPad (regular width):** Two-column layout. Sidebar visible by default.

**Implementation:** NavigationSplitView with `columnVisibility = .detailOnly` on initial load for iPhone. iPad uses `.automatic` or `.all`.

### Keyboard and Input

- Chat input box should dismiss keyboard on send
- Conversation list responds to keyboard shortcuts on iPad

---

## Intensive Weekend Session — What Worked and What Didn't

### What worked:
- Security audit (HIGH → MEDIUM → LOW framework) — comprehensive and found real issues
- Connection resilience fix — prevented spurious reconnection attempts
- Sidebar fix (NavigationSplitView pinned binding) — solved a 3-session problem in one deliberate fix

### What didn't work:
- 87 commits in 48 hours — too many small/reversal commits. Should have used squash rebase.
- 4 releases in one day — unsustainable. One per week is the target.
- No 5-bullet specs upfront — each feature evolved mid-implementation

### Going forward:
- Write specs before coding (5-minute spec prevents 3–5 revision turns)
- Compact at 50% context, not 95% (saves tokens, speeds up next turn)
- One deliverable per session (not 3 features + 2 refactors)
- Validate before committing (don't commit broken builds and fix in the next commit)

**Benefit observed:** With specs + planning, sessions cost 30% fewer tokens and need fewer revision turns.
