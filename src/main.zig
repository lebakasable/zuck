const std = @import("std");
const String = @import("String.zig");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const Token = enum {
    add,
    sub,
    right,
    left,
    read,
    write,
    begin_loop,
    end_loop,
};

fn tokenize(allocator: Allocator, input: []const u8) !ArrayList(Token) {
    var tokens = ArrayList(Token).init(allocator);

    for (input) |c| {
        switch (c) {
            '+' => try tokens.append(.add),
            '-' => try tokens.append(.sub),
            '>' => try tokens.append(.right),
            '<' => try tokens.append(.left),
            ',' => try tokens.append(.read),
            '.' => try tokens.append(.write),
            '[' => try tokens.append(.begin_loop),
            ']' => try tokens.append(.end_loop),
            else => {},
        }
    }

    return tokens;
}

fn generate(allocator: Allocator, tokens: ArrayList(Token)) !String {
    var output = try String.init_with_contents(allocator,
        \\#include "stdio.h"
        \\int main(){char tape[20000]={0};char *ptr=tape;
    );

    for (tokens.items) |token| {
        switch (token) {
            .add => {
                try output.concat("++*ptr;");
            },
            .sub => {
                try output.concat("--*ptr;");
            },
            .right => {
                try output.concat("++ptr;");
            },
            .left => {
                try output.concat("--ptr;");
            },
            .read => {
                try output.concat("*ptr=getchar();");
            },
            .write => {
                try output.concat("putchar(*ptr);");
            },
            .begin_loop => {
                try output.concat("while(*ptr){");
            },
            .end_loop => {
                try output.concat("}");
            },
        }
    }

    try output.concat("}");
    return output;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var tokens = try tokenize(allocator, "++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++.");
    defer tokens.deinit();

    var generated = try generate(allocator, tokens);
    defer generated.deinit();

    std.debug.print("{s}\n", .{generated.str()});
}
