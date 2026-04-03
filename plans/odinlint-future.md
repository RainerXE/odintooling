# 🚀 odin-lint Future Enhancements

## Configuration-Based Suppression Prefixes

### Feature Description

**User-Configurable Suppression Comment Prefixes** - Allow users to define custom suppression comment formats in `odin-lint.toml` that are used in addition to the built-in formats.

### Proposed Implementation

```toml
[suppression]
enable_inline_comments = true
comment_prefix = "odin-lint:ignore"

# User-defined additional prefixes
custom_prefixes = [
    "// lint:ignore",      # Shorter format
    "// no-lint",          # Alternative style
    "// disable: C001",     # Different syntax
]
```

### Benefits

1. **Team Customization** - Teams can use their preferred comment styles
2. **Legacy Code Support** - Adapt to existing codebase conventions
3. **Flexibility** - Support multiple suppression syntaxes
4. **Future-Proof** - Easy to add new formats without code changes

### Why Not Implemented Now

**Decision**: Postponed to future milestone (Post-M3.2)

**Rationale:**

1. **Current System Covers 95% of Use Cases**
   - Standard formats (`//odin-lint:ignore C001`) work for most teams
   - Multiple rule support (`C001,C002`) already implemented
   - Previous-line suppression already working

2. **Complexity vs. Benefit Analysis**
   - Requires TOML parsing infrastructure
   - Needs robust error handling for malformed configs
   - Complex string manipulation and validation
   - Estimated 2-3 days development time

3. **Higher Priority Tasks Exist**
   - Milestone 3.2: C002 rule implementation (critical path)
   - Completing core rule set (C003-C008)
   - LSP integration and real-world testing

4. **Backward Compatibility**
   - Can be added later without breaking changes
   - Existing suppression comments will continue to work
   - No urgency for this enhancement

5. **Lack of Immediate Need**
   - No user requests for this feature yet
   - Current system satisfies all known requirements
   - Can be driven by actual user feedback

### Technical Challenges

1. **TOML Parsing**
   - Need robust TOML parser or manual parsing
   - Error handling for malformed configuration files
   - Graceful fallback to defaults

2. **Configuration Management**
   - File I/O with proper error handling
   - Configuration caching and performance
   - Multiple configuration file support

3. **Prefix Validation**
   - Ensure custom prefixes don't conflict with code
   - Validate prefix formats
   - Prevent injection vulnerabilities

4. **Integration Complexity**
   - Update all rules to use configurable prefixes
   - Maintain backward compatibility
   - Comprehensive testing matrix

### Implementation Plan (Future)

**Phase 1: Infrastructure**
- [ ] Implement TOML parser or simple config reader
- [ ] Add configuration caching mechanism
- [ ] Create error handling framework

**Phase 2: Core Feature**
- [ ] Read suppression prefixes from config
- [ ] Merge with built-in prefixes
- [ ] Update suppression system to use combined list

**Phase 3: Integration**
- [ ] Update all existing rules
- [ ] Add configuration documentation
- [ ] Create comprehensive test suite

**Phase 4: Enhancements**
- [ ] Add validation and warnings
- [ ] Support per-rule prefix overrides
- [ ] Add IDE integration for config editing

### Alternative Approaches Considered

1. **Simple Text Config**
   - Pros: Easier to implement
   - Cons: Less flexible, no TOML benefits

2. **Environment Variables**
   - Pros: No file parsing needed
   - Cons: Limited complexity, hard to manage

3. **Command Line Arguments**
   - Pros: Immediate effect
   - Cons: Not persistent, hard to share

### Decision Summary

**✅ POSTPONED** - The configurable suppression prefixes feature is valuable but not critical. The current suppression system provides excellent functionality and covers the vast majority of use cases. Implementation is deferred to allow focus on completing the core rule set and achieving a stable, production-ready linter.

**Target Milestone**: Post-M3.2 (Enhancement Phase)
**Priority**: Medium (Nice-to-have, not critical)
**Estimated Effort**: 2-3 days development + testing

### Current Workaround

Users who want different suppression formats can:
1. Use the existing flexible formats (`//odin-lint:ignore`, `// odin-lint:ignore`, etc.)
2. Add suppression comments in a consistent style
3. Use previous-line suppression for better readability
4. Provide feedback to drive prioritization of this feature

### Example: Current Capabilities

```odin
// All these work today:
data := make([]int, 100)  // odin-lint:ignore C001
data := make([]int, 100)  // odin-lint: ignore C001
data := make([]int, 100)  // odin-lint:ignore C001,C002
// odin-lint:ignore C001
data := make([]int, 100)  // Previous line comment
```

### Future Example: With Configurable Prefixes

```toml
# odin-lint.toml
[suppression]
custom_prefixes = ["// lint:ignore", "// no-lint"]
```

```odin
# Future capability (not yet implemented):
data := make([]int, 100)  // lint:ignore C001
data := make([]int, 100)  // no-lint C001
```

---
**Status**: Future Enhancement (Postponed)
**Decision Date**: April 3, 2026
**Review Date**: After Milestone 3.2 completion