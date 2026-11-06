const std = @import("std");

pub const Kind = enum {
    sort,
    print,
    reg,
    corr,
    ttest,
    sgplot,
    means,
    summary,
    freq,
    transpose,
    sql,
    report,
    tabulate,
    univariate,
    rank,
    standard,
    contents,
    format,
    datasets,
    delete,
    compare,
    @"export",
    import,
    append,
    printto,
    copy,
};

pub const Spec = struct {
    name: []const u8,
    kind: Kind,
    listing: bool = false,
    support: enum { subset, noop } = .subset,
};

pub const specs = [_]Spec{
    .{ .name = "sort", .kind = .sort },
    .{ .name = "print", .kind = .print, .listing = true },
    .{ .name = "reg", .kind = .reg, .listing = true },
    .{ .name = "corr", .kind = .corr, .listing = true },
    .{ .name = "ttest", .kind = .ttest, .listing = true },
    .{ .name = "sgplot", .kind = .sgplot },
    .{ .name = "means", .kind = .means, .listing = true },
    .{ .name = "summary", .kind = .summary },
    .{ .name = "freq", .kind = .freq, .listing = true },
    .{ .name = "transpose", .kind = .transpose },
    .{ .name = "sql", .kind = .sql },
    .{ .name = "report", .kind = .report, .listing = true },
    .{ .name = "tabulate", .kind = .tabulate, .listing = true },
    .{ .name = "univariate", .kind = .univariate, .listing = true },
    .{ .name = "rank", .kind = .rank },
    .{ .name = "standard", .kind = .standard },
    .{ .name = "contents", .kind = .contents, .listing = true },
    .{ .name = "format", .kind = .format },
    .{ .name = "datasets", .kind = .datasets },
    .{ .name = "delete", .kind = .delete },
    .{ .name = "compare", .kind = .compare, .listing = true },
    .{ .name = "export", .kind = .@"export" },
    .{ .name = "import", .kind = .import },
    .{ .name = "append", .kind = .append },
    .{ .name = "printto", .kind = .printto, .support = .noop },
    .{ .name = "copy", .kind = .copy },
};

pub fn lookup(name: []const u8) ?Spec {
    for (specs) |spec| {
        if (std.ascii.eqlIgnoreCase(name, spec.name)) return spec;
    }
    return null;
}

test "procedure registry is unique and case insensitive" {
    for (specs, 0..) |spec, i| {
        try std.testing.expectEqual(spec.kind, lookup(spec.name).?.kind);
        for (specs[i + 1 ..]) |other| {
            try std.testing.expect(!std.ascii.eqlIgnoreCase(spec.name, other.name));
            try std.testing.expect(spec.kind != other.kind);
        }
    }
    try std.testing.expectEqual(Kind.reg, lookup("ReG").?.kind);
    try std.testing.expect(lookup("bogus") == null);
}
