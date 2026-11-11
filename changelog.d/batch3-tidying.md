### Removed

- `Resource#client_visible?` is gone; look resources up through `Project#client_visible_resources`, which also leaves out deleted ones.

### Changed

- New invitations get `Invitation::LIFETIME` (7 days) when no expiry is given.
