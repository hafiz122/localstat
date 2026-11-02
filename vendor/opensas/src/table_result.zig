const std = @import("std");

pub const Cell = struct {
    text: []const u8,
    span: usize = 1,
};

pub const Row = struct {
    kind: []const u8 = "data",
    cells: []const Cell,
};

pub const Table = struct {
    procedure: []const u8,
    title: []const u8,
    section: []const u8 = "",
    headers: std.ArrayList(Row) = .empty,
    rows: std.ArrayList(Row) = .empty,
    notes: std.ArrayList([]const u8) = .empty,

    pub fn header(self: *Table, a: std.mem.Allocator, values: []const Cell) !void {
        try self.headers.append(a, .{ .cells = try a.dupe(Cell, values) });
    }

    pub fn row(self: *Table, a: std.mem.Allocator, kind: []const u8, values: []const Cell) !void {
        try self.rows.append(a, .{ .kind = kind, .cells = try a.dupe(Cell, values) });
    }

    pub fn note(self: *Table, a: std.mem.Allocator, value: []const u8) !void {
        try self.notes.append(a, value);
    }
};

pub const Collector = struct {
    arena: std.mem.Allocator,
    tables: std.ArrayList(Table) = .empty,

    pub fn add(self: *Collector, table: Table) !void {
        try self.tables.append(self.arena, table);
    }

    pub fn json(self: *const Collector) ![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        const a = self.arena;
        try out.appendSlice(a, "{\"version\":1,\"tables\":[");
        for (self.tables.items, 0..) |table, ti| {
            if (ti > 0) try out.append(a, ',');
            try out.appendSlice(a, "{\"procedure\":");
            try quoted(a, &out, table.procedure);
            try out.appendSlice(a, ",\"title\":");
            try quoted(a, &out, table.title);
            try out.appendSlice(a, ",\"section\":");
            try quoted(a, &out, table.section);
            try out.appendSlice(a, ",\"headers\":");
            try writeRows(a, &out, table.headers.items);
            try out.appendSlice(a, ",\"rows\":");
            try writeRows(a, &out, table.rows.items);
            try out.appendSlice(a, ",\"notes\":[");
            for (table.notes.items, 0..) |note, ni| {
                if (ni > 0) try out.append(a, ',');
                try quoted(a, &out, note);
            }
            try out.appendSlice(a, "]}");
        }
        try out.appendSlice(a, "]}\n");
        return out.items;
    }
};

pub fn cells(a: std.mem.Allocator, values: []const []const u8) ![]const Cell {
    const result = try a.alloc(Cell, values.len);
    for (values, 0..) |value, i| result[i] = .{ .text = value };
    return result;
}

fn writeRows(a: std.mem.Allocator, out: *std.ArrayList(u8), rows: []const Row) !void {
    try out.append(a, '[');
    for (rows, 0..) |row, ri| {
        if (ri > 0) try out.append(a, ',');
        try out.appendSlice(a, "{\"kind\":");
        try quoted(a, out, row.kind);
        try out.appendSlice(a, ",\"cells\":[");
        for (row.cells, 0..) |cell, ci| {
            if (ci > 0) try out.append(a, ',');
            try out.appendSlice(a, "{\"text\":");
            try quoted(a, out, cell.text);
            try out.appendSlice(a, ",\"span\":");
            try out.appendSlice(a, try std.fmt.allocPrint(a, "{d}", .{cell.span}));
            try out.append(a, '}');
        }
        try out.appendSlice(a, "]}");
    }
    try out.append(a, ']');
}

fn quoted(a: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    try out.append(a, '"');
    for (value) |ch| switch (ch) {
        '"' => try out.appendSlice(a, "\\\""),
        '\\' => try out.appendSlice(a, "\\\\"),
        '\n' => try out.appendSlice(a, "\\n"),
        '\r' => try out.appendSlice(a, "\\r"),
        '\t' => try out.appendSlice(a, "\\t"),
        else => if (ch < 0x20) {
            try out.appendSlice(a, try std.fmt.allocPrint(a, "\\u{X:0>4}", .{ch}));
        } else try out.append(a, ch),
    };
    try out.append(a, '"');
}

test "table JSON escapes displayed strings" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    var collector = Collector{ .arena = arena.allocator() };
    var table = Table{ .procedure = "PRINT", .title = "A \"title\"" };
    try table.header(collector.arena, try cells(collector.arena, &.{"name"}));
    try table.row(collector.arena, "data", try cells(collector.arena, &.{"line\nnext"}));
    try collector.add(table);
    const result = try collector.json();
    try std.testing.expect(std.mem.indexOf(u8, result, "A \\\"title\\\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "line\\nnext") != null);
}
