# AGENTS.md

Global instructions for pi, applying across all sessions and projects.

## Human partner

- **Dan Bjorge** <dan@dbjorge.net>
- These are **personal projects**. Do not assume anything is Deque Systems work, and do not treat
  Deque-related work or constraints as in scope.

## Working environment

The session runs in a layered environment:

- **Host**: Windows, PowerShell 7 (pwsh), running a **Herdr** client.
- **WSL**: a RHEL-10 WSL distro running the **Herdr server**.
- **Sandbox**: the actual agent session runs in a **podman container** inside WSL
  (one container per workspace), with **pi** as the coding harness.

In practice this means:

- The repository visible at `/ws/...` is a mount of a host directory; edits are reflected on the host.
- The global agent directory `/root/.pi/agent` is a mount of the host's `~/.pi/agent`; anything written
  here is visible on the host and vice versa.
- Shells run inside the container are Linux (not Windows) shells; the container does not see the
  full host filesystem.
- Use `host-output.txt` in the workspace when host side output needs to be handed over (see the
  project AGENTS.md for the current multiline-paste workaround).

## Working preferences

- **TDD**: when implementing code changes, write tests first and follow a red-green-refactor loop where
  practical. Keep the test suite runnable and run it after changes.
- **Plan before code**: when starting significant new features or substantial work, **brainstorm with Dan
  first**. Come up with a plan and a shared understanding of the feature together before writing code, and
  confirm the approach rather than optimizing for silent velocity.