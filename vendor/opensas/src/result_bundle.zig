const std = @import("std");
const Io = std.Io;
const table_result = @import("table_result.zig");
const plot_result = @import("plot_result.zig");

pub const Object = struct {
    kind: []const u8,
    path: []const u8,
    name: ?[]const u8 = null,
    procedure: ?[]const u8 = null,
    index: ?usize = null,
};

pub const Manifest = struct {
    schema_version: u8 = 1,
    complete: bool = true,
    exit_code: u8,
    status: []const u8,
    objects: []const Object,
};

pub fn status(exit_code: u8) []const u8 {
    return switch (exit_code) {
        0 => "success",
        1 => "program_error",
        2 => "unsupported",
        else => "exited",
    };
}

pub fn manifestJson(a: std.mem.Allocator, tables: *const table_result.Collector, plots: *const plot_result.Collector, exit_code: u8) ![]const u8 {
    const objects = try a.alloc(Object, tables.tables.items.len + plots.plots.items.len + 2);
    objects[0] = .{ .kind = "listing", .path = "listing.txt" };
    objects[1] = .{ .kind = "diagnostics", .path = "diagnostics.txt" };
    for (tables.tables.items, 0..) |table, index| {
        objects[index + 2] = .{
            .kind = "table",
            .name = table.title,
            .procedure = table.procedure,
            .path = "tables.json",
            .index = index,
        };
    }
    for (plots.plots.items, 0..) |plot, index| {
        objects[tables.tables.items.len + index + 2] = .{
            .kind = "graphic",
            .name = plot.title,
            .procedure = plot.procedure,
            .path = try std.fmt.allocPrint(a, "graphics/plot-{d:0>4}.svg", .{index + 1}),
            .index = index,
        };
    }
    return std.json.Stringify.valueAlloc(a, Manifest{
        .exit_code = exit_code,
        .status = status(exit_code),
        .objects = objects,
    }, .{ .emit_null_optional_fields = false });
}

/// The directory must not exist. The manifest is the completion marker and is
/// renamed into place only after all referenced artifacts have been written.
pub fn write(a: std.mem.Allocator, io: Io, path: []const u8, output: []const u8, diagnostics: []const u8, tables: *const table_result.Collector, plots: *const plot_result.Collector, exit_code: u8) !void {
    try Io.Dir.cwd().createDir(io, path, .default_dir);
    var dir = try Io.Dir.cwd().openDir(io, path, .{});
    defer dir.close(io);
    try dir.writeFile(io, .{ .sub_path = "listing.txt", .data = output });
    try dir.writeFile(io, .{ .sub_path = "diagnostics.txt", .data = diagnostics });
    try dir.writeFile(io, .{ .sub_path = "tables.json", .data = try tables.json() });
    if (plots.plots.items.len > 0) {
        try dir.createDir(io, "graphics", .default_dir);
        for (plots.plots.items, 0..) |plot, index| {
            const file_path = try std.fmt.allocPrint(a, "graphics/plot-{d:0>4}.svg", .{index + 1});
            try dir.writeFile(io, .{ .sub_path = file_path, .data = plot.svg });
        }
    }
    try dir.writeFile(io, .{ .sub_path = "manifest.json.tmp", .data = try manifestJson(a, tables, plots, exit_code) });
    try dir.rename("manifest.json.tmp", dir, "manifest.json", io);
}

test "manifest describes every table and distinguishes program errors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tables = table_result.Collector{ .arena = a };
    const plots = plot_result.Collector{ .arena = a };
    try tables.add(.{ .procedure = "FREQ", .title = "One-Way Frequencies" });
    const json = try manifestJson(a, &tables, &plots, 1);
    const parsed = try std.json.parseFromSlice(Manifest, a, json, .{ .ignore_unknown_fields = false });
    try std.testing.expect(parsed.value.complete);
    try std.testing.expectEqual(@as(u8, 1), parsed.value.schema_version);
    try std.testing.expectEqualStrings("program_error", parsed.value.status);
    try std.testing.expectEqual(@as(usize, 3), parsed.value.objects.len);
    try std.testing.expectEqualStrings("One-Way Frequencies", parsed.value.objects[2].name.?);
    try std.testing.expectEqualStrings("FREQ", parsed.value.objects[2].procedure.?);
    try std.testing.expectEqual(@as(usize, 0), parsed.value.objects[2].index.?);
}

test "completed unsupported run publishes manifest after artifacts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fs.path.join(a, &.{ ".zig-cache", "tmp", &tmp.sub_path, "result" });
    const tables = table_result.Collector{ .arena = a };
    const plots = plot_result.Collector{ .arena = a };
    try write(a, std.testing.io, path, "", "UNSUPPORTED: PROC BOGUS\n", &tables, &plots, 2);
    const raw = try tmp.dir.readFileAlloc(std.testing.io, "result/manifest.json", a, .limited(1 << 20));
    const parsed = try std.json.parseFromSlice(Manifest, a, raw, .{});
    try std.testing.expect(parsed.value.complete);
    try std.testing.expectEqual(@as(u8, 2), parsed.value.exit_code);
    try std.testing.expectEqualStrings("unsupported", parsed.value.status);
    try std.testing.expectEqual(@as(usize, 2), parsed.value.objects.len);
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(std.testing.io, "result/manifest.json.tmp", .{}));
}

test "graphic is written before completed manifest" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fs.path.join(a, &.{ ".zig-cache", "tmp", &tmp.sub_path, "result" });
    const tables = table_result.Collector{ .arena = a };
    var plots = plot_result.Collector{ .arena = a };
    try plots.add(.{ .procedure = "SGPLOT", .title = "Scatter Plot", .svg = "<svg/>" });
    try write(a, std.testing.io, path, "", "", &tables, &plots, 0);
    const raw = try tmp.dir.readFileAlloc(std.testing.io, "result/manifest.json", a, .limited(1 << 20));
    const parsed = try std.json.parseFromSlice(Manifest, a, raw, .{});
    try std.testing.expectEqual(@as(usize, 3), parsed.value.objects.len);
    try std.testing.expectEqualStrings("graphic", parsed.value.objects[2].kind);
    try std.testing.expectEqualStrings("graphics/plot-0001.svg", parsed.value.objects[2].path);
    const svg = try tmp.dir.readFileAlloc(std.testing.io, "result/graphics/plot-0001.svg", a, .limited(100));
    try std.testing.expectEqualStrings("<svg/>", svg);
}
