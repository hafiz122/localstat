    for (records) |line| {
        if (line.len == 0) continue;
        _ = row_state.reset(.retain_capacity);
        const fields = try parseCsvLine(row_state.allocator(), line, delim);
        row_count += 1;
        for (inferred, 0..) |*info, ci| {
            const f = if (ci < fields.items.len) fields.items[ci] else "";
            if (isCsvMissing(f)) continue;
            info.any = true;
            if (info.numeric and parseF64(f) == null) info.numeric = false;
            if (detect_dates and info.uniform_date) {
                const trimmed = std.mem.trim(u8, f, " ");
                info.date_width = @max(info.date_width, trimmed.len);
                if (format.importDateGuess(trimmed)) |guess| {
                    if (info.date_kind) |kind| {
                        if (kind != guess.kind) info.uniform_date = false;
                    } else info.date_kind = guess.kind;
                } else info.uniform_date = false;
            }
        }
    }
