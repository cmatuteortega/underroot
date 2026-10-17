-- luacheck: what CI holds the code to. Undefined and stray globals, unused
-- locals and values; not line length, unused arguments (the per-kind methods
-- share one signature), shadowing or empty branches kept for their comment.
std = "luajit"
globals = { "love" }
ignore = { "631", "212", "411", "421", "431", "542" }
