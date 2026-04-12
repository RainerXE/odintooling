
# OdinLint Addons: Enhancer, Call Graph, and Helper
*Proposal for Extending OdinLint with Static Analysis, Refactoring, and Interactive Assistance*

---

## 1. Overview
This document outlines a **three-part extension** to OdinLint:
1. **Enhancer/Linter**: Flags risky constructs (e.g., unmarked pointers) and auto-applies fixes.
2. **Call Graph**: Builds a graph of function calls, variable usage, and memory flows for deep static analysis.
3. **Helper**: Provides interactive guidance (e.g., "How do I build X?" or "Why is this flagged?").

**Goal**: Make Odin code safer, more readable, and easier to refactor.

---

## 2. Enhancer/Linter
### A. Flag Mode
Uses **Tree-sitter** to detect risky patterns. Example rules:

#### Pointers Without Prefixes
```scheme
; Tree-sitter query for unmarked pointers
(variable_declaration
  name: (identifier) @name (#match? @name "^[^p]")
  type: (pointer_type))




Flag: warning: Pointer 'buffer' lacks p_/pa_ prefix. Use 'p_buffer' or 'pa_buffer'.
Unsafe Array Access
scheme
Copy

; Find array accesses without bounds checks
(index_expression
  left: (identifier) @array
  index: (_))




Flag: warning: Array 'a_data' accessed without bounds checks. Use SAFE_ARRAY_ACCESS or add #bound_check.
B. Fix Mode
Auto-applies fixes:

Rename buffer → p_buffer.
Wrap arrays in SAFE_ARRAY_ACCESS.
Example:
odin
Copy

; Before
buffer: ^int;
value := a_data[index];

; After (auto-fixed)
p_buffer: ^int;
value := SAFE_ARRAY_ACCESS(a_data, index);




C. CLI Integration
bash
Copy

odinlint flag ca.odin   # Show warnings
odinlint fix ca.odin    # Apply fixes




3. Call Graph
A. Schema (SQLite)
sql
Copy

CREATE TABLE functions (
    id INTEGER PRIMARY KEY,
    name TEXT,
    file TEXT,
    line INTEGER
);
CREATE TABLE variables (
    id INTEGER PRIMARY KEY,
    name TEXT,
    type TEXT,
    function_id INTEGER
);
CREATE TABLE usages (
    variable_id INTEGER,
    line INTEGER,
    kind TEXT  -- "read", "write", "declare", "free"
);
CREATE TABLE calls (
    caller_id INTEGER,
    callee_id INTEGER,
    line INTEGER
);



B. Queries
Dangling Pointers
sql
Copy

SELECT v.name
FROM variables v
JOIN usages u ON v.id = u.variable_id
WHERE v.type LIKE '^%'
  AND u.kind = 'free'
  AND EXISTS (
      SELECT 1 FROM usages u2
      WHERE u2.variable_id = v.id
        AND u2.line > u.line  -- Used after free
  );



Function Dependencies
sql
Copy

SELECT f2.name
FROM functions f1
JOIN calls c ON f1.id = c.caller_id
JOIN functions f2 ON c.callee_id = f2.id
WHERE f1.name = 'update_grid';



C. CLI Integration
bash
Copy

odinlint call-graph build ca.odin   # Build graph
odinlint call-graph query "dangling pointers"  # Run queries




4. Naming Conventions


  
    
      Risk
      Convention
      Example
    
  
  
    
      Regular pointer
      p_
      p_buffer: ^int
    
    
      Arena pointer
      pa_
      pa_node: ^Node
    
    
      Unsafe array
      _unsafe
      a_data_unsafe: []int
    
    
      Dangling pointer
      _dangling
      p_data_dangling: ^int
    
    
      Off-by-one risk
      _oboe
      i_max_oboe: int
    
  



5. Safety Wrappers
A. NonNullPointer
odin
Copy

NonNullPointer :: distinct ^T;

make_non_null :: proc(p: ^T): NonNullPointer[T] {
    if p == nil { panic("NonNullPointer cannot be nil"); }
    return transmit(p);
}

// Usage:
p_safe: NonNullPointer[int] = make_non_null(new(int));



B. SAFE_ARRAY_ACCESS Macro
odin
Copy

SAFE_ARRAY_ACCESS :: #load {
    arr: []\$T,
    index: int,
    `{
        if index < 0 or index >= len(arr) {
            panic("Array index out of bounds");
        }
        arr[index]
    }
};




6. Implementation Plan
Phase 1: Enhancer (1–2 Weeks)

Add Tree-sitter queries for pointers/arrays.
Implement --flag and --fix modes.
Test on your cellular automaton module.
Phase 2: Call Graph (2–3 Weeks)

Parse Odin code with Tree-sitter.
Store graph in SQLite.
Add queries for dangling pointers/function dependencies.
Phase 3: Helper (Optional)

Add --explain to describe flags.
Add --refactor to guide safe changes.

7. Example Workflow
bash
Copy

# 1. Flag issues
odinlint flag ca.odin

# 2. Auto-fix safe issues
odinlint fix ca.odin

# 3. Build call graph
odinlint call-graph build ca.odin

# 4. Query call graph
odinlint call-graph query "dangling pointers"

# 5. Interactive help
odinlint helper --explain ca.odin:42




8. Next Steps

Start with the Enhancer:

Implement flagging for unmarked pointers (p_/pa_).
Add --flag and --fix modes.

Test on Real Code:

Run on your cellular automaton module.

Design the Call Graph Schema:

Focus on functions, variables, and usages.

Document Conventions:

Add a CONVENTIONS.md to your project.

