# Risk Register

This register details security, data-integrity, and performance risks identified during the OpenClinic PR audit.

## Risk-01: Patient Record Cross-Linking during Import
* **Severity**: Critical (Release-blocking)
* **Status**: Open
* **Description**: If a patient import has empty/missing FHIR resource IDs or MRNs, the predicate can match arbitrary existing patients lacking those fields, resulting in merged profiles and HIPAA violations.
* **Mitigation**: Implement strict, deterministic matching rules. Do not match on missing/empty values. If ambiguity is detected, fail fast and throw a conflict error instead of choosing the first match.

## Risk-02: Child Record Scoping Leak
* **Severity**: Critical (Release-blocking)
* **Status**: Open
* **Description**: Lookups for existing conditions, medications, and appointments fetch global collections and build dictionaries keyed only by raw identifiers. Records from Patient A can be matches for Patient B's import and reassigned.
* **Mitigation**: Scope lookups strictly to the patient's existing attached relationships. Prefix/qualify database identifiers with the originating server URL to prevent global collisions.

## Risk-03: Silent Session Recovery Failures
* **Severity**: High
* **Status**: Open
* **Description**: Keychain Helper silently ignores status codes. If a write fails, the app assumes it succeeded. UserDefaults migration can delete the only valid token even if the Keychain write failed.
* **Mitigation**: Validate status codes on all Keychain operations. Require successful save and verification read-back before removing legacy UserDefaults tokens.
