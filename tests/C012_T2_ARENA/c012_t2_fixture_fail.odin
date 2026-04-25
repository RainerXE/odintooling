package fixture_c012_t2_fail

import "core:mem"
import "core:mem/virtual"

// C012-T2 failures: arena-typed variables missing 'arena' in name

scratch:  mem.Arena         // C012-T2: should be scratch_arena
backing:  mem.Arena         // C012-T2: should be backing_arena
storage:  virtual.Arena     // C012-T2: should be storage_arena

proc_with_arena :: proc() {
    temp:  mem.Arena        // C012-T2: should be temp_arena
    buf:   virtual.Arena    // C012-T2: should be buf_arena
    _ = temp; _ = buf
}
