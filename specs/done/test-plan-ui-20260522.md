⏺ Here's what to check on device (or simulator for layout-only items):

  ---
  Manual validation checklist — UI overhaul (Specs 1–6)

  Spec 1 — Navigation + Welcome screen

  - Cold launch on iPhone portrait: see logo + "What can I help with?" centered, InputBar at bottom, no conversation list
  - Hamburger ≡ top-left opens sidebar overlay (slides from left, dim scrim behind)
  - Connection icon top-right opens ConnectionView sheet
  - Tapping scrim closes sidebar
  - Starting a message from WelcomeView transitions to ChatView (logo disappears, messages appear)
  - iPad: unchanged NavigationSplitView layout (sidebar always visible)

  Spec 2 — Sidebar overlay content

  - Sidebar header shows "Mira" bold left + amber connection circle button right
  - Connection circle button in sidebar header opens ConnectionView
  - Chats row appears at top of list with chat bubble icon and chevron right
  - Projects section still shows and collapses/expands
  - Conversation rows show title only (no timestamp, no project tag)
  - At most 20 conversations shown in sidebar (if you have more)
  - Section header reads "RECENT" (not "CONVERSATIONS")
  - "+ New Chat" white pill centered at bottom — tap creates new conv and closes sidebar
  - Old bottom bar (square.and.pencil + connection icon) is gone

  Spec 3 — Chat list view

  - Tapping "Chats" in sidebar closes sidebar and slides in ChatListView from the right
  - ChatListView header: hamburger ≡ left, "Chats" title center, filter icon right
  - Hamburger in ChatListView re-opens the sidebar overlay
  - Each row: conversation title + relative timestamp ("21 hours ago") + chevron right
  - Tapping a row opens ChatView and closes ChatListView
  - Swipe left on a row: Delete (red); swipe right: Rename (amber)
  - Search bar at bottom filters the list live; clear button (×) works
  - "+ New Chat" white pill above the search bar — tap creates new conv and closes list
  - Filter icon (top right) is present (stub — no action expected yet)

  Spec 4 — Chat view redesign

  - Old header bar (hamburger | title | connection icon) is gone
  - Floating pill appears at top of message area with 3 buttons: ‹ · + · ···
  - Pill has frosted/blur background (.ultraThinMaterial) and subtle border
  - First message is not hidden under the pill (56pt inset at top of scroll)
  - ‹ back button returns to WelcomeView (clears current conversation)
  - Below the last completed assistant message: copy · retry · edit icon row (left-aligned, no labels)
  - Copy icon copies message text to clipboard
  - Retry and Edit icons work (same as existing resend/edit behaviour)
  - Action row disappears while streaming (only shows when response is complete)
  - macOS chat view: no pill, no action row — unchanged

  Spec 5 — Options menu (···)

  - Tapping ··· in the pill opens a sheet (~260pt tall) with drag indicator
  - Sheet header shows the conversation title (non-tappable)
  - Add to project row: folder+ icon, shows project picker sub-sheet on tap
  - Rename row: pencil icon, opens alert with pre-filled title field, saving renames the conversation
  - Delete row: trash icon in red, opens confirmation dialog; confirming deletes the conversation and returns to WelcomeView
  - Cancelling any action closes gracefully with no side effects

  Spec 6 — "+" attachment sheet

  - Tapping + in the floating pill OR + in the InputBar bottom row both open the same attachment sheet
  - Sheet shows 3 tiles: Camera (blue) · Photos (green) · Files (orange)
  - Camera tile: opens camera (disabled/greyed on simulator — check on device)
  - Photos tile: opens system photo picker; selected images appear as attachment chips in InputBar
  - Files tile: opens file importer; selected files appear as attachment chips
  - Attached images/files are sent with the message (existing RAG/image behaviour)
  - Add to project row below divider shows current project name (or nothing if none)
  - Thinking toggle row works: tap toggles on/off, chip appears/disappears in InputBar
  - macOS: old "Files & Images + Thinking" sheet layout unchanged

  ---
  Good signal that everything is wired correctly: open sidebar → tap Chats → tap a conversation → verify floating pill is visible → tap ··· → rename → back
   out → pill ‹ returns to welcome screen.
