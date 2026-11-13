### Fixed

- `bin/setup` on a fresh shared-preset fork no longer stops at the seed asking for `TENANCY_OWNER_EMAIL`: development seeds a placeholder owner, `owner@<slug>.test`, whose sign-in link waits in `/letter_opener`. Production still requires the variable.
- `bin/setup` no longer deletes the seed's sign-in mail from `/letter_opener` straight after sending it.
