# Smart Proxy - OpenBolt

This plug-in adds support for OpenBolt to Foreman's Smart Proxy.

# Things to be aware of
* Any SSH keys to be used should be readable by the foreman-proxy user.
* Results are currently stored on disk at /var/logs/foreman-proxy/openbolt by default (configurable in settings). Fetching old results is possible as long as the files stay on disk.

## how to release

* bump version in `lib/smart_proxy_openbolt/version.rb`
* run `CHANGELOG_GITHUB_TOKEN=github_pat... bundle exec rake changelog`
* create a PR
* get a review & merge
* create and push a tag
* github actions will publish the tag
