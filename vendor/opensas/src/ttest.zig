const std = @import("std");
const betaI = @import("functions.zig").betaI;
const diag = @import("diag.zig");
const lexer = @import("lexer.zig");
const proc = @import("proc.zig");
const Dataset = @import("dataset.zig").Dataset;
const Library = @import("exec.zig").Library;
const Value = @import("value.zig").Value;

pub fn run(cx: proc.ProcCtx, out: *std.ArrayList(u8), toks: []const lexer.Token) diag.Error!void {
    const a = cx.arena;
    const line = if (toks.len > 0) toks[0].line else 0;
    if (toks.len < 9 or !atName(toks, 2, "data") or toks[3].tag != .eq or toks[4].tag != .name)
        return cx.diags.fail(error.ParseError, line, "PROC TTEST requires DATA=", .{});
    var i: usize = 5;
    var dataset_name = toks[4].text;
    if (token(toks, i).tag == .dot and token(toks, i + 1).tag == .name) {
        dataset_name = try std.fmt.allocPrint(a, "{s}.{s}", .{ dataset_name, token(toks, i + 1).text });
        i += 2;
    }
    var null_mean: f64 = 0;
    var explicit_null = false;
    if (atName(toks, i, "h0")) {
        explicit_null = true;
        i += 1;
        if (token(toks, i).tag != .eq) return cx.diags.fail(error.ParseError, token(toks, i).line, "PROC TTEST H0 requires a number", .{});
        i += 1;
        var sign: f64 = 1;
        if (token(toks, i).tag == .minus or token(toks, i).tag == .plus) {
            if (token(toks, i).tag == .minus) sign = -1;
            i += 1;
        }
        if (token(toks, i).tag != .number) return cx.diags.fail(error.ParseError, token(toks, i).line, "PROC TTEST H0 requires a number", .{});
        null_mean = sign * (std.fmt.parseFloat(f64, token(toks, i).text) catch
            return cx.diags.fail(error.ParseError, token(toks, i).line, "PROC TTEST H0 requires a number", .{}));
        if (!std.math.isFinite(null_mean)) return cx.diags.fail(error.ParseError, token(toks, i).line, "PROC TTEST H0 must be finite", .{});
        i += 1;
    }
    if (token(toks, i).tag != .semicolon) return unsupported(cx, token(toks, i));
    i += 1;
    var class_variable: ?[]const u8 = null;
    if (atName(toks, i, "class")) {
        i += 1;
        if (token(toks, i).tag != .name or token(toks, i + 1).tag != .semicolon)
            return cx.diags.fail(error.ParseError, token(toks, i).line, "PROC TTEST CLASS requires one variable", .{});
        class_variable = token(toks, i).text;
        i += 2;
    }
    const paired = atName(toks, i, "paired");
    if (!paired and !atName(toks, i, "var")) return unsupported(cx, token(toks, i));
    i += 1;
    if (token(toks, i).tag != .name) return cx.diags.fail(error.ParseError, token(toks, i).line, "PROC TTEST requires a numeric VAR", .{});
    const variable = token(toks, i).text;
    i += 1;
    var paired_variable: ?[]const u8 = null;
    if (paired) {
        if (token(toks, i).tag != .star or token(toks, i + 1).tag != .name)
            return cx.diags.fail(error.ParseError, token(toks, i).line, "PROC TTEST PAIRED requires x*y", .{});
        paired_variable = token(toks, i + 1).text;
        i += 2;
    }
    if (token(toks, i).tag != .semicolon) return unsupported(cx, token(toks, i));
    i += 1;
    if (!atName(toks, i, "run") or token(toks, i + 1).tag != .semicolon)
        return unsupported(cx, token(toks, i));
    if (class_variable != null and paired)
        return unsupported(cx, token(toks, i));
    const original = cx.lib.find(dataset_name) orelse
        return cx.diags.fail(error.ExecError, line, "Dataset {s} not found", .{dataset_name});
    const ds = try proc.procInput(a, original, toks, cx.diags);
    const col = ds.indexOf(variable) orelse
        return cx.diags.fail(error.ExecError, line, "Variable {s} not found", .{variable});
    if (ds.columns.items[col].type != .num)
        return cx.diags.fail(error.ExecError, line, "PROC TTEST VAR {s} must be numeric", .{variable});
    const paired_col: ?usize = if (paired_variable) |name| ds.indexOf(name) orelse
        return cx.diags.fail(error.ExecError, line, "Variable {s} not found", .{name}) else null;
    if (paired_col) |other| if (ds.columns.items[other].type != .num)
        return cx.diags.fail(error.ExecError, line, "PROC TTEST PAIRED variable {s} must be numeric", .{paired_variable.?});
    if (class_variable) |class_name| {
        if (explicit_null) return unsupported(cx, token(toks, 0));
        const group_col = ds.indexOf(class_name) orelse
            return cx.diags.fail(error.ExecError, line, "Variable {s} not found", .{class_name});
        var first_group: ?Value = null;
        var second_group: ?Value = null;
        var first: std.ArrayList(f64) = .empty;
        var second: std.ArrayList(f64) = .empty;
        for (ds.rows.items) |row| {
            if (row[col].isMissing() or classMissing(row[group_col])) continue;
            const group = row[group_col];
            if (first_group == null) first_group = group;
            if (sameGroup(group, first_group.?)) {
                try first.append(a, row[col].num);
            } else {
                if (second_group == null) second_group = group;
                if (!sameGroup(group, second_group.?))
                    return cx.diags.fail(error.ExecError, line, "PROC TTEST CLASS requires exactly two nonmissing levels", .{});
                try second.append(a, row[col].num);
            }
        }
        const result = twoSample(first.items, second.items) catch |err| return statisticError(cx, line, err);
        try out.appendSlice(a, "The TTEST Procedure\nMethod: Two Sample\n");
        try out.appendSlice(a, try std.fmt.allocPrint(a, "Variable: {s}\nClass: {s}\nGroup\tN\tMean\tStd Dev\n", .{ variable, class_name }));
        try out.appendSlice(a, try std.fmt.allocPrint(a, "{s}\t{d}\t{d:.10}\t{d:.10}\n", .{ try groupText(a, first_group.?), result.first.n, result.first.mean, result.first.standard_deviation }));
        try out.appendSlice(a, try std.fmt.allocPrint(a, "{s}\t{d}\t{d:.10}\t{d:.10}\n", .{ try groupText(a, second_group.?), result.second.n, result.second.mean, result.second.standard_deviation }));
        try out.appendSlice(a, "Variance\tDF\tt Value\tPr > |t|\n");
        try out.appendSlice(a, try std.fmt.allocPrint(a, "Pooled\t{d:.10}\t{d:.10}\t{d:.10}\n", .{ result.pooled_df, result.pooled_t, result.pooled_p_two_sided }));
        try out.appendSlice(a, try std.fmt.allocPrint(a, "Satterthwaite\t{d:.10}\t{d:.10}\t{d:.10}\n", .{ result.welch_df, result.welch_t, result.welch_p_two_sided }));
        return;
    }
    var values: std.ArrayList(f64) = .empty;
    for (ds.rows.items) |row| {
        if (row[col].isMissing()) continue;
        if (paired_col) |other| {
            if (row[other].isMissing()) continue;
            try values.append(a, row[col].num - row[other].num);
        } else try values.append(a, row[col].num);
    }
    const result = oneSample(values.items, null_mean) catch |err| return statisticError(cx, line, err);
    try out.appendSlice(a, if (paired) "The TTEST Procedure\nMethod: Paired\n" else "The TTEST Procedure\nMethod: One Sample\n");
    try out.appendSlice(a, "Variable\tN\tMean\tStd Dev\tStd Err\tDF\tt Value\tPr > |t|\n");
    const display_name = if (paired) try std.fmt.allocPrint(a, "{s} - {s}", .{ variable, paired_variable.? }) else variable;
    try out.appendSlice(a, try std.fmt.allocPrint(a, "{s}\t{d}\t{d:.10}\t{d:.10}\t{d:.10}\t{d}\t{d:.10}\t{d:.10}\n", .{
        display_name, result.n, result.mean, result.standard_deviation, result.standard_error,
        @as(usize, @intFromFloat(result.df)), result.t, result.p_two_sided,
    }));
}

fn token(toks: []const lexer.Token, i: usize) lexer.Token {
    if (i < toks.len) return toks[i];
    return .{ .tag = .eof, .line = if (toks.len > 0) toks[toks.len - 1].line else 0 };
}

fn sameGroup(a: Value, b: Value) bool {
    return switch (a) {
        .num => |x| switch (b) { .num => |y| x == y, else => false },
        .str => |x| switch (b) { .str => |y| std.mem.eql(u8, x, y), else => false },
    };
}

fn classMissing(value: Value) bool {
    return switch (value) {
        .num => |n| std.math.isNan(n),
        .str => |s| std.mem.trim(u8, s, " ").len == 0,
    };
}

fn groupText(a: std.mem.Allocator, value: Value) ![]const u8 {
    return switch (value) {
        .num => |n| try std.fmt.allocPrint(a, "{d}", .{n}),
        .str => |s| s,
    };
}

fn atName(toks: []const lexer.Token, i: usize, name: []const u8) bool {
    return i < toks.len and toks[i].tag == .name and std.ascii.eqlIgnoreCase(toks[i].text, name);
}

fn unsupported(cx: proc.ProcCtx, bad_token: lexer.Token) diag.Error {
    diag.markGap();
    return cx.diags.fail(error.ParseError, bad_token.line, "PROC TTEST does not support '{s}' in this release", .{bad_token.text});
}

fn statisticError(cx: proc.ProcCtx, line: usize, err: anyerror) diag.Error {
    if (err == error.ZeroVariance or err == error.InsufficientData) {
        diag.markGap();
        return cx.diags.fail(error.ExecError, line, "PROC TTEST zero variance or insufficient-data results are not supported yet", .{});
    }
    return cx.diags.fail(error.ExecError, line, "PROC TTEST cannot calculate a t test ({t})", .{err});
}

pub const OneSample = struct {
    n: usize,
    mean: f64,
    standard_deviation: f64,
    standard_error: f64,
    t: f64,
    df: f64,
    p_two_sided: f64,
};

pub const TwoSample = struct {
    first: GroupSummary,
    second: GroupSummary,
    pooled_t: f64,
    pooled_df: f64,
    pooled_p_two_sided: f64,
    welch_t: f64,
    welch_df: f64,
    welch_p_two_sided: f64,
};

pub const GroupSummary = struct {
    n: usize,
    mean: f64,
    standard_deviation: f64,
};

const Moments = struct { n: usize, mean: f64, variance: f64, df: f64 };

pub fn twoSample(first: []const f64, second: []const f64) error{ InsufficientData, ZeroVariance, NonFinite }!TwoSample {
    const a = try moments(first);
    const b = try moments(second);
    const n1: f64 = @floatFromInt(a.n);
    const n2: f64 = @floatFromInt(b.n);
    const var1 = a.variance;
    const var2 = b.variance;
    const pooled_df = a.df + b.df;
    const pooled_var = (a.df * var1 + b.df * var2) / pooled_df;
    const pooled_se = @sqrt(pooled_var * (1 / n1 + 1 / n2));
    const component1 = var1 / n1;
    const component2 = var2 / n2;
    const welch_se = @sqrt(component1 + component2);
    if (!(pooled_se > 0) or !(welch_se > 0)) return error.ZeroVariance;
    const pooled_t = (a.mean - b.mean) / pooled_se;
    const welch_t = (a.mean - b.mean) / welch_se;
    const welch_df = (component1 + component2) * (component1 + component2) /
        (component1 * component1 / a.df + component2 * component2 / b.df);
    if (!std.math.isFinite(pooled_t) or !std.math.isFinite(welch_t) or !std.math.isFinite(welch_df))
        return error.NonFinite;
    return .{
        .first = .{ .n = a.n, .mean = a.mean, .standard_deviation = @sqrt(var1) },
        .second = .{ .n = b.n, .mean = b.mean, .standard_deviation = @sqrt(var2) },
        .pooled_t = pooled_t,
        .pooled_df = pooled_df,
        .pooled_p_two_sided = betaI(pooled_df / (pooled_df + pooled_t * pooled_t), pooled_df / 2, 0.5),
        .welch_t = welch_t,
        .welch_df = welch_df,
        .welch_p_two_sided = betaI(welch_df / (welch_df + welch_t * welch_t), welch_df / 2, 0.5),
    };
}

pub fn oneSample(values: []const f64, null_mean: f64) error{ InsufficientData, ZeroVariance, NonFinite }!OneSample {
    if (!std.math.isFinite(null_mean)) return error.NonFinite;
    const summary = try moments(values);
    if (!(summary.variance > 0)) return error.ZeroVariance;
    const standard_deviation = @sqrt(summary.variance);
    const standard_error = standard_deviation / @sqrt(@as(f64, @floatFromInt(summary.n)));
    const statistic = (summary.mean - null_mean) / standard_error;
    if (!std.math.isFinite(statistic)) return error.NonFinite;
    return .{
        .n = summary.n,
        .mean = summary.mean,
        .standard_deviation = standard_deviation,
        .standard_error = standard_error,
        .t = statistic,
        .df = summary.df,
        .p_two_sided = betaI(summary.df / (summary.df + statistic * statistic), summary.df / 2, 0.5),
    };
}

fn moments(values: []const f64) error{ InsufficientData, NonFinite }!Moments {
    if (values.len < 2) return error.InsufficientData;
    var mean: f64 = 0;
    var sum_squares: f64 = 0;
    for (values, 0..) |value, index| {
        if (!std.math.isFinite(value)) return error.NonFinite;
        const n: f64 = @floatFromInt(index + 1);
        const delta = value - mean;
        mean += delta / n;
        sum_squares += delta * (value - mean);
    }
    const df: f64 = @floatFromInt(values.len - 1);
    const variance = sum_squares / df;
    if (!std.math.isFinite(mean) or !std.math.isFinite(variance)) return error.NonFinite;
    return .{ .n = values.len, .mean = mean, .variance = variance, .df = df };
}

test "one-sample t statistic and probability for five observations" {
    const result = try oneSample(&.{ 1, 2, 3, 4, 5 }, 0);
    try std.testing.expectEqual(@as(usize, 5), result.n);
    try std.testing.expectApproxEqAbs(@as(f64, 3), result.mean, 1e-12);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 2.5)), result.standard_deviation, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 4.242640687119285), result.t, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 4), result.df, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.013235599563682695), result.p_two_sided, 1e-10);
}

test "one-sample t rejects variance overflow" {
    try std.testing.expectError(error.NonFinite, oneSample(&.{ -1e200, 1e200 }, 0));
}

test "two-sample pooled and Welch statistics for equal group variances" {
    const result = try twoSample(&.{ 1, 2, 3 }, &.{ 3, 4, 5 });
    try std.testing.expectEqual(@as(usize, 3), result.first.n);
    try std.testing.expectEqual(@as(usize, 3), result.second.n);
    try std.testing.expectApproxEqAbs(@as(f64, 2), result.first.mean, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 4), result.second.mean, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, -2.449489742783178), result.pooled_t, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 4), result.pooled_df, 1e-12);
    try std.testing.expectApproxEqAbs(result.pooled_t, result.welch_t, 1e-12);
    try std.testing.expectApproxEqAbs(result.pooled_df, result.welch_df, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.07048399691021993), result.pooled_p_two_sided, 1e-10);
}

test "two-sample t allows one constant group when the other varies" {
    const result = try twoSample(&.{ 1, 1, 1 }, &.{ 2, 3, 4 });
    try std.testing.expectApproxEqAbs(@as(f64, 0), result.first.standard_deviation, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, -3.4641016151377544), result.pooled_t, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, -3.4641016151377544), result.welch_t, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 2), result.welch_df, 1e-12);
}

test "TTEST one-sample run reports mean t statistic and probability" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 1, 2, 3, 4, 5 }) |x| try ds.appendRow(&.{.{ .num = x }});
    try lib.putInput("d", ds);
    var diags = diag.Diagnostics.init(a);
    const toks = try lexer.tokenize(a, "proc ttest data=d; var x; run;", &diags);
    var out: std.ArrayList(u8) = .empty;
    try run(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "x\t5\t3.0000000000") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "4.2426406871") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "0.0132355996") != null);
}

test "TTEST H0 option changes one-sample statistic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 1, 2, 3, 4, 5 }) |x| try ds.appendRow(&.{.{ .num = x }});
    try lib.putInput("d", ds);
    var diags = diag.Diagnostics.init(a);
    const toks = try lexer.tokenize(a, "proc ttest data=d h0=2; var x; run;", &diags);
    var out: std.ArrayList(u8) = .empty;
    try run(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "1.4142135624") != null);
}

test "TTEST paired run uses complete pairs and x minus y" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    for ([_][2]f64{ .{ 4, 1 }, .{ 5, 2 }, .{ 6, 2 }, .{ 7, 3 } }) |pair|
        try ds.appendRow(&.{ .{ .num = pair[0] }, .{ .num = pair[1] } });
    try ds.appendRow(&.{ .{ .num = 100 }, @import("value.zig").Value.missing });
    try lib.putInput("d", ds);
    var diags = diag.Diagnostics.init(a);
    const toks = try lexer.tokenize(a, "proc ttest data=d; paired x*y; run;", &diags);
    var out: std.ArrayList(u8) = .empty;
    try run(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Method: Paired") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "x - y\t4\t3.5000000000") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "12.1243556530") != null);
}

test "TTEST two-sample CLASS run reports pooled and Welch tests" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 1, 2, 3 }) |x| try ds.appendRow(&.{ .{ .str = "A" }, .{ .num = x } });
    for ([_]f64{ 3, 4, 5 }) |x| try ds.appendRow(&.{ .{ .str = "B" }, .{ .num = x } });
    try ds.appendRow(&.{ .{ .str = "   " }, .{ .num = 999 } });
    try lib.putInput("d", ds);
    var diags = diag.Diagnostics.init(a);
    const toks = try lexer.tokenize(a, "proc ttest data=d; class g; var x; run;", &diags);
    var out: std.ArrayList(u8) = .empty;
    try run(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Method: Two Sample") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "A\t3\t2.0000000000") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "B\t3\t4.0000000000") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Pooled\t4.0000000000\t-2.4494897428") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Satterthwaite\t4.0000000000\t-2.4494897428") != null);
}

test "TTEST unsupported option fails loud as runtime gap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var diags = diag.Diagnostics.init(a);
    const toks = try lexer.tokenize(a, "proc ttest data=d alpha=.05; var x; run;", &diags);
    var out: std.ArrayList(u8) = .empty;
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, run(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
    try std.testing.expect(diag.gapHit());
    try std.testing.expect(std.mem.indexOf(u8, try diags.render(), "does not support 'alpha'") != null);
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
}

test "TTEST truncated token slices return an error without trapping" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("g", .char);
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .str = "A" } });
    try lib.putInput("d", ds);
    var diags = diag.Diagnostics.init(a);
    const toks = try lexer.tokenize(a, "proc ttest data=d h0=-1; class g; var x; run;", &diags);
    for (0..toks.len - 2) |end| {
        var partial_diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const result = run(.{ .arena = a, .lib = &lib, .diags = &partial_diags }, &out, toks[0..end]);
        try std.testing.expectError(error.ParseError, result);
    }
}

test "TTEST zero variance reports a runtime gap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    try ds.appendRow(&.{.{ .num = 1 }});
    try ds.appendRow(&.{.{ .num = 1 }});
    try lib.putInput("d", ds);
    var diags = diag.Diagnostics.init(a);
    const toks = try lexer.tokenize(a, "proc ttest data=d; var x; run;", &diags);
    var out: std.ArrayList(u8) = .empty;
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ExecError, run(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
    try std.testing.expect(diag.gapHit());
    try std.testing.expect(std.mem.indexOf(u8, try diags.render(), "zero variance") != null);
}
