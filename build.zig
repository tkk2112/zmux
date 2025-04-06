const std = @import("std");

const targets: []const std.Target.Query = &.{
    .{ .os_tag = .macos, .cpu_arch = .aarch64 },
    .{ .os_tag = .macos, .cpu_arch = .x86_64 },
    .{ .os_tag = .linux, .cpu_arch = .aarch64 },
    .{ .os_tag = .linux, .cpu_arch = .x86_64, .abi = .gnu },
    .{ .os_tag = .linux, .cpu_arch = .x86, .abi = .gnu },
    .{ .os_tag = .linux, .cpu_arch = .x86_64, .abi = .musl },
    .{ .os_tag = .linux, .cpu_arch = .x86, .abi = .musl },
};
const Modules = struct { libModule: *std.Build.Module, lib: *std.Build.Step.Compile, exeModule: *std.Build.Module, exe: *std.Build.Step.Compile };
fn compileProject(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !Modules {
    const build_zig_zon = b.createModule(.{
        .root_source_file = b.path("build.zig.zon"),
        .target = target,
        .optimize = optimize,
    });

    const libModule = b.createModule(.{
        .root_source_file = b.path("src/lib/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    libModule.addImport("build.zig.zon", build_zig_zon);

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zmux",
        .root_module = libModule,
        .version = std.SemanticVersion.parse("1.0.0") catch unreachable,
    });

    const exeModule = b.createModule(.{
        .root_source_file = b.path("src/app/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exeModule.addImport("zmux.lib", libModule);

    const exe = b.addExecutable(.{
        .name = "zmux",
        .root_module = exeModule,
    });

    return .{ .libModule = libModule, .lib = lib, .exeModule = exeModule, .exe = exe };
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const native_build = try compileProject(b, target, optimize);
    b.installArtifact(native_build.lib);
    b.installArtifact(native_build.exe);

    const run_cmd = b.addRunArtifact(native_build.exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_module = native_build.libModule,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = native_build.exeModule,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);

    const release_step = b.step("release", "Build release targets");

    for (targets) |t| {
        const resolved_target = b.resolveTargetQuery(t);
        const target_build = try compileProject(b, resolved_target, optimize);
        const dir_name = try t.zigTriple(std.heap.page_allocator);

        const artifacts = [_]*std.Build.Step.Compile{ target_build.lib, target_build.exe };
        for (artifacts) |artifact| {
            const target_artifact = b.addInstallArtifact(artifact, .{ .dest_dir = .{ .override = .{ .custom = dir_name } } });
            release_step.dependOn(&target_artifact.step);
        }
    }
}
