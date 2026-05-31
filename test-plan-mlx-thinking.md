# Manual Test Plan — mlx-lm Adaptive Thinking

Covers `spec-mlx-lm-thinking.md` + `spec-thinking-sync.md` + the split-marker fix in `orchestrator.py`.

**Scope:** server (mira-core: Qwen3 default, two-pass strip loop, adaptive heuristic) and app (mira-apps: no toggle UI, thinking chip, persistence).

---

## How the heuristic decides (reference)

Client always sends `thinking_enabled=false`, so the **server** decides via `_should_think()`. Trivial acks never think. Otherwise score and think if **≥ 3**:

| Signal | Points |
|---|---|
| Has attachment | +3 |
| Message > 500 chars | +2 (or +1 if > 150) |
| Code signal — ``` ``` ```, `def `, `class `, `import `, `error:`, `traceback`, or `name.ext` (`.swift .py .js .ts .kt .java .go .rs .rb .cpp .c .h .vue .tsx .jsx`) | +2 |
| Reasoning verb — why, how, fix, debug, implement, refactor, explain, design, analyze, review, optimize, architect, plan, compare, difference, tradeoff | +1 |

> Note: "thinking allowed" ≠ "thinking guaranteed". Qwen3 is adaptive at the model level too — when allowed, it still decides per query. **Suppressed cases must show NO thinking block; allowed+complex cases should show one.**

---

## Setup

- [ ] **0.1** Restart server so it picks up the Qwen3 default and the edited `orchestrator.py`:
      run `/mira-server restart` (or `reload` — the orchestrator change is code, restart is enough).
- [ ] **0.2** Confirm health: `/mira-server status` → process running, `/health` ok.
- [ ] **0.3** In the app, open the model picker → active model is **Qwen3.6-35B-A3B-4bit** (mlx-lm section).
- [ ] **0.4** Model pill in chat shows the Qwen3 display name.

---

## A. Adaptive heuristic — SUPPRESSED (must show NO thinking block)

Send each as a fresh first message in a new conversation.

- [ ] **A.1** `thanks` → trivial → no thinking, short reply.
- [ ] **A.2** `what time is it?` → score 0 → no thinking block.
- [ ] **A.3** `summarize this paragraph: <paste 2 short sentences>` → "summarize" is **not** a reasoning verb, no file, short → score 0 → no thinking block.

## B. Adaptive heuristic — ALLOWED (thinking block should appear)

- [ ] **B.1** `review the ChatView.swift` → file ref (+2) + "review" (+1) = 3 → **Thinking… block appears**, then collapses to a reopenable summary when the answer streams.
- [ ] **B.2** `fix the crash in parser.py` → `parser.py` (+2) + "fix" (+1) = 3 → thinking block appears.
- [ ] **B.3** Attach any file + send `review this` → attachment (+3) + "review" (+1) = 4 → thinking block appears (most reliable trigger — real content to reason over).

## C. No leaked markup (two-pass strip + split-marker fix)

- [ ] **C.1** During B.1–B.3, the **visible answer contains no** `<think>`, `</think>`, `<|channel>`, `thought`, or `<channel|>` text.
- [ ] **C.2** The answer is never empty when a thinking block was shown (guards against the split-close-tag bug where the answer gets swallowed).
- [ ] **C.3** Switch model to **Gemma 4** (model picker) and send `review this for bugs` with a code file attached.
      → Response is clean prose — **no** `<|channel>thought` / `<channel|>` garbage anywhere (this was the active pre-fix bug).
- [ ] **C.4** Switch back to **Qwen3** before continuing.

## D. Persistence (spec-thinking-sync.md)

- [ ] **D.1** After a thinking response (e.g. B.1), the thinking block is collapsed but **expandable** in place.
- [ ] **D.2** Switch to another conversation, then back → the thinking block is **still present and expandable** (loaded from DB, not just in-memory).
- [ ] **D.3** Force-quit and relaunch the app, reopen that conversation → thinking content still there.
- [ ] **D.4** (optional, macOS+iOS) Same conversation viewed on the other platform shows the same thinking content.

## E. UI — toggle fully removed

- [ ] **E.1** iOS: tap `+` / attach sheet → **no** "Thinking" toggle row.
- [ ] **E.2** macOS: the add-to-chat popover → **no** "Thinking" toggle row.
- [ ] **E.3** Model picker (both platforms) → **no** "Thinking" toggle section.
- [ ] **E.4** The thinking **chip/indicator still appears** live while the model is thinking (it's automatic now, not user-controlled).

## F. Regression sanity

- [ ] **F.1** A normal multi-turn conversation streams correctly; tokens/sec and context % still update.
- [ ] **F.2** Tool use still works (e.g. a query that triggers search) and the response completes (`task_done` / stream end unaffected).
- [ ] **F.3** Send a long (>500 char) message with a verb → thinking allowed, answer complete, no markup leak.

---

## Notes on what can't be forced manually

The split-marker bug depends on how the backend tokenizes/chunks the stream — you can't deterministically force a tag to split across chunks from the UI. The fix is proven in isolation (13/13 cases incl. 1-char-at-a-time in `/tmp/claude_strip_sim2.py`). Manual testing here confirms the **symptoms** are absent: no leaked markup (C.1, C.3) and no vanished answers (C.2). If either ever appears in normal use, that's the regression to report.

---

## Result

- Date/build:
- Server model confirmed Qwen3:  ☐
- Sections A–F:  A ☐  B ☐  C ☐  D ☐  E ☐  F ☐
- Overall:  PASS / FAIL —
- Failures / notes:
