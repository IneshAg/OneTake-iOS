# OneTake iOS — Contributor Guide

Welcome to the OneTake iOS project. We welcome focused, high-quality contributions from human engineers and autonomous AI coding agents.

---

## 1. Core Principles Before Changing Code

1. **Source Code is Truth**: Comments, old reports, and commit messages can become outdated. Verify actual behavior against Swift source code, project configuration, and executable tests.
2. **Preserve Product Constraints & Non-Goals**:
   - ❌ **No Casting Marketplace**: Never add talent listings, agent directories, or job boards.
   - ❌ **No AI Acting Judgment**: Never grade dramatic performance or score emotional execution.
   - ❌ **No AI Synthetic Voices**: Never replace actor-recorded reader cues with synthetic voices.
   - 🔒 **Export Choices**: Keep user-facing export choices strictly limited to `Share Link` and `Separate Elements`.
   - 📄 **Independent PDF Workflows**: Never merge Casting Call and Script Sides into a destructive single import.
3. **No Unrelated Architectural Rewrites**: Keep changes scoped, reviewable, and focused strictly on the assigned task.

---

## 2. Engineering & Development Workflow

### Step 1: Research & Location
- Read [`docs/INDEX.md`](INDEX.md) and [`docs/CODEBASE_MAP.md`](CODEBASE_MAP.md) to locate the relevant files and types.
- Check [`docs/KNOWN_ISSUES.md`](KNOWN_ISSUES.md) and [`docs/ENGINEERING_DECISIONS.md`](ENGINEERING_DECISIONS.md) to understand existing constraints.

### Step 2: Implementation Discipline
- Maintain documentation integrity: preserve existing comments and docstrings unless explicitly refactoring.
- Maintain MainActor thread-safety: UI state belongs on `@MainActor`; disk and network I/O belong in isolated actors or background workers.
- Avoid silent error swallowing: never use blanket `try?` on critical persistence or backup paths.

### Step 3: Testing & Verification
- Add or update native XCTest cases in `OneTakeTests/` for any meaningful change.
- Run the full automated regression suite across all phases:
  ```powershell
  python scripts/test_notice_and_script_parsers.py
  python scripts/test_separate_pdf_import.py
  python scripts/test_local_backup_safety.py
  python scripts/test_persistence_reliability.py
  python scripts/test_recording_reliability.py
  python scripts/test_export_performance.py
  python scripts/test_sharing_lifecycle.py
  python scripts/test_phase7_quality.py
  python scripts/test_phase8_remediation.py
  ```
- If running on macOS, execute native XCTest via `xcodebuild test`.

### Step 4: Documentation Updates
- Update relevant documentation in `docs/` whenever behavior, models, or workflows change.
- If working as an AI agent, update [`docs/WORK_IN_PROGRESS.md`](WORK_IN_PROGRESS.md) following the session handoff protocol.

### Step 5: Clean Commits
- Review `git diff` carefully to ensure zero unintended whitespace, generated files, or debug prints.
- Use standard conventional commit format:
  `fix(scope): concise description` or `feat(scope): concise description`.
