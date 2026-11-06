const std = @import("std");

pub const Plot = struct {
    procedure: []const u8,
    title: []const u8,
    svg: []const u8,
};

pub const Collector = struct {
    arena: std.mem.Allocator,
    plots: std.ArrayList(Plot) = .empty,

    pub fn add(self: *Collector, plot: Plot) !void {
        try self.plots.append(self.arena, plot);
    }
};
