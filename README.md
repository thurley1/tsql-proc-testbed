# `tsql-proc-testbed`

The committed fixture for spec `351` — T-SQL programmable objects: procedures, functions and triggers,
with the tables they read and write.

**Asserted exactly. Never mutate it casually** — the same rule `rpg-testbed/`, `cpp-testbed/` and
`ssis-testbed/` carry. `TsqlProgrammableReaderTests` and `TsqlTestbedIntegrationTests` assert the counts
below as literals, so a change here fails the suite rather than quietly moving a number.

## Files

| File | Holds |
|---|---|
| `01-schema.sql` | 6 tables, 1 view — the schema the objects below operate on |
| `02-procedures.sql` | 9 stored procedures |
| `03-functions.sql` | 3 functions — scalar, inline table-valued, multi-statement table-valued |
| `04-triggers.sql` | 2 triggers |

## Counts, through the real parser

`SqlSchemaParser.Parse` over this directory emits **one** project, `SQL (schema)`, language `SQL`:

| | Count |
|---|---|
| Types | **21** |
| — `Table` | 6 |
| — `View` | 1 |
| — `SqlProcedure` | 9 |
| — `SqlFunction` | 3 |
| — `SqlTrigger` | 2 |
| Edges | **26** |
| — `TableRead` | 13 |
| — `TableWrite` | 8 |
| — `ProcedureCall` | 2 |
| — `DataAccess` (foreign keys + the view's own read, from the schema reader) | 3 |

Every programmable object has exactly **one** body-bearing member of kind `Procedure` beside its
parameter members. That is not decoration: the quality denominator requires a member with a non-null
body, and `ParsedType` has none — so a type whose members were only its parameters would report
complexity **zero**, which reads as *clean code* rather than as an error.

## The planted answer key

Each item is a specific claim, not a count.

### Direction — the load-bearing new fact

The existing `FileUsage`/`DataAccess` kinds deliberately carry no direction. These do, and a direction
can be wrong *quietly*: the lineage diagram still looks plausible with the arrow reversed.

| Procedure | Must read | Must write | Why it is here |
|---|---|---|---|
| `usp_MergeCustomers` | `StagingCustomers` | `Customers` | `MERGE`'s `USING` source is a **read inside a write statement** |
| `usp_AdjustTotals` | `OrderLines`, `Orders` | `Orders` | `UPDATE o … FROM dbo.Orders o JOIN dbo.OrderLines l` — the update target is an **alias**, so a naive reading writes to a table called `o`. `Orders` is both read and written; `OrderLines` is read only, and recording it as a write would reverse the arrow |
| `usp_DeleteStaleAudit` | *nothing* | `AuditLog` | The `FROM` belongs to the `DELETE`. Treating every `FROM` as a read reports a purge procedure as reading the table it empties |
| `usp_InsertOrderWithOutput` | *nothing* | `Orders` | `OUTPUT INSERTED.OrderId INTO @inserted` — neither `INSERTED` nor the table variable is a table |
| `usp_WriteAudit` | *nothing* | `AuditLog` | The simple case, and the callee two other objects reach |

### What is deliberately not a table

**Zero types and zero edges** for all of these. The type half alone is not enough —
`SchemaProjection` derives its referenced-but-not-defined list from access edges whose target is absent
from the defined names, so an edge with no type still puts `#staged` on the Data tab as a missing table.

| Name | What it is | Where |
|---|---|---|
| `#staged` | temp table | `usp_LoadOrders` |
| `@skipped` | table variable | `usp_LoadOrders` |
| `Recent` | CTE alias | `usp_LoadOrders` |
| `@inserted` | table variable | `usp_InsertOrderWithOutput` |
| `@summary` | a multi-statement TVF's declared return table | `fn_CustomerSummary` |
| `INSERTED`, `DELETED` | engine-supplied range variables | both triggers |
| `o`, `l`, `c`, `s`, `i`, `t`, `a`, `target`, `source` | range aliases | throughout |

### Dynamic SQL

`usp_BuildDynamicReport` carries the modifiers `dynamic-sql` **and** `unresolved-call`, and emits
**zero** data edges. Its string literal names `dbo.Orders`, `dbo.OrderLines` and `dbo.AuditLog` — those
must not appear as edges. The negative half is the half that fails silently, so it is asserted too: a
procedure whose statement is built at runtime bounds the lineage and is a finding in its own right,
where inferring its targets manufactures edges nobody can check.

It also does `EXEC @ProcName`, which is an unresolved call — recorded as such rather than dropped — and
`EXEC sp_executesql`, which is **not** recorded as a procedure call, because a system procedure in every
lineage diagram is noise.

### Cross-database reference

`usp_CompareWithArchive` reads `ArchiveDb.dbo.Orders` **and** `dbo.Orders`, and produces two distinct
read edges: one to `ArchiveDb.dbo.Orders`, one to `Orders`.

A three-part name keeps its qualifier. Resolving it to the bare `Orders` would silently merge two
databases' same-named tables into one node; keeping it whole can match no local type, so it lands in the
referenced-but-not-defined list — which is what a cross-database reference honestly is from here. One-
and two-part names resolve to the **bare** table name, because that is how `SchemaProjectBuilder` names
its types (schema on the namespace) and every consumer joins on it.

### The partial parse

`usp_Unterminated` is the **only** object with `IsPartial = true`. Its `BEGIN` is never closed. It still
carries what was recovered — its one parameter, its body, and its read of `StagingOrders` — because a
procedure StormBoard cannot read confidently is itself a finding, and omitting it would read as the
estate not having one.

Everything else parses cleanly. In particular `usp_LoadOrders` must **not** be partial: it contains a
`CASE … END`, which contributes an `END` with no `BEGIN`, and the first implementation of the balance
check reported the fixture's most realistic procedure as unparseable because of it.

### Complexity

`usp_LoadOrders` is the branchiest object, at cyclomatic **8** over **39** statements, and
`ComplexityApproximate` is true for the corpus. The assertion is on the *value*, never on the member
existing: a type with a body-less member reports zero, and zero reads as clean code.

Its body also contains a `CASE` expression, a `BEGIN TRY`/`BEGIN CATCH` pair, a `WHILE` loop and an
`IF`/`ELSE IF`/`ELSE` chain, which is what makes 8 rather than 1.

### The cross-parser contract

This corpus holds `.sql` **schema** and `.sql` **procedures** together, deliberately, so a procedure's
edge target can be asserted against what the schema parser *actually emits* rather than against a
literal. That is the shape `CrossParserTableSpellingTests` exists for: v1.56.0 shipped SSIS data edges
spelled `dbo.Orders` against consumers that join on the bare name, and **neither parser's own fixture
could catch it** — the SSIS fixture held no `.sql` and the SQL fixture no `.dtsx`.
