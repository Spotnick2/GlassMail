# Glass Mailbox

A mailbox addon for **World of Warcraft: Forever**, in the liquid-glass look of the Glass addons.

It keeps Blizzard's mail windows and adds what the mailbox is missing: Open All with filters,
multi-select, a tooltip of every attachment, an inbox view of all your attachments, an address
book of your characters and contacts, a memory of every character's mailbox you can browse from
anywhere, a history of what you sent where, and help sending to your bank character.

**Status:** early development (milestone M0). The planned features are in
[docs/FEATURES.md](docs/FEATURES.md).

`/gmail help` lists the commands.

## Development

- Tests: `pwsh tests/run.ps1` (Lua 5.1, needs a LibGlass checkout at `..\LibGlass` or `$env:LIBGLASS`).
- Deploy a dev copy: `pwsh Tools/deploy.ps1 -Probe`.
- See [CLAUDE.md](CLAUDE.md) for the conventions.

License: GPL-3.0. The embedded LibGlass-1.0 is MIT.
