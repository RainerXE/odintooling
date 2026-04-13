# Milestone 3 — Rule Implementation (C002-C008)
*Updated Implementation Plan — April 2026*
*Incorporates architecture review feedback*

---

## Overview

**Goal**: Implement real linting rules C002-C008, with C002 treated as a full sub-milestone
matching the rigour applied to C001.

**Priority order**:
1. C002 — correctness rule, complex, deserves its own sub-milestone
2. C003-C008 — naming rules, grouped as a single sub-milestone (shared detection pattern)
3. Gate 3 validation — real-world testing and fixture completion

**Principle**: Rules must be stable before autofix is added. Autofix is scoped to Milestone 4.5,
not M3. Do not add fix generation logic to rules during this milestone.

---

## Sub-Milestones

---

### 3.1 — Clippy Best Practices Integration ✅ COMPLETED

**Sub-Gate 3.1**: All criteria met
- [x] Clippy analysis completed and documented
- [x] Configuration file enhanced
- [x] Rule categorization implemented (RuleCategory enum, 6 categories)
- [x] Rule file naming convention improved (Cnnn-CAT-Description.odin)
- [x] Test system reorganized with descriptive naming
- [x] Fixture tests consolidated into Cnnn folders
- [x] C001 defer delete issue resolved and verified
- [x] Inline suppression working (centralized suppression system)
- [ ] Rule documentation template created ← still outstanding

---

### 3.2 — C002 Rule Implementation (Defer Free on Wrong Pointer)

**Status**: In progress — multiple review iterations completed, core issues identified.

**Why this is its own full sub-milestone**: C002 involves scope tracking, allocation/free
pairing across AST nodes, reassignment detection, and two-path AST handling (tree-sitter CLI
path vs ^ast.File OLS path). It is more complex than C001 and must be treated accordingly.

#### Known architecture decisions (from review)

- `C002AnalysisContext` struct holds all per-file state (no globals) ✅
- `c002Matcher` returns `[]Diagnostic` (not single Diagnostic) ✅
- `c002Matcher` is called directly from main, not via `Rule.matcher` (signature mismatch) ✅
- Scope tracking must use pre-order push / post-order pop pattern (not enter/exit heuristic)
- `is_pointer_allocation` must match assignment/declaration nodes, not call_expression nodes
- `extract_var_name_from_allocation` must handle both `:=` and `=` assignment forms
- `extract_var_name_from_free` must handle both `free(` and `delete(` patterns ✅

#### Remaining implementation tasks

- [ ] Fix scope tracking: push before child recursion, pop after (pre/post-order)
- [ ] Fix `is_pointer_allocation`: match `short_var_declaration` / `assignment` node types
      whose text contains a known allocator call, not `call_expression` nodes
- [ ] Verify no duplicate allocation registration from ancestor nodes (test with AST dump)
- [ ] Implement `=` branch in `extract_var_name_from_allocation` (currently stubs to `""`)
- [ ] Remove Pattern 1 from `is_suspicious_pointer_usage` or tighten to argument region only
- [ ] Remove `matcher = nil` from registry or add nil guard in all dispatch code
- [ ] Remove unused `import "core:os"` from c002 file

#### Testing tasks

- [ ] Create 3 pass fixtures: valid pointer usage, correct defer free, arena pattern
- [ ] Create 3 fail fixtures: wrong pointer freed, double free, freed after reassignment
- [ ] Run on RuiShin codebase, document findings and false positive rate
- [ ] Run on OLS codebase, document findings and false positive rate

#### Quality criteria for Sub-Gate 3.2

- False positive rate on RuiShin and OLS must be < 5% (i.e. most findings are real issues)
- All 3 pass fixtures produce zero diagnostics
- All 3 fail fixtures produce exactly the documented diagnostic
- Scope tracking verified correct across nested blocks (unit test or AST dump evidence)

**Sub-Gate 3.2**: C002 implemented, tested, false positive rate documented
- [ ] Scope tracking correct (pre/post-order)
- [ ] Allocation tracking works for both `:=` and `=` forms
- [ ] Free detection handles `free(` and `delete(`
- [ ] Fixture tests passing (3 pass, 3 fail)
- [ ] Real-world testing on RuiShin + OLS completed
- [ ] Findings documented in `tests/real-world/c002.md`

---

### 3.3 — C003-C008 Naming Rules (Grouped Sub-Milestone)

**Rationale for grouping**: C003 through C008 are structurally identical — extract a name
from a declaration node, apply a naming convention predicate, emit a diagnostic if it fails.
Implementing them as six sequential sub-milestones would be repetitive. Instead, build a
shared naming rule infrastructure and configure each rule against it.

#### Naming rules covered

| Rule | Target | Convention |
|------|--------|------------|
| C003 | All identifiers | Consistent casing within file/project |
| C004 | Private procedures | snake_case (unexported, leading underscore or package-private) |
| C005 | Internal procedures | snake_case |
| C006 | Public procedures | PascalCase |
| C007 | Type names | PascalCase |
| C008 | Acronyms | Consistent (e.g. HTTP not Http, ID not Id) |

#### Shared infrastructure to build first

```
naming_rule_matcher(node, convention, rule_id) -> []Diagnostic
  - extract_identifier_from_node(node) -> string
  - check_convention(name, convention) -> bool
  - is_public_declaration(node) -> bool
  - is_private_declaration(node) -> bool
```

Each rule (C003-C008) then becomes a thin wrapper that calls this with the appropriate
convention and target node types. Estimated code per rule: ~20 lines.

#### Node types to target

- `proc_declaration` — for C004/C005/C006
- `type_declaration`, `struct_type`, `enum_type`, `union_type` — for C007
- Any identifier — for C008 (acronym scan)
- All declaration nodes — for C003 (consistency check)

#### Real-world testing scope

**Important**: Do NOT test naming rules against Odin core or base libraries.
Core/base use their own internal conventions and will produce high false positive noise.
Limit real-world testing to:
- RuiShin project
- OLS project

#### Tasks

- [ ] Design and implement shared `naming_rule_matcher` infrastructure
- [ ] Implement C003 using shared infrastructure
- [ ] Implement C004 using shared infrastructure
- [ ] Implement C005 using shared infrastructure
- [ ] Implement C006 using shared infrastructure
- [ ] Implement C007 using shared infrastructure
- [ ] Implement C008 using shared infrastructure
- [ ] Create 3 pass + 3 fail fixtures per rule (18 fixture files total)
- [ ] Run all 6 rules on RuiShin and OLS, document findings
- [ ] Measure false positive rate per rule, refine if > 10%

**Sub-Gate 3.3**: All naming rules implemented and tested
- [ ] Shared naming infrastructure implemented and used by all 6 rules
- [ ] All fixture tests passing (18 pass, 18 fail)
- [ ] Real-world testing on RuiShin + OLS completed for all rules
- [ ] False positive rate documented per rule
- [ ] Findings documented in `tests/real-world/c003-c008.md`

---

### 3.4 — Rule Documentation Template

*Carried over from 3.1 as still outstanding.*

- [ ] Create documentation template for rules
- [ ] Apply template to C001 (retroactively)
- [ ] Apply template to C002-C008 as they are completed

---

## Gate 3 — CLI with Clippy-Inspired Rule Set

**Quality criteria (explicit)**:

- C002 false positive rate < 5% on RuiShin and OLS
- C003-C008 false positive rate < 10% per rule on RuiShin and OLS
- All rules have fixture tests (3 pass + 3 fail minimum)
- No rule has known false negatives on the documented target patterns
- Inline suppression works for all rules (// odin-lint:ignore C00x)

**Checklist**:

- [x] Clippy analysis completed and documented
- [x] Configuration file enhanced with Clippy patterns
- [x] Rule categorization system implemented
- [x] Inline suppression comments working
- [ ] C002 detects real defer free issues — false positive rate documented
- [ ] C003-C008 implemented via shared naming infrastructure
- [ ] All rules tested with fixture tests (pass/fail)
- [ ] Real-world testing on RuiShin and OLS for all rules
- [ ] Findings documented per rule in `tests/real-world/`
- [ ] Rule documentation template created and applied

---

## Testing Strategy

### Fixture Testing (per rule)
- 3 pass fixtures — must produce zero diagnostics
- 3 fail fixtures — must produce exactly the documented diagnostic
- Snapshot files with expected stdout output for each fail fixture
- Run via `scripts/test_rules.sh`

### Real-World Testing (scoped)

| Rule | Odin core | Odin base | RuiShin | OLS |
|------|-----------|-----------|---------|-----|
| C002 | ❌ too noisy | ❌ | ✅ | ✅ |
| C003-C008 | ❌ different conventions | ❌ | ✅ | ✅ |

### False Positive Threshold
- Correctness rules (C001, C002): < 5%
- Style/naming rules (C003-C008): < 10%
- If threshold exceeded: refine rule before proceeding to Gate 3

---

## What is explicitly OUT OF SCOPE for M3

- **Autofix / --fix flag**: Scoped to Milestone 4.5. Rules must be stable first.
- **OLS plugin wiring**: Scoped to Milestone 5.
- **MCP gateway**: Scoped to Milestone 5.5.
- **JSON output format**: Scoped to Milestone 4 CLI enhancements.
- **Performance optimization**: Only if a rule demonstrably impacts CLI usability.

---

## Timeline Estimate

| Sub-Milestone | Estimated effort |
|--------------|-----------------|
| 3.2 C002 completion | 1-2 weeks (complex, needs scope fix + testing) |
| 3.3 C003-C008 naming rules | 1-2 weeks (shared infrastructure amortises cost) |
| 3.4 Documentation template | 1-2 days |
| Gate 3 validation | 2-3 days |
| **Total** | **3-5 weeks** |

---

## Next Steps After Gate 3

Proceed to Milestone 4 (CLI enhancements: --help, --list-rules, JSON output),
then Milestone 4.5 (Autofix layer), then Milestone 5 (OLS plugin integration).

---

*Version: 2.0*
*Updated: April 2026*
*Previous version: M3-implementation.md (v1.0)*
