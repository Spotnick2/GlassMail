# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

GlassMailbox is a **mailbox addon for World of Warcraft: Forever 1.60.1** (Interface `16001`),
written in **Lua 5.1**. It has a single owner (Spotnick) and uses the same stack and conventions
as the sibling Forever addons, above all `..\GlassChat` (the template for this repo's tooling,
tests and CI) and `..\AltStable` (the character tracker it integrates with). When this file
doesn't cover something, check how those handle it before you invent a new idiom.

**Goal:** the useful parts of Postal, in the Glass look, plus mail awareness across your
characters. The feature list is [docs/FEATURES.md](docs/FEATURES.md); the milestones and the
probe checklist are [docs/PLAN.md](docs/PLAN.md); measured results go in
[docs/FOREVER-PROBE.md](docs/FOREVER-PROBE.md).

**Status: M0** (skeleton, options page, first glass pass, MailProbe). No feature code until the
probe has run on the live client.

## The UI contract (non-negotiable)

**Extend Blizzard's mail windows; never replace them.**
- Keep `MailFrame`, `InboxFrame`, `SendMailFrame`, `OpenMailFrame`.
- Only `hooksecurefunc`, `HookScript` and addon-owned frames. Never reassign a Blizzard global
  (not even to itself), never replace a Blizzard method (`InboxFrame:Update` is hooked, not
  overwritten), never write a field onto a Blizzard frame. Reading a template's `parentKey`
  child (`MailFrame.NineSlice`, `InboxFrame.OpenAllMail`) is fine; that's declared XML.
- The inbox rows keep their stock clicks (shift-click auto-loots). Extra actions live on our own
  controls.
- **Every send goes through Blizzard's Send button and its secure-transfer confirmation.** Never
  call `SendMail` from a timer or event, whatever a probe shows. `C_SecureTransfer.SendMail` is
  restricted.
- There is **no stable mail ID**. An inbox index is valid until the next `MAIL_INBOX_UPDATE`.
  Before any action on a remembered mail, find it again and check it is the same one; if two
  mails match, don't act.

## Licensing of the references

`C:\Projects\References\Mail\` holds Postal 4.3.5 ("All Rights Reserved"), PostalReborn 1.0.04 and
Kerzo Postal Suite 3.2 (no license). **They are behaviour references only: never copy their code.**
Write everything from the client APIs and `C:\Projects\wow-ui-source`. This repo is GPL-3.0.

## Layout

TOC load order: `Libs\LibGlass-1.0\LibGlass-1.0.xml` → `Compat.lua` → `Glass.lua` → `Skin.lua` →
`Options.lua` → `GlassMailbox.lua`. M1 adds `Core\*.lua` (the mail core) before the feature files.

- **`Compat.lua`**: `GlassMailbox.API`, the only route to client APIs that moved or may be absent:
  `IsSecret`, `RegisterEvents` (reports failures), `Fail(key, err)` (the **one** failure recorder,
  read by `/gmail failures`), `PlayerFullName`, `AddOnVersion`, `SafeFrame`, `Button`;
  `MEASURED_ON_BUILD`. A subset of GlassChat's; lift more from there.
- **`Glass.lua`**: `GlassMailbox.Glass = LibStub("LibGlass-1.0"):New()`, this addon's instance of
  the material. Material changes are LibGlass PRs.
- **`Skin.lua`**: a glass panel under each mail window; the stock art (`NineSlice`, `Bg`,
  `TopTileStreaks`) faded with `SetAlpha`, never hidden.
- **`Options.lua`**: the Esc > Options > AddOns page, built with the porting guide's recipe.
- **`GlassMailbox.lua`**: bootstrap, saved settings (only what the player set is saved), the
  `Settings` helpers, `/gmail`.
- **`Tools/MailProbe/`**: the throwaway measurement addon (`/mprobe help`).

## Mail facts for this client

- The mail UI is `Blizzard_MailFrame` (not load-on-demand); there is no `FrameXML` variant. Read
  `C:\Projects\wow-ui-source\Interface\AddOns\Blizzard_MailFrame\MailFrame.lua` and `.xml` first.
- Postal-era globals are gone: `InboxFrame_Update` → `InboxFrame:Update()`, `OpenMail_Update` →
  `OpenMailFrame:Update()`; the page buttons are `InboxFrame.PrevPageButton` / `NextPageButton`.
- Blizzard already has an Open All button (`OpenAllMail`, `OpenAllMailMixin`): it skips COD and GM
  mail, waits for `C_Mail.IsCommandPending()` and at least 0.15 s between takes, wraps the run in
  `C_Mail.SetOpeningAll(true/false)`, and skips item IDs that `MAIL_FAILED` reported.
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

- One plain `GlassMailbox.toc`, `## Interface: 16001` (**`11601` is a transposed-digit bug**). Never
  commit a literal version over `@project-version@`; the deploy script writes `dev` into its copy.
- One global namespace, `GlassMailbox`; files start `GlassMailbox = GlassMailbox or {}` and alias
  it `local GM = GlassMailbox`. A `_test` seam table exposes file-local internals to tests.
- **Secret values:** test with `issecretvalue(v)` **before** any other use; never save one.
- **`RegisterEvent` throws on unknown names and returns `false` for refusals**: always
  `API.RegisterEvents`.
- `ReloadUI()` is protected. Options use `Settings.RegisterCanvasLayoutCategory`.
- SavedVariables persist as of 70009; read them at `ADDON_LOADED` / `PLAYER_LOGIN`, cope when
  they're absent, and **verify persistence only with a full client exit**.
- **IDs, never names**: never compare against or save an English display string (localized
  clients). Mail types come from the client's `AUCTION_*_MAIL_SUBJECT` globals, not literals.

## References: read these before touching an unfamiliar API

- `C:\Projects\References\PORTING-TBC-TO-FOREVER.md`: measured, addon-agnostic field notes. Treat
  them as fact. New addon-agnostic findings go there, not into a copy here.
- `C:\Projects\References\forever-api-1.60.1.70291.md`: the API dump (functions, events, widget
  methods, `_G`). **Presence is not a contract.** Mail: `MailInfoDocumentation.lua` in
  wow-ui-source's `Blizzard_APIDocumentationGenerated`.
- `C:\Projects\References\EMBEDDED-LIBRARIES.md`, `LIBGLASS-MIGRATION.md`: library rules.
- `C:\Projects\wow-ui-source` (branch `forever`): the client's own FrameXML; line numbers match
  in-game error traces.
- `C:\Projects\AltStable\PublicAPI.lua` and `docs\PUBLIC-API.md`: the character list we read.

## Toolchain and commands

Lua 5.1 at `C:\Program Files (x86)\Lua\5.1\` (`lua.exe`, `luac.exe`). No build step.

```powershell
pwsh tests\run.ps1                                                   # luac -p on the TOC files + probe, then every tests\test_*.lua (needs ..\LibGlass or $env:LIBGLASS)
& 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_boot.lua      # one test, from the repo root
pwsh Tools\deploy.ps1 -Probe                                         # copy the addon (+ MailProbe) into AddOns
```

- Default AddOns path: `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns`
  (`-AddOnsPath` to change).
- In game: `/console scriptErrors 1` first, then `/reload`. A brand-new addon folder no longer
  needs a client restart, unless it brings new textures (owner, 2026-10-09; see the porting guide).
- Shell heredocs in this environment can collapse `\\` to `\`: write files that contain Lua
  backslash escapes or Windows paths with the Write/Edit tools.

## Testing

GlassChat's harness, trimmed: `tests\wow_stubs.lua` (strict globals as an allowlist of APIs
verified in the dump, secrets as throwing `newproxy` values, event names validated against the
dump or `tests\events-70291.txt`, every widget method recorded), `tests\harness.lua` (`check`,
`eq`, `loadAddon`, `newChat`, `chatHas`), `test_methods.lua` (every method called exists on this
client). **Mutation-test every new test**: break the behaviour, confirm it goes red. Offline tests
can't cover taint, real secrets or rendering; that's the probe and an in-game checklist.

## Workflow and releasing

Same as GlassChat's CLAUDE.md, "Workflow and releasing":
- Issue → branch off `main` → PR with `Closes #N`. Never commit to `main`; commit or push only
  when asked. `luac -p` clean and tests green before committing; check the PR's `package-check`
  run after pushing.
- **The owner merges and closes PRs and launches reviews.**
- **Plans** get an adversarial review before coding: Codex via the `codex-consult` skill,
  `gpt-6-astra` at high effort, looping until consensus. Hand it this file, `docs/PLAN.md`,
  `docs/FEATURES.md` and the porting guide. Verify its claims; push back on complexity.
- **Code reviews are manual** (by the owner) unless the owner asks for one.
- CurseForge builds releases from the tag webhook through `.pkgmeta`; the `release` job publishes
  a GitHub Release from the tag's `## vX.Y.Z` section of `CHANGELOG.md`.

## Conventions

- **Right-size for a single maintainer.** The simplest thing that works; no speculative
  abstraction. No library until a second addon needs the code (M3).
- **Measured beats reasoned.** If a claim about the client can be checked in game, check it.
- Match the surrounding code's idiom. Keep pure refactors in their own commit.
