# Contributing to OpenClinic

OpenClinic is a research prototype and clinical architecture playground. We welcome contributions that align with our native, privacy-first technical goals. This document outlines the prerequisites, workflow guidelines, and expectations for all contributors—both human developers and autonomous coding agents.

---

## 1. Project Alignment

Before submitting code, please ensure your changes support our core architecture principles:
* **Local-First Processing:** Keep database reads/writes and AI model inference completely on-device. No new third-party cloud SDK dependencies.
* **Apple-Native Design:** Write structured SwiftUI components that utilize native layouts (split views, sidebar sheets) and SwiftData bindings.
* **Data Provenance:** Keep track of where data comes from. If your changes modify clinical record sources, make sure they attach appropriate `sourceKind` values.

---

## 2. Development Prerequisites

To compile and validate changes:
* **Operating System:** macOS 15.0+ or compatible environment.
* **Xcode Toolchain:** Xcode 26.3 or compatible development builds.
* **Target SDKs:** iOS 26.2, macOS 26.2, and visionOS 26.2.
* **Apple Silicon:** While the app builds on Intel Macs, reviewing on-device Apple Intelligence prompts requires an Apple Silicon processor (M1/M2/M3 base, Pro, Max, or Ultra) or target device.

---

## 3. Branching and Workflow

* Always base your changes on the `main` branch.
* Name your branches descriptively, separating concerns with forward slashes (e.g. `feature/fhir-writeback`, `fix/fts-tokenizer`).
* Commit frequently using clean, imperative commit messages. Format your commits with prefix tags:
  * `feat:` for new capabilities.
  * `fix:` for bug fixes.
  * `docs:` for documentation updates.
  * `refactor:` for code cleanups without functional changes.

---

## 4. Coding Conventions

* **Safety First:** Enforce Swift 6 strict concurrency checks. Use structured concurrency (`Task`, `TaskGroup`) and actor isolation (e.g. `ClinicalVectorStore`) where database heavy-lifting occurs.
* **View Design:** Keep SwiftUI views focused and modular. Separate layouts into reusable subviews, leveraging properties and environment objects rather than nesting everything in monolithic containers.
* **PII/PHI Safety:** Never write plain-text patient names, medical record numbers, or access keys to system logs or debug consoles. Use private log templates.

---

## 5. Pull Request Checklist

When preparing a pull request, ensure the following checklist is completed:

* [ ] The project builds successfully with no compilation warnings or errors.
* [ ] No credentials, access tokens, private keys, or actual patient details are included in the commits.
* [ ] The documentation (including ARCHITECTURE.md if relevant) is updated to reflect any changes to schemas or data flows.
* [ ] All new user-visible features are validated manually in a simulator or physical target device.
* [ ] A descriptive summary detailing the changes, manual verification steps, and tested platform versions is added to the PR body.

---

## 6. Guidelines for Autonomous AI Agents

If you are an autonomous coding agent contributing to this repository:
1. **Analyze First:** Inspect existing structures (such as `ClinicalRAGService.swift` and `VerificationGates.swift`) before proposing changes to the AI or search pipelines. Do not invent proprietary frameworks.
2. **Review-Driven Edits:** Present clean diff chunks before modifying files.
3. **Respect Limits:** When modifying LLM prompts or context packers, strictly respect the 4096-token system limit and maintain token budgeting heuristics.
4. **No Placeholder Code:** Do not write boilerplate or placeholder code. Ensure all generated Swift functions are fully implemented and typed.
5. **No Secret Exposures:** If mock or template configurations are written, automatically redact credentials and format them as `[REDACTED_SECRET]` placeholders.
