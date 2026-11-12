# SDD ledger — plan: docs/superpowers/plans/2026-11-12-design-system-and-modularization.md

Pre-flight scan:
- Task 0 -> Task 1-16: provides lint scripts & baseline; consumed by pre-build script and verification steps. Clean.
- Task 1 -> Task 2-4: provides OneTakeUI package skeleton, Tokens, Haptics, and @_exported import OneTakeUI. Clean.
- Task 2 -> Task 3-4: provides OTButtonStyle, OTControlSize, OTButtonVariant, OTMenuButton, OTSurface. Clean.
- Task 3 -> Task 4: provides OTBottomBar and OTCardKind (.otCard). Clean.
- Task 4 -> Task 5-16: provides OTScreen, OTNavHeader, OTCallout, OTStatusLine, and legacy typealiases so existing call sites stay compiling. Clean.
- Task 5 -> Task 6-7: provides restructured directory tree (App, Core, Features, Shared/UI). Clean.
- Task 6 -> Task 7-15: dismantles Components.swift into domain features, Shared/UI, and LegacyAliases.swift. Clean.
- Task 7 -> Task 8-15: splits AppStore and UIKitBridges into domain extensions and individual bridge files. Clean.
- Tasks 8-15: independent screen-by-screen feature migrations to OneTakeUI components and strict lint per feature folder. Clean.
- Task 16: removes legacy aliases and deprecations, enforces strict lint across entire project, writes documentation. Clean.
Pre-flight: all shared interfaces consistent.
Task 0: complete (commits d093f79..21b1e74, tests: ./scripts/lint-design-system.sh → on-dark-flag 18)
Task 1: complete (commits 21b1e74..5f43fce, tests: ./scripts/lint-design-system.sh → on-dark-flag 18)
Task 1: Ruling: testScales leading-dot inference (.xs, .s) fails in Swift because OTSpace.xxs is typed as CGFloat; explicitly qualified elements as OTSpace.xs, OTRadius.s in DesignSystemTests — preserves public OTSpace / OTRadius CGFloat API per spec — cost if wrong: none
Task 1: Ruling: Package.swift platform requirement uses .iOS("18.0") for swift-tools-version: 5.10 compatibility — preserves iOS 18.0 target — cost if wrong: none
Task 2: complete (commits 5f43fce..9c01c2f, tests: ./scripts/lint-design-system.sh → on-dark-flag 16)
Task 3: complete (commits 9c01c2f..3a3c131, tests: ./scripts/lint-design-system.sh → on-dark-flag 16)
Task 4: complete (commits c0e7479..c0e7479, tests: ./scripts/lint-design-system.sh → on-dark-flag 11)
Task 5: complete (commits 030aa05..030aa05, tests: ./scripts/lint-design-system.sh → on-dark-flag 11)
Task 6: complete (commits 139432b..139432b, tests: ./scripts/lint-design-system.sh → on-dark-flag 11)
Task 7: complete (commits 4799c51..4799c51, tests: ./scripts/lint-design-system.sh → on-dark-flag 11)
Task 8: complete (commits 4799c51..9ea9a01, tests: ./scripts/lint-design-system.sh → on-dark-flag 8)
Task 9: complete (commits 9ea9a01..09cceec, tests: ./scripts/lint-design-system.sh → radius 180, 0 violations in Features/Auditions & Features/AuditionDetail)
Task 10: complete (commits 09cceec..bc838ce, tests: ./scripts/lint-design-system.sh → radius 106, 0 violations in Features/AddAudition)
Task 11: complete (tests: ./scripts/lint-design-system.sh → radius 74, 0 violations in Features/Prepare, 41/41 tests green)
Task 12: complete (tests: ./scripts/lint-design-system.sh → radius 36, 0 violations in Features/Shoot & Features/Takes, 41/41 tests green)
Task 13: complete (tests: ./scripts/lint-design-system.sh → radius 27, 0 violations in Features/Package, 41/41 tests green)
Task 14: complete (tests: ./scripts/lint-design-system.sh → radius 10, 0 violations in Features/Practice & Features/Onboarding, 41/41 tests green)
Task 15: complete (tests: ./scripts/lint-design-system.sh → radius 9, 0 violations in OneTakeWidgets, 41/41 tests green)
