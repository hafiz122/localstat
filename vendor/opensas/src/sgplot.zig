const std = @import("std");
const diag = @import("diag.zig");
const lex = @import("lexer.zig");
const Dataset = @import("dataset.zig").Dataset;
const Value = @import("value.zig").Value;
const proc = @import("proc.zig");

const Token = lex.Token;
const Kind = enum { scatter, series, vbar, hbar };
const Stat = enum { freq, sum, mean };
const Spec = struct {
    kind: Kind,
    x: ?[]const u8 = null,
    y: ?[]const u8 = null,
    category: ?[]const u8 = null,
    response: ?[]const u8 = null,
    stat: Stat = .freq,
};
const Point = struct { x: f64, y: f64 };
const Bar = struct { label: []const u8, value: f64, count: usize, sort_numeric: ?f64 = null };
const Series = struct { kind: Kind, points: []const Point };

fn eq(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

fn err(cx: proc.ProcCtx, line: usize, comptime format: []const u8, args: anytype) diag.Error {
    return cx.diags.fail(error.ParseError, line, format, args);
}

fn gap(cx: proc.ProcCtx, line: usize, comptime format: []const u8, args: anytype) diag.Error {
    diag.markGap();
    return err(cx, line, format, args);
}

fn append(a: std.mem.Allocator, out: *std.ArrayList(u8), comptime format: []const u8, args: anytype) !void {
    try out.appendSlice(a, try std.fmt.allocPrint(a, format, args));
}

fn escapeXml(a: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    for (value) |ch| switch (ch) {
        '&' => try out.appendSlice(a, "&amp;"),
        '<' => try out.appendSlice(a, "&lt;"),
        '>' => try out.appendSlice(a, "&gt;"),
        '"' => try out.appendSlice(a, "&quot;"),
        '\'' => try out.appendSlice(a, "&apos;"),
        else => if (ch >= 0x20) try out.append(a, ch),
    };
}

fn num(v: Value) ?f64 {
    return switch (v) {
        .num => |x| if (std.math.isFinite(x)) x else null,
        .str => null,
    };
}

fn label(a: std.mem.Allocator, v: Value) ![]const u8 {
    return switch (v) {
        .num => |x| if (std.math.isNan(x)) "." else try std.fmt.allocPrint(a, "{d}", .{x}),
        .str => |s| s,
    };
}

fn option(cx: proc.ProcCtx, tokens: []const Token, pos: *usize, keyword: []const u8) diag.Error!?[]const u8 {
    const i = pos.*;
    if (i >= tokens.len or !eq(tokens[i].text, keyword)) return null;
    if (i + 2 >= tokens.len or tokens[i + 1].tag != .eq or
        (tokens[i + 2].tag != .name and tokens[i + 2].tag != .string and tokens[i + 2].tag != .number))
        return err(cx, tokens[i].line, "PROC SGPLOT: {s}= requires a value", .{keyword});
    pos.* += 3;
    return tokens[i + 2].text;
}

fn parsePlot(cx: proc.ProcCtx, tokens: []const Token) diag.Error!Spec {
    const head = tokens[0];
    const kind: Kind = if (eq(head.text, "scatter")) .scatter else if (eq(head.text, "series")) .series else if (eq(head.text, "vbar")) .vbar else .hbar;
    var spec = Spec{ .kind = kind };
    var i: usize = 1;
    var stat_explicit = false;
    if (kind == .vbar or kind == .hbar) {
        if (i >= tokens.len or tokens[i].tag != .name)
            return err(cx, head.line, "PROC SGPLOT: {s} requires a category variable", .{head.text});
        spec.category = tokens[i].text;
        i += 1;
    }
    if (i < tokens.len and tokens[i].tag == .slash) i += 1;
    while (i < tokens.len) {
        if (try option(cx, tokens, &i, "x")) |v| {
            spec.x = v;
        } else if (try option(cx, tokens, &i, "y")) |v| {
            spec.y = v;
        } else if (try option(cx, tokens, &i, "response")) |v| {
            spec.response = v;
            if (!stat_explicit) spec.stat = .sum;
        } else if (try option(cx, tokens, &i, "stat")) |v| {
            stat_explicit = true;
            if (eq(v, "freq")) spec.stat = .freq else if (eq(v, "sum")) spec.stat = .sum else if (eq(v, "mean")) spec.stat = .mean else
                return gap(cx, tokens[i - 3].line, "PROC SGPLOT: STAT={s} is not supported", .{v});
        } else {
            return gap(cx, tokens[i].line, "PROC SGPLOT: plot option {s} is not supported", .{tokens[i].text});
        }
    }
    if ((kind == .scatter or kind == .series) and (spec.x == null or spec.y == null))
        return err(cx, head.line, "PROC SGPLOT: {s} requires X= and Y=", .{head.text});
    if ((kind == .scatter or kind == .series) and (spec.category != null or spec.response != null))
        return err(cx, head.line, "PROC SGPLOT: {s} has invalid plot options", .{head.text});
    if ((kind == .vbar or kind == .hbar) and (spec.x != null or spec.y != null))
        return err(cx, head.line, "PROC SGPLOT: bar statements use a category variable", .{});
    if ((kind == .vbar or kind == .hbar) and spec.stat != .freq and spec.response == null)
        return err(cx, head.line, "PROC SGPLOT: STAT={s} requires RESPONSE=", .{@tagName(spec.stat)});
    return spec;
}

fn column(cx: proc.ProcCtx, ds: *Dataset, name: []const u8, numeric: bool, line: usize) diag.Error!usize {
    const idx = ds.indexOf(name) orelse return err(cx, line, "PROC SGPLOT: variable {s} not found", .{name});
    if (numeric and ds.columns.items[idx].type != .num)
        return err(cx, line, "PROC SGPLOT: variable {s} must be numeric", .{name});
    return idx;
}

fn points(cx: proc.ProcCtx, ds: *Dataset, spec: Spec, line: usize) diag.Error![]const Point {
    const xcol = try column(cx, ds, spec.x.?, true, line);
    const ycol = try column(cx, ds, spec.y.?, true, line);
    var result: std.ArrayList(Point) = .empty;
    for (ds.rows.items) |row| {
        const x = num(row[xcol]) orelse continue;
        const y = num(row[ycol]) orelse continue;
        try result.append(cx.arena, .{ .x = x, .y = y });
    }
    return result.items;
}

fn bars(cx: proc.ProcCtx, ds: *Dataset, spec: Spec, line: usize) diag.Error![]const Bar {
    const ccol = try column(cx, ds, spec.category.?, false, line);
    const rcol = if (spec.response) |name| try column(cx, ds, name, true, line) else null;
    var result: std.ArrayList(Bar) = .empty;
    for (ds.rows.items) |row| {
        const cat = try label(cx.arena, row[ccol]);
        if (cat.len == 0 or std.mem.eql(u8, cat, ".")) continue;
        const response = if (rcol) |c| num(row[c]) else null;
        if (rcol != null and response == null) continue;
        var j: usize = 0;
        while (j < result.items.len and !std.mem.eql(u8, result.items[j].label, cat)) : (j += 1) {}
        if (j == result.items.len) try result.append(cx.arena, .{
            .label = cat,
            .value = 0,
            .count = 0,
            .sort_numeric = switch (row[ccol]) { .num => |v| v, .str => null },
        });
        result.items[j].count += 1;
        result.items[j].value += if (spec.stat == .freq) 1 else response.?;
    }
    if (spec.stat == .mean) {
        for (result.items) |*bar| bar.value /= @as(f64, @floatFromInt(bar.count));
    }
    std.mem.sort(Bar, result.items, ds.columns.items[ccol].type == .num, struct {
        fn less(numeric: bool, lhs: Bar, rhs: Bar) bool {
            if (numeric) return lhs.sort_numeric.? < rhs.sort_numeric.?;
            return std.mem.order(u8, lhs.label, rhs.label) == .lt;
        }
    }.less);
    return result.items;
}

fn bounds(series: []const Series) struct { xmin: f64, xmax: f64, ymin: f64, ymax: f64 } {
    var xmin = std.math.inf(f64);
    var xmax = -std.math.inf(f64);
    var ymin = std.math.inf(f64);
    var ymax = -std.math.inf(f64);
    for (series) |s| for (s.points) |p| {
        xmin = @min(xmin, p.x);
        xmax = @max(xmax, p.x);
        ymin = @min(ymin, p.y);
        ymax = @max(ymax, p.y);
    };
    if (!std.math.isFinite(xmin)) return .{ .xmin = 0, .xmax = 1, .ymin = 0, .ymax = 1 };
    if (xmin == xmax) { xmin -= 0.5; xmax += 0.5; }
    if (ymin == ymax) { ymin -= 0.5; ymax += 0.5; }
    return .{ .xmin = xmin, .xmax = xmax, .ymin = ymin, .ymax = ymax };
}

const Axis = struct {
    low: f64,
    high: f64,
    step: f64,

    fn ticks(self: Axis) usize {
        return @min(12, @as(usize, @intFromFloat(@round((self.high - self.low) / self.step))) + 1);
    }

    fn tick(self: Axis, index: usize) f64 {
        const value = self.low + self.step * @as(f64, @floatFromInt(index));
        return if (@abs(value) < self.step * 1e-9) 0 else value;
    }
};

fn niceAxis(minimum: f64, maximum: f64, include_zero: bool) Axis {
    var low = if (include_zero) @min(minimum, 0) else minimum;
    var high = if (include_zero) @max(maximum, 0) else maximum;
    if (low == high) {
        const padding = @max(1, @abs(low) * 0.1);
        low = if (include_zero) 0 else low - padding;
        high += padding;
    }
    const raw = (high - low) / 5;
    const magnitude = std.math.pow(f64, 10, @floor(@log10(raw)));
    const ratio = raw / magnitude;
    const rounded: f64 = if (ratio <= 1) 1 else if (ratio <= 2) 2 else if (ratio <= 5) 5 else 10;
    const step = rounded * magnitude;
    var tick_low = @floor(low / step) * step;
    var tick_high = @ceil(high / step) * step;
    if (!include_zero) {
        if (@abs(tick_low - minimum) <= step * 1e-9) tick_low -= step;
        if (@abs(tick_high - maximum) <= step * 1e-9) tick_high += step;
    }
    return .{ .low = tick_low, .high = tick_high, .step = step };
}

fn xySvg(a: std.mem.Allocator, series: []const Series, xname: []const u8, yname: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    const b = bounds(series);
    const xaxis = niceAxis(b.xmin, b.xmax, false);
    const yaxis = niceAxis(b.ymin, b.ymax, false);
    const left: f64 = 70;
    const right: f64 = 604;
    const top: f64 = 30;
    const bottom: f64 = 400;
    try out.appendSlice(a, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"640\" height=\"480\" viewBox=\"0 0 640 480\" role=\"img\" aria-label=\"SGPLOT chart\"><rect width=\"640\" height=\"480\" fill=\"white\"/><rect x=\"70\" y=\"30\" width=\"534\" height=\"370\" fill=\"white\" stroke=\"#a9b4bf\" stroke-width=\"1\"/><g font-family=\"Arial,Helvetica,sans-serif\" fill=\"#4c5965\" font-size=\"12\">");
    for (0..xaxis.ticks()) |k| {
        const value = xaxis.tick(k);
        const x = left + (value - xaxis.low) / (xaxis.high - xaxis.low) * (right - left);
        try append(a, &out, "<line x1=\"{d:.2}\" y1=\"400\" x2=\"{d:.2}\" y2=\"405\" stroke=\"#677684\"/><text class=\"value-tick\" x=\"{d:.2}\" y=\"423\" text-anchor=\"middle\">{d}</text>", .{ x, x, x, value });
    }
    for (0..yaxis.ticks()) |k| {
        const value = yaxis.tick(k);
        const y = bottom - (value - yaxis.low) / (yaxis.high - yaxis.low) * (bottom - top);
        try append(a, &out, "<line x1=\"65\" y1=\"{d:.2}\" x2=\"70\" y2=\"{d:.2}\" stroke=\"#677684\"/><text class=\"value-tick\" x=\"59\" y=\"{d:.2}\" text-anchor=\"end\">{d}</text>", .{ y, y, y + 4, value });
    }
    try out.appendSlice(a, "<text x=\"337\" y=\"458\" text-anchor=\"middle\" font-size=\"13\">");
    try escapeXml(a, &out, xname);
    try out.appendSlice(a, "</text><text transform=\"translate(19 215) rotate(-90)\" text-anchor=\"middle\" font-size=\"13\">");
    try escapeXml(a, &out, yname);
    try out.appendSlice(a, "</text></g>");
    const colors = [_][]const u8{ "#3f79ad", "#cf6d48", "#689c75", "#916b9f" };
    for (series, 0..) |s, si| {
        const color = colors[si % colors.len];
        if (s.kind == .series) {
            try append(a, &out, "<polyline class=\"plot-series\" fill=\"none\" stroke=\"{s}\" stroke-width=\"2\" points=\"", .{color});
            for (s.points) |p| try append(a, &out, "{d:.2},{d:.2} ", .{ left + (p.x - xaxis.low) / (xaxis.high - xaxis.low) * (right - left), bottom - (p.y - yaxis.low) / (yaxis.high - yaxis.low) * (bottom - top) });
            try out.appendSlice(a, "\"/>");
        } else {
            for (s.points) |p| {
                try append(a, &out, "<circle class=\"plot-point\" cx=\"{d:.2}\" cy=\"{d:.2}\" r=\"3.5\" fill=\"none\" stroke=\"{s}\" stroke-width=\"1.5\"/>", .{ left + (p.x - xaxis.low) / (xaxis.high - xaxis.low) * (right - left), bottom - (p.y - yaxis.low) / (yaxis.high - yaxis.low) * (bottom - top), color });
            }
        }
    }
    try out.appendSlice(a, "</svg>\n");
    return out.items;
}

fn barSvg(a: std.mem.Allocator, spec: Spec, data: []const Bar) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    const horizontal = spec.kind == .hbar;
    const count = @max(data.len, 1);
    const height = if (horizontal) @max(@as(usize, 480), 104 + count * 38) else 480;
    const maxv = blk: {
        var v: f64 = 0;
        for (data) |bar| v = @max(v, bar.value);
        break :blk v;
    };
    const axis = niceAxis(0, maxv, true);
    const top: f64 = 34;
    const bottom = @as(f64, @floatFromInt(height)) - 80;
    const right: f64 = 604;
    var max_label_len: usize = 0;
    for (data) |bar| max_label_len = @max(max_label_len, bar.label.len);
    const left: f64 = if (horizontal) @min(230, @max(88, @as(f64, @floatFromInt(max_label_len)) * 7 + 18)) else 70;
    try append(a, &out, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"640\" height=\"{d}\" viewBox=\"0 0 640 {d}\" role=\"img\" aria-label=\"SGPLOT bar chart\"><rect width=\"640\" height=\"{d}\" fill=\"white\"/><rect x=\"{d:.2}\" y=\"{d:.2}\" width=\"{d:.2}\" height=\"{d:.2}\" fill=\"white\" stroke=\"#a9b4bf\" stroke-width=\"1\"/><g font-family=\"Arial,Helvetica,sans-serif\" fill=\"#4c5965\" font-size=\"12\">", .{ height, height, height, left, top, right - left, bottom - top });
    if (horizontal) {
        for (0..axis.ticks()) |k| {
            const value = axis.tick(k);
            const x = left + (value - axis.low) / (axis.high - axis.low) * (right - left);
            try append(a, &out, "<line x1=\"{d:.2}\" y1=\"{d:.2}\" x2=\"{d:.2}\" y2=\"{d:.2}\" stroke=\"#677684\"/><text class=\"value-tick\" x=\"{d:.2}\" y=\"{d:.2}\" text-anchor=\"middle\">{d}</text>", .{ x, bottom, x, bottom + 5, x, bottom + 22, value });
        }
        const slot = (bottom - top) / @as(f64, @floatFromInt(count));
        for (data, 0..) |bar, i| {
            const y = bottom - (@as(f64, @floatFromInt(i)) + 1) * slot + slot * 0.1;
            const bar_height = slot * 0.8;
            const width = bar.value / (axis.high - axis.low) * (right - left);
            try append(a, &out, "<rect class=\"plot-bar\" data-value=\"{d}\" x=\"{d:.2}\" y=\"{d:.2}\" width=\"{d:.2}\" height=\"{d:.2}\" fill=\"#8fb9dc\" stroke=\"#5a8eBA\" stroke-width=\"0.6\"/><text class=\"category-label\" x=\"{d:.2}\" y=\"{d:.2}\" text-anchor=\"end\"", .{ bar.value, left, y, width, bar_height, left - 9, y + bar_height / 2 + 4 });
            if (@as(f64, @floatFromInt(bar.label.len)) * 7 > left - 22) try append(a, &out, " textLength=\"{d:.2}\" lengthAdjust=\"spacingAndGlyphs\"", .{left - 22});
            try out.appendSlice(a, ">");
            try escapeXml(a, &out, bar.label);
            try out.appendSlice(a, "</text>");
        }
        try append(a, &out, "<text x=\"{d:.2}\" y=\"{d:.2}\" text-anchor=\"middle\" font-size=\"13\">", .{ (left + right) / 2, @as(f64, @floatFromInt(height)) - 20 });
    } else {
        for (0..axis.ticks()) |k| {
            const value = axis.tick(k);
            const y = bottom - (value - axis.low) / (axis.high - axis.low) * (bottom - top);
            try append(a, &out, "<line x1=\"65\" y1=\"{d:.2}\" x2=\"70\" y2=\"{d:.2}\" stroke=\"#677684\"/><text class=\"value-tick\" x=\"59\" y=\"{d:.2}\" text-anchor=\"end\">{d}</text>", .{ y, y, y + 4, value });
        }
        const slot = (right - left) / @as(f64, @floatFromInt(count));
        const label_width = @as(f64, @floatFromInt(max_label_len)) * 7 + 12;
        const label_stride = @max(1, @as(usize, @intFromFloat(@ceil(label_width / slot))));
        for (data, 0..) |bar, i| {
            const x = left + (@as(f64, @floatFromInt(i)) + 0.1) * slot;
            const width = slot * 0.8;
            const bar_height = bar.value / (axis.high - axis.low) * (bottom - top);
            try append(a, &out, "<rect class=\"plot-bar\" data-value=\"{d}\" x=\"{d:.2}\" y=\"{d:.2}\" width=\"{d:.2}\" height=\"{d:.2}\" fill=\"#8fb9dc\" stroke=\"#5a8eBA\" stroke-width=\"0.6\"/>", .{ bar.value, x, bottom - bar_height, width, bar_height });
            if (i % label_stride == 0) {
                try append(a, &out, "<text class=\"category-label\" x=\"{d:.2}\" y=\"{d:.2}\" text-anchor=\"middle\">", .{ x + width / 2, bottom + 20 });
                try escapeXml(a, &out, bar.label);
                try out.appendSlice(a, "</text>");
            }
        }
        try out.appendSlice(a, "<text x=\"337\" y=\"455\" text-anchor=\"middle\" font-size=\"13\">");
        try escapeXml(a, &out, spec.category.?);
        try out.appendSlice(a, "</text><text transform=\"translate(18 215) rotate(-90)\" text-anchor=\"middle\" font-size=\"13\">");
    }
    const value_label = if (spec.response) |response| try std.fmt.allocPrint(a, "{s} ({s})", .{ response, switch (spec.stat) { .freq => "Frequency", .sum => "Sum", .mean => "Mean" } }) else "Frequency";
    try escapeXml(a, &out, value_label);
    try out.appendSlice(a, "</text></g>");
    try out.appendSlice(a, "</svg>\n");
    return out.items;
}

pub fn run(cx: proc.ProcCtx, out: *std.ArrayList(u8), toks: []const Token) diag.Error!void {
    if (cx.plots == null) return gap(cx, toks[1].line, "PROC SGPLOT requires --results-dir to save the chart", .{});
    var input_name: ?[]const u8 = null;
    var i: usize = 2;
    while (i < toks.len and toks[i].tag != .semicolon) {
        if (eq(toks[i].text, "data")) {
            const line = toks[i].line;
            if (i + 2 >= toks.len or toks[i + 1].tag != .eq or toks[i + 2].tag != .name)
                return err(cx, line, "PROC SGPLOT: DATA= requires a data set name", .{});
            input_name = toks[i + 2].text;
            i += 3;
            if (i + 1 < toks.len and toks[i].tag == .dot and toks[i + 1].tag == .name) {
                input_name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ input_name.?, toks[i + 1].text });
                i += 2;
            }
            if (i < toks.len and toks[i].tag == .lparen) {
                var depth: usize = 1;
                i += 1;
                while (i < toks.len and depth > 0) : (i += 1) {
                    if (toks[i].tag == .lparen) depth += 1;
                    if (toks[i].tag == .rparen) depth -= 1;
                }
                if (depth != 0) return err(cx, line, "PROC SGPLOT: DATA= options have an unclosed parenthesis", .{});
            }
        } else return gap(cx, toks[i].line, "PROC SGPLOT: option {s} is not supported", .{toks[i].text});
    }
    if (i < toks.len) i += 1;
    var specs: std.ArrayList(Spec) = .empty;
    while (i < toks.len and toks[i].tag != .eof) {
        if (eq(toks[i].text, "run") or eq(toks[i].text, "quit")) break;
        const start = i;
        while (i < toks.len and toks[i].tag != .semicolon and toks[i].tag != .eof) i += 1;
        const statement = toks[start..i];
        if (i < toks.len and toks[i].tag == .semicolon) i += 1;
        if (statement.len == 0) continue;
        if (eq(statement[0].text, "where")) continue; // procInput evaluates WHERE.
        if (eq(statement[0].text, "scatter") or eq(statement[0].text, "series") or eq(statement[0].text, "vbar") or eq(statement[0].text, "hbar")) {
            try specs.append(cx.arena, try parsePlot(cx, statement));
        } else return gap(cx, statement[0].line, "PROC SGPLOT: statement {s} is not supported", .{statement[0].text});
    }
    if (specs.items.len == 0) return err(cx, toks[1].line, "PROC SGPLOT: at least one plot statement is required", .{});
    if (specs.items.len > 1) return gap(cx, toks[1].line, "PROC SGPLOT: plot overlays are not supported", .{});
    const is_bar = specs.items[0].kind == .vbar or specs.items[0].kind == .hbar;
    const raw = if (input_name) |name| cx.lib.find(name) else if (cx.lib.sets.items.len > 0) cx.lib.sets.items[cx.lib.sets.items.len - 1] else null;
    const ds = try proc.procInput(cx.arena, raw orelse return err(cx, toks[1].line, "PROC SGPLOT: input data set {s} does not exist", .{input_name orelse "_last_"}), toks, cx.diags);
    if (ds.rows.items.len > 20_000) return gap(cx, toks[1].line, "PROC SGPLOT: charts above 20,000 observations are not supported", .{});
    const svg = if (is_bar) blk: {
        const data = try bars(cx, ds, specs.items[0], toks[1].line);
        if (data.len > 100) return gap(cx, toks[1].line, "PROC SGPLOT: charts above 100 categories are not supported", .{});
        for (data) |bar| if (bar.value < 0) return gap(cx, toks[1].line, "PROC SGPLOT: negative bar values are not supported", .{});
        break :blk try barSvg(cx.arena, specs.items[0], data);
    } else blk: {
        var series: std.ArrayList(Series) = .empty;
        for (specs.items) |spec| try series.append(cx.arena, .{ .kind = spec.kind, .points = try points(cx, ds, spec, toks[1].line) });
        break :blk try xySvg(cx.arena, series.items, specs.items[0].x.?, specs.items[0].y.?);
    };
    if (cx.plots) |collector| try collector.add(.{ .procedure = "SGPLOT", .title = "The SGPLOT Procedure", .svg = svg });
    try out.appendSlice(cx.arena, "The SGPLOT Procedure\n");
}

test "SVG escapes category labels and aggregates bar values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "work.test");
    _ = try ds.addColumn("category", .char);
    _ = try ds.addColumn("amount", .num);
    try ds.appendRow(&.{ .{ .str = "A&B" }, .{ .num = 2 } });
    try ds.appendRow(&.{ .{ .str = "A&B" }, .{ .num = 3 } });
    var lib = @import("exec.zig").Library.init(a);
    var diags = diag.Diagnostics.init(a);
    const cx = proc.ProcCtx{ .arena = a, .lib = &lib, .diags = &diags };
    const data = try bars(cx, &ds, .{ .kind = .vbar, .category = "category", .response = "amount", .stat = .sum }, 1);
    try std.testing.expectEqual(@as(usize, 1), data.len);
    try std.testing.expectEqual(@as(f64, 5), data[0].value);
    const svg = try barSvg(a, .{ .kind = .vbar, .category = "category" }, data);
    try std.testing.expect(std.mem.indexOf(u8, svg, "A&amp;B") != null);
}

test "response default and explicit frequency are independent of option order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var lib = @import("exec.zig").Library.init(a);
    const cx = proc.ProcCtx{ .arena = a, .lib = &lib, .diags = &diags };
    const one = [_]Token{
        .{ .tag = .name, .text = "vbar" }, .{ .tag = .name, .text = "group" }, .{ .tag = .slash },
        .{ .tag = .name, .text = "response" }, .{ .tag = .eq }, .{ .tag = .name, .text = "amount" },
    };
    try std.testing.expectEqual(Stat.sum, (try parsePlot(cx, &one)).stat);
    const two = [_]Token{
        .{ .tag = .name, .text = "vbar" }, .{ .tag = .name, .text = "group" }, .{ .tag = .slash },
        .{ .tag = .name, .text = "stat" }, .{ .tag = .eq }, .{ .tag = .name, .text = "freq" },
        .{ .tag = .name, .text = "response" }, .{ .tag = .eq }, .{ .tag = .name, .text = "amount" },
    };
    try std.testing.expectEqual(Stat.freq, (try parsePlot(cx, &two)).stat);
}

test "bars use ascending unformatted category order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "work.categories");
    _ = try ds.addColumn("category", .char);
    try ds.appendRow(&.{.{ .str = "B" }});
    try ds.appendRow(&.{.{ .str = "A" }});
    try ds.appendRow(&.{.{ .str = "C" }});
    var lib = @import("exec.zig").Library.init(a);
    var diags = diag.Diagnostics.init(a);
    const cx = proc.ProcCtx{ .arena = a, .lib = &lib, .diags = &diags };
    const data = try bars(cx, &ds, .{ .kind = .vbar, .category = "category" }, 1);
    try std.testing.expectEqualStrings("A", data[0].label);
    try std.testing.expectEqualStrings("B", data[1].label);
    try std.testing.expectEqualStrings("C", data[2].label);
}

test "scatter SVG has readable ticks and outlined data markers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const plotted = [_]Point{ .{ .x = 1.2, .y = 2.1 }, .{ .x = 9.7, .y = 8.8 } };
    const s = [_]Series{.{ .kind = .scatter, .points = &plotted }};
    const svg = try xySvg(a, &s, "x", "y");
    try std.testing.expect(std.mem.indexOf(u8, svg, "class=\"plot-point\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "fill=\"none\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "class=\"value-tick\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, ">10</text>") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, ">9.700</text>") == null);
}

test "bar SVG exposes zero baseline category labels and plot marks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const data = [_]Bar{ .{ .label = "A", .value = 2, .count = 2 }, .{ .label = "B", .value = 3, .count = 3 } };
    const svg = try barSvg(a, .{ .kind = .vbar, .category = "category" }, &data);
    try std.testing.expect(std.mem.indexOf(u8, svg, "class=\"plot-bar\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "class=\"category-label\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "class=\"value-tick\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, ">0</text>") != null);
}

test "bar frequency with response excludes missing response values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "work.frequency");
    _ = try ds.addColumn("category", .char);
    _ = try ds.addColumn("response", .num);
    try ds.appendRow(&.{ .{ .str = "A" }, .{ .num = 5 } });
    try ds.appendRow(&.{ .{ .str = "A" }, .{ .num = std.math.nan(f64) } });
    var lib = @import("exec.zig").Library.init(a);
    var diags = diag.Diagnostics.init(a);
    const cx = proc.ProcCtx{ .arena = a, .lib = &lib, .diags = &diags };
    const data = try bars(cx, &ds, .{ .kind = .vbar, .category = "category", .response = "response", .stat = .freq }, 1);
    try std.testing.expectEqual(@as(f64, 1), data[0].value);
}

test "long horizontal category labels fit inside the canvas" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const data = [_]Bar{.{ .label = "A category label that would otherwise be clipped", .value = 2, .count = 2 }};
    const svg = try barSvg(a, .{ .kind = .hbar, .category = "category" }, &data);
    try std.testing.expect(std.mem.indexOf(u8, svg, "lengthAdjust=\"spacingAndGlyphs\"") != null);
}

test "constant scatter and zero bars retain finite plot geometry" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const plotted = [_]Point{ .{ .x = 5, .y = 5 }, .{ .x = 5, .y = 5 } };
    const s = [_]Series{.{ .kind = .scatter, .points = &plotted }};
    const scatter = try xySvg(a, &s, "x", "y");
    const zeros = [_]Bar{.{ .label = "A", .value = 0, .count = 1 }};
    const bar = try barSvg(a, .{ .kind = .vbar, .category = "category" }, &zeros);
    for ([_][]const u8{ scatter, bar }) |svg| {
        try std.testing.expect(std.mem.indexOf(u8, svg, "nan") == null);
        try std.testing.expect(std.mem.indexOf(u8, svg, "inf") == null);
    }
    try std.testing.expect(std.mem.indexOf(u8, bar, "class=\"value-tick\"") != null);
}

test "dense vertical bars keep every mark while thinning category labels" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var data: [40]Bar = undefined;
    for (&data, 0..) |*bar, index| {
        bar.* = .{ .label = try std.fmt.allocPrint(a, "C{d:0>2}", .{index}), .value = 1, .count = 1 };
    }
    const svg = try barSvg(a, .{ .kind = .vbar, .category = "category" }, &data);
    try std.testing.expectEqual(@as(usize, 40), std.mem.count(u8, svg, "class=\"plot-bar\""));
    const labels = std.mem.count(u8, svg, "class=\"category-label\"");
    try std.testing.expect(labels > 0 and labels < data.len);
}

test "scatter axes leave room for outlined markers at data extremes" {
    const axis = niceAxis(1, 4, false);
    try std.testing.expect(axis.low < 1);
    try std.testing.expect(axis.high > 4);
}
