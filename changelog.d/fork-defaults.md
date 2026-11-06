### Changed

- A fork's clones push to its own repository by default, so `gh` no longer offers the template first for an unpushed branch.
- Specs that only apply to the template or to a fork are excluded elsewhere rather than showing as pending.
- A fork's rename commit passes CI's comment check, so its first PR isn't refused on lines it didn't write.
