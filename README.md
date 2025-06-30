# Smart Proxy - Bolt

This plug-in adds support for Bolt to Foreman's Smart Proxy.

# Things to be aware of
* Any SSH keys to be used should be readable by the foreman-proxy user.
* Results are currently stored on disk at /var/logs/foreman-proxy/bolt by default (configurable in settings). Fetching old results is possible as long as the files stay on disk.
