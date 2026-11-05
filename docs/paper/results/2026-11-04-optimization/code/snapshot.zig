pub fn snapshot(ds: *Dataset, pdv: *const Pdv) std.mem.Allocator.Error!void {
    const cells = try ds.arena.alloc(Value, ds.columns.items.len);
    for (ds.columns.items, 0..) |col, i| {
        const value = pdv.get(col.name) orelse missingOf(col.type);
        cells[i] = switch (value) {
            .num => value,
            .str => |s| .{ .str = try ds.arena.dupe(u8, s) },
        };
    }
    // The cells already belong to the dataset; appendRow would copy them again.
    try ds.rows.append(ds.arena, cells);
}
