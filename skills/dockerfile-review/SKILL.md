---
name: dockerfile-review
description: Guidelines for reviewing Dockerfile changes in PRs. Use when reviewing PRs that modify Dockerfiles, docker-compose files, or container-related CI workflows.
---

# Dockerfile PR Review

When reviewing PRs that modify Dockerfiles or container build infrastructure, follow these guidelines in addition to normal code review practices.

## Verify, don't assume

**Before writing any review comment about whether a package, binary, or library is or isn't available in a base image, you MUST verify by running the image.** Do not speculate, hedge ("may not be available"), or defer verification to the PR author. If you haven't checked, don't comment on it.

```bash
# List all installed packages
docker run --rm <image> rpm -qa | sort        # RPM-based
docker run --rm <image> dpkg -l               # Debian-based

# Check for a specific binary
docker run --rm <image> which <binary>
docker run --rm <image> rpm -q <package>
```

If the image requires authentication or isn't pulled locally, ask the user whether it's available before attempting to pull it. If it's not available and can't be pulled, state that you were unable to verify rather than guessing.

## Check layer sizes

Always build the image and inspect layer sizes with `docker history`. Look for:

- **`chown -R` or `chmod -R` after `COPY`**: These create a new layer that duplicates every file whose metadata changed. Fix by using `COPY --chown=user:group` or `COPY --chmod=755` instead, which applies ownership/permissions within the same layer.
- **Unexpectedly large layers**: Compare individual layer sizes against what you'd expect for their contents.
- **Redundant content across layers**: Multiple layers containing the same files (e.g., copying files then modifying them in a separate `RUN`).

Report the total image size and flag any layers that seem disproportionate.

## Evaluate version pins

When a Dockerfile pins package versions, evaluate whether the pins are actually durable:

1. **Check what the repository actually serves**: Use `microdnf repoquery`, `apt-cache policy`, or equivalent to see what versions are available. Does the repo retain old versions, or only serve the latest?
2. **Check build history**: Look up the package in public build systems (e.g., Koji for RHEL/CentOS, Debian snapshot) to understand how frequently the upstream version changes.
3. **Evaluate pin granularity**: Is the pin so tight it'll break on routine maintenance? Is it so loose it's meaningless? The right level is "pin far enough that breakage would indicate a change worth investigating."
4. **Verify comments match reality**: If a comment explains a pinning strategy, test whether the claimed behavior is accurate. Don't take pinning rationale at face value.

## Look for implicit coupling

Flag cases where values in one part of the Dockerfile silently depend on values in another part, especially if there's no comment linking them. Common examples:

- Package version pins that reference a specific OS minor release (e.g., `*.el9_7`) coupled to the base image tag (e.g., `ubi9-minimal:9.7`)
- `ENV` values that must match `ARG` defaults
- Multi-stage `COPY --from=` references that depend on specific stage names or paths

Suggest adding warning comments at the dependency site reminding maintainers to update both together.

## Healthchecks

- Prefer simple, low-overhead healthcheck commands (`curl --fail`) over heavyweight alternatives (spawning a Python interpreter).
- Verify the healthcheck binary is actually available in the final image (see "Verify, don't assume").
- `|| exit 1` is redundant in Docker `HEALTHCHECK CMD` -- Docker treats any non-zero exit code as unhealthy. Note it if present but don't block on it.

## Multi-stage builds

- Verify that build-time-only dependencies (compilers, `-devel` packages, package managers like `pip`/`uv`) are NOT present in the final image.
- Check that `COPY --from=builder` doesn't pull in more than intended (e.g., copying all of `/app` when only `/app/.venv` and source are needed).
- Verify the final image can actually run the application -- the runtime stage needs the same Python version, shared libraries, etc. that the built artifacts expect.

## CI workflow changes

When container-related CI workflows are modified:

- Check that registry authentication steps are added to ALL workflows that build or pull from private registries, not just some.
- Verify action versions are pinned to commit SHAs (not just tags) for supply chain security.
- Look for composite action extraction opportunities if the same authentication/setup block is repeated across multiple workflows.
