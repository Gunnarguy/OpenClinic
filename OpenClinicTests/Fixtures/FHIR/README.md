# FHIR test fixtures

Captured on 2026-10-07 from the open SMART Health IT R4 sandbox (`https://r4.smarthealthit.org`),
which serves synthetic Synthea patients. No real patient data is here.

- `*.schroeder.*`: patient `b8c71d92-a06b-4044-b053-64664e82f851` (Elisha Schroeder). The two
  Observation files are consecutive pages of one search (50 and 29 of 79), with the server's own `next` link.
- `*.rice.*`: patient `d4fb3bba-73a9-4b82-a0bc-678d47f386b4` (Babara Rice). The allergy bundle includes an
  entry marked entered-in-error, which an importer must leave out. The public sandbox is writable, and one
  allergy another user had entered under a profane name was renamed to "Peanut" here. Nothing else was edited.
  One appointment's `start` has no time zone, which FHIR does not allow; it is kept as captured because real
  servers send values like it.
- `AllergyIntolerance.empty.json`: a search with no results.
- `OperationOutcome.404.json`: the body the server returns for an unknown resource.
- `DocumentReference.synthetic.json`: written by hand for these tests, because the sandbox patients have no notes.
