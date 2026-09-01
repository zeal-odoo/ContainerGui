# Research: Version Update Reminder

## Decision 1: Use the latest stable GitHub Release as the update authority

- **Decision**: Query the fixed `zeal-odoo/ContainerGui` latest-release endpoint and accept only a non-draft, non-prerelease result.
- **Rationale**: The user installs from GitHub PKG assets, so the public Release is the source that matches the actual distribution path.
- **Alternatives considered**: A custom manifest would add another mutable source; Git tags alone do not prove a PKG was published; GitHub repository commits are not installable releases.

## Decision 2: Perform the remote check in the Swift service

- **Decision**: The browser calls a same-origin read-only endpoint while the service performs one bounded HTTPS request.
- **Rationale**: This preserves the existing same-origin browser boundary, avoids broadening the content-security connection policy, centralizes host and URL validation, and makes failures deterministic in tests.
- **Alternatives considered**: Direct browser GitHub calls would require a new cross-origin policy and expose parsing/validation in two trust domains; a background daemon is unnecessary.

## Decision 3: Reuse the existing no-redirect Foundation transport

- **Decision**: Inject the existing `RegistryHTTPTransport` boundary and production `FoundationRegistryHTTPTransport` into the release checker, with a release-specific 128 KiB response limit.
- **Rationale**: It already provides an ephemeral cookie-free session, a request timeout, disabled cache, and redirect rejection, and its injected protocol supports deterministic tests.
- **Alternatives considered**: Duplicating a second URLSession transport adds code without changing behavior; renaming the existing transport would be an unrelated refactor.

## Decision 4: Validate semantic versions and the returned release URL

- **Decision**: Normalize a leading `v`, compare exactly three numeric components, tolerate build metadata for comparison, reject prerelease syntax, and require an HTTPS URL under `/zeal-odoo/ContainerGui/releases/` on `github.com`.
- **Rationale**: Text ordering misclassifies versions such as `2.10.0`, while GitHub response fields are untrusted external input.
- **Alternatives considered**: Lexical comparison is incorrect; opening an arbitrary returned URL creates an avoidable navigation risk; accepting prerelease versions contradicts the stable-release scope.

## Decision 5: Throttle only automatic browser checks

- **Decision**: Store the last completed automatic-check timestamp in browser local storage and skip new automatic checks for 24 hours; manual checks always bypass the interval but share one in-flight request.
- **Rationale**: A browser-local timestamp is sufficient for this single-user local app and prevents repeated page reloads from consuming unauthenticated GitHub rate limits.
- **Alternatives considered**: Server persistence violates the no-database simplicity goal; throttling manual checks would make the control unreliable; session-only throttling would repeat after every browser restart.

## Decision 6: Use an explicit Material 3 dialog and existing toast feedback

- **Decision**: Show update availability in a dismissible dialog with current/latest versions and a GitHub action. Show current/failure manual outcomes through the existing accessible toast and disable the button while checking.
- **Rationale**: An available update deserves a durable choice, while successful current-state and retryable failure feedback are brief. Existing motion and reduced-motion handling stay consistent.
- **Alternatives considered**: Automatic navigation or download violates explicit consent; a permanent banner consumes dashboard space; native OS notifications require new permissions and lifecycle code.

## Decision 7: Replace the Release only after a new package is ready

- **Decision**: Keep `main` append-only, build and validate the replacement PKG first, then delete the old public Release and tag, tag the new commit, and immediately recreate `v2.17.0` with PKG and checksum.
- **Rationale**: This satisfies the explicit replacement request while minimizing asset downtime and avoiding a force push.
- **Alternatives considered**: Deleting first creates an unnecessary outage; rewriting the prior commit damages traceability; publishing a second tag does not replace the requested version.
