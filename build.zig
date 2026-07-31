const std = @import("std");

const CoreModules = struct {
    agent_profile: *std.Build.Module,
    compiler: *std.Build.Module,
    control_ir: *std.Build.Module,
    driver: *std.Build.Module,
    effect_v2: *std.Build.Module,
    machine: *std.Build.Module,
    portable_value: *std.Build.Module,
    program_v2: *std.Build.Module,
    rnf: *std.Build.Module,
};

fn addTestArtifact(
    b: *std.Build,
    step: *std.Build.Step,
    root_module: *std.Build.Module,
) void {
    const tests = b.addTest(.{ .root_module = root_module });
    step.dependOn(&b.addRunArtifact(tests).step);
}

fn addExpectedCompileFailure(
    b: *std.Build,
    step: *std.Build.Step,
    core: CoreModules,
    path: []const u8,
    expected_error: []const u8,
) void {
    const module = b.createModule(.{
        .root_source_file = b.path(path),
        .target = b.graph.host,
        .optimize = .Debug,
    });
    module.addImport("control_ir", core.control_ir);
    module.addImport("portable_value", core.portable_value);
    module.addImport("program_v2", core.program_v2);
    const compilation = b.addTest(.{ .root_module = module });
    compilation.expect_errors = .{ .contains = expected_error };
    step.dependOn(&compilation.step);
}

fn addCoreModules(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) CoreModules {
    const control_ir = b.createModule(.{
        .root_source_file = b.path("src/control_ir.zig"),
        .target = target,
        .optimize = optimize,
    });
    const portable_value = b.createModule(.{
        .root_source_file = b.path("src/portable_value.zig"),
        .target = target,
        .optimize = optimize,
    });
    const machine = b.createModule(.{
        .root_source_file = b.path("src/machine.zig"),
        .target = target,
        .optimize = optimize,
    });
    machine.addImport("portable_value", portable_value);
    const rnf = b.createModule(.{
        .root_source_file = b.path("src/rnf.zig"),
        .target = target,
        .optimize = optimize,
    });
    rnf.addImport("control_ir", control_ir);
    const compiler = b.createModule(.{
        .root_source_file = b.path("src/compiler.zig"),
        .target = target,
        .optimize = optimize,
    });
    compiler.addImport("control_ir", control_ir);
    compiler.addImport("machine", machine);
    compiler.addImport("portable_value", portable_value);
    compiler.addImport("rnf", rnf);
    const program_v2 = b.createModule(.{
        .root_source_file = b.path("src/program_v2.zig"),
        .target = target,
        .optimize = optimize,
    });
    program_v2.addImport("compiler", compiler);
    program_v2.addImport("machine", machine);
    const driver = b.createModule(.{
        .root_source_file = b.path("src/driver.zig"),
        .target = target,
        .optimize = optimize,
    });
    const effect_v2 = b.createModule(.{
        .root_source_file = b.path("src/effect_v2.zig"),
        .target = target,
        .optimize = optimize,
    });
    const agent_profile = b.createModule(.{
        .root_source_file = b.path("src/agent_profile.zig"),
        .target = target,
        .optimize = optimize,
    });
    agent_profile.addImport("program_v2", program_v2);

    return .{
        .agent_profile = agent_profile,
        .compiler = compiler,
        .control_ir = control_ir,
        .driver = driver,
        .effect_v2 = effect_v2,
        .machine = machine,
        .portable_value = portable_value,
        .program_v2 = program_v2,
        .rnf = rnf,
    };
}

fn wirePublicImports(module: *std.Build.Module, core: CoreModules) void {
    module.addImport("agent_profile", core.agent_profile);
    module.addImport("control_ir", core.control_ir);
    module.addImport("driver", core.driver);
    module.addImport("effect_v2", core.effect_v2);
    module.addImport("machine", core.machine);
    module.addImport("portable_value", core.portable_value);
    module.addImport("program_v2", core.program_v2);
}

fn programTestModule(
    b: *std.Build,
    core: CoreModules,
    path: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    include_driver: bool,
    include_portable_value: bool,
) *std.Build.Module {
    const module = b.createModule(.{
        .root_source_file = b.path(path),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("control_ir", core.control_ir);
    module.addImport("program_v2", core.program_v2);
    if (include_driver) module.addImport("driver", core.driver);
    if (include_portable_value) {
        module.addImport("portable_value", core.portable_value);
    }
    return module;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const core = addCoreModules(b, target, optimize);
    const host_core = addCoreModules(b, b.graph.host, optimize);

    const boundary = b.addModule("boundary", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    wirePublicImports(boundary, core);

    const library = b.addLibrary(.{
        .linkage = .static,
        .name = "boundary",
        .root_module = boundary,
    });
    b.installArtifact(library);

    const one_effect_module = b.createModule(.{
        .root_source_file = b.path("examples/one_effect.zig"),
        .target = target,
        .optimize = optimize,
    });
    one_effect_module.addImport("boundary", boundary);
    const one_effect_example = b.addExecutable(.{
        .name = "boundary-one-effect",
        .root_module = one_effect_module,
    });
    const examples_step = b.step(
        "check-boundary-examples",
        "Compile the Boundary Machine examples.",
    );
    examples_step.dependOn(&one_effect_example.step);

    const test_step = b.step("test", "Run the Boundary Machine test suite.");
    addTestArtifact(b, test_step, boundary);
    addTestArtifact(b, test_step, core.agent_profile);
    addTestArtifact(b, test_step, core.control_ir);
    addTestArtifact(b, test_step, core.effect_v2);
    addTestArtifact(b, test_step, core.machine);
    addTestArtifact(b, test_step, core.portable_value);
    addTestArtifact(b, test_step, core.rnf);

    const program_operations = programTestModule(
        b,
        host_core,
        "test/program_operations.zig",
        b.graph.host,
        optimize,
        false,
        true,
    );
    const integer_boolean_operations = programTestModule(
        b,
        host_core,
        "test/program_integer_boolean_operations.zig",
        b.graph.host,
        optimize,
        false,
        false,
    );
    const algebraic_collection_operations = programTestModule(
        b,
        host_core,
        "test/program_algebraic_collection_operations.zig",
        b.graph.host,
        optimize,
        false,
        true,
    );
    const research_digest = programTestModule(
        b,
        host_core,
        "test/research_digest_v2.zig",
        b.graph.host,
        optimize,
        false,
        true,
    );
    const program_compile = programTestModule(
        b,
        host_core,
        "test/program_compile.zig",
        b.graph.host,
        optimize,
        true,
        false,
    );
    const program_dynamic_fuel = programTestModule(
        b,
        host_core,
        "test/program_dynamic_fuel.zig",
        b.graph.host,
        optimize,
        false,
        true,
    );
    const program_residual_effects = programTestModule(
        b,
        host_core,
        "test/program_residual_effects.zig",
        b.graph.host,
        optimize,
        false,
        false,
    );
    program_residual_effects.addImport("machine", host_core.machine);
    const program_effect_morphism = programTestModule(
        b,
        host_core,
        "test/program_effect_morphism.zig",
        b.graph.host,
        optimize,
        false,
        false,
    );
    program_effect_morphism.addImport("effect_v2", host_core.effect_v2);
    program_effect_morphism.addImport("machine", host_core.machine);
    const program_effect_handler = programTestModule(
        b,
        host_core,
        "test/program_effect_handler.zig",
        b.graph.host,
        optimize,
        false,
        false,
    );
    program_effect_handler.addImport("effect_v2", host_core.effect_v2);
    program_effect_handler.addImport("machine", host_core.machine);
    const program_dead_control = programTestModule(
        b,
        host_core,
        "test/program_dead_control.zig",
        b.graph.host,
        optimize,
        false,
        false,
    );
    program_dead_control.addImport("machine", host_core.machine);
    const constructor_invariants = programTestModule(
        b,
        host_core,
        "test/program_constructor_invariants.zig",
        b.graph.host,
        optimize,
        false,
        false,
    );
    const recursion = programTestModule(
        b,
        host_core,
        "test/machine_recursion.zig",
        b.graph.host,
        optimize,
        false,
        false,
    );
    const after = programTestModule(
        b,
        host_core,
        "test/machine_after.zig",
        b.graph.host,
        optimize,
        false,
        false,
    );
    const machine_yield = programTestModule(
        b,
        host_core,
        "test/machine_yield.zig",
        b.graph.host,
        optimize,
        false,
        false,
    );
    const agent_loop = programTestModule(
        b,
        host_core,
        "test/agent_loop.zig",
        b.graph.host,
        optimize,
        false,
        false,
    );
    agent_loop.addImport("agent_profile", host_core.agent_profile);

    const performance_core = addCoreModules(
        b,
        b.graph.host,
        .ReleaseFast,
    );
    const performance_module = programTestModule(
        b,
        performance_core,
        "test/machine_performance.zig",
        b.graph.host,
        .ReleaseFast,
        false,
        true,
    );
    const performance_tests = b.addTest(.{
        .root_module = performance_module,
    });

    const rnf_step = b.step(
        "check-boundary-rnf",
        "Check private Resumption Normal Form synthesis.",
    );
    addTestArtifact(b, rnf_step, core.rnf);

    const control_step = b.step(
        "check-boundary-rnf-control",
        "Check typed Control IR, exact liveness, and local invariants.",
    );
    addTestArtifact(b, control_step, core.control_ir);
    addTestArtifact(b, control_step, core.rnf);
    addTestArtifact(b, control_step, constructor_invariants);
    addTestArtifact(b, control_step, machine_yield);
    addTestArtifact(b, control_step, program_dead_control);
    addTestArtifact(b, control_step, program_effect_handler);
    addTestArtifact(b, control_step, program_effect_morphism);

    const values_step = b.step(
        "check-boundary-rnf-values",
        "Check canonical fixed-width and bounded portable values.",
    );
    addTestArtifact(b, values_step, core.portable_value);
    addTestArtifact(b, values_step, program_operations);
    addTestArtifact(b, values_step, integer_boolean_operations);
    addTestArtifact(b, values_step, algebraic_collection_operations);
    addTestArtifact(b, values_step, program_dynamic_fuel);

    const research_step = b.step(
        "check-boundary-research-digest-v2",
        "Check Machine-owned Research Digest v2 transformation.",
    );
    addTestArtifact(b, research_step, research_digest);

    const machine_step = b.step(
        "check-boundary-machine",
        "Check the generated direct Boundary Machine ABI v2 reducer.",
    );
    addTestArtifact(b, machine_step, core.machine);
    addTestArtifact(b, machine_step, program_compile);
    addTestArtifact(b, machine_step, program_dynamic_fuel);
    addTestArtifact(b, machine_step, program_residual_effects);
    addTestArtifact(b, machine_step, program_dead_control);
    addTestArtifact(b, machine_step, program_effect_handler);
    addTestArtifact(b, machine_step, program_effect_morphism);
    addTestArtifact(b, machine_step, machine_yield);

    const state_step = b.step(
        "check-boundary-machine-state",
        "Check canonical ABL_RNF2 Machine state round trips.",
    );
    addTestArtifact(b, state_step, core.machine);

    const malformed_step = b.step(
        "check-boundary-machine-malformed",
        "Check fail-closed malformed ABL_RNF2 state rejection.",
    );
    addTestArtifact(b, malformed_step, core.machine);
    addTestArtifact(b, malformed_step, core.portable_value);
    addTestArtifact(b, malformed_step, program_compile);
    addTestArtifact(b, malformed_step, constructor_invariants);
    addTestArtifact(b, malformed_step, research_digest);

    const recursion_step = b.step(
        "check-boundary-rnf-recursion",
        "Check compiled bounded recursive frames and transactional overflow.",
    );
    addTestArtifact(b, recursion_step, recursion);

    const after_step = b.step(
        "check-boundary-rnf-after",
        "Check compiler-local after lowering with no exposed after sites.",
    );
    addTestArtifact(b, after_step, after);

    const agent_step = b.step(
        "check-boundary-agent-loop",
        "Check the typed model/tool agent loop across fresh instances.",
    );
    addTestArtifact(b, agent_step, agent_loop);

    const parity_native_witness = programTestModule(
        b,
        host_core,
        "test/machine_native_wasm.zig",
        b.graph.host,
        .ReleaseSafe,
        false,
        false,
    );
    const parity_native_runner = b.createModule(.{
        .root_source_file = b.path("test/run_machine_native.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    });
    parity_native_runner.addImport("parity_witness", parity_native_witness);
    const parity_native = b.addExecutable(.{
        .name = "boundary-machine-native-parity",
        .root_module = parity_native_runner,
    });
    const native_output = b.addRunArtifact(parity_native).captureStdOut(.{
        .basename = "boundary-machine-native-parity.bin",
    });

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
        .abi = .none,
    });
    const wasm_core = addCoreModules(b, wasm_target, .ReleaseSmall);
    const parity_wasm = programTestModule(
        b,
        wasm_core,
        "test/machine_native_wasm.zig",
        wasm_target,
        .ReleaseSmall,
        false,
        false,
    );
    const wasm_executable = b.addExecutable(.{
        .name = "boundary-machine-wasm-parity",
        .root_module = parity_wasm,
    });
    wasm_executable.entry = .disabled;
    wasm_executable.rdynamic = true;
    wasm_executable.export_memory = true;
    const run_wasm = b.addSystemCommand(&.{"node"});
    run_wasm.addFileArg(b.path("test/run_machine_wasm.mjs"));
    run_wasm.addFileArg(wasm_executable.getEmittedBin());
    const wasm_output = run_wasm.captureStdOut(.{
        .basename = "boundary-machine-wasm-parity.bin",
    });
    const compare_parity = b.addSystemCommand(&.{ "cmp", "-s" });
    compare_parity.addFileArg(native_output);
    compare_parity.addFileArg(wasm_output);
    const parity_step = b.step(
        "check-boundary-machine-native-wasm",
        "Check byte-identical native and wasm32 Machine observations.",
    );
    parity_step.dependOn(&compare_parity.step);

    const no_interpreter_command = b.addSystemCommand(&.{
        "sh",
        "-c",
        \\set -eu
        \\test ! -e src/interpreter.zig
        \\test ! -e src/program/loaded_execution.zig
        \\test ! -e src/lowered_machine.zig
        \\test ! -e src/internal/program_plan.zig
        \\! rg -n '@import\("(loaded_execution|lowered_machine|interpreter|internal_program_plan)"\)' src build.zig
        \\! rg -n 'ProgramPlan|Program\.Session|runtime instruction table|last_condition|after_stack' src/compiler.zig src/machine.zig src/program_v2.zig src/rnf.zig src/root.zig
    });
    const no_interpreter_step = b.step(
        "check-boundary-machine-no-interpreter",
        "Prove the production Machine graph has no legacy interpreter path.",
    );
    no_interpreter_step.dependOn(&no_interpreter_command.step);

    const deletion_command = b.addSystemCommand(&.{
        "sh",
        "-c",
        \\set -eu
        \\for path in \
        \\  src/boundary_shared.zig \
        \\  src/interpreter.zig \
        \\  src/lowered_machine.zig \
        \\  src/program/loaded_execution.zig \
        \\  src/program_api.zig \
        \\  src/internal/program_plan.zig \
        \\  src/internal_program_plan.zig \
        \\  test/program_api_test.zig \
        \\  test/static_machine_test.zig \
        \\  test/static_machine_wasm32_compile.zig \
        \\  conformance/static-machine-v1
        \\do
        \\  test ! -e "$path"
        \\done
        \\! rg -n 'pub const (Runtime|staticMachine|StaticMachineOptions)|Program\.Session|Loaded(Session|Module)|Certified Boundary Module' src/root.zig src
    });
    const deletion_step = b.step(
        "check-boundary-machine-deletion",
        "Prove removed Boundary v0 execution surfaces cannot reappear.",
    );
    deletion_step.dependOn(&deletion_command.step);

    const performance_command = b.addSystemCommand(&.{"sh"});
    performance_command.addFileArg(
        b.path("conformance/rnf-v1/check_performance.sh"),
    );
    performance_command.addFileArg(performance_tests.getEmittedBin());
    performance_command.addFileArg(wasm_executable.getEmittedBin());
    const performance_step = b.step(
        "check-boundary-machine-performance",
        "Compare RNF performance with the immutable Boundary v0.7.0 release.",
    );
    performance_step.dependOn(no_interpreter_step);
    performance_step.dependOn(deletion_step);
    performance_step.dependOn(&performance_command.step);

    const performance_falsifier_command = b.addSystemCommand(&.{"sh"});
    performance_falsifier_command.addFileArg(
        b.path("conformance/rnf-v1/check_performance.sh"),
    );
    performance_falsifier_command.addArg("--self-test");
    const performance_falsifier_step = b.step(
        "check-boundary-machine-performance-falsifiers",
        "Check that every RNF performance limit rejects its first regression.",
    );
    performance_falsifier_step.dependOn(&performance_falsifier_command.step);

    const compile_fail_step = b.step(
        "compile-fail",
        "Check fail-closed Boundary compiler admission.",
    );
    compile_fail_step.dependOn(deletion_step);
    inline for (.{
        .{
            "test/compile_fail/portable_usize.zig",
            "Boundary Machine integers must be explicit i8/i16/i32/i64 or u8/u16/u32/u64",
        },
        .{
            "test/compile_fail/portable_non_exhaustive_enum.zig",
            "Boundary Machine enums must be exhaustive",
        },
        .{
            "test/compile_fail/effect_resume_type_mismatch.zig",
            "effect resume type does not match its site",
        },
        .{
            "test/compile_fail/effect_handler_type_mismatch.zig",
            "effect handler function input must match source Payload",
        },
        .{
            "test/compile_fail/effect_morphism_type_mismatch.zig",
            "effect morphisms must preserve Payload and Resume types",
        },
        .{
            "test/compile_fail/effect_site_ordinal_mismatch.zig",
            "effect site ids must be dense from zero",
        },
        .{
            "test/compile_fail/generated_reducer_limit.zig",
            "Boundary compiler blocked program: GeneratedReducerLimitExceeded",
        },
        .{
            "test/compile_fail/missing_arithmetic_failure.zig",
            "Body.Failure must declare arithmetic_overflow",
        },
        .{
            "test/compile_fail/oversized_machine_state.zig",
            "Boundary Machine maximum_state_bytes must fit canonical u32 and its header",
        },
    }) |case| {
        addExpectedCompileFailure(
            b,
            compile_fail_step,
            host_core,
            case[0],
            case[1],
        );
    }

    inline for (.{
        program_operations,
        integer_boolean_operations,
        algebraic_collection_operations,
        research_digest,
        program_compile,
        program_dynamic_fuel,
        program_residual_effects,
        program_effect_morphism,
        program_effect_handler,
        program_dead_control,
        constructor_invariants,
        recursion,
        after,
        machine_yield,
        agent_loop,
    }) |integration_module| {
        addTestArtifact(b, test_step, integration_module);
    }
    test_step.dependOn(compile_fail_step);
    test_step.dependOn(parity_step);

    const format_command = b.addSystemCommand(&.{
        "zig",
        "fmt",
        "--check",
        "build.zig",
        "src",
        "test",
        "examples",
    });
    const lint_step = b.step("lint", "Check Boundary Zig formatting.");
    lint_step.dependOn(&format_command.step);

    const check_step = b.step("check", "Run the full Boundary Machine proof.");
    inline for (.{
        test_step,
        rnf_step,
        control_step,
        values_step,
        research_step,
        machine_step,
        state_step,
        malformed_step,
        recursion_step,
        after_step,
        agent_step,
        parity_step,
        no_interpreter_step,
        deletion_step,
        compile_fail_step,
        examples_step,
        lint_step,
        performance_falsifier_step,
    }) |dependency| {
        check_step.dependOn(dependency);
    }
}
