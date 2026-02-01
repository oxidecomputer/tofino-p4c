# Tofino P4 Compiler Bug: Uninitialized Metadata PHV Containers

## Summary

A bug in the Tofino P4 compiler causes metadata fields to remain uninitialized
even when explicitly initialized in P4 code. The compiler incorrectly removes
explicit zero initializations based on an assumption that the parser will
implicitly zero-initialize the PHV container the variable is assigned to, but
this assumption fails for metadata fields that are only used in MAU stages (not
the parser).

## Blast Radius

This bug potentially affects all P4 programs that depend on explicit metadata
initialization. Some programs are correct by coincidence when uninitialized
variables share a PHV container with initialized variables and thus benefit
from PHV container initialization through co-location. However, that's just
dumb luck. The behavior of P4 Programs that explicitly initialize metadata
variables to the underlying type's zero value should be considered undefined.

### Conditions for Corruption

A user-defined metadata field is corrupted when the following are true:

1. The field is explicitly initialized to `0`/`false` somewhere in P4 code
2. No `@pa_no_init` annotation
3. The field is NOT referenced in parser context, but only used in MAU stages.

### Common Vulnerable Patterns

This pattern is common in our P4 programs:

```p4
parser IngressParser(
    out sidecar_ingress_meta_t meta
    // ... other parameters
) {
    
    state meta_init {
        // Initialize flags in parser - ALL VULNERABLE
        meta.dropped = false;
        meta.ipv4_checksum_err = false;
        meta.is_switch_address = false;
        meta.service_routed = false;
        // ..
        // Initialize bit<N> values in parser - ALL VULNERABLE
        meta.nat_ingress_tgt = 0;
        meta.nat_inner_mac = 0;
        meta.nat_geneve_vni = 0;

    }
}

control Ingress(
    inout sidecar_ingress_meta_t meta,
) {
    //..
    apply {
        // ... later use these flags in tables/actions ...
        if (meta.service_routed) { ... }  // READS GARBAGE
    }
}
```

Any metadata field initialized at control block start or in the parser is
susceptible to corruption.

### The Silent Failure Problem

This bug is particularly dangerous because:
- **No compiler warning or error** - compilation succeeds
- **No runtime error** - program runs with garbage data
- **Behavior is non-deterministic** - depends on stale PHV contents
- **May work in simulation** - the tofino simulator seems to zero-initialize
  memory
- **Fails intermittently in hardware** - real PHV contains stale data from
  previous pipeline executions

## Root Cause

On the surface this bug is a **pass ordering issue** between two compiler passes
with incompatible assumptions.

### Pass 1: RemoveMetadataInits

**Location:** `backends/tofino/bf-p4c/phv/auto_init_metadata.cpp:104-159`

This pass removes explicit zero initializations like `meta.service_routed = false` when:

1. The field is user-defined metadata (as opposed to intrinsic metadata where
   `is_invalidate_from_arch()` returns false)
2. The assignment is `= 0` or `= false`
3. The assignment only overwrites `ImplicitParserInit`. This can be in parser
   or control code.

**Assumption:** If the explicit initialization is removed, the parser will
implicitly zero-initialize the container.

### Pass 2: ComputeInitZeroContainers

**Location:** `backends/tofino/bf-p4c/parde/lowered/compute_init_zero_containers.cpp:23-87`

This pass determines which containers need parser zero-initialization. It
works by iterating over metadata variables in a PHV to determine if the PHV
needs to be zero initialized. However, it only iterates over variables that are
_referenced_ in the parser context. If a variable is simply initialized in the
parser context, the PHV container is not marked as needing zero initialization.

### Concrete Disconnect

For `meta.service_routed` in
[metadata.p4](https://github.com/oxidecomputer/dendrite/blob/7a66c1b2415122b821611fd51012032a03e14ada/dpd/p4/metadata.p4#L22)
which is referenced in MAU stages 8-13 (not the parser):

1. `RemoveMetadataInits` removes the explicit `= false` initialization
2. `ComputeInitZeroContainers` calls `foreach_alloc(PARSER, ...)`
3. Because the field is **not referenced in the parser**, `foreach_alloc`
   returns nothing
4. `MB11` is the PHV container for `meta.service_routed`. `MB11` has no other
   fields and is thus **never added** to `initZeroContainers`
5. The parser does **not** zero-initialize `MB11`
6. The field contains garbage data
7. Sidecar switches randomly exhibit non-functional behaior in testing and QA

### Fundamental issue

UPDATE: ComputeInitZeroContainers does not even run on Tofino 2. So I have no
idea how this is expected to work at all. Unless the tofino hardwre is expected
to zero out containers on packet entry and is not for some reason.

This bug reflects an architectural problem, not just an implementation error in
pass ordering. `RemoveMetadataInits` makes a **speculative semantic program
change based on assumptions about future passes**:

```
RemoveMetadataInits runs EARLY (before PHV allocation)
    │
    ├─► Assumes: "Parser will zero-init this container"
    ├─► Removes explicit initialization
    │
    ... many passes, PHV allocation, etc. ...
    │
ComputeInitZeroContainers runs LATE (after PHV allocation)
    │
    └─► Actually decides what gets zero-inited
        └─► Assumption was WRONG for MAU-only fields
            └─► CORRUPTION
```

In order for the compiler to have any hope at being sound and maintainable, any
individual pass that modifies the program must produce a valid program. While
reordering of passes could produce more optimal results, reordering should never
impact soundness. Soundness can also not be maintained by convention, it has to
be by construction and enforced by the type system and structural model of the
compiler. In this particular case, a variable initialization must be tied to
an implentation that cannot be destroyed. The implementation can be transformed
(e.g. optimized), but it should not be possible to destroy. That's how this whole
optimization thing is supposed to work. Start with something obviously correct
and then apply a series of sound transformations over it yielding that something
that is unquestionably still correct and satisfies an evolving definition of
optimal as the compiler passes improve. But soundness should be an invariant by
design.

## Proposed Short Term Fix

### Attempt 1

Disable the Unsound Pass. This improves correctness at the cost of potentially
larger code.

A commit that does this is in this branch. Initial analysis of assembly and
testing in the lab suggests that the fix works.

#### Update

After running the P4 test suite on this attempted fix, it's become clear that
passes as a general rule are highly codependent. The compiler creates
synthetic initailizations that it depends on `RemoveMetadataInits` to remove
or PHV allocations will fail. There are no meaningful semantic boundaries around
passes, they should just be treated as an intertwined monolith.

### Attempt 2
