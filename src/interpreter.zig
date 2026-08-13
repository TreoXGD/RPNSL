const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Aligned = std.array_list.Aligned;

const tok = @import("./token.zig");
const Token = tok.Token;

pub const EvalError = error{ StackUnderflow, DivisionByZero, WriteFailed, Quit } || Allocator.Error;

pub const Stack = Aligned(i32, null);

pub const Interpreter = struct {
    arena: Allocator,
    writer: *std.Io.Writer,
    stack: Stack = .empty,

    pub fn init(arena: Allocator, writer: *std.Io.Writer) Interpreter {
        return .{
            .arena = arena,
            .writer = writer,
        };
    }

    pub fn eval(self: *Interpreter, token: Token) EvalError!void {
        switch (token) {
            .num => try self.stack.append(self.arena, token.num),
            .op => |op| {
                switch (op) {
                    // tertiary operations
                    .rot => {
                        const top = try self.popOrError();
                        const middle = try self.popOrError();
                        const bottom = try self.popOrError();

                        try self.stack.append(self.arena, middle);
                        try self.stack.append(self.arena, top);
                        try self.stack.append(self.arena, bottom);
                    },
                    // binary operations with return
                    .add, .sub, .mul, .div, .mod, .min, .max => {
                        const rhs = try self.popOrError();
                        const lhs = try self.popOrError();

                        const result: i32 = switch (op) {
                            .add => lhs + rhs,
                            .sub => lhs - rhs,
                            .mul => lhs * rhs,
                            .div => if (rhs == 0) return EvalError.DivisionByZero else @divTrunc(lhs, rhs),
                            .mod => if (rhs == 0) return EvalError.DivisionByZero else @rem(lhs, rhs),
                            .min => @min(lhs, rhs),
                            .max => @max(lhs, rhs),
                            else => unreachable,
                        };

                        try self.stack.append(self.arena, result);
                    },
                    // binary operations without return
                    .swap => {
                        const rhs = try self.popOrError();
                        const lhs = try self.popOrError();

                        try self.stack.append(self.arena, rhs);
                        try self.stack.append(self.arena, lhs);
                    },
                    .over => {
                        // second from top
                        const second = try self.peekAtOrError(1);
                        try self.stack.append(self.arena, second);
                    },
                    // unary operations with return
                    .neg, .abs => {
                        const num = try self.popOrError();

                        const result: i32 = switch (op) {
                            .neg => -num,
                            .abs => if (num < 0) -num else num,
                            else => unreachable,
                        };

                        try self.stack.append(self.arena, result);
                    },
                    // unary operations without return
                    .dup => {
                        const num = try self.popOrError();

                        try self.stack.append(self.arena, num);
                        try self.stack.append(self.arena, num);
                    },
                    .drop => _ = try self.popOrError(),
                    .print => try self.writer.print("> {}\n", .{try self.popOrError()}),
                    .peek => try self.writer.print("| {}\n", .{try self.peekAtOrError(0)}),
                    // no argument operations
                    .clear => self.stack.clearRetainingCapacity(),
                    .stack => {
                        if (self.stack.items.len == 0) {
                            try self.writer.writeAll("|\n");
                        } else {
                            var i = self.stack.items.len;
                            while (i > 0) : (i -= 1) try self.writer.print("| {}\n", .{self.stack.items[i - 1]});
                        }
                    },
                    .quit => return EvalError.Quit,
                    .help => {
                        const help_commands =
                            \\add - pops 2, pushes their sum
                            \\sub - pops 2, pushes their second-from-top minus top
                            \\mul - pops 2, pushes their product
                            \\div - pops 2, pushes their second-from-top over top and errors if top is 0
                            \\mod - pops 2, pushes remainder of second-from-top over top and errors if top is 0
                            \\neg - pops 1, pushes its negations
                            \\abs - pops 2, pushes its absolute value
                            \\min - pops 2, pushes smaller value
                            \\max - pops 2, pushes bigger value
                            \\dup - pushes a copy of the top
                            \\swap - swaps the 2 top values
                            \\drop - pops the top
                            \\over - pushes copy of second-from-top value to top
                            \\rot - moves third-from-top to top
                            \\clear - empties the stack
                            \\print - pops and prints the top
                            \\peek - prints the top without popping
                            \\stack - prints the entire stack top to bottom without popping
                            \\quit - exit the program
                            \\help - shows this message
                        ;

                        try self.writer.writeAll(help_commands);
                        try self.writer.writeAll("\n");
                    },
                }
            },
        }
    }

    fn peekAtOrError(self: *Interpreter, depth: usize) EvalError!i32 {
        if (depth >= self.stack.items.len) return EvalError.StackUnderflow;
        return self.stack.items[self.stack.items.len - 1 - depth];
    }

    fn popOrError(self: *Interpreter) EvalError!i32 {
        return self.stack.pop() orelse return EvalError.StackUnderflow;
    }
};

test "rot operation" {
    var buf: [32]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var interp = Interpreter.init(std.testing.allocator, &w);
    defer interp.stack.deinit(std.testing.allocator);

    try interp.eval(.{ .num = 1 });
    try interp.eval(.{ .num = 2 });
    try interp.eval(.{ .num = 3 });
    try interp.eval(.{ .op = .rot });

    try std.testing.expectEqualSlices(i32, &.{ 2, 3, 1 }, interp.stack.items);
}

test "add operation" {
    var buf: [32]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var interp = Interpreter.init(std.testing.allocator, &w);
    defer interp.stack.deinit(std.testing.allocator);

    try interp.eval(.{ .num = 2 });
    try interp.eval(.{ .num = 3 });
    try interp.eval(.{ .op = .add });

    try std.testing.expectEqualSlices(i32, &.{5}, interp.stack.items);
}

test "sub operation" {
    var buf: [32]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var interp = Interpreter.init(std.testing.allocator, &w);
    defer interp.stack.deinit(std.testing.allocator);

    try interp.eval(.{ .num = 10 });
    try interp.eval(.{ .num = 3 });
    try interp.eval(.{ .op = .sub });

    try std.testing.expectEqualSlices(i32, &.{7}, interp.stack.items);
}

test "mul operation" {
    var buf: [32]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var interp = Interpreter.init(std.testing.allocator, &w);
    defer interp.stack.deinit(std.testing.allocator);

    try interp.eval(.{ .num = 4 });
    try interp.eval(.{ .num = 5 });
    try interp.eval(.{ .op = .mul });

    try std.testing.expectEqualSlices(i32, &.{20}, interp.stack.items);
}

test "div operation" {
    var buf: [32]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var interp = Interpreter.init(std.testing.allocator, &w);
    defer interp.stack.deinit(std.testing.allocator);

    try interp.eval(.{ .num = 20 });
    try interp.eval(.{ .num = 4 });
    try interp.eval(.{ .op = .div });

    try std.testing.expectEqualSlices(i32, &.{5}, interp.stack.items);
}

test "div operation with division by zero" {
    var buf: [32]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var interp = Interpreter.init(std.testing.allocator, &w);
    defer interp.stack.deinit(std.testing.allocator);

    try interp.eval(.{ .num = 5 });
    try interp.eval(.{ .num = 0 });

    try std.testing.expectError(EvalError.DivisionByZero, interp.eval(.{ .op = .div }));
}

test "mod operation" {
    var buf: [32]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var interp = Interpreter.init(std.testing.allocator, &w);
    defer interp.stack.deinit(std.testing.allocator);

    try interp.eval(.{ .num = -7 });
    try interp.eval(.{ .num = 3 });
    try interp.eval(.{ .op = .mod });

    try std.testing.expectEqualSlices(i32, &.{-1}, interp.stack.items);
}

test "mod operation with division by zero" {
    var buf: [32]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var interp = Interpreter.init(std.testing.allocator, &w);
    defer interp.stack.deinit(std.testing.allocator);

    try interp.eval(.{ .num = 5 });
    try interp.eval(.{ .num = 0 });

    try std.testing.expectError(EvalError.DivisionByZero, interp.eval(.{ .op = .mod }));
}

test "neg operation" {
    var buf: [32]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var interp = Interpreter.init(std.testing.allocator, &w);
    defer interp.stack.deinit(std.testing.allocator);

    try interp.eval(.{ .num = 5 });
    try interp.eval(.{ .op = .neg });

    try std.testing.expectEqualSlices(i32, &.{-5}, interp.stack.items);
}

test "abs operation" {
    var buf: [32]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var interp = Interpreter.init(std.testing.allocator, &w);
    defer interp.stack.deinit(std.testing.allocator);

    try interp.eval(.{ .num = -5 });
    try interp.eval(.{ .op = .abs });

    try std.testing.expectEqualSlices(i32, &.{5}, interp.stack.items);
}

test "min operation" {
    var buf: [32]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var interp = Interpreter.init(std.testing.allocator, &w);
    defer interp.stack.deinit(std.testing.allocator);

    try interp.eval(.{ .num = 5 });
    try interp.eval(.{ .num = 2 });
    try interp.eval(.{ .op = .min });

    try std.testing.expectEqualSlices(i32, &.{2}, interp.stack.items);
}

test "max operation" {
    var buf: [32]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var interp = Interpreter.init(std.testing.allocator, &w);
    defer interp.stack.deinit(std.testing.allocator);

    try interp.eval(.{ .num = 3 });
    try interp.eval(.{ .num = 9 });
    try interp.eval(.{ .op = .max });

    try std.testing.expectEqualSlices(i32, &.{9}, interp.stack.items);
}

test "dup operation" {
    var buf: [32]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var interp = Interpreter.init(std.testing.allocator, &w);
    defer interp.stack.deinit(std.testing.allocator);

    try interp.eval(.{ .num = 7 });
    try interp.eval(.{ .op = .dup });

    try std.testing.expectEqualSlices(i32, &.{ 7, 7 }, interp.stack.items);
}

test "swap operation" {
    var buf: [32]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var interp = Interpreter.init(std.testing.allocator, &w);
    defer interp.stack.deinit(std.testing.allocator);

    try interp.eval(.{ .num = 1 });
    try interp.eval(.{ .num = 2 });
    try interp.eval(.{ .op = .swap });

    try std.testing.expectEqualSlices(i32, &.{ 2, 1 }, interp.stack.items);
}

test "over operation" {
    var buf: [32]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var interp = Interpreter.init(std.testing.allocator, &w);
    defer interp.stack.deinit(std.testing.allocator);

    try interp.eval(.{ .num = 1 });
    try interp.eval(.{ .num = 2 });
    try interp.eval(.{ .op = .over });

    try std.testing.expectEqualSlices(i32, &.{ 1, 2, 1 }, interp.stack.items);
}

test "drop operation" {
    var buf: [32]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var interp = Interpreter.init(std.testing.allocator, &w);
    defer interp.stack.deinit(std.testing.allocator);

    try interp.eval(.{ .num = 1 });
    try interp.eval(.{ .num = 2 });
    try interp.eval(.{ .op = .drop });

    try std.testing.expectEqualSlices(i32, &.{1}, interp.stack.items);
}

test "clear operation" {
    var buf: [32]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var interp = Interpreter.init(std.testing.allocator, &w);
    defer interp.stack.deinit(std.testing.allocator);

    try interp.eval(.{ .num = 1 });
    try interp.eval(.{ .num = 2 });
    try interp.eval(.{ .num = 3 });
    try interp.eval(.{ .op = .clear });

    try std.testing.expectEqual(0, interp.stack.items.len);
}

test "print operation" {
    var buf: [32]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var interp = Interpreter.init(std.testing.allocator, &w);
    defer interp.stack.deinit(std.testing.allocator);

    try interp.eval(.{ .num = 5 });
    try interp.eval(.{ .op = .print });

    try std.testing.expectEqualStrings("> 5\n", w.buffer[0..w.end]);
    try std.testing.expectEqual(0, interp.stack.items.len);
}

test "peek operation" {
    var buf: [32]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var interp = Interpreter.init(std.testing.allocator, &w);
    defer interp.stack.deinit(std.testing.allocator);

    try interp.eval(.{ .num = 5 });
    try interp.eval(.{ .op = .peek });

    try std.testing.expectEqualStrings("| 5\n", w.buffer[0..w.end]);
    try std.testing.expectEqualSlices(i32, &.{5}, interp.stack.items);
}

test "stack operation" {
    var buf: [32]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var interp = Interpreter.init(std.testing.allocator, &w);
    defer interp.stack.deinit(std.testing.allocator);

    try interp.eval(.{ .num = 1 });
    try interp.eval(.{ .num = 2 });
    try interp.eval(.{ .op = .stack });

    try std.testing.expectEqualStrings("| 2\n| 1\n", w.buffer[0..w.end]);
    try std.testing.expectEqualSlices(i32, &.{ 1, 2 }, interp.stack.items);
}

test "quit operation" {
    var buf: [32]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var interp = Interpreter.init(std.testing.allocator, &w);
    defer interp.stack.deinit(std.testing.allocator);

    try std.testing.expectError(EvalError.Quit, interp.eval(.{ .op = .quit }));
}
