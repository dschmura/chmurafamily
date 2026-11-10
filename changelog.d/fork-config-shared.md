### Changed

- `bin/setup`, `bin/fork`, `bin/mail-setup`, `bin/sync` and `bin/release` read `.fork.yml` through `ForkConfig` (`lib/fork_config.rb`); a fork that customised one of them should read the file the same way.
- `bin/setup` writes `.env` through a temp file, readable only by you, so an interrupted run can't empty it.
