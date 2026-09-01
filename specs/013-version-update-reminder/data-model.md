# Data Model: Version Update Reminder

## SemanticVersion

- **Fields**: `major`, `minor`, `patch` as non-negative integers.
- **Input normalization**: Optional leading `v`; surrounding whitespace ignored; build metadata may be ignored for precedence.
- **Validation**: Exactly three numeric components; no negative, empty, overflow, or prerelease component.
- **Ordering**: Compare major, then minor, then patch numerically.

## GitHubReleasePayload

- **Fields consumed**: tag name, HTML URL, draft flag, prerelease flag, optional publication time.
- **Trust**: External and untrusted.
- **Validation**: Stable release only; parseable semantic version; HTTPS `github.com` URL under the exact ContainerGui release path.

## UpdateSummary

- **Fields**:
  - `currentVersion`: normalized running application version.
  - `latestVersion`: normalized latest stable release version.
  - `updateAvailable`: true only when latest is numerically newer.
  - `releaseURL`: validated official GitHub release page.
  - `publishedAt`: optional release publication timestamp.
- **Persistence**: None on the service.

## BrowserUpdateState

- **States**: `idle`, `checking`, `available`, `current`, `failed`.
- **Context**: `automatic` or `manual`.
- **Transitions**:
  - idle -> checking when an allowed automatic or manual check starts.
  - checking -> available when `updateAvailable` is true.
  - checking -> current when `updateAvailable` is false.
  - checking -> failed on network, HTTP, parse, or validation failure.
  - available/current/failed -> checking on a later manual retry.
- **Concurrency rule**: Only one check may be in flight.

## AutomaticCheckRecord

- **Field**: last completed automatic-check timestamp in milliseconds since epoch.
- **Location**: Browser local storage.
- **Validity**: A finite timestamp not in the future and less than 24 hours old suppresses the automatic check. Missing, malformed, expired, or inaccessible storage permits a check.
- **Privacy**: Contains no user, container, credential, or machine identifier.
