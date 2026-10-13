# Changelog

## Unreleased

- First skeleton: the addon loads, `/gmail help`, an options page, and the glass look on the
  mailbox windows.
- Two glass looks, **clear** and **smoked**, or Blizzard's own art: `/gmail skin
  clear/smoked/stock` or the options page, switched live. The glass now covers the inset, the inbox
  rows' borders and the divider bars; a reading pane sits under the inbox rows. Under glass the
  letters are dark too, with light text (and a selection colour you can read it on), on the send
  tab and in an open letter. Each window's content and the send tab's footer sit on their own
  dark pane, as in the mockup, so busy scenery or the quest tracker don't read through.
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
