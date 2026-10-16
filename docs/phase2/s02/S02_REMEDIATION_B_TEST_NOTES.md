# S02 remediation B: test notes

## B1

- SF1: fake file system whose `readBytes` of the COMMIT of the highest generation throws a non-notfound `FileSystemException` (file still exists): after `start()` every generation directory of that activity still exists, the id is not in `report.absent`, `report.diagnostics` contains `unreadable:<id>`, and the next `start()` with the fault removed recovers the highest generation.
- SF1: same for an I/O error reading `record.json` of a committed generation (generation kept, `unreadable:<id>`).
- SF1: a genuinely missing COMMIT (file absent) or an invalid marker still deletes that uncommitted generation and keeps the older committed one.
