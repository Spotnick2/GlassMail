# GlassMail features

The agreed feature list (2026-10-09), chosen by the owner from Postal 4.3.5, PostalReborn 1.0.04 and
Kerzo Postal Suite 3.2 (`C:\Projects\WoW\References\Mail\`), then reviewed adversarially (Codex,
3 rounds, consensus). The milestones that deliver them are in [PLAN.md](PLAN.md).

**Those three addons are behaviour references only.** Postal is "All Rights Reserved";
PostalReborn and Kerzo ship no license. Everything here is written independently from the client
APIs and `C:\Projects\WoW\wow-ui-source`. No code is copied.

## UI contract

- Keep Blizzard's `MailFrame`, `InboxFrame`, `SendMailFrame` and `OpenMailFrame`.
- Use only `hooksecurefunc` / `HookScript` and addon-owned frames.
- Never reassign a Blizzard global, never replace a Blizzard method, never write a field onto a
  Blizzard frame.
- Keep the stock click behaviour of the inbox rows: shift-click already auto-loots
  (`InboxFrame_OnModifiedClick`). Extra actions go on our own controls.
- Blizzard's Send button and its secure-transfer confirmation stay in the loop for every send.

## The look

Two glass presets, **clear** and **smoked**, plus Blizzard's own art (owner, 2026-10-09). The
presets are AltStable's (`AltStable/Skin.lua`), so the addons look alike; they change the body and
the reading pane, never the rim. The choice switches live. Under glass the letters are dark with
light text (owner, 2026-10-10); the target for the rest of the look is
[mockups/inbox-and-send.png](mockups/inbox-and-send.png).

## Features

| # | Feature | Notes that shape the design |
|---|---|---|
| I1 | **Open All with filters**: AH / system / player mail, keep N bag slots free, stack-aware, skips COD and GM mail. Refilling past the loaded window waits until an overflow is measured (v0.1.0 says when more mail waits) | One engine at a time (`Core/Ops.lua`). The stock `OpenAllMail` is hidden in mouse mode; in gamepad UI mode Blizzard's own is left alone and ours isn't offered. Pacing: `C_Mail.IsCommandPending` plus a 0.15 s minimum. Taking money never needs a free bag slot. Stops when the mailbox closes, in combat, on any other mail action, or after 5 s without a confirmation. |
| I2 | **Select checkboxes**: shift for a range, ctrl for everything from that sender; Open / Return the selection | The checkboxes are our own frames, refreshed from a post-hook on `InboxFrame:Update`. **There is no stable mail ID**: a selection is a handle valid for this session only. Before acting, find the current index again and check it is the same mail; if more than one mail matches, drop the selection rather than act on the wrong one. |
| I3 | **Row extras**: a tooltip listing every attachment, a Delete / Return icon per row, a tooltip for long subjects | Our own controls only; no Ctrl-click takeover of the row. Return never falls through to Delete. |
| I4 | **Mail bag grid**: every attachment in the inbox, merged by item; a click takes every copy | Uses the I1 engine with an item filter. |
| S1 | **Address book**: your own characters, recent recipients, friends, guild. No hand-kept contacts list (2026-10-13: upkeep the owner wants gone) | Friends and guild are read live, never saved; recent recipients expire (`expiryDays` play days, at most `recentMax`). v1 is our own `MenuUtil` picker button by the recipient box, filling it with `SetText`. Merging these names into Blizzard's autocomplete (`AutoCompleteEditBox_SetAutoCompleteSource` with a merged provider) is a measured exception, done later only if autocomplete followed by Send proves untainted. |
| X1 | **Alt mailbox memory** (the window's **Inbox** folder): a snapshot of each character's inbox, browsable away from the mailbox, with an item search | A snapshot carries when it was taken, the loaded and total counts, and whether it is complete. A scan with an unresolved mail, or from before the visit's first inbox update, never replaces a snapshot; a partial one (over 100 mails) does, shown as "N of M loaded". It ends when its last mail expires, or with its character. The UI shows "last seen". The search covers this WoW account's characters. |
| X2 | **Sent and Trash** (owner, 2026-10-13: like Gmail): every send, and every return Glass Mail could identify and confirm ("returned to"), in the window's **Sent** folder; deleted mail in **Trash**, kept until it would have expired | Answers "which character did I send that to?" without a tour of the alts. A sent record captures the draft as plain values when `SendMail` is called; it is *sent* only on a `MAIL_SEND_SUCCESS` that can be attributed to it, else unconfirmed (still shown, marked). Deletes and returns are kept only once the inbox shows the mail gone, and one that can't be attributed is left out; whether Blizzard's own buttons can be captured too is measured first (session 6). The window opens on Sent. Takes by hand aren't recorded. |
| X3 | **Small comforts**: gold collected this visit, trade block while the mailbox is open, a new-mail alert with the senders. No minimap item: Blizzard hides its icon once everything is read (session 5) | The gold total adds up the money the engine confirmed taken, never the change in `GetMoney()` (which can be secret); money taken by hand isn't counted. The trade block uses the client's `blockTrades` CVar and only ever undoes its own block. The alert goes by the latest senders, not by arrival (there is no arrival ID). |
| N1 | **Bank character**: name a bank character and simple rules (an item list or a category, keep N) | On mailbox open: "N items ready for <Bank>". It fills a draft only when the draft is empty, and checks everything again before sending. Each batch needs **one Send click plus any Blizzard confirmation**. Never sends from timers. |
| N2 | **Return assistance for misdirected mail** | From the history (X2), mark a sent mail "recall" (your own characters on this WoW account in v1). When that character opens a mailbox, *possible matches* are highlighted, compared on full sender, subject, money/COD and attachments with counts. Ambiguous matches need you to look. Returning is one deliberate click. |

## Character registry (for S1, X1, N1, N2)

Characters are keyed by GUID, with "First Surname" as the mail address. Each entry also keeps the
realm, ruleset and faction, and a character is offered as a recipient only when those show mail
can reach it from the current character. Two sources:
1. GlassMail's own account-wide record of the characters that have logged in.
2. AltStable, live and read-only, when it is loaded: `AltStable.GetCharacters()` (checked against
   `PUBLIC_API_VERSION`) and `AltStable.RegisterCallback("CharactersChanged", fn)`. AltStable
   already includes its cross-account characters. Nothing from it is saved here.

Recent recipients are separate address-book data, and expire. Friends and guild members are read
live, never saved.

## Later, or out

- **Later:** Drafts and Spam folders (owner, 2026-10-13: "at some point"), cross-account recall over LibAccountSync (needs request IDs, acknowledgement,
  de-duplication and states), shared-settings sync, merged autocomplete, Forward.
- **Out for now:** QuickAttach, CarbonCopy, Wire, Kerzo's full auto-send rules, "empty this
  character", a replacement inbox UI.
