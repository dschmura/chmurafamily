### Added

- Kamal runs `bin/rails deploy:check` before every image build (`.kamal/hooks/pre-build`), so a deploy production would refuse stops before anything is built, and `hooks_output` in `config/deploy.yml` prints its warnings on every deploy. A fork with its own `pre-build` hook should call the check from it.
