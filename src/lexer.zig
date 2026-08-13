const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Aligned = std.array_list.Aligned;

const tok = @import("./token.zig");
const Token = tok.Token;
const OpType = tok.OpType;

pub const LexError = error{ NotKeyword, UnsupportedCharacter, Overflow, NegativeWithoutNumber } || Allocator.Error;

pub const TokenList = Aligned(Token, null);

pub const Lexer = struct {
    arena: Allocator,
    index: usize = 0,
    text: []const u8 = "",

    const LexState = enum {
        start,
        num,
        ident,
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
                    '-' => {
                        if (self.isAtEnd()) return LexError.NegativeWithoutNumber;
                        // line comment --
                        if (self.peekAt(0) == '-') {
                            while (!self.isAtEnd() and self.peekAt(0) != '\n') self.index += 1;
                            continue :state .start;
                        }
                        // negative number
                        if (!std.ascii.isDigit(self.peekAt(0))) return LexError.NegativeWithoutNumber;
                        continue :state .num;
                    },
                    ' ', '\t', '\r', '\n' => continue :state .start,
                    'a'...'z' => continue :state .ident,
                    else => return LexError.UnsupportedCharacter,
                }
            },
            .num => {
                // start_index is index - 1 in order to include the '-' sign for parsing and bound checking
                const start_index = self.index - 1;
                while (!self.isAtEnd() and std.ascii.isDigit(self.peekAt(0))) {
                    self.index += 1;
                }

                const num = try parseToInt(text[start_index..self.index]);

                try token_list.append(self.arena, .{ .num = num });

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

// parses string in form -?[0-9]+ to an i32 with checks for overflow and underflow
// starts by building a negative version of the actual number and then corrects in the end
// with a sign flip since more numbers can be stored once signed integer goes below 0
pub fn parseToInt(str: []const u8) LexError!i32 {
    const sign: i32 = if (str[0] == '-') -1 else 1;
    const trimmed: []const u8 = if (sign == -1) str[1..] else str;

    // what stores the final result
    var n: i32 = 0;

    for (trimmed) |digit| {
        if (n < std.math.minInt(i32) / 10 or (n == std.math.minInt(i32) / 10 and digit - '0' > 8))
            return LexError.Overflow;
        n = 10 * n - (digit - '0');
    }

    if (sign == 1 and n == std.math.minInt(i32)) return LexError.Overflow;

    // negating n would make minInt(i32) become an overflow error so the - was moved to sign in order
    // to avoid erroring on good value
    return -sign * n;
}

test "parsing int #1" {
    try std.testing.expect(try parseToInt("2147483647") == 2147483647);
}

test "parsing int #2" {
    try std.testing.expect(parseToInt("2147483648") catch |err| err == LexError.Overflow);
}

test "parsing int #3" {
    try std.testing.expect(try parseToInt("-2147483648") == -2147483648);
}

test "parsing int #4" {
    try std.testing.expect(parseToInt("-2147483649") catch |err| err == LexError.Overflow);
}

test "parsing int #5" {
    try std.testing.expect(try parseToInt("-42") == -42);
}

test "parsing int #6" {
    try std.testing.expect(parseToInt("10010130000000000") catch |err| err == LexError.Overflow);
}

test "lexer (numbers and add keyword)" {
    var lexer = Lexer{ .arena = std.testing.allocator };
    var token_list = try lexer.lex("3 4 add");
    defer token_list.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), token_list.items.len);
    try std.testing.expectEqual(Token{ .num = 3 }, token_list.items[0]);
    try std.testing.expectEqual(Token{ .num = 4 }, token_list.items[1]);
    try std.testing.expectEqual(Token{ .op = .add }, token_list.items[2]);
}

test "lexer (comment with no trailing newline doesn't run off the buffer)" {
    var lexer = Lexer{ .arena = std.testing.allocator };
    var token_list = try lexer.lex("-5 -- rest is ignored");
    defer token_list.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), token_list.items.len);
    try std.testing.expectEqual(Token{ .num = -5 }, token_list.items[0]);
}

test "lexer (errors on bad input)" {
    var lexer = Lexer{ .arena = std.testing.allocator };

    try std.testing.expectError(LexError.NegativeWithoutNumber, lexer.lex("-"));
    try std.testing.expectError(LexError.UnsupportedCharacter, lexer.lex("$"));
    try std.testing.expectError(LexError.NotKeyword, lexer.lex("foo"));
}
