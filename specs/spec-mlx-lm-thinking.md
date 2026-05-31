# Spec: Thinking Support for mlx-lm Backend

## Status: SUPERSEDED — premise was wrong

> **Correction (verified against the installed `mlx_lm.server`):** this spec assumed Qwen3 via
> mlx-lm emits `<think>...</think>` **inline in the content stream**. It does not. `mlx_lm.server`
> has a reasoning state machine that streams chain-of-thought in a **separate `delta.reasoning`
> field** (`mlx_lm/server.py:1353–1358`), with the thinking tokens removed from `content`.
>
> The real bug was that `_normalize_oai_stream` read only `delta.content` and hardcoded
> `thinking=""`, dropping the reasoning before any strip/emit logic ran. The fix is to surface
> `delta.reasoning` as `msg.thinking` in `_normalize_oai_stream`; the existing emission
> (`orchestrator.py:496–499`), SSE forwarding, app rendering and persistence then work unchanged.
>
> The `<think>`-tag strip loops described below remain valid only for backends that *do* inline
> tags (e.g. Ollama). The client-side toggle-removal work in this spec was completed separately.
> Everything under this line is kept for historical context.

## Status (original): NOT IMPLEMENTED

## Problem

The mlx-lm backend is explicitly excluded from thinking in Mira, even though mlx-lm models that support thinking (e.g. Qwen3-MLX) do emit `<think>...</think>` tags in their output. The UI disables the Thinking toggle and chip when `currentBackend == "mlx-lm"`, so users cannot enable it, and if the model emits thinking tags anyway they leak into the visible response text as literal markup.

## What's actually happening

**Server side (`mira-core/core/orchestrator.py`):**

The `<think>` tag stripping loop already exists (lines 494–516). It strips `<think>...</think>` from the content stream and discards the content silently — but it does NOT emit `{"type": "thinking", "content": ...}` events for the stripped text. So thinking tokens are consumed and thrown away rather than forwarded to the client.

The mlx-lm backend goes through `_normalize_oai_stream`, which sets `msg.thinking = ""` always. The Ollama-style `.thinking` field path (line 485) therefore yields nothing for mlx-lm. The `<think>` tag path (lines 494–516) runs but strips without emitting.

**Client side (`mira-apps`):**

Three places block mlx-lm thinking in the UI:
1. `InputBar.swift` chip guard: `vm.thinkingEnabled && vm.currentBackend != "mlx-lm"`
2. `InputBar.swift` macOS Toggle: `.disabled(vm.currentBackend == "mlx-lm")`
3. `ChatViewModel.swift` lines 322 + 371: `if info.backend == "mlx-lm" { thinkingEnabled = false }` (resets thinking to off when switching to mlx-lm)

## Fix

### Server — `mira-core/core/orchestrator.py`

In the `<think>` tag parsing loop, emit thinking events alongside stripping, instead of silently discarding:

```python
# Before (lines 494–516):
while think_buf:
    if in_thinking:
        close = think_buf.find("</think>")
        if close == -1:
            think_buf = ""  # all thinking, consume
            break
        in_thinking = False
        think_buf = think_buf[close + len("</think>"):]
    else:
        open_tag = think_buf.find("<think>")
        ...

# After:
while think_buf:
    if in_thinking:
        close = think_buf.find("</think>")
        if close == -1:
            # Entire buffer is thinking content — emit and consume
            _thinking_chars += len(think_buf)
            yield {"type": "thinking", "content": think_buf}
            think_buf = ""
            break
        # Found the closing tag — emit everything before it as thinking
        thinking_fragment = think_buf[:close]
        if thinking_fragment:
            _thinking_chars += len(thinking_fragment)
            yield {"type": "thinking", "content": thinking_fragment}
        in_thinking = False
        think_buf = think_buf[close + len("</think>"):]
    else:
        open_tag = think_buf.find("<think>")
        if open_tag == -1:
            yield {"type": "token", "content": think_buf}
            full_content += think_buf
            think_buf = ""
            break
        if open_tag > 0:
            regular = think_buf[:open_tag]
            yield {"type": "token", "content": regular}
            full_content += regular
            think_buf = think_buf[open_tag:]
        else:
            in_thinking = True
            think_buf = think_buf[len("<think>"):]
```

This change benefits all backends equally — if omlx ever emits `<think>` tags (instead of the `.thinking` field), they'll surface correctly too.

### Client — `mira-apps`

**`InputBar.swift`** — remove `!= "mlx-lm"` exclusions:

```swift
// Chip guard (line ~83):
// Before:
if vm.thinkingEnabled && vm.currentBackend != "mlx-lm" {
// After:
if vm.thinkingEnabled {

// macOS Toggle disabled condition (line ~269):
// Before:
.disabled(vm.currentBackend == "mlx-lm")
// After:
// Remove .disabled modifier entirely (or keep only if a future backend needs it)
```

Also remove the `opacity` dim on the macOS HStack if it was keyed to mlx-lm.

**`ChatViewModel.swift`** — remove the two auto-reset lines (lines 322 + 371):

```swift
// Before:
if info.backend == "mlx-lm" { thinkingEnabled = false }
// After: (delete both occurrences)
```

Thinking state should be preserved when switching backends. The user controls it explicitly.

## Caveats

- mlx-lm models must support thinking for this to work. Non-thinking MLX models (Gemma, Llama etc.) don't emit `<think>` tags, so enabling the toggle has no effect — but it also causes no harm since the tag stripping loop is a no-op when no tags appear.
- The mlx-lm server does not have a `think=true` API parameter (unlike Ollama). Thinking is triggered purely by the model's behavior and system prompt. Mira's `_inject_no_think` system prompt injection (used for Ollama when thinking is off) is not called for mlx-lm — that path is Ollama-only. For mlx-lm, turning thinking "off" in Mira is advisory only — a thinking-capable model may still emit `<think>` tags.
- If turning thinking off for mlx-lm needs to be enforced, the fix would be to call `_inject_no_think` for the mlx-lm path as well. Out of scope for this spec.

## Scope
- **Both repos**: `mira-core/core/orchestrator.py` (~15 lines changed), `mira-apps` InputBar + ChatViewModel (~5 lines removed)

## Verification
1. Set backend to mlx-lm with a thinking-capable model (e.g. Qwen3-MLX)
2. Enable Thinking toggle — confirm it is no longer greyed out
3. Send a message — "Thinking…" block appears during streaming, collapses on completion
4. Send with a non-thinking MLX model — no thinking block, response renders normally
5. Switch from Ollama (thinking on) to mlx-lm — thinking toggle stays on (no auto-reset)
