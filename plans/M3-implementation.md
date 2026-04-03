# Milestone 3 — Grammar Update & Rule Implementation
*Implementation Plan for C002-C008 Rules and Grammar Review*

---

## Overview

**Goal**: Implement real linting rules (C002-C008) and review grammar best practices from clippy.

**Priority**: CLI must be fully functional before OLS integration.

---

## Sub-Milestones

### 3.1 — Clippy Best Practices Integration

**Objective**: Apply Clippy lessons to odin-lint configuration and implementation.

#### Tasks:
- [x] Review clippy repository and document findings (COMPLETED)
- [x] Create `plans/clippy-lessons.md` with key takeaways (COMPLETED)
- [x] Update `odin-lint.toml` with Clippy-inspired configuration (COMPLETED)
- [ ] Implement rule categorization system
- [ ] Add inline suppression comments support
- [ ] Create rule documentation template

**Sub-Gate 3.1**: Clippy best practices integrated
- [x] Analysis completed and documented
- [x] Configuration file enhanced
- [ ] Rule categorization implemented
- [ ] Inline suppression working
- [ ] Documentation template created

---

### 3.2 — C002 Rule Implementation (Defer Free Issues)

**Objective**: Replace string matching with real AST analysis for defer free issues.

#### Tasks:
- [ ] Update `src/core/c002.odin` with AST analysis
- [ ] Detect defer free on wrong pointer types
- [ ] Use actual node types and relationships
- [ ] Generate accurate diagnostics
- [ ] Test with real Odin code examples

**Sub-Gate 3.2**: C002 rule implemented and tested
- [ ] AST analysis implemented
- [ ] Real Odin code tested (core, base, RuiShin, OLS)
- [ ] Accurate diagnostics generated
- [ ] Findings documented in `tests/real-world/c002.md`

---

### 3.3 — C003 Rule Implementation (Inconsistent Naming Conventions)

**Objective**: Detect and flag inconsistent naming conventions.

#### Tasks:
- [ ] Define naming convention rules
- [ ] Implement detection logic in `src/core/c003.odin`
- [ ] Test with various naming patterns
- [ ] Generate clear diagnostics

**Sub-Gate 3.3**: C003 rule implemented and tested
- [ ] Naming rules defined
- [ ] Detection logic implemented
- [ ] Tests passing
- [ ] Real-world testing completed (core, base, RuiShin, OLS)
- [ ] Findings documented in `tests/real-world/c003.md`

---

### 3.4 — C004 Rule Implementation (Private Procedure Naming)

**Objective**: Enforce naming conventions for private procedures.

#### Tasks:
- [ ] Define private procedure naming rules
- [ ] Implement detection in `src/core/c004.odin`
- [ ] Test with private procedures
- [ ] Generate diagnostics

**Sub-Gate 3.4**: C004 rule implemented and tested
- [ ] Rules defined
- [ ] Detection implemented
- [ ] Tests passing
- [ ] Real-world testing completed (core, base, RuiShin, OLS)
- [ ] Findings documented in `tests/real-world/c004.md`

---

### 3.5 — C005 Rule Implementation (Internal Procedure Naming)

**Objective**: Enforce naming conventions for internal procedures.

#### Tasks:
- [ ] Define internal procedure naming rules
- [ ] Implement detection in `src/core/c005.odin`
- [ ] Test with internal procedures
- [ ] Generate diagnostics

**Sub-Gate 3.5**: C005 rule implemented and tested
- [ ] Rules defined
- [ ] Detection implemented
- [ ] Tests passing
- [ ] Real-world testing completed (core, base, RuiShin, OLS)
- [ ] Findings documented in `tests/real-world/c005.md`

---

### 3.6 — C006 Rule Implementation (Public Procedure Naming)

**Objective**: Enforce naming conventions for public procedures.

#### Tasks:
- [ ] Define public procedure naming rules
- [ ] Implement detection in `src/core/c006.odin`
- [ ] Test with public procedures
- [ ] Generate diagnostics

**Sub-Gate 3.6**: C006 rule implemented and tested
- [ ] Rules defined
- [ ] Detection implemented
- [ ] Tests passing
- [ ] Real-world testing completed (core, base, RuiShin, OLS)
- [ ] Findings documented in `tests/real-world/c006.md`

---

### 3.7 — C007 Rule Implementation (Type Naming)

**Objective**: Enforce PascalCase for type names.

#### Tasks:
- [ ] Define type naming rules
- [ ] Implement detection in `src/core/c007.odin`
- [ ] Test with various type definitions
- [ ] Generate diagnostics

**Sub-Gate 3.7**: C007 rule implemented and tested
- [ ] Rules defined
- [ ] Detection implemented
- [ ] Tests passing
- [ ] Real-world testing completed (core, base, RuiShin, OLS)
- [ ] Findings documented in `tests/real-world/c007.md`

---

### 3.8 — C008 Rule Implementation (Acronym Consistency)

**Objective**: Enforce consistent acronym usage.

#### Tasks:
- [ ] Define acronym consistency rules
- [ ] Implement detection in `src/core/c008.odin`
- [ ] Test with various acronyms
- [ ] Generate diagnostics

**Sub-Gate 3.8**: C008 rule implemented and tested
- [ ] Rules defined
- [ ] Detection implemented
- [ ] Tests passing
- [ ] Real-world testing completed (core, base, RuiShin, OLS)
- [ ] Findings documented in `tests/real-world/c008.md`

---

## Gate 3 — CLI with Clippy-Inspired Features

**Criteria for Completion**:
- [x] Clippy analysis completed and documented
- [x] Configuration file enhanced with Clippy patterns
- [ ] Rule categorization system implemented
- [ ] Inline suppression comments working
- [ ] C002 detects real defer free issues in test files
- [ ] At least 4 additional rules implemented (C003-C006)
- [ ] All implemented rules tested with:
  - [ ] Fixture tests (pass/fail)
  - [ ] Odin core libraries
  - [ ] Odin base libraries
  - [ ] RuiShin project
  - [ ] OLS project
- [ ] Clear diagnostics generated for all rules
- [ ] Real-world testing findings documented
- [ ] Rule documentation created for implemented rules

---

## Testing Strategy

### Fixture Testing
For each rule:
- Create 3 pass fixtures (no diagnostics expected)
- Create 3 fail fixtures (specific diagnostics expected)
- Update snapshot files with expected output
- Run `scripts/test_rules.sh` to verify

### Real-World Testing
Test each rule on real codebases:
- **Odin core libraries**: Test against `vendor/odin/core/`
- **Odin base libraries**: Test against `vendor/odin/base/`
- **RuiShin project**: Test against the RuiShin codebase
- **OLS project**: Test against the OLS codebase

### Testing Process
1. Run rule on each codebase
2. Document findings in `tests/real-world/<rule>.md`
3. Analyze false positives/negatives
4. Refine rule implementation based on findings
5. Update documentation with real-world examples

---

## Performance Considerations

- Ensure rules don't significantly impact CLI performance
- Optimize AST traversal where possible
- Consider caching for repeated analysis

---

## Documentation Updates

- Update main implementation plan with progress
- Document each rule's purpose and examples
- Add usage examples to README

---

## Timeline

This milestone is expected to take 2-4 weeks depending on:
- Complexity of rule implementations
- Testing requirements
- Performance optimization needs

---

## Next Steps

After Gate 3 completion:
- Proceed to Milestone 4 (CLI enhancements)
- Consider OLS integration (Milestone 5) when CLI is stable

---

## Status Tracking

Use this document to track progress on each sub-milestone and task.
Update checklist items as work is completed.
Create separate task documents for complex implementations.

---

*Last updated: [date]*
*Version: 1.0*