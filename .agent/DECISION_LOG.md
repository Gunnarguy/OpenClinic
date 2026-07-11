# Decision Log

This log tracks architectural and implementation decisions for the OpenClinic PR audit.

## Dec-01: PR #11 Disposition - CLOSE
* **Decision**: Mark PR #11 as CLOSED without merging.
* **Rationale**: The PR claims to add `AnatomicalRegion.displayName(for:)` tests, but the actual patch only introduces `test_script.swift` which does a placeholder print. The script will be removed and real tests will be implemented independently in `AnatomicalRegionTests.swift`.

## Dec-02: PR #12 Disposition - REWORK/REIMPLEMENT
* **Decision**: Close/supersede PR #12 and implement a safe version directly on the audit branch.
* **Rationale**: The proposed patient fetch optimization predicate `sourceRecordIdentifier == id || medicalRecordNumber == mrn` is unsafe. It over-matches on missing/empty values and risks cross-linking patient records. A secure, patient-scoped re-implementation is required.

## Dec-03: Scope Child Records to Patient Collections
* **Decision**: Rework the dictionary-based lookup in `syncConditions`, `syncMedications`, and `syncAppointments` to query only the current patient's collections.
* **Rationale**: The merged PR #6 implementation builds lookup dictionaries from global collections. This creates a severe risk where Patient A's records could match an import for Patient B and be reassigned, violating patient isolation.
