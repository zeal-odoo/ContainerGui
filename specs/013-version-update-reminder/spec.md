# Feature Specification: Version Update Reminder

**Feature Branch**: `main`

**Created**: 2026-09-01

**Status**: Approved

**Input**: User description: "添加功能，自动提醒用户，有新的版本更新或手动点击更新，跳转到github，让用户下载PKG文件这个作为2.17.0并删除github上的2.17.0，并重新发布"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Automatically learn about a newer version (Priority: P1)

As a local Container GUI user, I want the application to check for a newer public release after the dashboard loads so that I do not have to monitor GitHub myself.

**Why this priority**: Automatic discovery is the core value of the feature and prevents users from continuing to run an outdated local build without knowing that an installer is available.

**Independent Test**: Load the dashboard while a newer public release is available and verify that a dismissible update prompt appears without blocking container information or triggering a download.

**Acceptance Scenarios**:

1. **Given** the installed version is older than the latest public stable release, **When** the dashboard finishes loading, **Then** the user sees the installed and latest versions plus an explicit action that leads to the official GitHub release.
2. **Given** the installed version is current or newer, **When** the automatic check completes, **Then** no update prompt interrupts the user.
3. **Given** an automatic check was completed less than 24 hours ago in the same browser, **When** the page is loaded again, **Then** the application does not repeat the automatic remote check or prompt.
4. **Given** the update service cannot be reached or returns unusable information, **When** the automatic check fails, **Then** the dashboard remains fully usable and no alarming error dialog is shown.

---

### User Story 2 - Check for updates on demand (Priority: P2)

As a user, I want a visible manual update check in the application header so that I can immediately confirm whether my installation is current.

**Why this priority**: A manual action gives the user control, bypasses the automatic check interval, and provides clear feedback even when no update exists.

**Independent Test**: Select the manual check action with newer, equal, and unavailable release results and verify the three distinct outcomes.

**Acceptance Scenarios**:

1. **Given** a newer release exists, **When** the user manually checks, **Then** the update prompt shows both versions and offers a GitHub download action.
2. **Given** no newer release exists, **When** the user manually checks, **Then** the user receives a concise confirmation that the application is current.
3. **Given** release information cannot be obtained, **When** the user manually checks, **Then** the user sees a retryable, non-destructive failure message.
4. **Given** the user selects the download action, **When** the target is accepted, **Then** the official public GitHub release page opens in a separate browser context and the Container GUI page remains open.

---

### User Story 3 - Understand update information in either language (Priority: P3)

As a Chinese- or English-language user, I want all update controls and messages to follow the selected interface language so that the workflow is understandable and consistent.

**Why this priority**: The application already supports Chinese and English, so an untranslated update flow would be incomplete and confusing.

**Independent Test**: Repeat the manual and automatic update states in Chinese and English and verify every visible label, status, and action changes language without losing state.

**Acceptance Scenarios**:

1. **Given** Chinese is selected, **When** any update state is displayed, **Then** all update-related text is Chinese.
2. **Given** English is selected, **When** any update state is displayed, **Then** all update-related text is English.
3. **Given** an update was found, **When** the user dismisses the prompt, switches language, and checks again, **Then** the same version and official Release action are shown in the selected language.

### Edge Cases

- The latest release name or tag contains a leading `v`, build metadata, or surrounding whitespace.
- The latest public release is equal to or older than the installed version.
- A response is successful but contains no valid release version or no public release URL.
- The release exists but its PKG asset is temporarily absent; the user must still be able to open the release page and see its published assets or notes.
- GitHub is offline, rate-limited, slow, or returns an oversized or malformed response.
- The update action is clicked repeatedly while a check is already in progress.
- The browser blocks a new tab or window; the current dashboard must remain intact and the user must be able to retry.
- A returned link points outside the official `github.com/zeal-odoo/ContainerGui` release path and must not be offered to the user.
- Reduced-motion preferences are enabled; the prompt remains understandable without requiring animation.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The application MUST expose a clearly identifiable manual update check in the persistent header.
- **FR-002**: The application MUST automatically check for a newer public stable release after the initial dashboard load without delaying or blocking container status.
- **FR-003**: Automatic checks MUST be limited to at most once per 24-hour period in the same browser profile; a manual check MUST bypass this limit.
- **FR-004**: The application MUST compare the installed application version with the latest public stable release using numeric semantic-version precedence rather than text ordering.
- **FR-005**: When a newer version exists, the application MUST show the installed version, latest version, and an explicit GitHub download action.
- **FR-006**: The application MUST NOT automatically download, install, replace, or execute an update.
- **FR-007**: The update action MUST open only the official public release page under `github.com/zeal-odoo/ContainerGui/releases` in a separate browser context.
- **FR-008**: A manual check MUST provide distinct visible feedback for checking, update available, already current, and check failed states.
- **FR-009**: A failed automatic check MUST be silent to normal dashboard operation, while a failed manual check MUST provide a retryable message.
- **FR-010**: Only a public, non-draft, non-prerelease release may be presented as the latest version.
- **FR-011**: Update controls, prompt content, statuses, and accessibility labels MUST be available in both Chinese and English and follow the currently selected interface language.
- **FR-012**: Repeated update actions while a check is already running MUST NOT start concurrent duplicate checks.
- **FR-013**: Release data and URLs MUST be treated as untrusted until their version and official repository path have been validated.
- **FR-014**: This feature and its replacement installation package MUST identify the application as version `2.17.0` as explicitly assigned by the user.
- **FR-015**: The existing public `v2.17.0` release and tag MUST be replaced only after the new code and PKG have passed validation, and the replacement release MUST publish the verified PKG plus its checksum.

### Key Entities

- **Installed Version**: The application version currently running and shown in the interface.
- **Release Summary**: The validated latest stable version, official release page, publication time, and whether it is newer than the installed version.
- **Update Check State**: Idle, checking, update available, already current, or failed, together with whether the check was automatic or manual.
- **Automatic Check Record**: The last completed automatic-check time kept by the browser to enforce the 24-hour interval.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: When a newer valid release is available, the update prompt appears within 5 seconds of the dashboard becoming usable on a normal internet connection.
- **SC-002**: In all tested network-failure cases, container listing and management remain usable and no automatic download or installation occurs.
- **SC-003**: A user can reach the official GitHub release page from the manual update action in no more than two explicit clicks.
- **SC-004**: Repeated dashboard loads within 24 hours produce no more than one automatic remote release check per browser profile.
- **SC-005**: Automated tests cover newer, equal, older, malformed, untrusted-link, timeout, manual-check, automatic-check, and bilingual interface outcomes.
- **SC-006**: The replacement `v2.17.0` release contains a downloadable PKG and matching checksum whose downloaded bytes verify successfully.

## Assumptions

- The update source is the public `zeal-odoo/ContainerGui` GitHub repository and its latest stable Release.
- Users may operate offline; update discovery is optional to normal local-container operations.
- The user remains responsible for choosing, downloading, and running the PKG installer.
- The release page is the durable download destination even if the exact PKG asset name changes.
- The selected 24-hour automatic-check interval balances timely notice with GitHub availability and rate limits; manual checks remain unrestricted except for duplicate in-flight requests.
- Existing Git history remains intact; only the public `v2.17.0` tag and Release are replaced after the new build is ready.
