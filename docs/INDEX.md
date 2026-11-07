# OneTake iOS — Documentation Index

Welcome to the OneTake iOS engineering and product documentation. This documentation serves as the single source of truth for human engineers, contributors, and autonomous AI coding agents.

---

## 📚 Core Documentation Map

| Document | Focus & Purpose |
| :--- | :--- |
| **[AI Agent Guide](AI_AGENT_GUIDE.md)** | **Mandatory reading for AI coding agents.** Invariants, modification protocol, and verification discipline. |
| **[Current Work Handoff](WORK_IN_PROGRESS.md)** | Active task status, current commit, recent test results, and next engineering steps. |
| **[Project Overview](PROJECT_OVERVIEW.md)** | Product identity, core audience (actors), product philosophy, primary use cases, and explicit non-goals. |
| **[Product Specification](PRODUCT_SPECIFICATION.md)** | Exhaustive feature-by-feature requirements, inputs, outputs, edge cases, and verification status. |
| **[User Flows](USER_FLOWS.md)** | Visual Mermaid diagrams and step-by-step journeys for audition taping, practice, import, recording, and sharing. |
| **[Architecture](ARCHITECTURE.md)** | High-level system design, state management (`AppStore`), concurrency models, actor boundaries, and App Group coordination. |
| **[Codebase Map](CODEBASE_MAP.md)** | Directory and file inventory, component responsibilities, symbol index, and practical "where to make changes" guide. |
| **[Data Models](DATA_MODELS.md)** | Schema definitions, model relationships, persistence invariants, and backward-compatibility rules. |
| **[Persistence & Backup](PERSISTENCE_AND_BACKUP.md)** | Off-MainActor `StateStorage`, sequence ordering, background assertions, crash-safe restore journaling, and rollback recovery. |
| **[Recording & Media](RECORDING_AND_MEDIA.md)** | AVFoundation capture pipeline, monotonic hardware timing, session interruptions, duration validation, and take review. |
| **[Import & Document Parsing](IMPORT_AND_DOCUMENT_PARSING.md)** | Independent Casting Call vs Script Sides import, Vision OCR, hierarchical scene splitting, and regex caching. |
| **[Export & Sharing](EXPORT_AND_SHARING.md)** | Delivery packaging, system zlib CRC32, Share Link vs Separate Elements, iCloud ubiquity containers, and revocation. |
| **[Testing & Quality](TESTING.md)** | Unit test suites, integration test harnesses, Python simulation scripts, and verification classification. |
| **[Development Setup](DEVELOPMENT_SETUP.md)** | Prerequisites, XcodeGen project generation, signing configuration, and running tests. |
| **[Engineering Decisions](ENGINEERING_DECISIONS.md)** | Architecture Decision Records (ADRs) documenting context, alternatives, and consequences for key decisions. |
| **[Audit & Remediation History](AUDIT_AND_REMEDIATION_HISTORY.md)** | Detailed changelog and analysis of remediation phases from Phase 1 (`6527bb2`) through Phase 8.2 (`d4a3e8b`). |
| **[Known Issues](KNOWN_ISSUES.md)** | Unresolved defects, technical debt, platform limitations, and investigation guides. |
| **[Roadmap](ROADMAP.md)** | Completed, in-progress, and planned engineering initiatives. |
| **[Contributing Guide](CONTRIBUTING.md)** | Contribution standards, code style, testing expectations, and pull request procedures. |

---

## 🧭 Quick Navigation by Engineering Task

- **Modifying Document Import & OCR:** See [Import & Document Parsing](IMPORT_AND_DOCUMENT_PARSING.md) and [`OneTake/ModelViews/NoticeOCR.swift`](../OneTake/ModelViews/NoticeOCR.swift).
- **Modifying Camera & Audio Recording:** See [Recording & Media](RECORDING_AND_MEDIA.md) and [`OneTake/ModelViews/CameraController.swift`](../OneTake/ModelViews/CameraController.swift).
- **Modifying Persistence or State Serialization:** See [Persistence & Backup](PERSISTENCE_AND_BACKUP.md), [`OneTake/Models/Persistence.swift`](../OneTake/Models/Persistence.swift), and [`OneTake/ModelViews/AppStore.swift`](../OneTake/ModelViews/AppStore.swift).
- **Modifying Backup & Crash Recovery:** See [Persistence & Backup](PERSISTENCE_AND_BACKUP.md) and [`OneTake/Models/LocalBackup.swift`](../OneTake/Models/LocalBackup.swift).
- **Modifying Export & Deliverable Packaging:** See [Export & Sharing](EXPORT_AND_SHARING.md) and [`OneTake/ModelViews/ZipArchive.swift`](../OneTake/ModelViews/ZipArchive.swift).
- **Modifying iCloud Public Link Sharing:** See [Export & Sharing](EXPORT_AND_SHARING.md) and [`OneTake/ModelViews/CloudLink.swift`](../OneTake/ModelViews/CloudLink.swift).
- **Understanding Non-Goals & Product Boundaries:** See [Project Overview](PROJECT_OVERVIEW.md).
- **Continuing Active Work:** See [AI Agent Guide](AI_AGENT_GUIDE.md) and [Current Work Handoff](WORK_IN_PROGRESS.md).
