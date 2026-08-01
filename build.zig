// zlinter-disable require_doc_comment
const std = @import("std");
const zlinter = @import("zlinter");

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

const CoreModuleId = enum {
    agent_profile,
    compiler,
    control_ir,
    driver,
    effect_v2,
    machine,
    portable_value,
    program_v2,
    rnf,
};

const CoreModuleRole = enum {
    agent_profile,
    compiler,
    control_ir,
    driver,
    effect_schema,
    reducer,
    portable_value,
    program_frontend,
    resumption_normal_form,
};

fn coreModuleRole(module: CoreModuleId) CoreModuleRole {
    return switch (module) {
        .agent_profile => .agent_profile,
        .compiler => .compiler,
        .control_ir => .control_ir,
        .driver => .driver,
        .effect_v2 => .effect_schema,
        .machine => .reducer,
        .portable_value => .portable_value,
        .program_v2 => .program_frontend,
        .rnf => .resumption_normal_form,
    };
}

const core_module_reducer_count: usize = count: {
    var result: usize = 0;
    for (std.meta.fields(CoreModuleId)) |field| {
        const module: CoreModuleId = @enumFromInt(field.value);
        if (coreModuleRole(module) == .reducer) result += 1;
    }
    break :count result;
};

const core_module_reducer_owner: CoreModuleId = owner: {
    var result: ?CoreModuleId = null;
    for (std.meta.fields(CoreModuleId)) |field| {
        const module: CoreModuleId = @enumFromInt(field.value);
        if (coreModuleRole(module) == .reducer) result = module;
    }
    break :owner result orelse @compileError(
        "Boundary core-module topology has no reducer owner",
    );
};

comptime {
    @setEvalBranchQuota(10_000);
    const module_fields = std.meta.fields(CoreModules);
    const module_ids = std.meta.fields(CoreModuleId);
    if (module_fields.len != module_ids.len) {
        @compileError("Boundary core-module topology is not total");
    }
    for (module_fields) |field| {
        if (std.meta.stringToEnum(CoreModuleId, field.name) == null) {
            @compileError(
                "Boundary core module lacks a semantic role: " ++ field.name,
            );
        }
    }
    if (core_module_reducer_count != 1 or
        core_module_reducer_owner != .machine)
    {
        @compileError(
            "Boundary core-module topology must assign exactly one reducer to machine",
        );
    }
}

const TestArgs = struct {
    filters: []const []const u8,
    passthrough: []const []const u8,
};

fn parseTestArgs(b: *std.Build) TestArgs {
    const args = b.args orelse return .{
        .filters = &.{},
        .passthrough = &.{},
    };

    var filters: std.ArrayList([]const u8) = .empty;
    var passthrough: std.ArrayList([]const u8) = .empty;

    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--test-filter")) {
            index += 1;
            if (index >= args.len or args[index].len == 0) {
                std.process.fatal(
                    "Expected a non-empty pattern after '--test-filter'.",
                    .{},
                );
            }
            filters.append(b.allocator, args[index]) catch |err|
                std.process.fatal(
                    "unable to store test filter: {s}",
                    .{@errorName(err)},
                );
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--test-filter=")) {
            const pattern = arg["--test-filter=".len..];
            if (pattern.len == 0) {
                std.process.fatal(
                    "Expected '--test-filter=' to include a non-empty pattern.",
                    .{},
                );
            }
            filters.append(b.allocator, pattern) catch |err|
                std.process.fatal(
                    "unable to store test filter: {s}",
                    .{@errorName(err)},
                );
            continue;
        }
        if (std.mem.eql(u8, arg, "--seed")) {
            index += 1;
            if (index >= args.len or args[index].len == 0) {
                std.process.fatal(
                    "Expected an unsigned 32-bit integer after '--seed'.",
                    .{},
                );
            }
            _ = std.fmt.parseUnsigned(u32, args[index], 0) catch
                std.process.fatal(
                    "Expected '--seed' to contain an unsigned 32-bit integer; got '{s}'.",
                    .{args[index]},
                );
            passthrough.append(
                b.allocator,
                b.fmt("--seed={s}", .{args[index]}),
            ) catch |err| std.process.fatal(
                "unable to store test runner seed: {s}",
                .{@errorName(err)},
            );
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--seed=")) {
            const seed = arg["--seed=".len..];
            if (seed.len == 0) {
                std.process.fatal(
                    "Expected '--seed=' to include an unsigned 32-bit integer.",
                    .{},
                );
            }
            _ = std.fmt.parseUnsigned(u32, seed, 0) catch
                std.process.fatal(
                    "Expected '--seed' to contain an unsigned 32-bit integer; got '{s}'.",
                    .{seed},
                );
            passthrough.append(b.allocator, arg) catch |err|
                std.process.fatal(
                    "unable to store test runner seed: {s}",
                    .{@errorName(err)},
                );
            continue;
        }
        if (std.mem.eql(u8, arg, "--cache-dir")) {
            index += 1;
            if (index >= args.len or args[index].len == 0) {
                std.process.fatal(
                    "Expected a path after '--cache-dir'.",
                    .{},
                );
            }
            passthrough.append(
                b.allocator,
                b.fmt("--cache-dir={s}", .{args[index]}),
            ) catch |err| std.process.fatal(
                "unable to store test runner cache directory: {s}",
                .{@errorName(err)},
            );
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--cache-dir=")) {
            if (arg["--cache-dir=".len..].len == 0) {
                std.process.fatal(
                    "Expected '--cache-dir=' to include a path.",
                    .{},
                );
            }
            passthrough.append(b.allocator, arg) catch |err|
                std.process.fatal(
                    "unable to store test runner cache directory: {s}",
                    .{@errorName(err)},
                );
            continue;
        }
        if (std.mem.eql(u8, arg, "--max-warnings")) {
            index += 1;
            if (index >= args.len or args[index].len == 0) {
                std.process.fatal(
                    "Expected a non-empty limit after '--max-warnings'.",
                    .{},
                );
            }
            _ = std.fmt.parseUnsigned(usize, args[index], 10) catch
                std.process.fatal(
                    "Expected '--max-warnings' to contain an unsigned integer; got '{s}'.",
                    .{args[index]},
                );
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--max-warnings=")) {
            const limit = arg["--max-warnings=".len..];
            if (limit.len == 0) {
                std.process.fatal(
                    "Expected '--max-warnings=' to include a non-empty limit.",
                    .{},
                );
            }
            _ = std.fmt.parseUnsigned(usize, limit, 10) catch
                std.process.fatal(
                    "Expected '--max-warnings' to contain an unsigned integer; got '{s}'.",
                    .{limit},
                );
            continue;
        }
        passthrough.append(b.allocator, arg) catch |err|
            std.process.fatal(
                "unable to store test runner argument: {s}",
                .{@errorName(err)},
            );
    }

    return .{
        .filters = filters.toOwnedSlice(b.allocator) catch |err|
            std.process.fatal(
                "unable to finalize test filters: {s}",
                .{@errorName(err)},
            ),
        .passthrough = passthrough.toOwnedSlice(b.allocator) catch |err|
            std.process.fatal(
                "unable to finalize test runner arguments: {s}",
                .{@errorName(err)},
            ),
    };
}

fn addZigPathCoverageGuard(b: *std.Build, lint_step: *std.Build.Step) void {
    const guard = b.addSystemCommand(&.{
        "sh",
        "-c",
        \\set -eu
        \\tmp="${TMPDIR:-/tmp}/boundary-zig-paths-$$"
        \\trap 'rm -f "$tmp.actual" "$tmp.expected"' EXIT
        \\find src examples test -type f -name '*.zig' | sort > "$tmp.actual"
        \\grep -E '^(src|examples|test)/.*\.zig$' repo_zig_paths.txt | sort > "$tmp.expected"
        \\diff -u "$tmp.expected" "$tmp.actual"
    });
    lint_step.dependOn(&guard.step);
}

fn addTestArtifactWithArgs(
    b: *std.Build,
    step: *std.Build.Step,
    root_module: *std.Build.Module,
    test_args: TestArgs,
) void {
    const tests = b.addTest(.{
        .root_module = root_module,
        .filters = test_args.filters,
    });
    const run = b.addRunArtifact(tests);
    if (test_args.passthrough.len != 0) {
        run.addArgs(test_args.passthrough);
    }
    step.dependOn(&run.step);
}

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
    module.addImport("driver", core.driver);
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
    const test_args = parseTestArgs(b);
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
    addTestArtifactWithArgs(b, test_step, boundary, test_args);
    addTestArtifactWithArgs(b, test_step, core.agent_profile, test_args);
    addTestArtifactWithArgs(b, test_step, core.control_ir, test_args);
    addTestArtifactWithArgs(b, test_step, core.effect_v2, test_args);
    addTestArtifactWithArgs(b, test_step, core.machine, test_args);
    addTestArtifactWithArgs(b, test_step, core.portable_value, test_args);
    addTestArtifactWithArgs(b, test_step, core.rnf, test_args);

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
        true,
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
    program_dead_control.addImport("compiler", host_core.compiler);
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
    constructor_invariants.addImport(
        "portable_value",
        host_core.portable_value,
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
    addTestArtifact(b, control_step, research_digest);

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
    addTestArtifact(b, machine_step, constructor_invariants);
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
        true,
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
    const performance_wasm_optimize: std.builtin.OptimizeMode =
        .ReleaseSmall;
    const performance_wasm_core = addCoreModules(
        b,
        wasm_target,
        performance_wasm_optimize,
    );
    const performance_wasm_module = programTestModule(
        b,
        performance_wasm_core,
        "test/machine_performance.zig",
        wasm_target,
        performance_wasm_optimize,
        false,
        true,
    );
    const performance_wasm_executable = b.addExecutable(.{
        .name = "boundary-machine-performance-one-effect",
        .root_module = performance_wasm_module,
    });
    performance_wasm_executable.entry = .disabled;
    performance_wasm_executable.rdynamic = true;

    const wasm_core = addCoreModules(b, wasm_target, .ReleaseSmall);
    const parity_wasm = programTestModule(
        b,
        wasm_core,
        "test/machine_native_wasm.zig",
        wasm_target,
        .ReleaseSmall,
        false,
        true,
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
        \\  bench/abortive_effect_decompose_bench.zig \
        \\  bench/algebraic_builder_decompose_bench.zig \
        \\  bench/direct_first_suspend_bench.zig \
        \\  bench/effect_family_matrix_bench.zig \
        \\  bench/no_capture_bench.zig \
        \\  bench/resource_effect_decompose_bench.zig \
        \\  bench/state_effect_bench.zig \
        \\  bench/writer_effect_decompose_bench.zig \
        \\  bench/zprof_hotspots.zig \
        \\  test/program_api_test.zig \
        \\  test/static_machine_test.zig \
        \\  test/static_machine_wasm32_compile.zig \
        \\  conformance/static-machine-v1
        \\do
        \\  test ! -e "$path"
        \\done
        \\! rg -n 'pub const (Runtime|staticMachine|StaticMachineOptions)|Program\.Session|Loaded(Session|Module)|Certified Boundary Module' src/root.zig src
        \\package_root=$(pwd -P)
        \\git_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
        \\if test -n "$git_root" && test "$(cd "$git_root" && pwd -P)" = "$package_root"; then
        \\  source_paths=$(
        \\    {
        \\      git ls-files '*.zig'
        \\      git ls-files --others --exclude-standard '*.zig'
        \\    } |
        \\      while IFS= read -r source; do
        \\        test -f "$source" && printf '%s\n' "$source"
        \\      done |
        \\      sort -u
        \\  )
        \\  test "$source_paths" = "$(cat repo_zig_paths.txt)"
        \\else
        \\  source_paths=$(cat repo_zig_paths.txt)
        \\fi
        \\legacy_source_matches=$(
        \\  for source in $source_paths; do
        \\    test "$source" = build.zig && continue
        \\    rg --with-filename -n \
        \\      '@import\("(loaded_execution|lowered_machine|interpreter|internal_program_plan)"\)|boundary\.(Runtime|Prompt|frontend|algebraic)|boundary\.effect\.(exception|optional|reader|resource|state|writer)|Program\.Session|Loaded(Session|Module)' \
        \\      "$source" || test "$?" -eq 1
        \\  done
        \\)
        \\test -z "$legacy_source_matches"
    });
    deletion_command.setCwd(b.path("."));
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
    performance_command.addFileArg(
        performance_wasm_executable.getEmittedBin(),
    );
    performance_command.addArg(b.graph.zig_exe);
    performance_command.addArg(@tagName(performance_wasm_optimize));
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

    const single_reducer_proof = b.addWriteFiles();
    _ = single_reducer_proof.add(
        "boundary-core-module-topology.txt",
        b.fmt(
            "core_module_count={d}\nreducer_count={d}\nreducer_owner={s}\n",
            .{
                std.meta.fields(CoreModules).len,
                core_module_reducer_count,
                @tagName(core_module_reducer_owner),
            },
        ),
    );
    const single_reducer_step = b.step(
        "check-boundary-machine-single-reducer",
        "Prove the total Boundary core-module graph has exactly one reducer owner.",
    );
    single_reducer_step.dependOn(&single_reducer_proof.step);

    const receipt_output_command =
        "printf '%s\\n' " ++
        "'boundary_machine_abi=2' " ++
        "'boundary_rnf=true' " ++
        "'single_boundary_reducer=true' " ++
        "'program_session_public=false' " ++
        "'boundary_runtime_public=false' " ++
        "'static_machine_public=false' " ++
        "'loaded_execution_present=false' " ++
        "'runtime_program_plan_decode=false' " ++
        "'generic_instruction_dispatch=false' " ++
        "'canonical_state_format=ABL_RNF2' " ++
        "'fixed_width_u32=true' " ++
        "'bounded_vector_of_products=true' " ++
        "'bounded_text_construction=true' " ++
        "'product_construction=true' " ++
        "'correlated_predicate_witness=true' " ++
        "'bounded_recursive_helper=true' " ++
        "'after_sites_exposed_to_world=0'";
    const receipt_command = b.addSystemCommand(&.{
        "sh",
        "-c",
        receipt_output_command,
    });
    inline for (.{
        control_step,
        values_step,
        state_step,
        recursion_step,
        after_step,
        single_reducer_step,
        no_interpreter_step,
        deletion_step,
    }) |dependency| {
        receipt_command.step.dependOn(dependency);
    }
    const receipt_step = b.step(
        "check-boundary-machine-receipt",
        "Emit the Boundary-owned completion receipt fields after their proofs.",
    );
    receipt_step.dependOn(&receipt_command.step);

    const receipt_falsifier_command = b.addSystemCommand(&.{
        "sh",
        "-c",
        "test ! -e conformance/rnf-v1/check_receipt.sh",
    });
    const receipt_falsifier_step = b.step(
        "check-boundary-machine-receipt-falsifiers",
        "Prove that no directly invokable unbound completion receipt remains.",
    );
    receipt_falsifier_step.dependOn(&receipt_falsifier_command.step);

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
            "test/compile_fail/portable_c_integer.zig",
            "Boundary Machine integers must be explicit i8/i16/i32/i64 or u8/u16/u32/u64",
        },
        .{
            "test/compile_fail/portable_non_exhaustive_enum.zig",
            "Boundary Machine enums must be exhaustive",
        },
        .{
            "test/compile_fail/vector_uninhabited_element.zig",
            "Boundary Vector element type must have a canonical default value",
        },
        .{
            "test/compile_fail/portable_sentinel_array.zig",
            "Boundary Machine portable arrays cannot have sentinels",
        },
        .{
            "test/compile_fail/forged_portable_container_marker.zig",
            "unsupported Boundary Machine portable value: *u8",
        },
        .{
            "test/compile_fail/generated_container_product_access.zig",
            "generated bounded values are semantic atoms, not generic products",
        },
        .{
            "test/compile_fail/dead_control_malformed_constant.zig",
            "constant instruction value is not canonical",
        },
        .{
            "test/compile_fail/effect_resume_type_mismatch.zig",
            "effect resume type does not match its site",
        },
        .{
            "test/compile_fail/driver_response_type_mismatch.zig",
            "Boundary Machine response type must match the selected effect site Resume type",
        },
        .{
            "test/compile_fail/driver_semantic_site_mismatch.zig",
            "Boundary Driver handler does not admit effect site semantic identity",
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
            "test/compile_fail/dead_control_schema_reference.zig",
            "Control IR value type schema index is out of bounds",
        },
        .{
            "test/compile_fail/missing_arithmetic_failure.zig",
            "Body.Failure must declare arithmetic_overflow",
        },
        .{
            "test/compile_fail/oversized_machine_state.zig",
            "Boundary Machine maximum_state_bytes must fit canonical u32 and one canonical frame",
        },
        .{
            "test/compile_fail/undersized_machine_state.zig",
            "Boundary Machine maximum_state_bytes must fit canonical u32 and one canonical frame",
        },
        .{
            "test/compile_fail/machine_state_below_entry_environment.zig",
            "Boundary Machine maximum_state_bytes must admit the initial RNF environment",
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
        addTestArtifactWithArgs(b, test_step, integration_module, test_args);
    }
    test_step.dependOn(compile_fail_step);
    test_step.dependOn(parity_step);

    const format_command = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "fmt",
        "--check",
        "build.zig",
        "src",
        "test",
        "examples",
    });
    const lint_step = b.step("lint", "Lint Boundary Zig source.");
    lint_step.dependOn(&format_command.step);
    addZigPathCoverageGuard(b, lint_step);
    var lint_builder = zlinter.builder(b, .{});
    lint_builder.addPaths(.{
        .include = &.{
            b.path("build.zig"),
            b.path("src"),
            b.path("examples"),
            b.path("test"),
            b.path("conformance"),
        },
        .exclude = &.{},
    });
    inline for ([_]zlinter.BuiltinLintRule{
        .file_naming,
        .import_ordering,
        .no_comment_out_code,
        .no_deprecated,
        .no_hidden_allocations,
        .no_literal_only_bool_expression,
        .no_panic,
        .no_todo,
        .require_errdefer_dealloc,
        .require_exhaustive_enum_switch,
    }) |rule| {
        lint_builder.addRule(.{ .builtin = rule }, .{});
    }
    const saved_global_cache_path = b.graph.global_cache_root.path;
    if (saved_global_cache_path) |path| {
        if (!std.Io.Dir.path.isAbsolute(path)) {
            b.graph.global_cache_root.path = b.pathFromRoot(path);
        }
    }
    defer b.graph.global_cache_root.path = saved_global_cache_path;
    lint_step.dependOn(lint_builder.build());

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
        performance_step,
        performance_falsifier_step,
        receipt_step,
        receipt_falsifier_step,
    }) |dependency| {
        check_step.dependOn(dependency);
    }
}
