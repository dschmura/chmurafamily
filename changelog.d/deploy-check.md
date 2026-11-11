### Added

- `bin/rails deploy:check` lists everything that would stop production booting, or a first deploy finishing, before you deploy (`DESTINATION=staging` for staging). It reads the deploy through Kamal, `.kamal/secrets` included.
