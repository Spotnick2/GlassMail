# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

GlassMail is a **mailbox addon for World of Warcraft: Forever 1.60.1** (Interface `16001`),
written in **Lua 5.1**. It has a single owner (Spotnick) and uses the same stack and conventions
as the sibling Forever addons, above all `..\GlassChat` (the template for this repo's tooling,
tests and CI) and `..\AltStable` (the character tracker it integrates with). When this file
doesn't cover something, check how those handle it before you invent a new idiom.

**Goal:** the useful parts of Postal, in the Glass look, plus mail awareness across your
characters. The feature list is [docs/FEATURES.md](docs/FEATURES.md); the milestones and the
probe checklist are [docs/PLAN.md](docs/PLAN.md); measured results go in
[docs/FOREVER-PROBE.md](docs/FOREVER-PROBE.md).

**Status: M0 done** (skeleton, options page, first glass pass, MailProbe run on the live client,
results in docs/FOREVER-PROBE.md). **M1 done** (issue #4, v0.1.0; the reviewed plan is in
docs/PLAN.md): the look, the mail core with Open All, selection with row extras, and X3. **M2**
(#17) is done with PR 5 (I4, the item grid, and the v0.2.0 prep); the v0.2.0 tag waits for the
in-game gate in docs/PLAN.md ("The grid PR in detail").
Some probe items are still open; FOREVER-PROBE.md's "Still open" table says which
milestone measures each one, before the feature that depends on it ships.

## The UI contract (non-negotiable)

**Extend Blizzard's mail windows; never replace them.**
- Keep `MailFrame`, `InboxFrame`, `SendMailFrame`, `OpenMailFrame`.
- Only `hooksecurefunc`, `HookScript` and addon-owned frames. Never reassign a Blizzard global
  (not even to itself), never replace a Blizzard method (`InboxFrame:Update` is hooked, not
  overwritten), never write a field onto a Blizzard frame. Reading a template's `parentKey`
  child (`MailFrame.NineSlice`, `InboxFrame.OpenAllMail`) is fine; that's declared XML.
- The inbox rows keep their stock clicks (shift-click auto-loots). Extra actions live on our own
  controls.
- **Every send goes through Blizzard's Send button, and through the secure-transfer confirmation
  whenever Blizzard shows it** (items or gold to a stranger, `Blizzard_SecureTransferUI.lua:298`).
  Never call `SendMail` from a timer or event, whatever a probe shows.
  `C_SecureTransfer.SendMail` is restricted.
- There is **no stable mail ID**. An inbox index is valid until the next `MAIL_INBOX_UPDATE`.
  Before any action on a remembered mail, find it again and check it is the same one; if two
  mails match, don't act.

## Licensing of the references

`C:\Projects\WoW\References\Addons\Mail\` holds Postal 4.3.5 ("All Rights Reserved"), PostalReborn 1.0.04 and
Kerzo Postal Suite 3.2 (no license). **They are behaviour references only: never copy their code.**
Write everything from the client APIs and `C:\Projects\WoW\wow-ui-source`. This repo is MIT.

## Layout

TOC load order: `Libs\LibGlass-1.0\LibGlass-1.0.xml` → `Compat.lua` → `Glass.lua` → `Skin.lua` →
`Core\Scan.lua` → `Core\Loot.lua` → `Core\Ops.lua` → `Core\Names.lua` → `Core\Store.lua` → `Core\Registry.lua` →
`Core\Sent.lua` → `Core\Trash.lua` → `Core\Summary.lua` → `Core\Memory.lua` → `OpenAll.lua` → `Inbox.lua` →
`Comforts.lua` → `Window.lua` → `Address.lua` → `Bag.lua` → `Options.lua` → `GlassMail.lua`. The mail core (`Core\`) loads before the feature files.

- **`Compat.lua`**: `GlassMail.API`, the only route to client APIs that moved or may be absent:
  `IsSecret`, `RegisterEvents` (reports failures), `NoteCombat` / `InCombat` (`InCombatLockdown()` is
  still false inside the `PLAYER_REGEN_DISABLED` handler), `Fail(key, err)` (the **one** failure recorder,
  read by `/gmail failures`), `PlayerFullName`, `AddOnVersion`, `SafeFrame`, `Button`;
  `MEASURED_ON_BUILD`; `Debug` (the in-game checks' line, `/gmail debug on`, this session only). A
  subset of GlassChat's; lift more from there.
- **`Glass.lua`**: `GlassMail.Glass = LibStub("LibGlass-1.0"):New({ preset = "clean" })` (LibGlass r8's
  clean material: thin rims, no grain), this addon's instance of
  the material. Material changes are LibGlass PRs.
- **`Skin.lua`**: the look, `GM.db.skin` = `clear` / `smoked` (glass presets, AltStable's
  numbers) or `stock`. A glass panel under each mail window and a reading pane under the inbox
  rows, repainted live by `Skin.Refresh()`. The stock art (template parentKeys, the inset,
  `InboxFrameBg`, the row borders, the horizontal bars and their unnamed ends) is faded with
  `SetAlpha`, never hidden, and found by structure, never by texture path (`GetTexture` returns
  file IDs). Under glass the letters go dark (`docs/mockups/inbox-and-send.png`): the stationery is
  faded, a pane takes its place, and the letter's text is turned light with `SetTextColor` on the
  mail widgets themselves, never on the shared font objects. Stationery, pane and text change
  together, per window; `stock` puts Blizzard's colours back. Sections as in the mockup: a pane
  on each window's content box (its `Inset`, which Blizzard moves per tab) and on the send tab's
  footer; the letter and row panes stack on them, darker. The mail window's portrait becomes the
  Glass Mail envelope (`Media\Envelope.tga`) and an open letter's the glass scroll
  (`Media\Scroll.tga`), our textures over Blizzard's faded ones.
- **`Core\Scan.lua`**: the inbox as plain values (`Scan.Inbox()`), never `GetInboxText`. Each mail
  has a type (`ah` by the six `AUCTION_*_MAIL_SUBJECT` templates, `system` when it can't be
  replied to, else `player`) and a fingerprint (length-prefixed sender, subject, money, COD,
  returned, and each slot's number, link and count). A secret field or a missing link leaves the
  mail unresolved: no fingerprint. `Scan.Residual` is the fingerprint an action should leave.
- **`Core\Loot.lua`**: what Open All takes next (`Loot.Next`, money first, then slots from the
  lowest) and whether an item fits (`Loot.Fits`: unlocked partial stacks, a specialty bag of its
  family, general slots above `keepFree`; unknown when not cached). Bags 0-4.
- **`Core\Ops.lua`**: the one owner of mail actions. One run, one attempt at a time, confirmed only
  from the inbox: the fingerprint's count fell by one and its residual's rose by one (or, for a
  mail its last take empties, the loaded count fell by one instead: removed; a mail with letter
  text can stay, empty). 5 s unconfirmed stops as
  uncertain. Foreign mail calls (post-hooks), the mailbox closing, combat and an input-mode change
  stop the run, and so does a letter being opened: nothing runs while one is open (Blizzard keeps it
  as a bare index; a removal above it would shift it). Open All takes twins (no remembered target);
  a remembered target (the selection, a Return / Delete) needs one match, and waits for every mail
  to load (5 s at most; our controls stay disabled meanwhile). Run kinds: `openall`,
  `selected` (its targets move to their residuals), `items` (I4: `opts.items`, only those items,
  never money; an unresolved mail is `loading`), `return`, `delete`; `Ops.Watch` repaints
  every control when a run starts or stops. A `SendMail` is a foreign call too.
- **`Core\Names.lua`**: `Names.Key` (trimmed, spaces collapsed, lower-cased; a `-Realm` suffix kept)
  and `Names.Display` (trimmed). A secret name has neither.
- **`Core\Store.lua`**: M2's saved memory in `GlassMailDB`: `version`, the play-day clock
  (`playDay`, `lastDate`, a high-water mark; `Store.Tick` at login and every 10 minutes), and the
  subtrees `chars`, `recents`, `sent`, `trash`, `snapshots`. Each subtree is read with a shape check
  and dropped whole if it fails; a secret field is never saved. Expiry: `expiryDays` play days
  (Trash and a snapshot's mails: when the mail would have expired; a snapshot goes with its
  character), then the caps (`recentMax`, 1000 Sent, 500 Trash, 100 mails a snapshot). The forget
  calls, and `Store.OnChange` after every change. The settings in the same table aren't its
  business.
- **`Core\Registry.lua`**: own characters by GUID (`chars`, refreshed on every tick), or
  AltStable's list live when it is loaded (`PUBLIC_API_VERSION` 1 with the `provenance` feature;
  only its `self` and `own-account` characters, never a third party's; nothing from it saved);
  `Registry.Reachable` (same faction tag and ruleset, `Registry.RulesetOf` from the realm name,
  any realm of it; not the current character).
- **`Core\Sent.lua`**: every send, captured at the `SendMail` post-hook and attributed by a 120 s
  window (`sent` only when it is the one candidate at `MAIL_SEND_SUCCESS`, else `unconfirmed` at its
  end; a stranger's send waits for the dialog's close; error 457 drops it), plus the returns Trash
  confirms. A `sent` send makes a recent recipient and its character's `lastTo` (S1's fill); every
  success first clears the current character's `lastTo`, so only an attributed one sets it.
- **`Core\Trash.lua`**: every Delete / Return, ours or Blizzard's, captured at its post-hook and kept
  only when the next update proves it (its fingerprint and the loaded count each one fewer, within
  5 s, on a settled inbox, with no other call in between). Deletes go to Trash, returns to Sent.
- **`Core\Summary.lua`**: `Summary.Of(snapshot, now)`, AltStable's mail rule (mails with items or
  money and time left: count, money, soonest expiry).
- **`Core\Memory.lua`**: X1's snapshots. A visit runs from `MAIL_SHOW` to the close; each inbox
  update in it scans a frame later, for that visit only; a scan replaces the character's snapshot
  only when it read every loaded mail whole (else the old one stays). That the first update carries
  the visit's own inbox is assumed, checked in game before v0.2.0 (the debug line logs each scan).
- **`OpenAll.lua`**: I1. Our button in the stock one's place (hidden in mouse mode on every show;
  left alone in gamepad UI mode), right-click filters (`MenuUtil`), the message count, a chat
  summary at the end.
- **`Inbox.lua`**: I2 + I3. Per row, our checkbox and Return / Delete icon (Blizzard's rule,
  `InboxItemCanDelete`; Delete only for empty mail; Return never falls through), enabled only for a
  mail with no twin. The selection is a set of fingerprints for this visit (shift: range, ctrl:
  sender); the bar has Open (n), Return next (n left) (one click per mail) and Clear. The row
  tooltip gets each attachment and the full subject. Everything disables in combat and while
  another run or a letter is open. `GlassMail.Selection` (`Get`, `OnChange`) is the selection's
  public read API, for Shatter (`docs/PUBLIC-API.md`): keep its contract when changing the selection.
- **`Comforts.lua`**: X3. The gold Ops confirmed this visit (`Ops.TakeVisitMoney`), said at close;
  the trade block (the `blockTrades` CVar while the mailbox is open; only our own block is undone,
  nothing written in combat, a per-character claim for crash recovery; never silent: a failed
  unblock and a login recovery are said in chat, `/gmail tradeblock` names who blocks); the new-mail alert (the
  latest senders changed, away from the mailbox).
- **`Window.lua`**: Glass Mail's own window (`/gmail mail`, and our button on the mailbox's title
  bar): Inbox (each character's snapshot, opening into its mails), Sent and Trash, a search box
  (names, subjects, item names loaded on demand once per session), a forget × on every row. A pool
  of rows and an offset; glass in the current preset (`stock` shows it smoked, `Skin.AddWindow` /
  `AddPane`). Escape closes it out of combat only (its `UISpecialFrames` entry leaves in combat).
- **`Address.lua`**: S1. Our button right of `SendMailNameEditBox` opens a `MenuUtil` menu: my
  characters (reachable, not hidden), recents, friends, the guild (a scrolling submenu); each name
  once, no other realm's, never the current character. A pick is `SetText` and nothing else. The
  fill: an empty To box gets `recents[chars[guid].lastTo].name`, highlighted, from a
  `MailFrameTab_OnClick` post-hook and a frame after an attributed send (`Sent.onConfirmed`);
  setting `autofill`. No focus hooks on Blizzard's box.
- **`Bag.lua`**: I4. Our bag button on the inbox's title bar (left of the window's) toggles a
  glass panel beside `MailFrame` (a child of `InboxFrame`): every non-currency attachment merged
  by itemID in a fixed pool of 6 x 9 buttons, a row offset. A click is an Ops `items` run
  (`Ops.TakeItems`: only those items, never money, COD and GM left); the footer's Stop, or the
  item's own button, stops it. Refreshed only while visible.
- **`Options.lua`**: the Esc > Options > AddOns page, built with the porting guide's recipe.
  Choices are radio groups (`radios`), not dropdowns; on/off settings are checkboxes (`checkbox`).
- **`GlassMail.lua`**: bootstrap, saved settings (only what the player set is saved), the
  `Settings` helpers, `/gmail`.
- **`Tools/MailProbe/`**: the throwaway measurement addon, a ForeverProbe module (`..\ForeverProbe`,
  its `docs/GUIDE.md`): `/fp mail` for its commands, `/fp steps mail <name>` for guided procedures;
  its lines go to the `/fp` console, never to chat. Its tests run locally only (CI skips them).

## Mail facts for this client

- The mail UI is `Blizzard_MailFrame` (not load-on-demand); there is no `FrameXML` variant. Read
  `C:\Projects\WoW\wow-ui-source\Interface\AddOns\Blizzard_MailFrame\MailFrame.lua` and `.xml` first.
- Postal-era globals are gone: `InboxFrame_Update` → `InboxFrame:Update()`, `OpenMail_Update` →
  `OpenMailFrame:Update()`; the page buttons are `InboxFrame.PrevPageButton` / `NextPageButton`.
- Blizzard already has an Open All button (`OpenAllMail`, `OpenAllMailMixin`): it skips COD and GM
  mail, waits for `C_Mail.IsCommandPending()` and at least 0.15 s between takes, wraps the run in
  `C_Mail.SetOpeningAll(true/false)`, and skips item IDs that `MAIL_FAILED` reported.
- **`MAIL_CLOSED` never fires** (measured, FOREVER-PROBE session 2). The mailbox opens with
  `MAIL_SHOW` + `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` (type 17) and closes with
  `PLAYER_INTERACTION_MANAGER_FRAME_HIDE` (17), which can fire twice at logout. Hiding
  `OpenAllMail` calls `C_Mail.SetOpeningAll(false)`.
- The AH sender name is faction-specific ("Horde Auction House"): classify mail by the subject
  templates, never by sender. `itemCount` is nil without items; an uncached attachment's name is
  `""`, so key attachments by itemID.
- Measured looting (sessions 3-4): `TakeInboxItem` works from timers (several in a row), and so
  did one `ReturnInboxItem`. After a return the inbox shrinks **before** `MAIL_SUCCESS`, so find
  each mail again before the next action. Taking money needs no bag slot; specialty bags take
  their items when general bags are full (Blizzard's free-slot total ignores them).
  **`MAIL_FAILED(itemID)` is the failure signal**; the `UI_ERROR_MESSAGE` beside it only says
  why (type 3 = inventory full, the one reason measured). `MAIL_SUCCESS` has no itemID.
  **`GetInboxText` marks mail read**, and so did a *failed* take: never call it on unread mail
  for a snapshot, and expect any take attempt to flip `wasRead`. The stock Open All button
  reappears on every mailbox open.
- Measured in session 5: **slots don't renumber** after a take (take by the slots the mail has
  now; a take on an empty slot does nothing, no event at all). A partial stack is room enough, and
  an item that fits a specialty bag goes there before a general slot. Item links carry fields
  beyond the item ID: a fingerprint is per session, saved data keys items by itemID. AH mail is
  told by the six `AUCTION_*_MAIL_SUBJECT` templates (a canceled auction has no invoice).
  Return vs Delete is Blizzard's rule, `InboxItemCanDelete(i)` (a returned mail keeps
  `canReply = true`). `HasNewMail()` turns false when the last unread mail is read, and the
  minimap icon follows it.
- Use `C_Mail.CanCheckInbox()` before `CheckInbox()`; the inbox loads at most 100 mails at a time
  (`GetInboxNumItems` returns loaded, total).
- Containers are `C_Container.*` only; `GetContainerItemInfo` returns a struct. Items:
  `C_Item.GetItemInfo` (returns nothing on a cache miss; retry on `GET_ITEM_INFO_RECEIVED`).
- Menus: `MenuUtil` (`CreateContextMenu`, `WowStyle1DropdownTemplate`). No `UIDropDownMenu`,
  no `EasyMenu`.
- Names are "First Surname", no realm (Forever). Key characters by **GUID**; the full name is the
  mail address.
- `GetMoney()` can be secret: never compare or do arithmetic on it.

## Forever basics (shared with the siblings)

- One plain `GlassMail.toc`, `## Interface: 16001` (**`11601` is a transposed-digit bug**). Never
  commit a literal version over `@project-version@`; the deploy script writes `dev` into its copy.
- One global namespace, `GlassMail`; files start `GlassMail = GlassMail or {}` and alias
  it `local GM = GlassMail`. A `_test` seam table exposes file-local internals to tests.
- **Secret values:** test with `issecretvalue(v)` **before** any other use; never save one.
- **`RegisterEvent` throws on unknown names and returns `false` for refusals**: always
  `API.RegisterEvents`.
- `ReloadUI()` is protected. Options use `Settings.RegisterCanvasLayoutCategory`.
- SavedVariables persist as of 70009; read them at `ADDON_LOADED` / `PLAYER_LOGIN`, cope when
  they're absent, and **verify persistence only with a full client exit**.
- **IDs, never names**: never compare against or save an English display string (localized
  clients). Mail types come from the client's `AUCTION_*_MAIL_SUBJECT` globals, not literals.

## References: read these before touching an unfamiliar API

- `C:\Projects\WoW\References\Docs\PORTING-TBC-TO-FOREVER.md`: measured, addon-agnostic field notes. Treat
  them as fact. New addon-agnostic findings go there, not into a copy here.
- `C:\Projects\WoW\References\Forever\api\forever-api-1.60.1.70291.md`: the API dump (functions, events, widget
  methods, `_G`). **Presence is not a contract.** Mail: `MailInfoDocumentation.lua` in
  wow-ui-source's `Blizzard_APIDocumentationGenerated`.
- `C:\Projects\WoW\References\Docs\EMBEDDED-LIBRARIES.md`, `LIBGLASS-MIGRATION.md`: library rules.
- `C:\Projects\WoW\wow-ui-source` (branch `forever`): the client's own FrameXML; line numbers match
  in-game error traces.
- `C:\Projects\WoW\AltStable\PublicAPI.lua` and `docs\PUBLIC-API.md`: the character list we read.

## Toolchain and commands

Lua 5.1 at `C:\Program Files (x86)\Lua\5.1\` (`lua.exe`, `luac.exe`). No build step.

```powershell
pwsh tests\run.ps1                                                   # luac -p on the TOC files + probe, then every tests\test_*.lua, through WowTestKit at its pin (needs ..\LibGlass or $env:LIBGLASS)
pwsh tests\run.ps1 -KitDev                                           # the same against the ..\WowTestKit working copy
& 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_boot.lua      # one test, from the repo root (once run.ps1 has fetched the kit)
pwsh Tools\deploy.ps1 -Probe                                         # copy the addon (+ MailProbe) into AddOns
```

- Default AddOns path: `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns`
  (`-AddOnsPath` to change).
- In game: `/console scriptErrors 1` first, then `/reload`. A brand-new addon folder no longer
  needs a client restart, unless it brings new textures (owner, 2026-10-09; see the porting guide).
- Shell heredocs in this environment can collapse `\\` to `\`: write files that contain Lua
  backslash escapes or Windows paths with the Write/Edit tools.

## Testing

The test scaffolding is WowTestKit (`C:\Projects\WoW\WowTestKit`; its README is the reference)
at the commit and client build `tests\kit.pin` names. `tests\run.ps1` puts that commit in
`%LOCALAPPDATA%\WowTestKit\<sha>` and hands off to the kit's runner; CI fetches it with
`tests\fetch_kit.sh`. `tests\kit.lua`, `kit.ps1` and `fetch_kit.sh` are the kit's bootstrap
copies: never edit them here. A kit need is an issue on the kit, worked around in
`tests\wow_stubs.lua` with a `-- WowTestKit #N:` comment meanwhile. `tests\run.ps1 -KitDev`
runs against the `..\WowTestKit` working copy instead of the pin.

The kit's core has the mechanics (strict globals, secrets as throwing `newproxy` values, event
names checked against the pinned build, every widget method recorded, `print` with the
stray-`|` check, timers, `check` / `eq` / `done`). `tests\wow_stubs.lua` adds the mailbox's
client APIs, the mail windows' frames and the widget methods the core lacks;
`tests\harness.lua` has `loadAddon`, `newChat`, `chatHas`; `test_methods.lua` checks every
`Type:Method` called exists on that widget type in the pinned build (`Kit.checkMethods`).
**Mutation-test every new test**: break the behaviour, confirm it goes red. Offline tests
can't cover taint, real secrets or rendering; that's the probe and an in-game checklist.

## Workflow and releasing

Same as GlassChat's CLAUDE.md, "Workflow and releasing":
- Issue → branch off `main` → PR with `Closes #N`. A milestone that spans several PRs uses
  `Part of #N` until the last one, which says `Closes #N`. Never commit to `main`; commit or push only
  when asked. `luac -p` clean and tests green before committing; check the PR's `package-check`
  run after pushing.
- **The owner merges and closes PRs and launches reviews.**
- **Plans** get an adversarial review before coding: Codex via the `codex-consult` skill,
  `gpt-6-astra` at high effort, looping until consensus. Hand it this file, `docs/PLAN.md`,
  `docs/FEATURES.md` and the porting guide. Verify its claims; push back on complexity.
- **Code reviews are manual** (by the owner) unless the owner asks for one.
- **A tag publishes three times** (`C:\Projects\WoW\References\Docs\RELEASING.md`):
  - CurseForge (project `1743548`) builds its own file from the tag webhook through `.pkgmeta`;
  - CI's `release` job makes a GitHub Release with the zip `check` built and `release.json`;
  - CI's `wago` job uploads the same zip to Wago Addons (project `b6XybbKp`, the TOC's `X-Wago-ID`;
    the `WAGO_API_TOKEN` secret, only that job sees it).
  The notes are the tag's `## vX.Y.Z` section of `CHANGELOG.md` (`tests/release_files.sh`, the
  template's copy, unchanged; an alpha falls back to `## vX.Y.Z`, then `## Unreleased`). The packager
  never uploads from CI (`-d`). Publish a failed tag again from Actions: Run workflow from `main`,
  `tag` + `publish`.

## Conventions

- **Right-size for a single maintainer.** The simplest thing that works; no speculative
  abstraction. No library until a second addon needs the code (M3).
- **Measured beats reasoned.** If a claim about the client can be checked in game, check it.
- Match the surrounding code's idiom. Keep pure refactors in their own commit.

## Consulting Codex

The shared `codex-consult` skill (user level) has the invocation and the gotchas. For this repo:

For GlassMail, good things to hand Codex:
- anything that takes, returns, deletes or sends mail: index revalidation after inbox updates,
  pacing, what counts as success, what happens when the mailbox closes mid-run;
- anything that touches a Blizzard mail frame or the send path (`SendMail`, secure transfer),
  where taint can get the action blocked;
- anything that writes to SavedVariables (mail snapshots, history), or reads `GetMoney`;
- any plan that grows scope back toward full Postal or Kerzo, or replaces a stock mail function
  instead of extending it.

**Always hand it `CLAUDE.md`, `docs/PLAN.md` and `docs/FEATURES.md` alongside the diff or plan**,
plus `C:/Projects/WoW/References/Docs/PORTING-TBC-TO-FOREVER.md` and `docs/FOREVER-PROBE.md`. Those findings
were measured on the live client. Without them, a cold reviewer argues from Classic-era or Retail
behaviour that doesn't hold here (that names carry a realm, that the old global mail functions
exist).
`C:/Projects/WoW/References/Forever/api/forever-api-<version>.<build>.md` (take the highest build) is the full API surface when a question
turns on whether something exists, and `C:/Projects/WoW/wow-ui-source` (branch `forever`) is the
client's own FrameXML (`Blizzard_MailFrame`). The design references are in
`C:/Projects/WoW/References/Addons/Mail/` (Postal, PostalReborn, Kerzo); they are behaviour references only,
their code is never copied, and their RawHooks are the part we deliberately don't use.
