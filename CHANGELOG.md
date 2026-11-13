# Changelog

## Unreleased

- **A bank character.** Name one of your characters as the bank for each faction and ruleset, and
  say what goes there, on the new Bank page of the Glass Mail window (`/gmail bank`): drop an item
  on it, or add a category (Cloth, Herb, Metal & Stone and others), each with how many to keep.
  At the mailbox, a chat line says what is ready. On the Send tab, the new button on the title bar
  fills an empty draft for the bank, up to 12 stacks; you check it and press Send, then click
  again for the next mail. To keep exactly that many, it first splits the stacks it needs (one
  click, "Prepare"), then fills. Soulbound items stay. `/gmail banknotice off` turns the chat line
  off, also on the options page.
- The address book's button moved to the Send tab's title bar (where the inbox has the item
  grid's), and its list opens beside the mail window: beside the To box it covered the "P" of
  "Postage" once a mail cost more than a few copper to send.

## v0.3.0

- **Recall a mail sent to the wrong alt.** In the Glass Mail window's Sent folder, the new arrow
  on a send marks it "recall" (for mail with items or gold to your characters on this WoW
  account that have logged in with Glass Mail). When that character opens a mailbox, the mail is
  highlighted and a Return button under the mail window's tabs sends it back in one click. When two mails could
  be it, both are highlighted for you to check. The Sent row says whether the mail was last seen
  in that character's mailbox.
- Glass Mail reads the mailbox through LibMailbox, a small library it now shares with AltStable,
  so both read your mail the same way. Nothing looks different.
- **Glass UI's look.** With Glass UI installed, Glass Mail follows its appearance: its material,
  its tint (clear, smoked or your class colour), changed live from Glass UI's "Suite look" page,
  and its accent colour on the address book's headings. A look you pick in Glass Mail's options
  wins over Glass UI's; "Glass UI" there goes back to following. Blizzard's own look shows on
  Glass UI's page as Glass Mail's choice. Switching to or from Blizzard's own look in combat
  waits for the fight to end.
- The glass is the softer Pearl material now, with or without Glass UI.
- The embedded glass library is LibGlass r11.

## v0.2.1

- Typing in the To box now completes your characters on your other WoW accounts too (the ones
  AltStable knows), which the game's own suggestions can't see. It works like the game's: the rest
  of the name appears highlighted, keep typing to change it, Enter or Tab to keep it. Names the
  game already suggests are left to it.
- Under glass, the inbox keeps its shape when it is empty: a faint slot where each row's icon
  goes, a line between rows, and the envelope with "No mail" (without the lines) when there is
  none. Off on the options page or with `/gmail guides off`.

## v0.2.0

- Every item in the mailbox in one grid: the bag button on the inbox's title bar opens a panel
  beside it, each item merged across mails with its total count; hover for how many mails hold
  it, click to take every copy (money, other items and COD mail stay), Stop to end it.
- An address book on the send tab: the button right of the To box lists your own characters
  that can receive mail from this one (same faction and ruleset, whichever realm), the names you
  mailed recently, your friends and your guild, with a search box: type part of a name, even in a
  guild of hundreds, each name in its class colour. Click one, or press Enter for the first, and it
  goes in the To box; you still click Send.
- The To box starts with the last name this character mailed, highlighted, so two sends in a
  row to the same alt need no typing. Reply still puts the sender in. Off on the options page
  ("Fill in the last name this character mailed") or with `/gmail autofill off`.
- The Glass Mail window (`/gmail mail`, or the new button on the mailbox's title bar), organised
  like Gmail: **Sent** (every send and return, newest first, with what it carried and whether the
  game confirmed it), **Inbox** (each character's mailbox as you last saw it: what is worth
  keeping, gold, the first expiry, and every mail) and **Trash**. Search names, subjects and item
  names; forget any row with its ×.
- Each character's mailbox is remembered when you visit it, so the window can show your alts'
  mail from anywhere. A mail goes from memory when it would have expired; the rest goes with its
  character.
- Glass Mail remembers what you send: every send is kept in Sent, marked sent once the game
  confirms it, or unconfirmed when no confirmation can be tied to it. Mail you return goes there too, as "returned to". Mail you delete
  goes to Trash, until it would have expired. Only what Glass Mail could prove is kept: a delete or
  return made while another mail action was still in flight is left out.
- Nothing piles up: a name you stop mailing, an alt you stop playing and an old Sent record are
  forgotten after 30 days of play (7, 14, 60 or 90 on the options page, or `/gmail expiry`); days
  you don't play don't count. The recent recipients are capped at 20 (10 or 50, `/gmail recents`).

- Glass Mail is now also on Wago Addons (the Wago app installs and updates it) and on GitHub
  Releases, with a `release.json` for addon managers such as WowUp.
- Other addons can read the mails you selected: `GlassMail.Selection.Get()` and
  `GlassMail.Selection.OnChange(fn)` (docs/PUBLIC-API.md). Shatter's Mail Mode reads them for
  its "Selected mails" option.
- Closing the mailbox during Open (n) no longer risks leaving the unopened mails selected.
- An open letter's portrait is the glass scroll under glass, to match the mail window's envelope.
- LibGlass r8. Switching between clear and smoked repaints the wash through `SetWash`, the
  library's supported way to change it (a gradient ignores `SetAlpha` on Forever).

## v0.1.0

Released 2026-10-13. The first release.

- Two glass looks, **clear** and **smoked**, on LibGlass r6's clean material (thin rims, no
  grain), or Blizzard's own art: `/gmail skin
  clear/smoked/stock` or the options page, switched live. The glass now covers the inset, the inbox
  rows' borders and the divider bars; a reading pane sits under the inbox rows. Under glass the
  letters are dark too, with light text (and a selection colour you can read it on), on the send
  tab and in an open letter. Each window's content and the send tab's footer sit on their own
  dark pane, as in the mockup, so busy scenery or the quest tracker don't read through.
  The mail window's portrait is the Glass Mail envelope under glass.
  Switching looks with a letter open recolours it at once.
- **Open All with filters**, in place of Blizzard's button: right-click it to choose Auction House,
  system and player mail, and how many bag slots to keep free (0, 2, 5 or 10). Money first, then
  each attachment that fits (a partial stack or a matching special bag counts as room); COD and
  GM mail are left for you. It stops when the mailbox closes, in combat, if anything else takes
  or returns mail, or when a take isn't confirmed within 5 s, and prints one line with what it
  took and what it left. The inbox shows how many messages it holds.
- **Select mail** with a checkbox on each row (shift-click for a range, ctrl-click for everything
  from that sender), then **Open** the selection or **Return next**, one mail per click. Each row
  also has a Return or Delete icon (Delete only for an empty mail), and its tooltip lists every
  attachment and the full subject. Identical mails can't be selected, nothing runs while a letter
  is open, and the controls wait out combat.
- **At the mailbox:** the gold Open All and Open (n) collected, in one line when you close it (money
  you take by hand from a letter isn't counted). Trades are blocked while it is open, through the
  game's own Block Trades setting, which is put back as it was (`/gmail tradeblock on/off`).
  `/gmail tradeblock` says who is blocking trades right now, and if the setting can't be put back,
  a chat line says so and where to turn it off.
- **New mail:** one chat line with the senders when new mail comes while you are away from the
  mailbox (`/gmail alert on/off`). It goes by the latest senders, so a second mail from the same
  people isn't announced again.
- `/gmail help` lists the commands; the same settings are on the options page.
