# Glass Mail

A mailbox addon for **World of Warcraft: Forever**, in the liquid-glass look of the Glass addons.

It keeps Blizzard's mail windows and adds what the mailbox is missing.

**v0.1.0** (the first release):
- **Two glass looks**, clear and smoked, or Blizzard's own art, switched live.
- **Open All with filters**: Auction House, system and player mail, and how many bag slots to keep
  free. Money first, then each attachment that fits; COD and GM mail are left for you.
- **Select mail** with a checkbox on each row (shift for a range, ctrl for a sender), then Open the
  selection or Return it, one mail per click.
- **Row extras:** a Return or Delete icon, and a tooltip with every attachment and the full subject.
- **At the mailbox:** the gold collected, trades blocked while it is open, and a chat line with the
  senders when new mail comes.

**Planned** ([docs/FEATURES.md](docs/FEATURES.md)): an inbox view of all your attachments, an
address book of your characters and contacts, a memory of every character's mailbox you can
browse from anywhere, a history of what you sent where, and help sending to your bank character.

`/gmail help` lists the commands.

## Development

- Tests: `pwsh tests/run.ps1` (Lua 5.1, needs a LibGlass checkout at `..\LibGlass` or `$env:LIBGLASS`).
- Deploy a dev copy: `pwsh Tools/deploy.ps1 -Probe`.
- See [CLAUDE.md](CLAUDE.md) for the conventions.

License: GPL-3.0. The embedded LibGlass-1.0 is MIT.
