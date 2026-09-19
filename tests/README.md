Run `lua5.1 tests/run.lua` or `luajit tests/run.lua` from the repository root.

These regression tests load the real addon source with minimal WoW stubs.
They cover animation scheduling, sandbox lookups, nested aura environment activation,
options validation, raid assignments, group roles, talent caching, load conditions, talent triggers, taxi/vehicle conditions, PvP flags, ruleset migration, and instance filters. Picker checks
use stubbed frames; in-game rendering still needs manual verification.
Adapted from WeakAuras upstream sandbox tests (9069a62d).
