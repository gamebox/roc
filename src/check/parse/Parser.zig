const std = @import("std");

const IR = @import("IR.zig");
const NodeList = IR.NodeList;

const tokenize = @import("tokenize.zig");
const TokenizedBuffer = tokenize.TokenizedBuffer;
const Token = tokenize.Token;
const TokenIdx = Token.Idx;

const exitOnOom = @import("../../collections/utils.zig").exitOnOom;

pub const Parser = @This();

allocator: std.mem.Allocator,
pos: TokenIdx,
tok_buf: TokenizedBuffer,
store: IR.NodeStore,
scratch_nodes: std.ArrayList(IR.Node.Idx),
diagnostics: std.ArrayList(IR.Diagnostic),

pub fn init(gpa: std.mem.Allocator, tokens: TokenizedBuffer) Parser {
    const estimated_node_count = (tokens.tokens.len + 2) / 2;
    const store = IR.NodeStore.initWithCapacity(gpa, estimated_node_count);

    return Parser{
        .allocator = gpa,
        .pos = 0,
        .tok_buf = tokens,
        .store = store,
        .scratch_nodes = std.ArrayList(IR.Node.Idx).init(gpa),
        .diagnostics = std.ArrayList(IR.Diagnostic).init(gpa),
    };
}

pub fn deinit(parser: *Parser) void {
    parser.scratch_nodes.deinit();
    parser.diagnostics.deinit();
}

const TestError = error{TestError};
fn test_parser(source: []const u8, run: fn (parser: Parser) TestError!void) TestError!void {
    const gc = try @import("GenCatData").GenCatData.init(std.testing.allocator);
    defer gc.deinit();
    const messages = [128]tokenize.Diagnostic;
    const tokenizer = tokenize.Tokenizer.init(source, messages[0..], gc, std.testing.allocator);
    tokenizer.tokenize();
    const tok_result = tokenizer.finalize_and_deinit();
    defer tok_result.tokens.deinit();
    const parser = Parser.init(std.testing.allocator, tok_result.tokens);
    defer parser.store.deinit();
    defer parser.scratch_nodes.deinit();
    defer parser.diagnostics.deinit();
    try run(parser);
}

pub fn advance(self: *Parser) void {
    while (true) {
        self.pos += 1;
        if (self.peek() != .Newline) {
            break;
        }
    }
    std.debug.print("Advanced to {s}\n", .{@tagName(self.peek())});
    // We have an EndOfFile token that we never expect to advance past
    std.debug.assert(self.pos < self.tok_buf.tokens.len);
}

pub fn advanceOne(self: *Parser) void {
    self.pos += 1;
    // We have an EndOfFile token that we never expect to advance past
    std.debug.assert(self.pos < self.tok_buf.tokens.len);
}

pub fn peek(self: *Parser) Token.Tag {
    std.debug.assert(self.pos < self.tok_buf.tokens.len);
    return self.tok_buf.tokens.items(.tag)[self.pos];
}

pub fn peekNext(self: Parser) Token.Tag {
    const next = self.pos + 1;
    if (next >= self.tok_buf.tokens.len) {
        return .EndOfFile;
    }
    return self.tok_buf.tokens.items(.tag)[next];
}

pub fn parseFile(self: *Parser) void {
    self.store.emptyScratch();
    _ = self.store.addFile(.{
        .header = IR.NodeStore.HeaderIdx{ .id = 0 },
        .statements = &[0]IR.NodeStore.StatementIdx{},
        .region = .{ .start = 0, .end = 0 },
    });

    const header = self.parseHeader();

    while (self.peek() != .EndOfFile) {
        if (self.peek() == .EndOfFile) {
            break;
        }
        const scratch_top = self.store.scratch_statements.items.len;
        if (self.parseStmt()) |idx| {
            if (self.store.scratch_statements.items.len > scratch_top) {
                self.store.scratch_statements.shrinkRetainingCapacity(scratch_top);
            }
            // ddd
            self.store.scratch_statements.append(idx) catch exitOnOom();
        } else {
            if (self.store.scratch_statements.items.len > scratch_top) {
                self.store.scratch_statements.shrinkRetainingCapacity(scratch_top);
            }
            break;
        }
    }

    std.debug.assert(self.store.scratch_statements.items.len > 0);

    _ = self.store.addFile(.{
        .header = header,
        .statements = self.store.scratch_statements.items[0..],
        .region = .{ .start = 0, .end = @intCast(self.tok_buf.tokens.len - 1) },
    });
}

fn parseCollection(comptime T: type, self: *Parser, end_token: Token.Tag, parser: fn (*Parser) T) void {
    _ = self;
    _ = end_token;
    _ = parser;
}

/// Parses a module header using the following grammar:
///
/// provides_entry :: [LowerIdent|UpperIdent] Comma Newline*
/// package_entry :: LowerIdent Comma "platform"? String Comma
/// app_header :: KwApp Newline* OpenSquare provides_entry* CloseSquare OpenCurly package_entry CloseCurly
pub fn parseHeader(self: *Parser) IR.NodeStore.HeaderIdx {
    if (self.peek() != .KwApp) {
        std.debug.panic("TODO: Support other headers besides app", .{});
    }
    var provides: []TokenIdx = &.{};
    var packages: []IR.NodeStore.RecordFieldIdx = &.{};
    var platform: ?TokenIdx = null;
    var platform_name: ?TokenIdx = null;

    self.advance();

    // Get provides
    if (self.peek() != .OpenSquare) {
        std.debug.panic("TODO: Handle header with no provides open bracket: {s}", .{@tagName(self.peek())});
    }
    self.advance();
    const scratch_top = self.store.scratch_tokens.items.len;
    while (self.peek() != .CloseSquare) {
        if (self.peek() != .LowerIdent and self.peek() != .UpperIdent) {
            std.debug.panic("TODO: Handler header bad provides contents: {s}", .{@tagName(self.peek())});
        }

        self.store.scratch_tokens.append(self.pos) catch exitOnOom();
        self.advance();

        if (self.peek() != .Comma) {
            provides = self.store.scratch_tokens.items[scratch_top..];
            self.store.scratch_tokens.shrinkRetainingCapacity(scratch_top);
            break;
        }
    }
    if (self.peek() != .CloseSquare) {
        std.debug.panic("TODO: Handle Bad header no closing provides bracket: {s}", .{@tagName(self.peek())});
    }
    self.advance();

    // Get platform and packages
    const statement_scratch_top = self.store.scratch_record_fields.items.len;
    if (self.peek() != .OpenCurly) {
        std.debug.panic("TODO: Handle Bad header no packages curly: {s}", .{@tagName(self.peek())});
    }
    self.advance();
    while (self.peek() != .CloseCurly) {
        if (self.peek() != .LowerIdent) {
            std.debug.panic("TODO: Handle bad package identifier: {s}", .{@tagName(self.peek())});
        }
        const name_tok = self.pos;
        self.advance();
        if (self.peek() != .OpColon) {
            std.debug.panic("TODO: Handle bad package identifier: {s}", .{@tagName(self.peek())});
        }
        self.advance();
        if (self.peek() == .KwPlatform) {
            if (platform != null) {
                std.debug.panic("TODO: Handle multiple platforms in app header: {s}", .{@tagName(self.peek())});
            }
            self.advance();
            if (self.peek() != .String) {
                std.debug.panic("TODO: Handle bad package URI in app header: {s}", .{@tagName(self.peek())});
            }
            platform = self.pos;
            platform_name = name_tok;
        } else {
            if (self.peek() != .String) {
                std.debug.panic("TODO: Handle bad package URI in app header: {s}", .{@tagName(self.peek())});
            }
            const value = self.store.addExpr(.{ .string = .{
                .token = self.pos,
                .parts = &.{},
                .region = .{ .start = self.pos, .end = self.pos },
            } });
            self.store.scratch_record_fields.append(self.store.addRecordField(.{
                .name = name_tok,
                .value = value,
                .optional = false,
            })) catch exitOnOom();
        }
        self.advance();
        if (self.peek() != .Comma) {
            packages = self.store.scratch_record_fields.items[statement_scratch_top..];
            self.store.scratch_record_fields.shrinkRetainingCapacity(statement_scratch_top);
        } else {
            self.advance();
        }
    }
    if (self.peek() != .CloseCurly) {
        std.debug.panic("TODO: Handle Bad header no end curly in packages: {s}", .{@tagName(self.peek())});
    }
    self.advance();

    if (platform) |p| {
        if (platform_name) |pn| {
            const header = IR.NodeStore.Header{
                .app = .{
                    .platform = p,
                    .platform_name = pn,
                    .provides = provides,
                    .packages = packages,
                    .region = .{ .start = 0, .end = 0 },
                },
            };
            const idx = self.store.addHeader(header);
            return idx;
        }
    }
    std.debug.panic("TODO: Handle header with no platform: {s}", .{@tagName(self.peek())});
}

pub fn parseStmt(self: *Parser) ?IR.NodeStore.StatementIdx {
    switch (self.peek()) {
        .LowerIdent => {
            const start = self.pos;
            if (self.peekNext() == .OpAssign) {
                self.advance();
                const idx = self.finishParseAssign();
                const patt_idx = self.store.addPattern(.{ .ident = .{
                    .ident_tok = start,
                    .region = .{ .start = start, .end = start },
                } });
                const statement_idx = self.store.addStatement(.{ .decl = .{
                    .pattern = patt_idx,
                    .body = idx,
                    .region = .{ .start = start, .end = self.pos },
                } });
                return statement_idx;
            } else {
                // If not a decl
                const expr = self.store.addExpr(.{ .ident = .{
                    .token = start,
                    .qualifier = null,
                    .region = .{ .start = start, .end = start },
                } });
                const statement_idx = self.store.addStatement(.{ .expr = .{
                    .expr = expr,
                    .region = .{ .start = start, .end = start },
                } });
                return statement_idx;
            }
        },
        .KwImport => {
            const start = self.pos;
            self.advance();
            var qualifier: ?TokenIdx = null;
            if (self.peek() == .LowerIdent) {
                qualifier = self.pos;
                self.advance();
            }
            if (self.peek() == .UpperIdent or (qualifier != null and self.peek() == .NoSpaceDotUpperIdent)) {
                const statement_idx = self.store.addStatement(.{ .import = .{
                    .module_name_tok = self.pos,
                    .qualifier_tok = qualifier,
                    .alias_tok = null,
                    .exposes = &[0]TokenIdx{},
                    .region = .{ .start = start, .end = self.pos },
                } });
                self.advance();

                return statement_idx;
            }
            return null;
        },
        .KwExpect => {
            return null;
        },
        .KwCrash => {
            return null;
        },
        .KwIf => {
            return null;
        },
        .KwWhen => {
            return null;
        },
        .UpperIdent => {
            const start = self.pos;
            const expr = self.parseExpr();
            const statement_idx = self.store.addStatement(.{ .expr = .{
                .expr = expr,
                .region = .{ .start = start, .end = self.pos },
            } });
            return statement_idx;
        },
        else => {
            std.debug.print("Tokens:\n{any}", .{self.tok_buf.tokens.items(.tag)});
            std.debug.panic("todo: emit error, unexpected token {s}", .{@tagName(self.peek())});
            return null;
        },
    }
}

pub fn parsePattern(self: *Parser) IR.NodeStore.PatternIdx {
    const start = self.pos;
    var pattern: ?IR.NodeStore.PatternIdx = null;
    switch (self.peek()) {
        .LowerIdent => {
            pattern = self.store.addPattern(.{ .ident = .{
                .ident_tok = start,
                .region = .{ .start = start, .end = self.pos },
            } });
            self.advance();
        },
        .Underscore => {
            pattern = self.store.addPattern(.{ .underscore = .{
                .region = .{ .start = start, .end = start },
            } });
            self.advance();
        },
        else => {},
    }

    if (pattern) |p| {
        return p;
    }
    std.debug.panic("Should have gotten a valid pattern", .{});
}

pub fn parseExpr(self: *Parser) IR.NodeStore.ExprIdx {
    const start = self.pos;
    var expr: ?IR.NodeStore.ExprIdx = null;
    switch (self.peek()) {
        .UpperIdent => {
            self.advance();

            if (self.peek() == .NoSpaceDotLowerIdent) {
                // This is a qualified lowercase ident
                const id = self.pos;
                self.advance();
                const ident = self.store.addExpr(.{ .ident = .{
                    .token = id,
                    .qualifier = start,
                    .region = .{ .start = start, .end = id },
                } });

                expr = ident;
            } else {
                // This is a Tag
                const tag = self.store.addExpr(.{ .tag = .{
                    .token = start,
                    .region = .{ .start = start, .end = start },
                } });

                expr = tag;
            }
        },
        .LowerIdent => {
            self.advance();
            const ident = self.store.addExpr(.{ .ident = .{
                .token = start,
                .qualifier = null,
                .region = .{ .start = start, .end = start },
            } });

            expr = ident;
        },
        .Int => {
            self.advance();
            expr = self.store.addExpr(.{ .int = .{
                .token = start,
                .region = .{ .start = start, .end = start },
            } });
        },
        .String => {
            self.advance();
            expr = self.store.addExpr(.{ .string = .{
                .token = start,
                .parts = &.{},
                .region = .{ .start = start, .end = start },
            } });
        },
        .StringBegin => {
            // Start parsing string interpolation
            // StringBegin, OpenCurly, <expr>, CloseCurly, StringPart, OpenCurly, <expr>, CloseCurly, StringEnd
            const string_begin_node_idx = self.store.addExpr(.{ .string = .{
                .token = start,
                .parts = &.{},
                .region = .{ .start = start, .end = start },
            } });
            self.advanceOne();
            const scratch_top = self.store.scratch_exprs.items.len;
            defer self.store.scratch_exprs.shrinkRetainingCapacity(scratch_top);
            self.store.scratch_exprs.append(string_begin_node_idx) catch exitOnOom();
            while (self.peek() != .StringEnd and self.peek() != .EndOfFile) {
                if (self.peek() != .OpenCurly) {
                    break;
                }
                self.advanceOne();
                const ex = self.parseExpr();
                std.debug.print("parseExpr: String interpolation, got expression {any}", .{ex});
                self.store.scratch_exprs.append(ex) catch exitOnOom();
                if (self.peek() != .CloseCurly) {
                    continue;
                }
                self.advanceOne();
                if (self.peek() == .StringPart) {
                    std.debug.print("parseExpr: String interpolation, got StringPart", .{});
                    self.store.scratch_exprs.append(self.store.addExpr(.{ .string = .{
                        .token = self.pos,
                        .parts = &.{},
                        .region = .{ .start = self.pos, .end = self.pos },
                    } })) catch exitOnOom();
                    self.advanceOne();
                }
            }
            if (self.peek() == .StringEnd) {
                std.debug.print("parseExpr: String interpolation, got StringEnd", .{});
                self.store.scratch_exprs.append(self.store.addExpr(.{ .string = .{
                    .token = self.pos,
                    .parts = &.{},
                    .region = .{ .start = self.pos, .end = self.pos },
                } })) catch exitOnOom();
                self.advance();
            }
            const parts = self.store.scratch_exprs.items[scratch_top..];
            expr = self.store.addExpr(.{ .string = .{
                .token = start,
                .parts = parts,
                .region = .{ .start = start, .end = self.pos },
            } });
            self.store.scratch_exprs.shrinkRetainingCapacity(scratch_top);
        },
        .OpenSquare => {
            const scratch_top = self.store.scratch_exprs.items.len;
            defer self.store.scratch_exprs.shrinkRetainingCapacity(scratch_top);
            self.advance();
            while (self.peek() != .CloseSquare) {
                self.store.scratch_exprs.append(self.parseExpr()) catch exitOnOom();
                if (self.peek() != .Comma) {
                    break;
                }
                self.advance();
            }
            if (self.peek() != .CloseSquare) {
                // No close problem
                self.addProblem(
                    .{ .region = .{ .start = start, .end = self.pos }, .tag = .list_not_closed },
                );
            }
            self.advance();
            const items = self.store.scratch_exprs.items[scratch_top..];
            expr = self.store.addExpr(.{ .list = .{
                .items = items,
                .region = .{ .start = start, .end = self.pos },
            } });
        },
        .OpBar => {
            const scratch_top = self.store.scratch_patterns.items.len;
            defer self.store.scratch_patterns.shrinkRetainingCapacity(scratch_top);
            self.advance();
            while (self.peek() != .OpBar) {
                self.store.scratch_patterns.append(self.parsePattern()) catch exitOnOom();
                if (self.peek() != .Comma) {
                    break;
                }
                self.advance();
            }
            if (self.peek() != .OpBar) {
                // self.addProblem()
                std.debug.panic("TODO: Add problem for unclosed args, got {s}\n", .{@tagName(self.peek())});
            }
            const args = self.store.scratch_patterns.items[scratch_top..];
            const body = self.finishParseAssign();
            expr = self.store.addExpr(.{ .lambda = .{
                .body = body,
                .args = args,
                .region = .{ .start = start, .end = self.pos },
            } });
        },
        else => {
            std.debug.print("Tokens:\n{any}\n", .{self.tok_buf.tokens.items(.tag)});
            std.debug.panic("todo: emit error - {s}\n", .{@tagName(self.peek())});
        },
    }
    if (expr) |e| {
        var expression = e;
        // Check for an apply...
        if (self.peek() == .OpenRound) {
            const scratch_top = self.store.scratch_exprs.items.len;
            self.advance();
            while (self.peek() != .CloseRound) {
                const arg_expression = self.parseExpr();
                std.debug.print("arg_expression is {any}\n", .{self.store.getExpr(arg_expression)});
                self.store.scratch_exprs.append(arg_expression) catch exitOnOom();
                std.debug.print("Before checking comma {s}\n", .{@tagName(self.peek())});
                if (self.peek() != .Comma) {
                    break;
                }
                self.advance();
                std.debug.print("After checking comma {s}\n", .{@tagName(self.peek())});
            }
            if (self.peek() != .CloseRound) {
                // Problem
                std.debug.print("Tokens:\n{any}\n", .{self.tok_buf.tokens.items(.tag)});
                std.debug.panic("TODO: malformed apply @ {d}, got {s}", .{ self.pos, @tagName(self.peek()) });
            }
            self.advance();
            const args = self.store.scratch_exprs.items[scratch_top..];
            expression = self.store.addExpr(.{ .apply = .{
                .args = args,
                .@"fn" = e,
                .region = .{ .start = start, .end = self.pos },
            } });
            self.store.scratch_exprs.shrinkRetainingCapacity(scratch_top);
        }
        if (self.peek() == .NoSpaceOpQuestion) {
            expression = self.store.addExpr(.{ .suffix_single_question = .{
                .expr = expression,
                .region = .{ .start = start, .end = self.pos },
            } });
            self.advance();
        }
        // Check for try suffix...
        return expression;
    }
    std.debug.panic("todo: Malformed Expr", .{});
}

pub fn finishParseAssign(self: *Parser) IR.NodeStore.BodyIdx {
    self.advance();
    if (self.peek() == .OpenCurly) {
        self.advance();
        const scratch_top = self.store.scratch_statements.items.len;
        defer self.store.scratch_statements.shrinkRetainingCapacity(scratch_top);

        while (true) {
            const statement = self.parseStmt() orelse break;
            self.store.scratch_statements.append(statement) catch exitOnOom();
            if (self.peek() == .CloseCurly) {
                self.advance();
                break;
            }
        }

        const statements = self.store.scratch_statements.items[scratch_top..];

        const body = self.store.addBody(.{ .statements = statements, .whitespace = self.pos - 1 });
        return body;
    } else {
        const start = self.pos;
        const expr = self.parseExpr();
        const statement = self.store.addStatement(.{ .expr = .{
            .expr = expr,
            .region = .{ .start = start, .end = self.pos },
        } });
        const body = self.store.addBody(.{ .statements = &.{statement}, .whitespace = null });
        return body;
    }
}

pub fn addProblem(self: *Parser, diagnostic: IR.Diagnostic) void {
    self.diagnostics.append(diagnostic) catch exitOnOom();
}
