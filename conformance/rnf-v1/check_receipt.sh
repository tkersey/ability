#!/bin/sh
set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)

test -f "$repository_root/src/rnf.zig"
test -f "$repository_root/src/machine.zig"
test ! -e "$repository_root/src/interpreter.zig"
test ! -e "$repository_root/src/program/loaded_execution.zig"
test ! -e "$repository_root/src/lowered_machine.zig"
test ! -e "$repository_root/src/internal/program_plan.zig"

printf '%s\n' \
    'boundary_machine_abi=2' \
    'boundary_rnf=true' \
    'single_boundary_reducer=true' \
    'program_session_public=false' \
    'boundary_runtime_public=false' \
    'static_machine_public=false' \
    'loaded_execution_present=false' \
    'runtime_program_plan_decode=false' \
    'generic_instruction_dispatch=false' \
    'canonical_state_format=ABL_RNF2' \
    'fixed_width_u32=true' \
    'bounded_vector_of_products=true' \
    'bounded_text_construction=true' \
    'product_construction=true' \
    'correlated_predicate_witness=true' \
    'bounded_recursive_helper=true' \
    'after_sites_exposed_to_world=0'
