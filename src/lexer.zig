const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Aligned = std.array_list.Aligned;

const tok = @import("./token.zig");
const Token = tok.Token;
const OpType = tok.OpType;

pub const LexError = error{ NotKeyword, UnsupportedCharacter, Overflow, DecimalPointWithoutNumber } || Allocator.Error;

pub const TokenList = Aligned(Token, null);

pub const Lexer = struct {
    arena: Allocator,
    index: usize = 0,
    text: []const u8 = "",

    const LexState = enum {
        start,
        num,
        ident,
        op,
        end,
    };

    pub fn lex(self: *Lexer, text: []const u8) LexError!TokenList {
        var token_list: TokenList = .empty;
        self.index = 0;
        self.text = text;

        state: switch (LexState.start) {
            .start => {
                if (self.isAtEnd()) continue :state .end;
                switch (self.advance()) {
                    '0'...'9' => {
                        continue :state .num;
                    },
                    '+', '*', '/', '%' => continue :state .op,
                    '-' => {
                        if (std.ascii.isDigit(self.peekAt(0))) continue :state .num;

                        continue :state .op;
                    },
                    ';' => {
                        while (!self.isAtEnd() and self.peekAt(0) != '\n') self.index += 1;
                        continue :state .start;
                    },
                    ' ', '\t', '\r', '\n' => continue :state .start,
                    'a'...'z' => continue :state .ident,
                    else => return LexError.UnsupportedCharacter,
                }
            },
            .op => {
                const op: OpType = switch (self.text[self.index - 1]) {
                    '+' => .plus,
                    '-' => .minus,
                    '*' => .star,
                    '/' => .slash,
                    '%' => .percent,
                    else => unreachable,
                };

                try token_list.append(self.arena, .{ .op = op });

                continue :state .start;
            },
            .num => {
                // start_index is index - 1 in order to include the '-' sign for parsing and bound checking
                const start_index = self.index - 1;
                while (!self.isAtEnd() and std.ascii.isDigit(self.peekAt(0))) {
                    self.index += 1;
                }

                // floats
                if (!self.isAtEnd() and self.peekAt(0) == '.') {
                    self.index += 1;
                    if (self.isAtEnd() or !std.ascii.isDigit(self.peekAt(0))) return LexError.DecimalPointWithoutNumber;

                    while (!self.isAtEnd() and std.ascii.isDigit(self.peekAt(0))) {
                        self.index += 1;
                    }
                    const num = std.fmt.parseFloat(f64, text[start_index..self.index]) catch unreachable;

                    try token_list.append(self.arena, .{ .float = num });
                } else {
                    const num = std.fmt.parseInt(i32, text[start_index..self.index], 10) catch |err| switch (err) {
                        error.InvalidCharacter => unreachable,
                        error.Overflow => return LexError.Overflow,
                    };

                    try token_list.append(self.arena, .{ .int = num });
                }

                continue :state .start;
            },
            .ident => {
                const start_index = self.index - 1;
                while (!self.isAtEnd() and std.ascii.isAlphabetic(self.peekAt(0))) {
                    self.index += 1;
                }

                // no support for non-keyword identifiers for now
                const keyword = try strToKeyword(text[start_index..self.index]);

                try token_list.append(self.arena, keyword);

                continue :state .start;
            },
            .end => {},
        }

        return token_list;
    }

    fn strToKeyword(str: []const u8) LexError!Token {
        const op = std.meta.stringToEnum(OpType, str) orelse return LexError.NotKeyword;
        return .{ .op = op };
    }

    fn isAtEnd(self: *Lexer) bool {
        return self.index >= self.text.len;
    }

    fn advance(self: *Lexer) u8 {
        self.index += 1;
        return self.text[self.index - 1];
    }

    fn previous(self: *Lexer) u8 {
        return self.text[self.index - 1];
    }

    fn peekAt(self: *Lexer, ahead: usize) u8 {
        return self.text[self.index + ahead];
    }
};

test "lexer (numbers and add keyword)" {
    var lexer = Lexer{ .arena = std.testing.allocator };
    var token_list = try lexer.lex("3 4 +");
    defer token_list.deinit(std.testing.allocator);

    try std.testing.expectEqual(3, token_list.items.len);
    try std.testing.expectEqual(Token{ .int = 3 }, token_list.items[0]);
    try std.testing.expectEqual(Token{ .int = 4 }, token_list.items[1]);
    try std.testing.expectEqual(Token{ .op = .plus }, token_list.items[2]);
}

test "lexer (comment with no trailing newline doesn't run off the buffer)" {
    var lexer = Lexer{ .arena = std.testing.allocator };
    var token_list = try lexer.lex("-5 ; rest is ignored");
    defer token_list.deinit(std.testing.allocator);

    try std.testing.expectEqual(1, token_list.items.len);
    try std.testing.expectEqual(Token{ .int = -5 }, token_list.items[0]);
}

test "lexer (errors on bad input)" {
    var lexer = Lexer{ .arena = std.testing.allocator };

    try std.testing.expectError(LexError.UnsupportedCharacter, lexer.lex("$"));
    try std.testing.expectError(LexError.NotKeyword, lexer.lex("foo"));
}

test "lexer (float literal)" {
    var lexer = Lexer{ .arena = std.testing.allocator };
    var token_list = try lexer.lex("2.5");
    defer token_list.deinit(std.testing.allocator);

    try std.testing.expectEqual(1, token_list.items.len);
    try std.testing.expectEqual(Token{ .float = 2.5 }, token_list.items[0]);
}

test "lexer (negative float literal)" {
    var lexer = Lexer{ .arena = std.testing.allocator };
    var token_list = try lexer.lex("-2.5");
    defer token_list.deinit(std.testing.allocator);

    try std.testing.expectEqual(1, token_list.items.len);
    try std.testing.expectEqual(Token{ .float = -2.5 }, token_list.items[0]);
}

test "lexer (mixed int and float)" {
    var lexer = Lexer{ .arena = std.testing.allocator };
    var token_list = try lexer.lex("3 4.5 +");
    defer token_list.deinit(std.testing.allocator);

    try std.testing.expectEqual(3, token_list.items.len);
    try std.testing.expectEqual(Token{ .int = 3 }, token_list.items[0]);
    try std.testing.expectEqual(Token{ .float = 4.5 }, token_list.items[1]);
    try std.testing.expectEqual(Token{ .op = .plus }, token_list.items[2]);
}

test "lexer (errors on decimal point without digits)" {
    var lexer = Lexer{ .arena = std.testing.allocator };

    try std.testing.expectError(LexError.DecimalPointWithoutNumber, lexer.lex("3."));
}
