# Implementation Plan: Optional local AI log analysis

**Branch**: `codex/local-ai-logs` | **Date**: 2026-09-08 | **Spec**: [spec.md](spec.md)

## Summary

Opt-in Qwen3-1.7B analysis in existing details. A private child mode of the same Swift executable owns CoreML state. One actor owns installation, worker lifetime, a single generation and browser lease. Normal log SSE remains independent.

## Technical Context

**Language/Version**: Swift6, native JavaScript/HTML/CSS.
**Dependencies**: Existing Hummingbird; system CoreML/Foundation/CryptoKit; no Python or new model server.
**Storage**: Fixed pinned model files in user Application Support; bounded transient logs/results.
**Testing**: XCTest fixture/lifecycle/API, Node frontend, isolated real-model and browser smoke tests.
**Platform**: Apple silicon macOS26+; ANE placement requires measurement.
**Performance**: One worker/inference, 2048 context, max256 output tokens; no inference for identical evidence; bounded shutdown/idle lease.
**Constraints**: Default off; no cloud logs/arbitrary prompts/URLs; GPU excluded; weights excluded from Git/PKG.
**Scope**: One selected container globally; available-memory safety gate; untested hardware explicitly unverified.

## Constitution Check

CLI remains authoritative. Existing Host/Origin/body guards cover new APIs. Tests precede implementations; real container checks read-only. One Swift service retained: private transient child is needed for verified unload, not another listening service. No DB/frontend build chain. Fixed model hashes verified, downloaded scripts never executed. Analysis advisory and log input never diagnostic-logged. Increment2.21.0 and commit after verification; no publish.

## Project Structure

- `Sources/ContainerGUI/AI/`: fixed catalog/install, Qwen tokenizer/inference, private worker, lifecycle/service.
- `Sources/ContainerGUI/Web/AILogRoutes.swift`: bounded local APIs.
- `Sources/ContainerGUI/Resources/Public/ai-logs.js`: isolated UI controller and existing HTML/CSS/i18n/hooks.
- Existing executable entry and `App/AppFactory.swift`: worker dispatch and wiring.
- `Tests/ContainerGUITests/{Unit,Contract}/AI*`, `Tests/Frontend/AILog*`: tests.
- `specs/014-local-ai-logs/`: specification/contracts/tasks/evidence.

## Complexity Tracking

Private process necessary for reliable unload. Parent must verify exit and reject late generations. CoreML native preflight gates final UI acceptance; incompatibility never triggers silent GPU/cloud fallback.
