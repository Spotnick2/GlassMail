# Glass Mail's public API

A small, read-only API for other addons. It was first asked for by Shatter's Mail Mode
(GlassMail#26, Spotnick2/Shatter#49), which reads the mails you selected. Build on these
functions, never on Glass Mail's internals (`GlassMail._test`, the `Inbox.lua` locals): those
change without notice.

```toc
## OptionalDeps: GlassMail
```

Check before calling: the player may not have Glass Mail installed.

```lua
if GlassMail and GlassMail.Selection and GlassMail.Selection.Get then ... end
```

## `GlassMail.Selection.Get()`

Returns the inbox mails that are ticked in Glass Mail's checkboxes, as `{ [inboxIndex] = true }`.

- **What's included:** only mails with no identical twin in the inbox, and only once each is fully
  loaded. These are the mails Glass Mail's own Open (n) and Return next act on. A ticked mail
  that gains a twin, or goes away, drops out.
- **Indices:** they come from a fresh inbox read on every call, and stay good until the next
  `MAIL_INBOX_UPDATE`. Turn them into your own references straight away.
- **The table:** a new one on every call, so changing it changes nothing in Glass Mail. It is
  empty, never nil, when nothing is selected, when the mailbox is closed, or before login.
- **Cost:** while nothing is selected, a call returns at once without reading the inbox.

## `GlassMail.Selection.OnChange(fn)`

Registers `fn()`, which is called with no arguments after anything changes what `Get` returns:
- a click, a Shift-click range, a Ctrl-click on a sender, or Clear;
- a selected mail going away or gaining a twin;
- the mailbox closing, or an Open (n) run ending;
- a selected mail moving to another index (a mail arriving above it).

It isn't called when a refresh changes nothing, so it is cheap to keep a count on it. Errors in
`fn` are caught and recorded (`/gmail failures`). They don't break Glass Mail or the other
listeners. A non-function argument is ignored, and there is no way to unregister.
