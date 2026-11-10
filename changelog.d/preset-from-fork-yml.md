### Fixed

- Production uses the tenancy preset (and the shared preset's slug) that `bin/fork` recorded in `.fork.yml` when `WORKSPACE_ON_SIGNUP` is unset, so a `shared` or `none` fork no longer goes live as `personal`. Set the variable only to override it.
