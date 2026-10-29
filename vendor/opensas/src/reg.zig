//! LocalStat's bounded PROC REG: numeric OLS with an intercept and one MODEL.
//! Added by LocalStat to the vendored OpenSAS source snapshot.
const std = @import("std");
const diag = @import("diag.zig");
const proc = @import("proc.zig");
const parser = @import("parser.zig");
const Token = @import("lexer.zig").Token;
const betaI = @import("functions.zig").betaI;
const eq = std.ascii.eqlIgnoreCase;

pub const Fit = struct {
    coefficients: []f64,
    standard_errors: []f64,
    sse: f64,
    sst: f64,
    mean: f64,
    n: usize,
    p: usize,
};
pub const FitError = error{ OutOfMemory, InsufficientObservations, RankDeficient, NumericalFailure };

/// Column scaling keeps the rank test independent of predictor units. QR with
/// column pivoting avoids squaring the condition number as X'X would do.
pub fn fit(a: std.mem.Allocator, x: []const f64, y: []const f64, p: usize) FitError!Fit {
    const n = y.len;
    if (p == 0 or n <= p or x.len != n * p) return error.InsufficientObservations;
    const qr = try a.dupe(f64, x);
    const qty = try a.dupe(f64, y);
    const scales = try a.alloc(f64, p);
    const perm = try a.alloc(usize, p);
    for (0..p) |j| {
        perm[j] = j;
        var norm: f64 = 0;
        for (0..n) |i| norm = std.math.hypot(norm, qr[i * p + j]);
        if (!std.math.isFinite(norm)) return error.NumericalFailure;
        if (norm == 0) return error.RankDeficient;
        scales[j] = norm;
        for (0..n) |i| qr[i * p + j] /= norm;
    }
    const threshold = 16 * std.math.floatEps(f64) * @as(f64, @floatFromInt(@max(n, p)));
    for (0..p) |k| {
        var best = k;
        var best_norm: f64 = 0;
        for (k..p) |j| {
            var norm: f64 = 0;
            for (k..n) |i| norm = std.math.hypot(norm, qr[i * p + j]);
            if (norm > best_norm) {
                best = j;
                best_norm = norm;
            }
        }
        if (best_norm <= threshold) return error.RankDeficient;
        if (best != k) {
            for (0..n) |i| std.mem.swap(f64, &qr[i * p + k], &qr[i * p + best]);
            std.mem.swap(usize, &perm[k], &perm[best]);
        }
        const first = qr[k * p + k];
        const alpha = if (first >= 0) -best_norm else best_norm;
        const v0 = first - alpha;
        const tau = (alpha - first) / alpha;
        for (k + 1..n) |i| qr[i * p + k] /= v0;
        qr[k * p + k] = alpha;
        for (k + 1..p) |j| {
            var dot = qr[k * p + j];
            for (k + 1..n) |i| dot += qr[i * p + k] * qr[i * p + j];
            dot *= tau;
            qr[k * p + j] -= dot;
            for (k + 1..n) |i| qr[i * p + j] -= qr[i * p + k] * dot;
        }
        var dot = qty[k];
        for (k + 1..n) |i| dot += qr[i * p + k] * qty[i];
        dot *= tau;
        qty[k] -= dot;
        for (k + 1..n) |i| qty[i] -= qr[i * p + k] * dot;
    }
    const b = try a.alloc(f64, p);
    const z = try a.alloc(f64, p);
    var i = p;
    while (i > 0) {
        i -= 1;
        var value = qty[i];
        for (i + 1..p) |j| value -= qr[i * p + j] * z[j];
        z[i] = value / qr[i * p + i];
        b[perm[i]] = z[i] / scales[perm[i]];
        if (!std.math.isFinite(b[perm[i]])) return error.NumericalFailure;
    }
    var mean: f64 = 0;
    for (y, 0..) |value, r| mean += (value - mean) / @as(f64, @floatFromInt(r + 1));
    var sse: f64 = 0;
    var sst: f64 = 0;
    var yscale: f64 = 0;
    for (y, 0..) |value, r| {
        var predicted: f64 = 0;
        for (0..p) |j| predicted += x[r * p + j] * b[j];
        sse += (value - predicted) * (value - predicted);
        sst += (value - mean) * (value - mean);
        yscale += value * value;
    }
    if (!std.math.isFinite(sse) or !std.math.isFinite(sst) or !std.math.isFinite(yscale)) return error.NumericalFailure;
    if (sse <= 64 * std.math.floatEps(f64) * std.math.floatEps(f64) * @as(f64, @floatFromInt(n)) * yscale) sse = 0;
    const mse = sse / @as(f64, @floatFromInt(n - p));
    // diag(R^-1 R^-T), computed by triangular solves, in original column order.
    const inverse = try a.alloc(f64, p * p);
    @memset(inverse, 0);
    for (0..p) |col| {
        i = p;
        while (i > 0) {
            i -= 1;
            var value: f64 = if (i == col) 1 else 0;
            for (i + 1..p) |j| value -= qr[i * p + j] * inverse[j * p + col];
            inverse[i * p + col] = value / qr[i * p + i];
        }
    }
    const se = try a.alloc(f64, p);
    for (0..p) |j| {
        var sum: f64 = 0;
        for (0..p) |k| sum += inverse[j * p + k] * inverse[j * p + k];
        se[perm[j]] = @sqrt(mse * sum) / scales[perm[j]];
        if (!std.math.isFinite(se[perm[j]])) return error.NumericalFailure;
    }
    return .{ .coefficients = b, .standard_errors = se, .sse = sse, .sst = sst, .mean = mean, .n = n, .p = p };
}

fn unsupported(cx: proc.ProcCtx, token: Token) diag.Error {
    diag.markGap();
    return cx.diags.fail(error.ParseError, token.line, "PROC REG does not support '{s}' in this release", .{token.text});
}

fn expect(cx: proc.ProcCtx, toks: []const Token, i: usize, tag: @import("lexer.zig").Tag) diag.Error!void {
    if (i >= toks.len or toks[i].tag != tag)
        return cx.diags.fail(error.ParseError, if (i < toks.len) toks[i].line else toks[0].line, "Malformed PROC REG statement", .{});
}

pub fn run(cx: proc.ProcCtx, out: *std.ArrayList(u8), toks: []const Token) diag.Error!void {
    const a = cx.arena;
    var i: usize = 2;
    try expect(cx, toks, i, .name);
    if (!eq(toks[i].text, "data")) return unsupported(cx, toks[i]);
    i += 1;
    try expect(cx, toks, i, .eq);
    i += 1;
    try expect(cx, toks, i, .name);
    var dataset_name = toks[i].text;
    i += 1;
    if (i < toks.len and toks[i].tag == .dot) {
        i += 1;
        try expect(cx, toks, i, .name);
        dataset_name = try std.fmt.allocPrint(a, "{s}.{s}", .{ dataset_name, toks[i].text });
        i += 1;
    }
    if (i < toks.len and toks[i].tag != .semicolon) return unsupported(cx, toks[i]);
    try expect(cx, toks, i, .semicolon);
    i += 1;
    var response: ?[]const u8 = null;
    var names: std.ArrayList([]const u8) = .empty;
    var model_line = toks[0].line;
    while (i < toks.len and toks[i].tag != .eof) {
        if (toks[i].tag == .semicolon) {
            i += 1;
            continue;
        }
        const t = toks[i];
        if (t.tag != .name) return cx.diags.fail(error.ParseError, t.line, "Malformed PROC REG statement", .{});
        if (eq(t.text, "run") or eq(t.text, "quit")) {
            i += 1;
            try expect(cx, toks, i, .semicolon);
            i += 1;
            continue;
        }
        if (parser.isMidStepSkippable(t.text)) {
            while (i < toks.len and toks[i].tag != .semicolon and toks[i].tag != .eof) i += 1;
            continue;
        }
        if (!eq(t.text, "model") or response != null) return unsupported(cx, t);
        model_line = t.line;
        i += 1;
        try expect(cx, toks, i, .name);
        response = toks[i].text;
        i += 1;
        try expect(cx, toks, i, .eq);
        i += 1;
        while (i < toks.len and toks[i].tag == .name) : (i += 1) {
            for (names.items) |name| if (eq(name, toks[i].text))
                return cx.diags.fail(error.ParseError, toks[i].line, "Duplicate predictor {s}", .{name});
            try names.append(a, toks[i].text);
        }
        if (i < toks.len and toks[i].tag != .semicolon) return unsupported(cx, toks[i]);
        try expect(cx, toks, i, .semicolon);
        i += 1;
    }
    if (response == null or names.items.len == 0)
        return cx.diags.fail(error.ParseError, model_line, "PROC REG requires MODEL response = predictor(s)", .{});
    const original = cx.lib.find(dataset_name) orelse
        return cx.diags.fail(error.ExecError, model_line, "Dataset {s} not found", .{dataset_name});
    const ds = try proc.procInput(a, original, toks, cx.diags);
    const ycol = ds.indexOf(response.?) orelse
        return cx.diags.fail(error.ExecError, model_line, "Variable {s} not found", .{response.?});
    if (ds.columns.items[ycol].type != .num)
        return cx.diags.fail(error.ExecError, model_line, "PROC REG response must be numeric", .{});
    const p = names.items.len + 1;
    const columns = try a.alloc(usize, names.items.len);
    for (names.items, 0..) |name, j| {
        columns[j] = ds.indexOf(name) orelse return cx.diags.fail(error.ExecError, model_line, "Variable {s} not found", .{name});
        if (ds.columns.items[columns[j]].type != .num)
            return cx.diags.fail(error.ExecError, model_line, "Predictor {s} must be numeric", .{name});
    }
    var x: std.ArrayList(f64) = .empty;
    var y: std.ArrayList(f64) = .empty;
    rows: for (ds.rows.items) |row| {
        if (row[ycol].isMissing()) continue;
        for (columns) |col| if (row[col].isMissing()) continue :rows;
        if (!std.math.isFinite(row[ycol].num)) return cx.diags.fail(error.ExecError, model_line, "Non-finite model value", .{});
        try x.append(a, 1);
        for (columns) |col| {
            if (!std.math.isFinite(row[col].num)) return cx.diags.fail(error.ExecError, model_line, "Non-finite model value", .{});
            try x.append(a, row[col].num);
        }
        try y.append(a, row[ycol].num);
    }
    const result = fit(a, x.items, y.items, p) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.RankDeficient => return cx.diags.fail(error.ExecError, model_line, "Rank-deficient model: aliased coefficients are not supported", .{}),
        error.InsufficientObservations => return cx.diags.fail(error.ExecError, model_line, "Insufficient observations: positive residual degrees of freedom required", .{}),
        error.NumericalFailure => return cx.diags.fail(error.ExecError, model_line, "Numerical overflow or instability in PROC REG", .{}),
    };
    try render(a, out, result, response.?, names.items, ds.rows.items.len);
}

fn number(a: std.mem.Allocator, x: f64) ![]const u8 {
    if (!std.math.isFinite(x)) return ".";
    return std.fmt.allocPrint(a, "{d:.10}", .{x});
}
fn append(a: std.mem.Allocator, out: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
    try out.appendSlice(a, try std.fmt.allocPrint(a, fmt, args));
}
fn render(a: std.mem.Allocator, out: *std.ArrayList(u8), f: Fit, response: []const u8, names: []const []const u8, read: usize) !void {
    const nan = std.math.nan(f64);
    const df: f64 = @floatFromInt(f.n - f.p);
    const model_df: f64 = @floatFromInt(f.p - 1);
    const mse = f.sse / df;
    const ssmodel = @max(0, f.sst - f.sse);
    const fstat = if (mse > 0) (ssmodel / model_df) / mse else nan;
    const fp = if (mse > 0) betaI(df / (df + model_df * fstat), df / 2, model_df / 2) else nan;
    const rsq = if (f.sst > 0) 1 - f.sse / f.sst else nan;
    const adj = if (f.sst > 0) 1 - (1 - rsq) * @as(f64, @floatFromInt(f.n - 1)) / df else nan;
    try append(a, out, "The REG Procedure\nDependent Variable: {s}\nObservations Read: {d}\nObservations Used: {d}\n\nAnalysis of Variance\nSource\tDF\tSum of Squares\tMean Square\tF Value\tPr > F\n", .{ response, read, f.n });
    try append(a, out, "Model\t{d}\t{s}\t{s}\t{s}\t{s}\n", .{ f.p - 1, try number(a, ssmodel), try number(a, ssmodel / model_df), try number(a, fstat), try number(a, fp) });
    try append(a, out, "Error\t{d}\t{s}\t{s}\t.\t.\nCorrected Total\t{d}\t{s}\t.\t.\t.\n", .{ f.n - f.p, try number(a, f.sse), try number(a, mse), f.n - 1, try number(a, f.sst) });
    try append(a, out, "\nRoot MSE\t{s}\nDependent Mean\t{s}\nR-Square\t{s}\nAdj R-Sq\t{s}\n\nParameter Estimates\nVariable\tDF\tEstimate\tStandard Error\tt Value\tPr > |t|\n", .{ try number(a, @sqrt(mse)), try number(a, f.mean), try number(a, rsq), try number(a, adj) });
    for (f.coefficients, f.standard_errors, 0..) |b, se, j| {
        const t = if (se > 0) b / se else nan;
        const probability = if (se > 0) betaI(df / (df + t * t), df / 2, 0.5) else nan;
        try append(a, out, "{s}\t1\t{s}\t{s}\t{s}\t{s}\n", .{ if (j == 0) "Intercept" else names[j - 1], try number(a, b), try number(a, se), try number(a, t), try number(a, probability) });
    }
    if (f.sse == 0) try append(a, out, "NOTE: Perfect fit; zero-variance inference is displayed as missing (.).\n", .{});
    if (f.sst == 0) try append(a, out, "NOTE: Constant response; R-square statistics are undefined (.).\n", .{});
}

test "OLS analytic coefficients and standard errors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try fit(arena.allocator(), &.{ 1, 1, 1, 2, 1, 3, 1, 4, 1, 5 }, &.{ 2, 4, 5, 4, 5 }, 2);
    try std.testing.expectApproxEqAbs(@as(f64, 2.2), result.coefficients[0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.6), result.coefficients[1], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 2.4), result.sse, 1e-12);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 0.88)), result.standard_errors[0], 1e-12);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 0.08)), result.standard_errors[1], 1e-12);
}

test "multiple predictors, scaling, and pivot permutation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try fit(arena.allocator(), &.{ 1, -1e8, -1, 1, -1e8, 1, 1, 0, -1, 1, 0, 1, 1, 1e8, -1, 1, 1e8, 1 }, &.{ 4, -4, 4, -4, 10, 2 }, 3);
    try std.testing.expectApproxEqAbs(@as(f64, 2), result.coefficients[0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 3e-8), result.coefficients[1], 1e-20);
    try std.testing.expectApproxEqAbs(@as(f64, -4), result.coefficients[2], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 12), result.sse, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1e-8), result.standard_errors[1], 1e-20);
}

test "degenerate and perfect fits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectError(error.RankDeficient, fit(a, &.{ 1, 1, 1, 1, 1, 1 }, &.{ 1, 2, 3 }, 2));
    try std.testing.expectError(error.InsufficientObservations, fit(a, &.{ 1, 1, 1, 2 }, &.{ 1, 2 }, 2));
    const exact = try fit(a, &.{ 1, 1, 1, 2, 1, 3 }, &.{ 3, 5, 7 }, 2);
    try std.testing.expectEqual(@as(f64, 0), exact.sse);
    const constant = try fit(a, &.{ 1, 1, 1, 2, 1, 3 }, &.{ 4, 4, 4 }, 2);
    try std.testing.expectEqual(@as(f64, 0), constant.sst);
}
