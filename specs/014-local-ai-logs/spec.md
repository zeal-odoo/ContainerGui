# Feature Specification: Optional local AI log analysis

**Feature Branch**: `codex/local-ai-logs`
**Created**: 2026-09-08
**Status**: Ready for implementation
**Input**: Optional local Qwen3-1.7B log analysis; disabling stops the model and releases its loaded resources. Keep resource usage low on supported Macs.

## User Scenarios & Testing

### User Story 1 - Analyse logs locally (Priority: P1)

The user selects a container and explicitly enables AI. After a confirmed first-use model download, the GUI reports a concise analysis in the selected language without uploading logs.

**Why this priority**: Log interpretation is the requested user value.
**Independent Test**: Synthetic connection-failure logs produce an evidence-based answer without uploads or mutations.
**Acceptance Scenarios**:
1. No model installed: enabling shows the fixed model and download size, requiring confirmation.
2. Model available: enabling shows loading, analysing and result states for the selected container.
3. New logs: bounded batches are analysed; identical logs do not repeatedly trigger inference.
4. Empty logs or unavailable CLI: clear non-success state; ordinary logs remain usable.

### User Story 2 - Stop and release the model (Priority: P1)

The user disables during loading or generation. Pending analysis is discarded and the loaded model stops running; downloaded files remain installed.

**Why this priority**: Prevent a persistent resource burden.
**Independent Test**: Disable during loading/generation; repeat ten times with no remaining model process or stale result.
**Acceptance Scenarios**:
1. Disabling shows closing until actual shutdown is verified.
2. Unresponsive analysis ends within ten seconds or reports failure rather than falsely claiming release.
3. A closed browser/lost connection/stopped GUI does not leave inference running indefinitely.
4. Restarting the GUI does not automatically enable AI.

### User Story 3 - Resource and safety boundaries (Priority: P2)

Users can see why AI is unavailable and keep using all ordinary GUI functions.

**Why this priority**: Lower-memory Macs and failures must remain safe and usable.
**Independent Test**: Simulate memory pressure, corrupt files, oversized/hostile logs and multiple windows.
**Acceptance Scenarios**:
1. Insufficient available memory prevents analysis with a clear reason.
2. Multiple requests share at most one model and one generation; disabling works globally.
3. Detectable secrets are redacted; log instructions cannot execute commands.
4. Corrupt/interrupted model files never become ready; retry is safe.

### Edge Cases

- CLI off; removed or stopped container; empty/repeated logs; very long lines or truncated backtraces.
- Disable during download, load, fetch or inference; late result after a new session.
- Browser/service exit; insufficient memory; unsupported model/hardware; competing windows.

## Requirements

### Functional Requirements

- **FR-001**: Use local Qwen3-1.7B, opt-in and off on service start; no cloud fallback.
- **FR-002**: Confirm first download, display progress, verify fixed artifacts, retain files when disabled.
- **FR-003**: Chinese/English container details support enable, disable and analysis results.
- **FR-004**: Results present possible causes, suggestions and analysed evidence; uncertainty is explicit.
- **FR-005**: AI cannot execute commands or mutate containers; logs are untrusted data.
- **FR-006**: Disable cancels pending work and model execution; released is shown only after verified shutdown. System-managed caches are not promised to vanish instantly.
- **FR-007**: One model, one inference, finite input/output, timeouts and memory checks bound resource use. Identical logs do not trigger inference.
- **FR-008**: No log upload or diagnostic logging of input; transient results render as plain text.
- **FR-009**: Existing container/image controls, ordinary logs and loopback-only access remain unchanged.
- **FR-010**: Compatibility scope is Apple silicon/macOS 26+; actual ANE execution and untested machines must not be claimed as verified.

### Key Entities

- Model installation: fixed identity/version/files, verification and download progress.
- Analysis session: enabled state, target, language, activity and generation identity.
- Analysis result: bounded redacted evidence, advisory answer and observation time.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Empty/failure/secret/hostile-log tests pass without uploads or container mutations.
- **SC-002**: Ten enable/disable cycles leave no model running; active shutdown finishes within ten seconds or reports verified failure.
- **SC-003**: At most one inference runs and ordinary GUI requests continue during analysis.
- **SC-004**: Real-model tests record load/generation time, memory and worker exit, and yield a relevant answer for a known failure.
- **SC-005**: Browser checks cover both languages, narrow layout and lifecycle/error states; low-memory compatibility is labelled measured or unverified.

## Assumptions

- Disable unloads the running model, not downloaded files.
- Initial scope is the selected container, not silent analysis of every container.
- User has authorized development testing with the selected public model; shipping users confirm download.
- Suggestions are advisory and detectable-only redaction is not guaranteed to remove every secret.
- Installation uses the network; analysis itself must be offline.
