### Fixed

- `bin/rails deploy:check` no longer refuses a server whose HTTPS ends at a web server in front of kamal-proxy, once `proxy.run` moves the proxy off port 80.
