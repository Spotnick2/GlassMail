# Glass Mail

A mailbox addon for **World of Warcraft: Forever**, in the liquid-glass look of the Glass addons.
It keeps Blizzard's mail windows and adds what the mailbox is missing: Open All with filters,
checkboxes to select mail, every item in the inbox in one grid, an address book, and a memory of
what you sent, what you deleted and what waits in each of your characters' mailboxes.

![The inbox in glass: two mails ticked, the Open (2) bar above the rows, a Return icon on the first row and Delete icons on the empty mails](docs/images/selected.png)

## Install

Install **Glass Mail** from [CurseForge](https://www.curseforge.com/wow/addons/glass-mail) with
the CurseForge app, or from [Wago Addons](https://addons.wago.io/addons/glassmail) with the Wago
app. Both keep it up to date. Or download the zip from
[GitHub Releases](https://github.com/Spotnick2/GlassMail/releases) and unzip it into the
`Interface\AddOns` folder inside your Forever game folder. Then `/reload`, or start the game.
Visit a mailbox: there is nothing else to open.

## What it does

**Two glass looks**, clear and smoked, or Blizzard's own art. The look changes live, from the
options page or `/gmail skin`. Under glass the letters are dark too, with light text.

**Open All with filters.** Glass Mail's Open All takes the place of Blizzard's button. Right-click
it to choose what it opens: Auction House, system and player mail, and how many bag slots to keep
free (0, 2, 5 or 10). It takes the money first, then each attachment that fits (a partial stack or
a matching special bag counts as room). COD and GM mail are left for you. It stops when you close
the mailbox, enter combat or take mail by hand, and prints one line with what it took and what
it left.

**Select mail.** Each row has a checkbox: shift-click selects a range, ctrl-click everything from
that sender. Then **Open** the selection, or **Return next**, one mail per click.

**Row extras.** Each row has a Return icon, or a Delete icon when the mail is empty, so nothing
with money or items is ever deleted. Its tooltip lists every attachment and the full subject.

![An open Auction House letter beside the inbox, and a row tooltip listing its attachment](docs/images/letter.png)

**Every item in one grid.** The bag button on the inbox's title bar opens a panel beside it with
every item in the mailbox, merged across mails, with its total count. Hover for how many mails
hold it; click to take every copy (money, other items and COD mail stay). A Stop button ends it.

**The Glass Mail window** (`/gmail mail`, or the letter button on the mailbox's title bar),
organised like Gmail:
- **Sent:** every send and return, newest first: to whom, from which character, when, what it
  carried, and whether the game confirmed it. "Where did I send that?" answered.
- **Inbox:** each of your characters' mailboxes as you last saw it: how many mails hold items or
  gold, how much gold, when the first expires. Click a character to see its mails.
- **Trash:** mail you deleted, until it would have expired.
- **Search** names, subjects and item names; **forget** any row with its ×. Only Glass Mail's
  memory changes, never your mailbox.

**An address book.** The button right of the To box lists your own characters that can receive
mail from this one (same faction and ruleset, whichever realm), the names you mailed recently,
your friends and your guild. Pick one and it goes in the To box; you still click Send. The To box
also starts with the last name this character mailed, so two sends in a row to the same alt need
no typing (off on the options page or with `/gmail autofill off`). With AltStable loaded, your
characters on your other accounts are listed too.

**Nothing piles up.** A name you stop mailing, an alt you stop playing and an old Sent record are
forgotten after 30 days of play (7, 14, 60 or 90 on the options page, or `/gmail expiry`); days
you don't play don't count. Mail goes from memory when it would have expired.

**At the mailbox:**
- the gold Open All collected, in one chat line when you close the mailbox;
- trades are blocked while the mailbox is open, through the game's own Block Trades setting,
  and put back as they were when you leave. `/gmail tradeblock` says who is blocking trades
  right now, and if the setting can't be put back, a chat line says so and where to turn it off;
- one chat line with the senders when new mail arrives while you're away from the mailbox.

![Writing a letter: dark stationery, light text](docs/images/send.png)

## Commands

| Command | What it does |
|---|---|
| `/gmail help` | List the commands |
| `/gmail skin clear` / `smoked` / `stock` | The mailbox's look |
| `/gmail tradeblock on` / `off` | Block trades while the mailbox is open (on by default) |
| `/gmail tradeblock` | Who is blocking trades right now |
| `/gmail alert on` / `off` | A chat line when new mail comes (on by default) |
| `/gmail mail` | The Glass Mail window: Sent, Inbox, Trash |
| `/gmail autofill on` / `off` | Start the To box with the last name this character mailed (on by default) |
| `/gmail expiry 7` / `14` / `30` / `60` / `90` | Play days before an unused name or record is forgotten (30) |
| `/gmail recents 10` / `20` / `50` | How many recent recipients are kept (20) |
| `/gmail options` | Open the options page (Esc > Options > AddOns > Glass Mail) |
| `/gmail version` | The addon's version and the client build |

`/glassmail` works too.

## Planned

Help sending to your bank character, and help with mail to return. The full list is in [docs/FEATURES.md](docs/FEATURES.md).

## Reporting a problem

Open an issue on [GitHub](https://github.com/Spotnick2/GlassMail/issues) with what you did, what
you expected and what happened instead, plus the line from `/gmail version`.

Lua errors are hidden by default on this client. If something seems broken, type
`/console scriptErrors 1` and do it again; the error text is the most useful thing you can send.

## Development

- Tests: `pwsh tests/run.ps1` (Lua 5.1, needs a LibGlass checkout at `..\LibGlass` or
  `$env:LIBGLASS`).
- Deploy a dev copy: `pwsh Tools/deploy.ps1 -Probe`.
- [CLAUDE.md](CLAUDE.md) has the conventions, [docs/PLAN.md](docs/PLAN.md) the milestones, and
  [docs/FOREVER-PROBE.md](docs/FOREVER-PROBE.md) what was measured on the live client.

## Licence

MIT, see [LICENSE](LICENSE). The embedded LibGlass-1.0 is MIT too, under its own licence.
