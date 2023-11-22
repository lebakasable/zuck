const std = @import("std");
const String = @import("String.zig");
const clap = @import("clap");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const ChildProcess = std.ChildProcess;

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
        \\char tape[20000]={0};char*ptr=tape;int main(){
    );

    for (tokens.items) |token| {
        try output.concat(switch (token) {
            .add => "++*ptr;",
            .sub => "--*ptr;",
            .right => "++ptr;",
            .left => "--ptr;",
            .read => "*ptr=getchar();",
            .write => "putchar(*ptr);",
            .begin_loop => "while(*ptr){",
            .end_loop => "}",
        });
    }

    try output.concat("}");
    return output;
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var aa = std.heap.ArenaAllocator.init(gpa.allocator());
    defer aa.deinit();

    const allocator = aa.allocator();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help   Display the help and exit.
        \\-r, --run    Run the generated binary file.
        \\-d, --debug  Keep the generated C file.
        \\<file>...    The BrainFuck source file(s) to compile.
        \\
    );

    var res = try clap.parse(
        clap.Help,
        &params,
        comptime .{
            .file = clap.parsers.string,
        },
        .{},
    );

    if (res.args.help != 0) {
        try stdout.print("Usage: zuck ", .{});
        return clap.usage(stdout, clap.Help, &params);
    }

    if (res.positionals.len == 0) {
        return try stderr.print("error: At least one input file is required", .{});
    }

    for (res.positionals) |file_path| {
        var file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        var contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));

        std.log.info("Tokenizing `{s}`", .{file_path});
        var tokens = try tokenize(allocator, contents);

        var generated = try generate(allocator, tokens);

        var c_file_path: []const u8 = undefined;

        var ext_index = file_path.len - 1;
        var ext_found = false;
        while (ext_index > 0) : (ext_index -= 1) {
            if (file_path[ext_index] == '.') {
                c_file_path = try std.mem.concat(allocator, u8, &.{ file_path[0..ext_index], ".c" });
                ext_found = true;
                break;
            }
        }

        if (!ext_found) {
            c_file_path = try std.mem.concat(allocator, u8, &.{ file_path, ".c" });
        }

        std.log.info("Generating `{s}`", .{c_file_path});

        var c_file = try std.fs.cwd().createFile(c_file_path, .{});
        defer c_file.close();

        try c_file.writeAll(generated.str());

        std.log.info("Compiling `{s}`", .{c_file_path});

        const bin_file_path = file_path[0..ext_index];

        {
            var child = ChildProcess.init(&.{
                "gcc",
                "-O3",
                "-o",
                bin_file_path,
                c_file_path,
            }, allocator);
            _ = try child.spawnAndWait();
        }

        if (res.args.debug == 0) {
            var child = ChildProcess.init(&.{ "rm", c_file_path }, allocator);
            _ = try child.spawnAndWait();
        }

        if (res.args.run != 0) {
            var child = ChildProcess.init(&.{bin_file_path}, allocator);
            _ = try child.spawnAndWait();
        }
    }
}
