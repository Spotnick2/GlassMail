-- Glass.lua: this addon's instance of the "liquid glass" material.
--
-- The material lives in the embedded library LibGlass-1.0
-- (Libs\LibGlass-1.0, from github.com/Spotnick2/LibGlass through .pkgmeta
-- externals; the TOC loads it first). Material changes are LibGlass PRs, not
-- edits here.
--
-- An instance, not the library itself: the tuning and the font registry are
-- GlassMail's own and never touch another glass addon's surfaces. Call
-- sites keep the dot-call shape (Glass.Apply, Glass.Font, Glass.MEDIA, ...).
--
-- The clean material (LibGlass r6, issue #14): thin rectangular rims, no
-- grain, softer gloss and shading. A construction setting: it shapes every
-- surface built from this instance. The body's tint stays Skin.lua's
-- (clear / smoked), repainted live.

GlassMail = GlassMail or {}
GlassMail.Glass = LibStub("LibGlass-1.0"):New({ preset = "clean" })
