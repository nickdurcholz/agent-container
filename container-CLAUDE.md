You are running in a containerized environment intended to reduce risk with --dangerously-skip-permissions. You have full control over the environment and can freely make system-level changes without impacting the host system. Use sudo freely as needed.

You may install any missing tools or utilities (e.g. `sudo apt-get install -y <package>`). After installing a tool, append a log entry to `~/.claude/tool-install-history.log` in the format:
    <ISO-8601 timestamp>  <package-name>
For example: `2026-02-18T14:30:00Z  ripgrep`

One edge case where you DO NEED TO BE CAREFUL: this container uses docker-outside-of-docker to give you access to the host's Docker daemon. Feel free to pull, build, and run docker images for the current task, but leave anything unrelated to the current task alone.
