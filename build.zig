// zlinter-disable require_doc_comment
const std = @import("std");
const zlinter = @import("zlinter");

const CoreModules = struct {
    agent_profile: *std.Build.Module,
    compiler: *std.Build.Module,
    control_ir: *std.Build.Module,
    driver: *std.Build.Module,
    dynamic_value_v1: *std.Build.Module,
    effect_v2: *std.Build.Module,
    image_v1: *std.Build.Module,
    image_emit_v1: *std.Build.Module,
    kernel_v1: *std.Build.Module,
    kernel_machine_v1: *std.Build.Module,
    kernel_wasm_v1: *std.Build.Module,
    machine: *std.Build.Module,
    machine_v2_metering_v1: *std.Build.Module,
    machine_v2_profile_v1: *std.Build.Module,
    portable_value: *std.Build.Module,
    process_advance_v1: *std.Build.Module,
    process_capsule_v1: *std.Build.Module,
    process_effect_v1: *std.Build.Module,
    process_kernel_wasm_v1: *std.Build.Module,
    process_state_v1: *std.Build.Module,
    process_v1: *std.Build.Module,
    program_semantics_v1: *std.Build.Module,
    program_v2: *std.Build.Module,
    reducer_clause_v1: *std.Build.Module,
    reified_program_v1: *std.Build.Module,
    rnf: *std.Build.Module,
};

const CoreModuleId = enum {
    agent_profile,
    compiler,
    control_ir,
    driver,
    dynamic_value_v1,
    effect_v2,
    image_v1,
    image_emit_v1,
    kernel_v1,
    kernel_machine_v1,
    kernel_wasm_v1,
    machine,
    machine_v2_metering_v1,
    machine_v2_profile_v1,
    portable_value,
    process_advance_v1,
    process_capsule_v1,
    process_effect_v1,
    process_kernel_wasm_v1,
    process_state_v1,
    process_v1,
    program_semantics_v1,
    program_v2,
    reducer_clause_v1,
    reified_program_v1,
    rnf,
};

const CoreModuleRole = enum {
    support,
    direct_runtime_semantics,
    image_runtime_semantics,
    shared_runtime_semantics,
};

fn coreModulePath(module: CoreModuleId) []const u8 {
    return switch (module) {
        .agent_profile => "src/agent_profile.zig",
        .compiler => "src/compiler.zig",
        .control_ir => "src/control_ir.zig",
        .driver => "src/driver.zig",
        .dynamic_value_v1 => "src/dynamic_value_v1.zig",
        .effect_v2 => "src/effect_v2.zig",
        .image_v1 => "src/image_v1.zig",
        .image_emit_v1 => "src/image_emit_v1.zig",
        .kernel_v1 => "src/kernel_v1.zig",
        .kernel_machine_v1 => "src/kernel_machine_v1.zig",
        .kernel_wasm_v1 => "src/kernel_wasm_v1.zig",
        .machine => "src/machine.zig",
        .machine_v2_metering_v1 => "src/machine_v2_metering_v1.zig",
        .machine_v2_profile_v1 => "src/machine_v2_profile_v1.zig",
        .portable_value => "src/portable_value.zig",
        .process_advance_v1 => "src/process_advance_v1.zig",
        .process_capsule_v1 => "src/process_capsule_v1.zig",
        .process_effect_v1 => "src/process_effect_v1.zig",
        .process_kernel_wasm_v1 => "src/process_kernel_wasm_v1.zig",
        .process_state_v1 => "src/process_state_v1.zig",
        .process_v1 => "src/process_v1.zig",
        .program_semantics_v1 => "src/program_semantics_v1.zig",
        .program_v2 => "src/program_v2.zig",
        .reducer_clause_v1 => "src/reducer_clause_v1.zig",
        .reified_program_v1 => "src/reified_program_v1.zig",
        .rnf => "src/rnf.zig",
    };
}

fn coreModuleRole(module: CoreModuleId) CoreModuleRole {
    return switch (module) {
        .compiler, .machine, .machine_v2_metering_v1 => .direct_runtime_semantics,
        .dynamic_value_v1,
        .image_v1,
        .reducer_clause_v1,
        .kernel_v1,
        .kernel_machine_v1,
        .kernel_wasm_v1,
        .machine_v2_profile_v1,
        .process_advance_v1,
        .process_capsule_v1,
        .process_effect_v1,
        .process_kernel_wasm_v1,
        .process_state_v1,
        => .image_runtime_semantics,
        .program_semantics_v1 => .shared_runtime_semantics,
        .agent_profile,
        .control_ir,
        .driver,
        .effect_v2,
        .image_emit_v1,
        .portable_value,
        .process_v1,
        .program_v2,
        .reified_program_v1,
        .rnf,
        => .support,
    };
}

fn requireDirectDependency(
    owner: *std.Build.Step,
    dependency: *std.Build.Step,
) void {
    for (owner.dependencies.items) |candidate| {
        if (candidate == dependency) return;
    }
    std.process.fatal(
        "build step '{s}' must directly depend on '{s}'",
        .{ owner.name, dependency.name },
    );
}

comptime {
    @setEvalBranchQuota(50_000);
    const module_fields = std.meta.fields(CoreModules);
    const module_ids = std.meta.fields(CoreModuleId);
    if (module_fields.len != module_ids.len) {
        @compileError("Boundary core-module topology is not total");
    }
    for (module_fields) |field| {
        if (std.meta.stringToEnum(CoreModuleId, field.name) == null) {
            @compileError(
                "Boundary core module lacks a source identity: " ++ field.name,
            );
        }
    }
    for (module_ids, 0..) |field, index| {
        const module: CoreModuleId = @enumFromInt(field.value);
        for (module_ids[index + 1 ..]) |other_field| {
            const other: CoreModuleId = @enumFromInt(other_field.value);
            if (std.mem.eql(
                u8,
                coreModulePath(module),
                coreModulePath(other),
            )) {
                @compileError("Boundary core-module topology has duplicate source paths");
            }
        }
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

fn addZigPathCoverageGuard(b: *std.Build) *std.Build.Step {
    const guard = b.addSystemCommand(&.{
        "sh",
        "-c",
        \\set -eu
        \\tmp="${TMPDIR:-/tmp}/boundary-zig-paths-$$"
        \\trap 'rm -f "$tmp.actual" "$tmp.expected"' EXIT
        \\{ printf '%s\n' build.zig; find src examples test -type f -name '*.zig'; } | sort > "$tmp.actual"
        \\sort repo_zig_paths.txt > "$tmp.expected"
        \\diff -u "$tmp.expected" "$tmp.actual"
    });
    guard.setCwd(b.path("."));
    return &guard.step;
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
    module.addImport("image_emit_v1", core.image_emit_v1);
    module.addImport("portable_value", core.portable_value);
    module.addImport("program_v2", core.program_v2);
    const compilation = b.addTest(.{ .root_module = module });
    compilation.expect_errors = .{ .contains = expected_error };
    step.dependOn(&compilation.step);
}

fn addReificationReceiptSources(
    b: *std.Build,
    command: *std.Build.Step.Run,
) void {
    var zig_paths = std.mem.splitScalar(
        u8,
        @embedFile("repo_zig_paths.txt"),
        '\n',
    );
    while (zig_paths.next()) |source_path| {
        if (source_path.len != 0) command.addFileArg(b.path(source_path));
    }
    inline for (.{
        "repo_zig_paths.txt",
        "conformance/reification-v1/baseline.lock.json",
        "conformance/reification-v1/baseline/vectors.json",
        "conformance/reification-v1/check_baseline.sh",
        "conformance/reification-v1/v1.5.0-baseline-fixture.patch",
        "conformance/rnf-v1/check_performance.sh",
        "conformance/rnf-v1/measure_wasm.mjs",
        "conformance/rnf-v1/v0.7.0-performance.patch",
        "scripts/write_reification_proof.mjs",
        "scripts/write_reification_receipt.mjs",
        "test/reification_receipt_v1.mjs",
        "test/run_kernel_wasm.mjs",
        "test/run_machine_wasm.mjs",
    }) |source_path| command.addFileArg(b.path(source_path));
}

const PureProgramModules = struct {
    control_ir: *std.Build.Module,
    portable_value: *std.Build.Module,
    rnf: *std.Build.Module,
    dynamic_value_v1: *std.Build.Module,
    program_semantics_v1: *std.Build.Module,
    image_v1: *std.Build.Module,
    reducer_clause_v1: *std.Build.Module,
};

fn addPureProgramModules(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) PureProgramModules {
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
    const rnf = b.createModule(.{
        .root_source_file = b.path("src/rnf.zig"),
        .target = target,
        .optimize = optimize,
    });
    rnf.addImport("control_ir", control_ir);
    const dynamic_value_v1 = b.createModule(.{
        .root_source_file = b.path("src/dynamic_value_v1.zig"),
        .target = target,
        .optimize = optimize,
    });
    const program_semantics_v1 = b.createModule(.{
        .root_source_file = b.path("src/program_semantics_v1.zig"),
        .target = target,
        .optimize = optimize,
    });
    program_semantics_v1.addImport("control_ir", control_ir);
    program_semantics_v1.addImport("portable_value", portable_value);
    program_semantics_v1.addImport("rnf", rnf);
    const image_v1 = b.createModule(.{
        .root_source_file = b.path("src/image_v1.zig"),
        .target = target,
        .optimize = optimize,
    });
    image_v1.addImport("dynamic_value_v1", dynamic_value_v1);
    image_v1.addImport("program_semantics_v1", program_semantics_v1);
    const reducer_clause_v1 = b.createModule(.{
        .root_source_file = b.path("src/reducer_clause_v1.zig"),
        .target = target,
        .optimize = optimize,
    });
    reducer_clause_v1.addImport("dynamic_value_v1", dynamic_value_v1);
    reducer_clause_v1.addImport("image_v1", image_v1);
    reducer_clause_v1.addImport("program_semantics_v1", program_semantics_v1);
    return .{
        .control_ir = control_ir,
        .portable_value = portable_value,
        .rnf = rnf,
        .dynamic_value_v1 = dynamic_value_v1,
        .program_semantics_v1 = program_semantics_v1,
        .image_v1 = image_v1,
        .reducer_clause_v1 = reducer_clause_v1,
    };
}

fn addCoreModules(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) CoreModules {
    const pure = addPureProgramModules(b, target, optimize);
    const control_ir = pure.control_ir;
    const portable_value = pure.portable_value;
    const rnf = pure.rnf;
    const dynamic_value_v1 = pure.dynamic_value_v1;
    const program_semantics_v1 = pure.program_semantics_v1;
    const image_v1 = pure.image_v1;
    const reducer_clause_v1 = pure.reducer_clause_v1;
    const process_state_v1 = b.createModule(.{
        .root_source_file = b.path(coreModulePath(.process_state_v1)),
        .target = target,
        .optimize = optimize,
    });
    const process_capsule_v1 = b.createModule(.{
        .root_source_file = b.path(coreModulePath(.process_capsule_v1)),
        .target = target,
        .optimize = optimize,
    });
    process_capsule_v1.addImport("dynamic_value_v1", dynamic_value_v1);
    process_capsule_v1.addImport("image_v1", image_v1);
    process_capsule_v1.addImport("process_state_v1", process_state_v1);
    const process_effect_v1 = b.createModule(.{
        .root_source_file = b.path(coreModulePath(.process_effect_v1)),
        .target = target,
        .optimize = optimize,
    });
    process_effect_v1.addImport("image_v1", image_v1);
    process_effect_v1.addImport("process_state_v1", process_state_v1);
    const process_advance_v1 = b.createModule(.{
        .root_source_file = b.path(coreModulePath(.process_advance_v1)),
        .target = target,
        .optimize = optimize,
    });
    process_advance_v1.addImport("dynamic_value_v1", dynamic_value_v1);
    process_advance_v1.addImport("image_v1", image_v1);
    process_advance_v1.addImport("process_effect_v1", process_effect_v1);
    process_advance_v1.addImport("process_state_v1", process_state_v1);
    process_advance_v1.addImport("reducer_clause_v1", reducer_clause_v1);
    process_capsule_v1.addImport("process_advance_v1", process_advance_v1);
    const process_v1 = b.createModule(.{
        .root_source_file = b.path(coreModulePath(.process_v1)),
        .target = target,
        .optimize = optimize,
    });
    process_v1.addImport("process_capsule_v1", process_capsule_v1);
    process_v1.addImport("process_advance_v1", process_advance_v1);
    process_v1.addImport("process_effect_v1", process_effect_v1);
    process_v1.addImport("process_state_v1", process_state_v1);
    const machine = b.createModule(.{
        .root_source_file = b.path(coreModulePath(.machine)),
        .target = target,
        .optimize = optimize,
    });
    machine.addImport("portable_value", portable_value);
    const machine_v2_metering_v1 = b.createModule(.{
        .root_source_file = b.path(coreModulePath(.machine_v2_metering_v1)),
        .target = target,
        .optimize = optimize,
    });
    machine_v2_metering_v1.addImport("control_ir", control_ir);
    machine_v2_metering_v1.addImport("dynamic_value_v1", dynamic_value_v1);
    machine_v2_metering_v1.addImport("image_v1", image_v1);
    machine_v2_metering_v1.addImport(
        "program_semantics_v1",
        program_semantics_v1,
    );
    machine_v2_metering_v1.addImport("reducer_clause_v1", reducer_clause_v1);
    const machine_v2_profile_v1 = b.createModule(.{
        .root_source_file = b.path(coreModulePath(.machine_v2_profile_v1)),
        .target = target,
        .optimize = optimize,
    });
    const kernel_v1 = b.createModule(.{
        .root_source_file = b.path(coreModulePath(.kernel_v1)),
        .target = target,
        .optimize = optimize,
    });
    kernel_v1.addImport("dynamic_value_v1", dynamic_value_v1);
    kernel_v1.addImport("image_v1", image_v1);
    kernel_v1.addImport("machine_v2_metering_v1", machine_v2_metering_v1);
    kernel_v1.addImport("machine_v2_profile_v1", machine_v2_profile_v1);
    kernel_v1.addImport("reducer_clause_v1", reducer_clause_v1);
    const kernel_machine_v1 = b.createModule(.{
        .root_source_file = b.path(coreModulePath(.kernel_machine_v1)),
        .target = target,
        .optimize = optimize,
    });
    kernel_machine_v1.addImport("image_v1", image_v1);
    kernel_machine_v1.addImport("kernel_v1", kernel_v1);
    kernel_machine_v1.addImport("machine", machine);
    kernel_machine_v1.addImport("portable_value", portable_value);
    const kernel_wasm_v1 = b.createModule(.{
        .root_source_file = b.path(coreModulePath(.kernel_wasm_v1)),
        .target = target,
        .optimize = optimize,
    });
    kernel_wasm_v1.addImport("image_v1", image_v1);
    kernel_wasm_v1.addImport("kernel_v1", kernel_v1);
    const process_kernel_wasm_v1 = b.createModule(.{
        .root_source_file = b.path(coreModulePath(.process_kernel_wasm_v1)),
        .target = target,
        .optimize = optimize,
    });
    const process_kernel_options = b.addOptions();
    process_kernel_options.addOption(usize, "input_capacity", 32 << 20);
    process_kernel_options.addOption(usize, "output_capacity", 16 << 20);
    process_kernel_options.addOption(usize, "state_capacity", 8 << 20);
    process_kernel_options.addOption(usize, "value_capacity", 4 << 20);
    process_kernel_options.addOption(usize, "request_capacity", 4 << 20);
    process_kernel_options.addOption(usize, "environment_capacity", 8 << 20);
    process_kernel_options.addOption(usize, "scratch_capacity", 64 << 20);
    process_kernel_options.addOption(usize, "error_capacity", 4 << 10);
    process_kernel_wasm_v1.addImport("image_v1", image_v1);
    process_kernel_wasm_v1.addImport(
        "process_advance_v1",
        process_advance_v1,
    );
    process_kernel_wasm_v1.addOptions(
        "process_kernel_options",
        process_kernel_options,
    );
    const image_emit_v1 = b.createModule(.{
        .root_source_file = b.path(coreModulePath(.image_emit_v1)),
        .target = target,
        .optimize = optimize,
    });
    image_emit_v1.addImport("dynamic_value_v1", dynamic_value_v1);
    image_emit_v1.addImport("image_v1", image_v1);
    image_emit_v1.addImport("portable_value", portable_value);
    const reified_program_v1 = b.createModule(.{
        .root_source_file = b.path(coreModulePath(.reified_program_v1)),
        .target = target,
        .optimize = optimize,
    });
    machine_v2_profile_v1.addImport("dynamic_value_v1", dynamic_value_v1);
    machine_v2_profile_v1.addImport("image_v1", image_v1);
    machine_v2_profile_v1.addImport(
        "machine_v2_metering_v1",
        machine_v2_metering_v1,
    );
    image_emit_v1.addImport("program_semantics_v1", program_semantics_v1);
    const compiler = b.createModule(.{
        .root_source_file = b.path(coreModulePath(.compiler)),
        .target = target,
        .optimize = optimize,
    });
    compiler.addImport("control_ir", control_ir);
    compiler.addImport("machine", machine);
    compiler.addImport("machine_v2_metering_v1", machine_v2_metering_v1);
    compiler.addImport("machine_v2_profile_v1", machine_v2_profile_v1);
    compiler.addImport("portable_value", portable_value);
    compiler.addImport("reified_program_v1", reified_program_v1);
    compiler.addImport("program_semantics_v1", program_semantics_v1);
    compiler.addImport("rnf", rnf);
    const program_v2 = b.createModule(.{
        .root_source_file = b.path(coreModulePath(.program_v2)),
        .target = target,
        .optimize = optimize,
    });
    program_v2.addImport("compiler", compiler);
    program_v2.addImport("image_emit_v1", image_emit_v1);
    program_v2.addImport("kernel_machine_v1", kernel_machine_v1);
    program_v2.addImport("machine", machine);
    program_v2.addImport("machine_v2_profile_v1", machine_v2_profile_v1);
    const driver = b.createModule(.{
        .root_source_file = b.path(coreModulePath(.driver)),
        .target = target,
        .optimize = optimize,
    });
    const effect_v2 = b.createModule(.{
        .root_source_file = b.path(coreModulePath(.effect_v2)),
        .target = target,
        .optimize = optimize,
    });
    const agent_profile = b.createModule(.{
        .root_source_file = b.path(coreModulePath(.agent_profile)),
        .target = target,
        .optimize = optimize,
    });
    agent_profile.addImport("program_v2", program_v2);

    return .{
        .agent_profile = agent_profile,
        .compiler = compiler,
        .control_ir = control_ir,
        .driver = driver,
        .dynamic_value_v1 = dynamic_value_v1,
        .effect_v2 = effect_v2,
        .image_v1 = image_v1,
        .image_emit_v1 = image_emit_v1,
        .kernel_v1 = kernel_v1,
        .kernel_machine_v1 = kernel_machine_v1,
        .kernel_wasm_v1 = kernel_wasm_v1,
        .machine = machine,
        .machine_v2_metering_v1 = machine_v2_metering_v1,
        .machine_v2_profile_v1 = machine_v2_profile_v1,
        .portable_value = portable_value,
        .process_advance_v1 = process_advance_v1,
        .process_capsule_v1 = process_capsule_v1,
        .process_effect_v1 = process_effect_v1,
        .process_kernel_wasm_v1 = process_kernel_wasm_v1,
        .process_state_v1 = process_state_v1,
        .process_v1 = process_v1,
        .program_semantics_v1 = program_semantics_v1,
        .program_v2 = program_v2,
        .reducer_clause_v1 = reducer_clause_v1,
        .reified_program_v1 = reified_program_v1,
        .rnf = rnf,
    };
}

fn wirePublicImports(module: *std.Build.Module, core: CoreModules) void {
    module.addImport("agent_profile", core.agent_profile);
    module.addImport("control_ir", core.control_ir);
    module.addImport("driver", core.driver);
    module.addImport("effect_v2", core.effect_v2);
    module.addImport("image_v1", core.image_v1);
    module.addImport("kernel_v1", core.kernel_v1);
    module.addImport("machine", core.machine);
    module.addImport("portable_value", core.portable_value);
    module.addImport("process_v1", core.process_v1);
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
    const host_boundary = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    wirePublicImports(host_boundary, host_core);

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
    const reification_operations_fixture = programTestModule(
        b,
        host_core,
        "test/program_operations.zig",
        b.graph.host,
        optimize,
        false,
        true,
    );
    reification_operations_fixture.addImport("image_v1", host_core.image_v1);
    reification_operations_fixture.addImport("kernel_v1", host_core.kernel_v1);
    reification_operations_fixture.addImport("machine", host_core.machine);
    const reification_handler_fixture = programTestModule(
        b,
        host_core,
        "test/program_effect_handler.zig",
        b.graph.host,
        optimize,
        false,
        false,
    );
    reification_handler_fixture.addImport("effect_v2", host_core.effect_v2);
    reification_handler_fixture.addImport("machine", host_core.machine);
    const reification_morphism_fixture = programTestModule(
        b,
        host_core,
        "test/program_effect_morphism.zig",
        b.graph.host,
        optimize,
        false,
        false,
    );
    reification_morphism_fixture.addImport("effect_v2", host_core.effect_v2);
    reification_morphism_fixture.addImport("machine", host_core.machine);
    const reification_recursion_fixture = programTestModule(
        b,
        host_core,
        "test/machine_recursion.zig",
        b.graph.host,
        optimize,
        false,
        false,
    );
    reification_recursion_fixture.addImport("image_v1", host_core.image_v1);
    reification_recursion_fixture.addImport("kernel_v1", host_core.kernel_v1);
    reification_recursion_fixture.addImport("machine", host_core.machine);
    const reification_baseline_module = b.createModule(.{
        .root_source_file = b.path("test/reification_baseline.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    reification_baseline_module.addImport("boundary", host_boundary);
    reification_baseline_module.addImport("compiler", host_core.compiler);
    reification_baseline_module.addImport(
        "operations_fixture",
        reification_operations_fixture,
    );
    reification_baseline_module.addImport(
        "handler_fixture",
        reification_handler_fixture,
    );
    reification_baseline_module.addImport(
        "morphism_fixture",
        reification_morphism_fixture,
    );
    reification_baseline_module.addImport(
        "recursion_fixture",
        reification_recursion_fixture,
    );
    const reification_baseline_executable = b.addExecutable(.{
        .name = "boundary-reification-baseline",
        .root_module = reification_baseline_module,
    });
    const reification_baseline_run = b.addRunArtifact(
        reification_baseline_executable,
    );
    const reification_baseline_emit_step = b.step(
        "emit-boundary-reification-baseline",
        "Emit the current Boundary reification baseline vectors.",
    );
    reification_baseline_emit_step.dependOn(&reification_baseline_run.step);
    const reification_baseline_check = b.addSystemCommand(&.{"sh"});
    reification_baseline_check.addFileArg(
        b.path("conformance/reification-v1/check_baseline.sh"),
    );
    reification_baseline_check.addFileArg(
        reification_baseline_executable.getEmittedBin(),
    );
    reification_baseline_check.addArg(b.graph.zig_exe);
    reification_baseline_check.addFileArg(
        b.path("conformance/reification-v1/baseline.lock.json"),
    );
    reification_baseline_check.addFileArg(
        b.path("conformance/reification-v1/baseline/vectors.json"),
    );
    reification_baseline_check.addFileArg(
        b.path("conformance/reification-v1/v1.5.0-baseline-fixture.patch"),
    );
    reification_baseline_check.addFileArg(
        b.path("test/reification_baseline.zig"),
    );
    reification_baseline_check.addFileArg(
        b.path("conformance/rnf-v1/check_performance.sh"),
    );
    reification_baseline_check.addFileArg(
        b.path("conformance/rnf-v1/v0.7.0-performance.patch"),
    );
    reification_baseline_check.setCwd(b.path("."));
    const reification_baseline_proof = reification_baseline_check.captureStdOut(.{
        .basename = "boundary-reification-baseline-proof.json",
    });
    const reification_baseline_step = b.step(
        "check-boundary-reification-baseline",
        "Verify the immutable Boundary v1.5.0 reification baseline.",
    );
    reification_baseline_step.dependOn(&reification_baseline_check.step);
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
    program_operations.addImport("image_v1", host_core.image_v1);
    program_operations.addImport("kernel_v1", host_core.kernel_v1);
    program_operations.addImport("machine", host_core.machine);
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
    algebraic_collection_operations.addImport("image_v1", host_core.image_v1);
    algebraic_collection_operations.addImport("kernel_v1", host_core.kernel_v1);
    algebraic_collection_operations.addImport("machine", host_core.machine);
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
    const reified_program_test = programTestModule(
        b,
        host_core,
        "test/reified_program_v1.zig",
        b.graph.host,
        optimize,
        false,
        false,
    );
    reified_program_test.addImport("compiler", host_core.compiler);
    reified_program_test.addImport("image_emit_v1", host_core.image_emit_v1);
    reified_program_test.addImport("image_v1", host_core.image_v1);
    reified_program_test.addImport("kernel_v1", host_core.kernel_v1);
    reified_program_test.addImport("machine", host_core.machine);
    reified_program_test.addImport(
        "machine_v2_profile_v1",
        host_core.machine_v2_profile_v1,
    );
    reified_program_test.addImport(
        "reducer_clause_v1",
        host_core.reducer_clause_v1,
    );
    const reification_receipt_witness_module = b.createModule(.{
        .root_source_file = b.path("test/reification_receipt_witness.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    reification_receipt_witness_module.addImport(
        "reified_program_fixture",
        reified_program_test,
    );
    const reification_receipt_witness_executable = b.addExecutable(.{
        .name = "boundary-reification-semantic-proof",
        .root_module = reification_receipt_witness_module,
    });
    const run_reification_receipt_witness = b.addRunArtifact(
        reification_receipt_witness_executable,
    );
    const reification_semantic_proof =
        run_reification_receipt_witness.captureStdOut(.{
            .basename = "boundary-reification-semantic-proof.json",
        });
    const reification_generated_test = programTestModule(
        b,
        host_core,
        "test/reification_generated_v1.zig",
        b.graph.host,
        optimize,
        false,
        false,
    );
    reification_generated_test.addImport("machine", host_core.machine);
    const reification_generated_proof_executable = b.addExecutable(.{
        .name = "boundary-reification-generated-proof",
        .root_module = reification_generated_test,
    });
    const run_reification_generated_proof = b.addRunArtifact(
        reification_generated_proof_executable,
    );
    const reification_generated_proof = run_reification_generated_proof.captureStdOut(.{
        .basename = "boundary-reification-generated-proof.json",
    });
    const reducer_semantics_test = b.createModule(.{
        .root_source_file = b.path("test/program_semantics_v1.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    reducer_semantics_test.addImport("control_ir", host_core.control_ir);
    reducer_semantics_test.addImport("rnf", host_core.rnf);
    reducer_semantics_test.addImport(
        "program_semantics_v1",
        host_core.program_semantics_v1,
    );
    const machine_v2_metering_test = b.createModule(.{
        .root_source_file = b.path("test/machine_v2_metering_v1.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    machine_v2_metering_test.addImport("control_ir", host_core.control_ir);
    machine_v2_metering_test.addImport(
        "machine_v2_metering_v1",
        host_core.machine_v2_metering_v1,
    );
    const image_test = b.createModule(.{
        .root_source_file = b.path("test/image_v1.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    image_test.addImport("image_v1", host_core.image_v1);
    const process_test = b.createModule(.{
        .root_source_file = b.path("test/process_v1.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    process_test.addImport("process_effect_v1", host_core.process_effect_v1);
    process_test.addImport("process_capsule_v1", host_core.process_capsule_v1);
    process_test.addImport("process_state_v1", host_core.process_state_v1);
    const process_advance_test = b.createModule(.{
        .root_source_file = b.path("test/process_advance_v1.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    process_advance_test.addImport("boundary", host_boundary);
    process_advance_test.addImport(
        "process_advance_v1",
        host_core.process_advance_v1,
    );
    process_advance_test.addImport(
        "process_state_v1",
        host_core.process_state_v1,
    );
    const process_recursion_fixture = programTestModule(
        b,
        host_core,
        "test/machine_recursion.zig",
        b.graph.host,
        optimize,
        false,
        false,
    );
    process_recursion_fixture.addImport("image_v1", host_core.image_v1);
    process_recursion_fixture.addImport("kernel_v1", host_core.kernel_v1);
    process_recursion_fixture.addImport("machine", host_core.machine);
    process_advance_test.addImport(
        "recursion_fixture",
        process_recursion_fixture,
    );
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
    constructor_invariants.addImport("compiler", host_core.compiler);
    constructor_invariants.addImport(
        "image_emit_v1",
        host_core.image_emit_v1,
    );
    constructor_invariants.addImport("image_v1", host_core.image_v1);
    constructor_invariants.addImport("kernel_v1", host_core.kernel_v1);
    constructor_invariants.addImport(
        "reducer_clause_v1",
        host_core.reducer_clause_v1,
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
    recursion.addImport("image_v1", host_core.image_v1);
    recursion.addImport("kernel_v1", host_core.kernel_v1);
    recursion.addImport("machine", host_core.machine);
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
    machine_yield.addImport("image_v1", host_core.image_v1);
    machine_yield.addImport("compiler", host_core.compiler);
    machine_yield.addImport("kernel_v1", host_core.kernel_v1);
    machine_yield.addImport("machine", host_core.machine);
    machine_yield.addImport(
        "machine_v2_profile_v1",
        host_core.machine_v2_profile_v1,
    );
    const effectful_decision_loop = programTestModule(
        b,
        host_core,
        "test/effectful_decision_loop.zig",
        b.graph.host,
        optimize,
        false,
        false,
    );
    effectful_decision_loop.addImport(
        "agent_profile",
        host_core.agent_profile,
    );

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

    const reified_core_step = b.step(
        "check-boundary-reified-core",
        "Prove direct specialization consumes one canonical Reified Program.",
    );
    reified_core_step.dependOn(reification_baseline_step);
    addTestArtifact(b, reified_core_step, reified_program_test);
    addTestArtifact(b, reified_core_step, reducer_semantics_test);
    addTestArtifact(b, reified_core_step, machine_v2_metering_test);
    const reification_generated_step = b.step(
        "check-boundary-reification-generated",
        "Exhaust finite graphs and run 10000 seeded direct/kernel traces.",
    );
    addTestArtifact(b, reification_generated_step, reification_generated_test);

    const image_step = b.step(
        "check-boundary-image",
        "Validate the canonical BPI1 envelope and section directory.",
    );
    addTestArtifact(b, image_step, host_core.dynamic_value_v1);
    addTestArtifact(b, image_step, host_core.image_emit_v1);
    addTestArtifact(b, image_step, image_test);

    const process_step = b.step(
        "check-boundary-process-v1",
        "Check canonical Process State and residual-effect records.",
    );
    addTestArtifact(b, process_step, process_test);
    addTestArtifact(b, process_step, process_advance_test);
    addTestArtifact(b, process_step, program_compile);
    const process_surface_guard = b.addSystemCommand(&.{
        "sh",
        "-c",
        "if rg -n 'MachineV2Profile|machine_v2|caller_fuel|cumulative_fuel|maximum_machine_fuel|maximum_frames|maximum_state_bytes|execution_budget_exceeded|frame_depth_exceeded|ABL_RNF2' src/process_*.zig; then exit 1; fi; if rg -n '@import\\(\"(machine|machine_v2|kernel)' src/process_*.zig; then exit 1; fi",
    });
    process_step.dependOn(&process_surface_guard.step);

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
    addTestArtifact(b, agent_step, effectful_decision_loop);

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
    const process_kernel_wasm_executable = b.addExecutable(.{
        .name = "boundary-process-kernel-v1",
        .root_module = wasm_core.process_kernel_wasm_v1,
    });
    process_kernel_wasm_executable.entry = .disabled;
    process_kernel_wasm_executable.rdynamic = true;
    process_kernel_wasm_executable.export_memory = true;
    process_kernel_wasm_executable.max_memory = 256 << 20;
    const install_process_kernel = b.addInstallFileWithDir(
        process_kernel_wasm_executable.getEmittedBin(),
        .prefix,
        "boundary-process-kernel-v1.wasm",
    );
    const emit_process_kernel_step = b.step(
        "emit-boundary-process-kernel-v1",
        "Emit the fixed import-free Boundary Process kernel.",
    );
    emit_process_kernel_step.dependOn(&install_process_kernel.step);
    process_step.dependOn(&process_kernel_wasm_executable.step);
    const process_kernel_vector_module = b.createModule(.{
        .root_source_file = b.path("test/process_kernel_vector.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    });
    process_kernel_vector_module.addImport("boundary", host_boundary);
    process_kernel_vector_module.addImport(
        "process_advance_v1",
        host_core.process_advance_v1,
    );
    const process_kernel_vector_executable = b.addExecutable(.{
        .name = "boundary-process-kernel-vector",
        .root_module = process_kernel_vector_module,
    });
    const run_process_kernel_vector = b.addRunArtifact(
        process_kernel_vector_executable,
    );
    const process_kernel_vector = run_process_kernel_vector.captureStdOut(.{
        .basename = "boundary-process-kernel-vector.bin",
    });
    const constrained_process_kernel_options = b.addOptions();
    constrained_process_kernel_options.addOption(
        usize,
        "input_capacity",
        1 << 20,
    );
    constrained_process_kernel_options.addOption(
        usize,
        "output_capacity",
        64,
    );
    constrained_process_kernel_options.addOption(
        usize,
        "state_capacity",
        64 << 10,
    );
    constrained_process_kernel_options.addOption(
        usize,
        "value_capacity",
        64 << 10,
    );
    constrained_process_kernel_options.addOption(
        usize,
        "request_capacity",
        64 << 10,
    );
    constrained_process_kernel_options.addOption(
        usize,
        "environment_capacity",
        64 << 10,
    );
    constrained_process_kernel_options.addOption(
        usize,
        "scratch_capacity",
        1 << 20,
    );
    constrained_process_kernel_options.addOption(
        usize,
        "error_capacity",
        4 << 10,
    );
    const constrained_process_kernel_module = b.createModule(.{
        .root_source_file = b.path("src/process_kernel_wasm_v1.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    });
    constrained_process_kernel_module.addImport(
        "image_v1",
        wasm_core.image_v1,
    );
    constrained_process_kernel_module.addImport(
        "process_advance_v1",
        wasm_core.process_advance_v1,
    );
    constrained_process_kernel_module.addOptions(
        "process_kernel_options",
        constrained_process_kernel_options,
    );
    const constrained_process_kernel = b.addExecutable(.{
        .name = "boundary-process-kernel-v1-constrained",
        .root_module = constrained_process_kernel_module,
    });
    constrained_process_kernel.entry = .disabled;
    constrained_process_kernel.rdynamic = true;
    constrained_process_kernel.export_memory = true;
    constrained_process_kernel.initial_memory = 4 << 20;
    constrained_process_kernel.max_memory = 32 << 20;
    const capacity_vector_module = b.createModule(.{
        .root_source_file = b.path("test/process_kernel_capacity_vector.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    });
    capacity_vector_module.addImport("boundary", host_boundary);
    capacity_vector_module.addImport(
        "process_advance_v1",
        host_core.process_advance_v1,
    );
    capacity_vector_module.addImport(
        "process_kernel_fixture",
        process_kernel_vector_module,
    );
    const capacity_vector_executable = b.addExecutable(.{
        .name = "boundary-process-kernel-capacity-vector",
        .root_module = capacity_vector_module,
    });
    const run_capacity_vector = b.addRunArtifact(capacity_vector_executable);
    const capacity_vector = run_capacity_vector.captureStdOut(.{
        .basename = "boundary-process-kernel-capacity-vector.bin",
    });
    const run_process_kernel_wasm = b.addSystemCommand(&.{"node"});
    run_process_kernel_wasm.addFileArg(
        b.path("test/run_process_kernel_wasm.mjs"),
    );
    run_process_kernel_wasm.addFileArg(
        process_kernel_wasm_executable.getEmittedBin(),
    );
    run_process_kernel_wasm.addFileArg(process_kernel_vector);
    run_process_kernel_wasm.addArg("0,1,2,3,4");
    process_step.dependOn(&run_process_kernel_wasm.step);
    const check_existing_repository_repair_bpi1 = b.addSystemCommand(&.{"node"});
    check_existing_repository_repair_bpi1.addFileArg(
        b.path("test/check_existing_repository_repair_bpi1.mjs"),
    );
    check_existing_repository_repair_bpi1.addFileArg(
        process_kernel_wasm_executable.getEmittedBin(),
    );
    check_existing_repository_repair_bpi1.addFileArg(b.path(
        "conformance/process-v1/repository-repair.agent.bpi1.base64",
    ));
    check_existing_repository_repair_bpi1.addFileArg(b.path(
        "conformance/process-v1/repository-repair.initial-args.bin.base64",
    ));
    process_step.dependOn(&check_existing_repository_repair_bpi1.step);
    const run_constrained_process_kernel_wasm = b.addSystemCommand(&.{"node"});
    run_constrained_process_kernel_wasm.addFileArg(
        b.path("test/run_process_kernel_wasm.mjs"),
    );
    run_constrained_process_kernel_wasm.addFileArg(
        constrained_process_kernel.getEmittedBin(),
    );
    run_constrained_process_kernel_wasm.addFileArg(capacity_vector);
    run_constrained_process_kernel_wasm.addArg("5");
    process_step.dependOn(&run_constrained_process_kernel_wasm.step);
    const check_process_step = b.addSystemCommand(&.{"node"});
    check_process_step.addFileArg(b.path("test/check_process_step.mjs"));
    check_process_step.addFileArg(
        process_kernel_wasm_executable.getEmittedBin(),
    );
    check_process_step.addFileArg(process_kernel_vector);
    check_process_step.addFileArg(
        b.path("scripts/boundary-process-step.mjs"),
    );
    process_step.dependOn(&check_process_step.step);
    const check_constrained_process_step = b.addSystemCommand(&.{"node"});
    check_constrained_process_step.addFileArg(
        b.path("test/check_process_step.mjs"),
    );
    check_constrained_process_step.addFileArg(
        constrained_process_kernel.getEmittedBin(),
    );
    check_constrained_process_step.addFileArg(capacity_vector);
    check_constrained_process_step.addFileArg(
        b.path("scripts/boundary-process-step.mjs"),
    );
    process_step.dependOn(&check_constrained_process_step.step);

    const kernel_wasm_executable = b.addExecutable(.{
        .name = "boundary-machine-v2-kernel-v1",
        .root_module = wasm_core.kernel_wasm_v1,
    });
    kernel_wasm_executable.entry = .disabled;
    kernel_wasm_executable.rdynamic = true;
    kernel_wasm_executable.export_memory = true;
    kernel_wasm_executable.max_memory = 128 << 20;
    check_process_step.addFileArg(kernel_wasm_executable.getEmittedBin());
    check_constrained_process_step.addFileArg(
        kernel_wasm_executable.getEmittedBin(),
    );
    const wasm_repro_core = addCoreModules(b, wasm_target, .ReleaseSmall);
    const kernel_wasm_reproducible = b.addExecutable(.{
        .name = "boundary-machine-v2-kernel-v1-reproducible",
        .root_module = wasm_repro_core.kernel_wasm_v1,
    });
    kernel_wasm_reproducible.entry = .disabled;
    kernel_wasm_reproducible.rdynamic = true;
    kernel_wasm_reproducible.export_memory = true;
    kernel_wasm_reproducible.max_memory = 128 << 20;
    const compare_kernel_wasm = b.addSystemCommand(&.{ "cmp", "-s" });
    compare_kernel_wasm.addFileArg(kernel_wasm_executable.getEmittedBin());
    compare_kernel_wasm.addFileArg(kernel_wasm_reproducible.getEmittedBin());
    const kernel_vector_module = b.createModule(.{
        .root_source_file = b.path("test/kernel_wasm_vector.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    });
    kernel_vector_module.addImport("control_ir", host_core.control_ir);
    kernel_vector_module.addImport("image_v1", host_core.image_v1);
    kernel_vector_module.addImport("kernel_v1", host_core.kernel_v1);
    kernel_vector_module.addImport("machine", host_core.machine);
    kernel_vector_module.addImport("program_v2", host_core.program_v2);
    const kernel_vector_executable = b.addExecutable(.{
        .name = "boundary-kernel-wasm-vector",
        .root_module = kernel_vector_module,
    });
    const run_kernel_vector = b.addRunArtifact(kernel_vector_executable);
    const kernel_vector_output = run_kernel_vector.captureStdOut(.{
        .basename = "boundary-kernel-wasm-vector.bin",
    });
    const kernel_failure_vector_module = b.createModule(.{
        .root_source_file = b.path("test/kernel_wasm_machine_failure_vector.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    });
    kernel_failure_vector_module.addImport("control_ir", host_core.control_ir);
    kernel_failure_vector_module.addImport("image_v1", host_core.image_v1);
    kernel_failure_vector_module.addImport("kernel_v1", host_core.kernel_v1);
    kernel_failure_vector_module.addImport("machine", host_core.machine);
    kernel_failure_vector_module.addImport("program_v2", host_core.program_v2);
    const kernel_failure_vector_executable = b.addExecutable(.{
        .name = "boundary-kernel-wasm-machine-failure-vector",
        .root_module = kernel_failure_vector_module,
    });
    const run_kernel_failure_vector = b.addRunArtifact(
        kernel_failure_vector_executable,
    );
    const kernel_failure_vector_output = run_kernel_failure_vector.captureStdOut(.{
        .basename = "boundary-kernel-wasm-machine-failure-vector.bin",
    });
    const one_effect_image_module = b.createModule(.{
        .root_source_file = b.path("test/emit_one_effect_image.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    });
    one_effect_image_module.addImport("boundary", host_boundary);
    const one_effect_image_executable = b.addExecutable(.{
        .name = "emit-one-effect-boundary-program-image",
        .root_module = one_effect_image_module,
    });
    const run_one_effect_image = b.addRunArtifact(one_effect_image_executable);
    const one_effect_image = run_one_effect_image.captureStdOut(.{
        .basename = "one-effect.boundary-program-image",
    });
    const one_effect_profile_module = b.createModule(.{
        .root_source_file = b.path("test/emit_one_effect_profile.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    });
    one_effect_profile_module.addImport(
        "image_fixture",
        one_effect_image_module,
    );
    const one_effect_profile_executable = b.addExecutable(.{
        .name = "emit-one-effect-machine-v2-profile",
        .root_module = one_effect_profile_module,
    });
    const run_one_effect_profile = b.addRunArtifact(one_effect_profile_executable);
    const one_effect_profile = run_one_effect_profile.captureStdOut(.{
        .basename = "one-effect.machine-v2-profile",
    });
    const portable_values_image_module = b.createModule(.{
        .root_source_file = b.path("test/emit_portable_values_image.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    });
    portable_values_image_module.addImport("boundary", host_boundary);
    portable_values_image_module.addImport(
        "operations_fixture",
        reification_operations_fixture,
    );
    const portable_values_image_executable = b.addExecutable(.{
        .name = "emit-portable-values-boundary-program-image",
        .root_module = portable_values_image_module,
    });
    const run_portable_values_image = b.addRunArtifact(
        portable_values_image_executable,
    );
    const portable_values_image = run_portable_values_image.captureStdOut(.{
        .basename = "portable-values.boundary-program-image",
    });
    const portable_values_profile_module = b.createModule(.{
        .root_source_file = b.path("test/emit_portable_values_profile.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    });
    portable_values_profile_module.addImport(
        "operations_fixture",
        reification_operations_fixture,
    );
    const portable_values_profile_executable = b.addExecutable(.{
        .name = "emit-portable-values-machine-v2-profile",
        .root_module = portable_values_profile_module,
    });
    const run_portable_values_profile = b.addRunArtifact(
        portable_values_profile_executable,
    );
    const portable_values_profile = run_portable_values_profile.captureStdOut(.{
        .basename = "portable-values.machine-v2-profile",
    });
    const kernel_sha_command = b.addSystemCommand(&.{
        "sh",
        "-c",
        "shasum -a 256 \"$1\" | awk '{print $1}'",
        "sh",
    });
    kernel_sha_command.addFileArg(kernel_wasm_executable.getEmittedBin());
    const kernel_sha = kernel_sha_command.captureStdOut(.{
        .basename = "boundary-machine-v2-kernel-v1.wasm.sha256",
    });
    const one_effect_sha_command = b.addSystemCommand(&.{
        "sh",
        "-c",
        "shasum -a 256 \"$1\" | awk '{print $1}'",
        "sh",
    });
    one_effect_sha_command.addFileArg(one_effect_image);
    const one_effect_sha = one_effect_sha_command.captureStdOut(.{
        .basename = "one-effect.boundary-program-image.sha256",
    });
    const portable_values_sha_command = b.addSystemCommand(&.{
        "sh",
        "-c",
        "shasum -a 256 \"$1\" | awk '{print $1}'",
        "sh",
    });
    portable_values_sha_command.addFileArg(portable_values_image);
    const portable_values_sha = portable_values_sha_command.captureStdOut(.{
        .basename = "portable-values.boundary-program-image.sha256",
    });
    const one_effect_profile_sha_command = b.addSystemCommand(&.{
        "sh",
        "-c",
        "shasum -a 256 \"$1\" | awk '{print $1}'",
        "sh",
    });
    one_effect_profile_sha_command.addFileArg(one_effect_profile);
    const one_effect_profile_sha = one_effect_profile_sha_command.captureStdOut(.{
        .basename = "one-effect.machine-v2-profile.sha256",
    });
    const portable_values_profile_sha_command = b.addSystemCommand(&.{
        "sh",
        "-c",
        "shasum -a 256 \"$1\" | awk '{print $1}'",
        "sh",
    });
    portable_values_profile_sha_command.addFileArg(portable_values_profile);
    const portable_values_profile_sha = portable_values_profile_sha_command.captureStdOut(.{
        .basename = "portable-values.machine-v2-profile.sha256",
    });
    const reification_asset_receipt_command = b.addSystemCommand(&.{
        "node",
        "scripts/write_reification_receipt.mjs",
    });
    reification_asset_receipt_command.addFileArg(
        kernel_wasm_executable.getEmittedBin(),
    );
    reification_asset_receipt_command.addFileArg(one_effect_image);
    reification_asset_receipt_command.addFileArg(portable_values_image);
    reification_asset_receipt_command.addFileArg(one_effect_profile);
    reification_asset_receipt_command.addFileArg(portable_values_profile);
    addReificationReceiptSources(b, reification_asset_receipt_command);
    reification_asset_receipt_command.addFileArg(
        reification_generated_proof,
    );
    const reification_receipt_file = reification_asset_receipt_command.captureStdOut(.{
        .basename = "boundary-reification-v1-receipt.json",
    });
    const install_kernel = b.addInstallFileWithDir(
        kernel_wasm_executable.getEmittedBin(),
        .prefix,
        "boundary-machine-v2-kernel-v1.wasm",
    );
    const install_kernel_sha = b.addInstallFileWithDir(
        kernel_sha,
        .prefix,
        "boundary-machine-v2-kernel-v1.wasm.sha256",
    );
    const install_one_effect = b.addInstallFileWithDir(
        one_effect_image,
        .prefix,
        "one-effect.boundary-program-image",
    );
    const install_one_effect_sha = b.addInstallFileWithDir(
        one_effect_sha,
        .prefix,
        "one-effect.boundary-program-image.sha256",
    );
    const install_portable_values = b.addInstallFileWithDir(
        portable_values_image,
        .prefix,
        "portable-values.boundary-program-image",
    );
    const install_portable_values_sha = b.addInstallFileWithDir(
        portable_values_sha,
        .prefix,
        "portable-values.boundary-program-image.sha256",
    );
    const install_one_effect_profile = b.addInstallFileWithDir(
        one_effect_profile,
        .prefix,
        "one-effect.machine-v2-profile",
    );
    const install_one_effect_profile_sha = b.addInstallFileWithDir(
        one_effect_profile_sha,
        .prefix,
        "one-effect.machine-v2-profile.sha256",
    );
    const install_portable_values_profile = b.addInstallFileWithDir(
        portable_values_profile,
        .prefix,
        "portable-values.machine-v2-profile",
    );
    const install_portable_values_profile_sha = b.addInstallFileWithDir(
        portable_values_profile_sha,
        .prefix,
        "portable-values.machine-v2-profile.sha256",
    );
    const install_reification_receipt = b.addInstallFileWithDir(
        reification_receipt_file,
        .prefix,
        "boundary-reification-v1-receipt.json",
    );
    const install_kernel_runtime_asset = b.addInstallFileWithDir(
        kernel_wasm_executable.getEmittedBin(),
        .prefix,
        "boundary-machine-v2-kernel-v1.wasm",
    );
    const install_one_effect_runtime_image = b.addInstallFileWithDir(
        one_effect_image,
        .prefix,
        "one-effect.boundary-program-image",
    );
    const install_one_effect_runtime_profile = b.addInstallFileWithDir(
        one_effect_profile,
        .prefix,
        "one-effect.machine-v2-profile",
    );
    const emit_kernel_assets_step = b.step(
        "emit-boundary-kernel-assets",
        "Emit the fixed kernel and unrelated validation pair without release receipts.",
    );
    inline for (.{
        install_kernel_runtime_asset,
        install_one_effect_runtime_image,
        install_one_effect_runtime_profile,
    }) |installation| emit_kernel_assets_step.dependOn(&installation.step);
    const emit_unrelated_pair_step = b.step(
        "emit-boundary-unrelated-pair",
        "Emit the unrelated BPI1 and MachineV2Profile validation pair.",
    );
    inline for (.{
        install_one_effect_runtime_image,
        install_one_effect_runtime_profile,
    }) |installation| emit_unrelated_pair_step.dependOn(&installation.step);
    const emit_reification_assets_step = b.step(
        "emit-boundary-reification-assets",
        "Emit BPI1 examples, fixed kernel, checksums, and receipt.",
    );
    inline for (.{
        install_kernel,
        install_kernel_sha,
        install_one_effect,
        install_one_effect_sha,
        install_portable_values,
        install_portable_values_sha,
        install_one_effect_profile,
        install_one_effect_profile_sha,
        install_portable_values_profile,
        install_portable_values_profile_sha,
        install_reification_receipt,
    }) |installation| emit_reification_assets_step.dependOn(&installation.step);
    const run_kernel_wasm = b.addSystemCommand(&.{"node"});
    run_kernel_wasm.addFileArg(b.path("test/run_kernel_wasm.mjs"));
    run_kernel_wasm.addFileArg(kernel_wasm_executable.getEmittedBin());
    run_kernel_wasm.addFileArg(kernel_vector_output);
    run_kernel_wasm.addFileArg(kernel_failure_vector_output);
    run_kernel_wasm.addArg("--release-assets");
    run_kernel_wasm.addFileArg(one_effect_image);
    run_kernel_wasm.addFileArg(portable_values_image);
    run_kernel_wasm.addFileArg(one_effect_profile);
    run_kernel_wasm.addFileArg(portable_values_profile);
    const kernel_wasm_proof = run_kernel_wasm.captureStdOut(.{
        .basename = "boundary-machine-v2-kernel-wasm-proof.json",
    });
    const kernel_wasm_step = b.step(
        "check-boundary-machine-v2-kernel-wasm",
        "Check fixed import-free Boundary Kernel WASM ABI and profile.",
    );
    kernel_wasm_step.dependOn(&run_kernel_wasm.step);
    kernel_wasm_step.dependOn(&compare_kernel_wasm.step);
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

    const source_topology_proof = b.addWriteFiles();
    var topology: std.Io.Writer.Allocating = .init(b.allocator);
    topology.writer.print(
        "core_module_count={d}\nsource_module root support src/root.zig\n",
        .{std.meta.fields(CoreModules).len},
    ) catch |err| std.process.fatal(
        "failed to render Boundary module topology: {s}",
        .{@errorName(err)},
    );
    inline for (std.meta.fields(CoreModuleId)) |field| {
        const module: CoreModuleId = @enumFromInt(field.value);
        topology.writer.print(
            "source_module {s} {s} {s}\n",
            .{
                field.name,
                @tagName(coreModuleRole(module)),
                coreModulePath(module),
            },
        ) catch |err| std.process.fatal(
            "failed to render Boundary module topology: {s}",
            .{@errorName(err)},
        );
    }
    const topology_receipt = source_topology_proof.add(
        "boundary-core-module-topology.txt",
        topology.toOwnedSlice() catch |err| std.process.fatal(
            "failed to finalize Boundary module topology: {s}",
            .{@errorName(err)},
        ),
    );

    const single_reducer_module = b.createModule(.{
        .root_source_file = b.path("test/single_reducer.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    single_reducer_module.addImport("boundary", host_boundary);
    const single_reducer_executable = b.addExecutable(.{
        .name = "boundary-machine-single-reducer-proof",
        .root_module = single_reducer_module,
    });
    const single_reducer_run = b.addRunArtifact(single_reducer_executable);
    const single_reducer_receipt = single_reducer_run.captureStdOut(.{
        .basename = "boundary-machine-single-reducer.txt",
    });

    const performance_command = b.addSystemCommand(&.{"sh"});
    performance_command.setEnvironmentVariable(
        "ZIG_GLOBAL_CACHE_DIR",
        b.graph.global_cache_root.path orelse ".",
    );
    performance_command.addFileArg(
        b.path("conformance/rnf-v1/check_performance.sh"),
    );
    performance_command.addFileArg(performance_tests.getEmittedBin());
    performance_command.addFileArg(
        performance_wasm_executable.getEmittedBin(),
    );
    performance_command.addArg(b.graph.zig_exe);
    performance_command.addArg(@tagName(performance_wasm_optimize));
    performance_command.addFileArg(topology_receipt);
    performance_command.addFileArg(single_reducer_receipt);
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

    const single_reducer_step = b.step(
        "check-boundary-machine-single-reducer",
        "Prove a compiled Program exposes exactly one normative reducer.",
    );
    single_reducer_step.dependOn(&source_topology_proof.step);
    single_reducer_step.dependOn(&single_reducer_run.step);

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
            "Boundary Driver handler does not admit effect site semantic contract",
        },
        .{
            "test/compile_fail/driver_semantic_contract_mismatch.zig",
            "Boundary Driver handler does not admit effect site semantic contract",
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
            "test/compile_fail/non_enum_failure_tagged_union.zig",
            "Body.Failure must be an exhaustive enum",
        },
        .{
            "test/compile_fail/non_enum_failure_void.zig",
            "Body.Failure must be an exhaustive enum",
        },
        .{
            "test/compile_fail/image_failure_variant_limit.zig",
            "BPI1 failure variants exceed validator capacity",
        },
        .{
            "test/compile_fail/image_schema_member_limit.zig",
            "BPI1 schema members exceed validator capacity",
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

    const public_surface_compile_fail_sources = b.addWriteFiles();
    const vector_borrowed_slice_source = public_surface_compile_fail_sources.add("vector_borrowed_slice.zig",
        \\const portable_value = @import("portable_value");
        \\
        \\comptime {
        \\    const value = portable_value.Vector(u32, 1).empty();
        \\    _ = value.slice();
        \\}
        \\
        \\pub fn main() void {}
    );
    const vector_borrowed_slice_module = b.createModule(.{
        .root_source_file = vector_borrowed_slice_source,
        .target = b.graph.host,
        .optimize = .Debug,
    });
    vector_borrowed_slice_module.addImport("portable_value", host_core.portable_value);
    const vector_borrowed_slice_compilation = b.addTest(.{
        .root_module = vector_borrowed_slice_module,
    });
    vector_borrowed_slice_compilation.expect_errors = .{
        .contains = "no field or member function named 'slice' in 'portable_value.Vector(u32,1)'",
    };
    compile_fail_step.dependOn(&vector_borrowed_slice_compilation.step);

    const failure_value_type_mismatch_source = public_surface_compile_fail_sources.add("failure_value_type_mismatch.zig",
        \\const cir = @import("control_ir");
        \\const program_v2 = @import("program_v2");
        \\
        \\const blocks = [_]cir.Block{
        \\    .{
        \\        .id = 0,
        \\        .parameters = &.{0},
        \\        .terminator = .{ .fail_value = 0 },
        \\    },
        \\};
        \\
        \\const Body = struct {
        \\    pub const InitialArgs = u32;
        \\    pub const Result = void;
        \\    pub const Failure = enum { rejected };
        \\    pub const effect_sites = .{};
        \\    pub const schema_types = .{};
        \\    pub const control_ir: cir.Program = .{
        \\        .label = "failure-value-type-mismatch",
        \\        .value_types = &.{.{ .scalar = .u32 }},
        \\        .blocks = &blocks,
        \\        .entry = 0,
        \\        .result_type = .{ .scalar = .unit },
        \\    };
        \\};
        \\
        \\const Machine = program_v2.program(
        \\    "failure-value-type-mismatch",
        \\    Body,
        \\).compile(.{
        \\    .maximum_frames = 2,
        \\    .maximum_state_bytes = 1024,
        \\    .maximum_machine_fuel = 8,
        \\});
        \\
        \\comptime {
        \\    _ = Machine.abi_version;
        \\}
    );
    const failure_value_type_mismatch_module = b.createModule(.{
        .root_source_file = failure_value_type_mismatch_source,
        .target = b.graph.host,
        .optimize = .Debug,
    });
    failure_value_type_mismatch_module.addImport("control_ir", host_core.control_ir);
    failure_value_type_mismatch_module.addImport("program_v2", host_core.program_v2);
    const failure_value_type_mismatch_compilation = b.addTest(.{
        .root_module = failure_value_type_mismatch_module,
    });
    failure_value_type_mismatch_compilation.expect_errors = .{
        .contains = "Control IR fail_value must reference Body.Failure",
    };
    compile_fail_step.dependOn(&failure_value_type_mismatch_compilation.step);

    const vector_source_authority_source = public_surface_compile_fail_sources.add("vector_source_authority.zig",
        \\const std = @import("std");
        \\const portable_value = @import("portable_value");
        \\
        \\test "language-visible Vector fields remain untrusted source values" {
        \\    const Item = portable_value.Text(4);
        \\    const Values = portable_value.Vector(Item, 1);
        \\
        \\    var values = Values.empty();
        \\    values.storage[0].storage[0] = 0xff;
        \\    values.storage[0].logical_length = 1;
        \\    values.logical_length = 1;
        \\
        \\    try std.testing.expectError(error.InvalidUtf8, values.get(0));
        \\    try std.testing.expectError(
        \\        error.InvalidUtf8,
        \\        portable_value.encodedSize(Values, values),
        \\    );
        \\}
    );
    const vector_source_authority_module = b.createModule(.{
        .root_source_file = vector_source_authority_source,
        .target = b.graph.host,
        .optimize = .Debug,
    });
    vector_source_authority_module.addImport("portable_value", host_core.portable_value);
    const vector_source_authority_compilation = b.addTest(.{
        .root_module = vector_source_authority_module,
    });
    const vector_source_authority_run = b.addRunArtifact(vector_source_authority_compilation);
    values_step.dependOn(&vector_source_authority_run.step);

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
        effectful_decision_loop,
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
    const zig_path_coverage_guard = addZigPathCoverageGuard(b);
    lint_step.dependOn(zig_path_coverage_guard);
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

    const image_canonical_step = b.step(
        "check-boundary-image-canonical",
        "Check canonical BPI1 emission, validation, and exact re-encoding.",
    );
    image_canonical_step.dependOn(image_step);
    image_canonical_step.dependOn(reified_core_step);
    const image_profile_invariance_step = b.step(
        "check-boundary-image-profile-invariance",
        "Prove BPI1 bytes ignore Machine v2 profiles and metering annotations.",
    );
    image_profile_invariance_step.dependOn(reified_core_step);
    const machine_v2_profile_projection_step = b.step(
        "check-boundary-machine-v2-profile-projection",
        "Prove semantic RNF quotients mixed legacy checkpoint and jump paths.",
    );
    addTestArtifact(b, machine_v2_profile_projection_step, machine_yield);
    const pure_evaluator_surface_guard = b.addSystemCommand(&.{
        "sh",
        "-c",
        "if rg -n 'machine_v2|machine\\.zig|MachineOptions|caller_fuel|cumulative_fuel|maximum_machine_fuel|maximum_frames|maximum_state_bytes|execution_budget_exceeded|frame_depth_exceeded|ABL_RNF2' src/program_semantics_v1.zig src/reducer_clause_v1.zig src/image_v1.zig src/reified_program_v1.zig; then exit 1; fi; if rg -n '@import\\(\"(machine|machine_v2|kernel)' src/program_semantics_v1.zig src/reducer_clause_v1.zig src/image_v1.zig src/image_emit_v1.zig src/reified_program_v1.zig; then exit 1; fi",
    });
    const isolated_pure = addPureProgramModules(
        b,
        b.graph.host,
        optimize,
    );
    const isolated_clause_test = b.createModule(.{
        .root_source_file = b.path("test/reducer_clause_v1.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    isolated_clause_test.addImport(
        "reducer_clause_v1",
        isolated_pure.reducer_clause_v1,
    );
    isolated_clause_test.addImport("image_v1", isolated_pure.image_v1);
    const pure_topology_files = b.addWriteFiles();
    const pure_topology_receipt = pure_topology_files.add(
        "boundary-pure-module-topology.txt",
        "control_ir -> program_semantics_v1\n" ++
            "portable_value -> program_semantics_v1\n" ++
            "rnf -> program_semantics_v1\n" ++
            "dynamic_value_v1 -> image_v1\n" ++
            "program_semantics_v1 -> image_v1\n" ++
            "dynamic_value_v1 -> reducer_clause_v1\n" ++
            "image_v1 -> reducer_clause_v1\n" ++
            "program_semantics_v1 -> reducer_clause_v1\n",
    );
    const pure_topology_guard = b.addSystemCommand(&.{
        "sh",
        "-c",
        "test \"$(wc -l < \"$1\" | tr -d ' ')\" -eq 8 && ! rg -n 'machine|kernel' \"$1\"",
        "sh",
    });
    pure_topology_guard.addFileArg(pure_topology_receipt);
    const pure_evaluator_step = b.step(
        "check-boundary-pure-evaluator",
        "Check one finite BPI1 reducer clause without Machine v2 policy.",
    );
    addTestArtifact(b, pure_evaluator_step, isolated_clause_test);
    pure_evaluator_step.dependOn(&pure_evaluator_surface_guard.step);
    pure_evaluator_step.dependOn(&pure_topology_guard.step);
    const image_malformed_step = b.step(
        "check-boundary-image-malformed",
        "Reject deterministic malformed BPI1 and ABL_RNF2 corpora.",
    );
    image_malformed_step.dependOn(reified_core_step);
    image_malformed_step.dependOn(malformed_step);
    const image_digest_step = b.step(
        "check-boundary-image-digest",
        "Reconstruct Program, Machine, schema, and effect digests from BPI1.",
    );
    image_digest_step.dependOn(reified_core_step);
    const kernel_native_step = b.step(
        "check-boundary-machine-v2-kernel-native",
        "Check fixed native kernel execution across the admitted algebra.",
    );
    kernel_native_step.dependOn(reified_core_step);
    kernel_native_step.dependOn(values_step);
    kernel_native_step.dependOn(recursion_step);
    const kernel_machine_step = b.step(
        "check-boundary-machine-v2-kernel-adapter",
        "Check typed KernelMachine ABI and ownership parity.",
    );
    kernel_machine_step.dependOn(reified_core_step);
    kernel_machine_step.dependOn(single_reducer_step);
    const specialization_equivalence_step = b.step(
        "check-boundary-specialization-equivalence",
        "Check direct and fixed-kernel transition equivalence.",
    );
    specialization_equivalence_step.dependOn(kernel_native_step);
    specialization_equivalence_step.dependOn(kernel_machine_step);
    specialization_equivalence_step.dependOn(parity_step);
    const engine_switch_step = b.step(
        "check-boundary-engine-switch",
        "Exchange canonical States between direct and kernel engines.",
    );
    engine_switch_step.dependOn(reified_core_step);
    engine_switch_step.dependOn(recursion_step);
    const reification_deletion_step = b.step(
        "check-boundary-reification-deletion",
        "Check declared engine independence and removed runtime surfaces.",
    );
    reification_deletion_step.dependOn(deletion_step);
    reification_deletion_step.dependOn(single_reducer_step);
    const reification_measure_step = b.step(
        "check-boundary-reification-measure",
        "Measure direct and fixed-kernel artifacts under retained hard gates.",
    );
    reification_measure_step.dependOn(performance_step);
    reification_measure_step.dependOn(kernel_wasm_step);
    const reification_receipt_step = b.step(
        "check-boundary-reification-receipt",
        "Run the executable Boundary Reification v1 receipt surface.",
    );
    const reification_receipt_script_test = b.addSystemCommand(&.{
        "node",
        "test/reification_receipt_v1.mjs",
    });
    reification_receipt_step.dependOn(&reification_receipt_script_test.step);
    inline for (.{
        image_canonical_step,
        image_profile_invariance_step,
        machine_v2_profile_projection_step,
        image_malformed_step,
        image_digest_step,
        pure_evaluator_step,
        specialization_equivalence_step,
        engine_switch_step,
        reification_generated_step,
        reification_deletion_step,
        reification_measure_step,
    }) |dependency| reification_receipt_step.dependOn(dependency);
    const reification_proof_stamp_command = b.addSystemCommand(&.{
        "node",
        "scripts/write_reification_proof.mjs",
    });
    reification_proof_stamp_command.addFileArg(kernel_wasm_proof);
    reification_proof_stamp_command.addFileArg(reification_baseline_proof);
    reification_proof_stamp_command.addFileArg(reification_semantic_proof);
    reification_proof_stamp_command.addFileArg(reification_generated_proof);
    reification_proof_stamp_command.addFileArg(b.path("src/root.zig"));
    reification_proof_stamp_command.addFileArg(b.path("build.zig"));
    inline for (.{
        "src/control_ir.zig",
        "src/dynamic_value_v1.zig",
        "src/image_v1.zig",
        "src/portable_value.zig",
        "src/program_semantics_v1.zig",
        "src/reducer_clause_v1.zig",
        "src/rnf.zig",
    }) |source_path| reification_proof_stamp_command.addFileArg(
        b.path(source_path),
    );
    reification_proof_stamp_command.addArg("--pure-semantics");
    inline for (.{
        "src/image_emit_v1.zig",
        "src/image_v1.zig",
        "src/program_semantics_v1.zig",
        "src/reducer_clause_v1.zig",
        "src/reified_program_v1.zig",
    }) |source_path| reification_proof_stamp_command.addFileArg(
        b.path(source_path),
    );
    reification_proof_stamp_command.addArg("--all-sources");
    var reification_source_paths = std.mem.splitScalar(
        u8,
        @embedFile("repo_zig_paths.txt"),
        '\n',
    );
    while (reification_source_paths.next()) |source_path| {
        if (!std.mem.startsWith(u8, source_path, "src/") or
            source_path.len == 0)
        {
            continue;
        }
        reification_proof_stamp_command.addFileArg(b.path(source_path));
    }
    reification_proof_stamp_command.addArg("--receipt-sources");
    addReificationReceiptSources(b, reification_proof_stamp_command);
    reification_proof_stamp_command.step.dependOn(zig_path_coverage_guard);
    const reification_proof_stamp = reification_proof_stamp_command.captureStdOut(.{
        .basename = "boundary-reification-v1-proof.json",
    });
    reification_asset_receipt_command.addFileArg(reification_proof_stamp);
    reification_receipt_step.dependOn(&reification_asset_receipt_command.step);
    inline for (.{
        install_kernel,
        install_kernel_sha,
        install_one_effect,
        install_one_effect_sha,
        install_portable_values,
        install_portable_values_sha,
        install_one_effect_profile,
        install_one_effect_profile_sha,
        install_portable_values_profile,
        install_portable_values_profile_sha,
        install_reification_receipt,
    }) |installation| installation.step.dependOn(reification_receipt_step);
    emit_reification_assets_step.dependOn(reification_receipt_step);

    const receipt_falsifier_step = b.step(
        "check-boundary-machine-receipt-falsifiers",
        "Prove completion receipt reachability from the live build graph.",
    );
    receipt_falsifier_step.dependOn(&reification_receipt_script_test.step);

    const release_proof_step = b.step(
        "check-boundary-machine-release-proof",
        "Run the complete Boundary Machine release-proof DAG.",
    );
    inline for (.{
        test_step,
        reification_baseline_step,
        reified_core_step,
        image_step,
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
        kernel_wasm_step,
        reification_generated_step,
        reification_receipt_step,
        no_interpreter_step,
        deletion_step,
        compile_fail_step,
        examples_step,
        lint_step,
        performance_step,
        performance_falsifier_step,
        single_reducer_step,
        receipt_falsifier_step,
    }) |dependency| {
        release_proof_step.dependOn(dependency);
    }

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
    receipt_command.step.dependOn(release_proof_step);
    const receipt_step = b.step(
        "check-boundary-machine-receipt",
        "Emit the Boundary-owned completion receipt after the release proof.",
    );
    receipt_step.dependOn(&receipt_command.step);

    const check_step = b.step("check", "Run the full Boundary Machine proof.");
    check_step.dependOn(release_proof_step);
    check_step.dependOn(receipt_step);
    check_step.dependOn(process_step);

    requireDirectDependency(&receipt_command.step, release_proof_step);
    requireDirectDependency(receipt_step, &receipt_command.step);
    requireDirectDependency(check_step, release_proof_step);
    requireDirectDependency(check_step, receipt_step);
    requireDirectDependency(check_step, process_step);
}
