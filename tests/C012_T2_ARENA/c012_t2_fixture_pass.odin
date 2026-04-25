package fixture_c012_t2_pass

import "core:mem"
import "core:mem/virtual"

// C012-T2 passes: arena in name, or non-arena types

scratch_arena: mem.Arena         // OK: 'arena' present
my_arena:      mem.Arena         // OK: 'arena' present
virt_arena:    virtual.Arena     // OK: 'arena' present

// Non-arena types: unaffected by T2
counter:   int                   // OK: value type
allocator: mem.Allocator         // OK: T1 rule (has 'allocator'), not T2

proc_passing_arenas :: proc() {
    temp_arena:  mem.Arena       // OK: 'arena' present
    page_arena:  virtual.Arena   // OK: 'arena' present
    _ = temp_arena; _ = page_arena
}
