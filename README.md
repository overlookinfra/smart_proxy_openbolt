# Smart Proxy - OpenBolt

[![License](https://img.shields.io/github/license/overlookinfra/smart_proxy_openbolt.svg)](https://github.com/overlookinfra/smart_proxy_openbolt/blob/master/LICENSE)
[![Test](https://github.com/overlookinfra/smart_proxy_openbolt/actions/workflows/ci.yml/badge.svg)](https://github.com/overlookinfra/smart_proxy_openbolt/actions/workflows/ci.yml)
[![Release](https://github.com/overlookinfra/smart_proxy_openbolt/actions/workflows/release.yml/badge.svg)](https://github.com/overlookinfra/smart_proxy_openbolt/actions/workflows/release.yml)
[![RubyGem Version](https://img.shields.io/gem/v/smart_proxy_openbolt.svg)](https://rubygems.org/gems/smart_proxy_openbolt)
[![RubyGem Downloads](https://img.shields.io/gem/dt/smart_proxy_openbolt.svg)](https://rubygems.org/gems/smart_proxy_openbolt)

This plugin adds [OpenBolt](https://github.com/OpenVoxProject/openbolt) support to [Foreman's Smart Proxy](https://github.com/theforeman/smart-proxy).
It exposes an HTTP API that the [foreman_openbolt](https://github.com/overlookinfra/foreman_openbolt) plugin uses to run Tasks and Plans on remote targets via the OpenBolt CLI.

## Introduction

[OpenBolt](https://github.com/OpenVoxProject/openbolt) is the open source successor of [Bolt](https://github.com/puppetlabs/bolt) by [Perforce](https://www.perforce.com/).
It runs Tasks and Plans against remote targets over SSH, WinRM, Choria, or other transports.

This smart proxy plugin wraps the OpenBolt CLI and provides:

* A REST API for listing available tasks, launching task runs, and retrieving results
* Concurrent job execution via a configurable thread pool
* Disk-based result storage so results survive proxy restarts
* Transport option forwarding (SSH, WinRM, Choria) from the Foreman UI

The Foreman UI talks to this plugin; it does not invoke OpenBolt directly. See the [foreman_openbolt README](https://github.com/overlookinfra/foreman_openbolt) for screenshots and the full user-facing workflow.

## Installation

See [How to Install a Plugin](https://theforeman.org/plugins/#2.Installation) for general Foreman plugin installation instructions.
The [theforeman/foreman_proxy](https://github.com/theforeman/puppet-foreman_proxy/blob/master/manifests/plugin/openbolt.pp) Puppet module supports automated installation.

You need `bolt` in your `$PATH` on the Smart Proxy host.
OpenBolt packages are available at [yum.voxpupuli.org](https://yum.voxpupuli.org/) and [apt.voxpupuli.org](https://apt.voxpupuli.org/) in the openvox8 repo.
You can also use the legacy Bolt packages from Perforce from the `puppet-tools` repo on [apt.puppet.com](https://apt.puppet.com/) or [yum.puppet.com](https://yum.puppet.com/).

OpenBolt relies on Tasks and Plans distributed as Puppet modules.
Deploy your code with [r10k](https://github.com/puppetlabs/r10k) or [g10k](https://github.com/xorpaul/g10k), as you do on your compilers.
A handful of core Tasks and Plans are also included in the [OpenBolt packages](https://github.com/OpenVoxProject/openbolt/blob/main/Puppetfile).

The integration is supported on Foreman 3.17 and all following versions, including development/nightly builds.

## Things to be aware of

* Any SSH keys to be used should be readable by the foreman-proxy user.
* Results are stored on disk at `/var/log/foreman-proxy/openbolt` by default (configurable via `log_dir`). Fetching old results is possible as long as the files remain on disk.

## Configuration

The plugin is configured in `settings.d/openbolt.yml` on the Smart Proxy host. All settings have sensible defaults:

```yaml
---
:enabled: https
:environment_path: /etc/puppetlabs/code/environments/production
:workers: 20
:concurrency: 100
:connect_timeout: 30
:log_dir: /var/log/foreman-proxy/openbolt
```

| Setting | Default | Description |
|---------|---------|-------------|
| `enabled` | `https` | Enable the plugin (`https`, `http`, or `false`) |
| `environment_path` | `/etc/puppetlabs/code/environments/production` | Path to the Puppet environment containing Tasks and Plans |
| `workers` | `20` | Number of threads in the job executor pool |
| `concurrency` | `100` | Maximum number of concurrent target connections per job |
| `connect_timeout` | `30` | Connection timeout in seconds for target connections |
| `log_dir` | `/var/log/foreman-proxy/openbolt` | Directory for job result files (created automatically if missing) |

## Choria Transport

**Requires OpenBolt 5.5 or later.** The Choria transport is not available
in Puppet Bolt. SSH and WinRM transports work with any version.

The Choria transport works out of the box on HTTPS-enabled proxies. The
proxy ships a built-in MCollective client configuration and automatically
derives SSL paths and the MCollective certname from the proxy's own
OpenVox/Puppet certificates (configured via `ssl_certificate`,
`ssl_private_key`, and `ssl_ca_file` in `settings.yml`).

The `foreman-proxy` user must be in the `puppet` group to read the SSL
files. This is the default when the proxy is set up with
`foreman-installer` (the `puppet-foreman_proxy` module's
`manage_puppet_group` parameter handles this).

If the Choria client cannot locate a broker via the config file, SRV
records, or the `puppet:4222` fallback, set the Choria Brokers option in
the Foreman UI under Settings > OpenBolt. All other Choria settings
(SSL cert/key/CA, config file, MCollective certname) have sensible
defaults that can be overridden per-launch from the Foreman UI if needed.

### Custom Choria configuration file

The built-in default config is at
`lib/smart_proxy_openbolt/config/choria-client.conf` in this gem. You
can view it to see what settings are included. To use a custom
MCollective client configuration file instead, set the "Choria Config
File" setting in the Foreman UI. When a custom config file is provided,
the proxy does not inject SSL defaults (the config file is expected to
handle SSL on its own). SSL settings from the Foreman UI still override
the config file if set.

### How it works

When the transport is Choria and no custom config file is provided:

1. The proxy uses its built-in `choria-client.conf` (MCollective boilerplate)
2. SSL cert, key, and CA default from the proxy's `settings.yml` SSL paths
3. The MCollective certname is read from the certificate's CN
4. All values are passed as OpenBolt CLI flags (`--choria-ssl-cert`,
   `--choria-ssl-key`, `--choria-ssl-ca`, `--choria-mcollective-certname`,
   `--choria-config-file`)

For full Choria infrastructure setup (broker, managed nodes, Puppet modules),
see the [Choria Testing](https://github.com/overlookinfra/foreman_openbolt/blob/main/docs/choria-testing.md) guide in the foreman_openbolt repo.

## API

The plugin mounts its API at `/openbolt` on the Smart Proxy. All endpoints are used by the Foreman plugin and are not intended for direct use, but can be useful for debugging.

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/openbolt/tasks` | List available tasks from the configured environment |
| `GET` | `/openbolt/tasks/reload` | Clear the task cache and reload from disk |
| `GET` | `/openbolt/tasks/options` | Get available transport options (SSH, WinRM, Choria) |
| `POST` | `/openbolt/launch/task` | Launch a task run against specified targets |
| `GET` | `/openbolt/job/:id/status` | Get the status of a running or completed job |
| `GET` | `/openbolt/job/:id/result` | Get the full result of a completed job |
| `DELETE` | `/openbolt/job/:id/artifacts` | Delete stored result files for a job |

## Authentication

The OpenBolt API is HTTPS-only and requires SSL client certificate authentication.
The smart proxy verifies that:

1. The client presents a valid SSL certificate signed by the same CA configured
   in `ssl_ca_file` in `/etc/foreman-proxy/settings.yml`.
2. The certificate's CN appears in the `trusted_hosts` list in that same file.

In a standard Foreman installation, the Foreman server's certificate is already
trusted by the smart proxy, so no additional configuration is needed for
Foreman-to-proxy communication.

### Direct API access

If you want to hit the smart proxy OpenBolt API directly from the Foreman host
(for debugging, scripting, etc.), you can reuse Foreman's own client
certificates since they are already trusted by the proxy:

```bash
curl -s \
  --cacert /etc/puppetlabs/puppet/ssl/certs/ca.pem \
  --cert /etc/puppetlabs/puppet/ssl/certs/$(hostname -f).pem \
  --key /etc/puppetlabs/puppet/ssl/private_keys/$(hostname -f).pem \
  https://$(hostname -f):8443/openbolt/tasks
```

The Foreman server's CN should already be in `trusted_hosts` in the smart
proxy's `/etc/foreman-proxy/settings.yml`. If not, add it:

```yaml
:trusted_hosts:
  - foreman.example.com
```

## Development

### Unit Tests

```bash
bundle exec rake test
```

### Acceptance Tests (SSH)

Acceptance tests run against Docker containers with a proxy and SSH targets.

```bash
bundle exec rake acceptance:ssh:up    # Start containers
bundle exec rake acceptance:ssh       # Run tests
bundle exec rake acceptance:ssh:down  # Stop and clean up
```

### Building Packages

Build RPM or DEB packages locally using containers. The [foreman-packaging](https://github.com/theforeman/foreman-packaging) repo is cloned automatically:

```bash
bundle exec rake build:rpm   # Build RPM
bundle exec rake build:deb   # Build DEB
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `FOREMAN_PACKAGING_REPO` | `https://github.com/theforeman/foreman-packaging.git` | Git URL for foreman-packaging |
| `FOREMAN_VERSION` | `3.18` | Foreman version for package builds |

## Contributing and support

Fork and send a Pull Request. Thanks!
If you have questions or need professional support, please join the `#sig-orchestrator` channel on the [Vox Pupuli Slack](https://voxpupuli.org/connect/).

## Copyright

Copyright (c) 2025 Overlook InfraTech

Copyright (c) 2025 betadots GmbH

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

## How to Release

### Release steps

1. Go to [Actions > Prepare Release](../../actions/workflows/prepare_release.yml) and run the workflow with the version to release (e.g. `1.2.0`)
2. The workflow bumps the version in `version.rb`, generates the changelog, and opens a PR with the `skip-changelog` label
3. Review and merge the PR
4. Go to [Actions > Release](../../actions/workflows/release.yml) and run the workflow with the same version
5. The release workflow:
   - Verifies the version in `version.rb` matches the input
   - Creates and pushes a git tag
   - Builds the gem
   - Creates a GitHub Release with auto-generated notes and the gem attached
   - Publishes the gem to GitHub Packages
   - Publishes the gem to RubyGems.org (requires the `release` environment)
   - Verifies the gem is available on RubyGems.org

### RPM/DEB packaging

After the gem is published to RubyGems, both RPM and DEB packages need to be updated in [theforeman/foreman-packaging](https://github.com/theforeman/foreman-packaging).

A bot automatically creates PRs against the `rpm/develop` and `deb/develop` branches to pick up the new gem version. These PRs build packages for Foreman nightly.

For stable Foreman releases (currently 3.17 and 3.18), cherry-pick the packaging commits from the develop branches into the corresponding stable branches. For each stable version you want to support:

```bash
cd foreman-packaging

# RPM: cherry-pick from rpm/develop into a branch off the stable target
git checkout rpm/3.18
git checkout -b cherry-pick/rubygem-smart_proxy_openbolt-rpm-3.18
git cherry-pick <commit-from-rpm/develop>
# Push to your fork and open a PR targeting rpm/3.18

# DEB: same approach for the deb side
git checkout deb/3.18
git checkout -b cherry-pick/rubygem-smart_proxy_openbolt-deb-3.18
git cherry-pick <commit-from-deb/develop>
# Push to your fork and open a PR targeting deb/3.18
```

PRs against stable branches should be labeled "Stable branch".

**Alternative: manual version bump**

If the cherry-pick doesn't apply cleanly, you can bump the version manually on the stable branch instead.

*RPM:* Checkout the target branch and run `bump_rpm.sh`:
```bash
cd foreman-packaging
git checkout rpm/3.18
git checkout -b bump_rpm/rubygem-smart_proxy_openbolt
./bump_rpm.sh packages/plugins/rubygem-smart_proxy_openbolt
# Review changes, push to your fork, and open a PR targeting rpm/3.18
```

*DEB:* Checkout the target branch and update these files:
- `debian/gem.list` -- new gem filename
- `smart_proxy_openbolt.rb` -- new version
- `debian/control` -- dependency versions (if changed)
- `debian/changelog` -- add a new entry

```bash
git checkout deb/3.18
git checkout -b bump_deb/ruby-smart-proxy-openbolt
# Make the changes above, push to your fork, and open a PR targeting deb/3.18
```
