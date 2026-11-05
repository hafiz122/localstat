    try ds.rows.ensureTotalCapacityPrecise(a, row_count);
    for (records) |line| {
        if (line.len == 0) continue;
        _ = row_state.reset(.retain_capacity);
        const fields = try parseCsvLine(row_state.allocator(), line, delim);
        const cells = try a.alloc(Value, ncol);
        for (0..ncol) |ci| {
            const f = if (ci < fields.items.len) fields.items[ci] else "";
            if (col_date[ci] != null) {
                cells[ci] = if (isCsvMissing(f)) Value.missing else .{ .num = format.importDateGuess(f).?.value };
            } else if (ds.columns.items[ci].type == .num) {
                cells[ci] = if (isCsvMissing(f)) Value.missing else .{ .num = parseF64(f).? };
            } else cells[ci] = .{ .str = try a.dupe(u8, f) };
        }
        ds.rows.appendAssumeCapacity(cells);
    }
