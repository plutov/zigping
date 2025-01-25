const std = @import("std");

pub fn calculate(num1: f64, num2: f64, op: u8) !f64 {
    return switch (op) {
        '+' => num1 + num2,
        '-' => num1 - num2,
        '*' => num1 * num2,
        '/' => if (num2 == 0) {
            return error.DivisionByZero;
        } else num1 / num2,
        '%' => @mod(num1, num2),
        else => error.InvalidOperation,
    };
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    while (true) {
        try stdout.writeAll("\nCalculator (enter 'q' to quit)\n");
        try stdout.writeAll("Enter first number: ");

        var first_input_buffer: [16]u8 = undefined;
        const first_input = try stdin.readUntilDelimiter(&first_input_buffer, '\n');
        if (first_input.len == 1 and first_input[0] == 'q') break;

        const num1 = try std.fmt.parseFloat(f64, first_input);

        try stdout.writeAll("Enter operation (+, -, *, /): ");

        var op_buffer: [16]u8 = undefined;
        const op = try stdin.readUntilDelimiter(&op_buffer, '\n');

        if (op.len == 0) {
            try stdout.writeAll("Error: No operation entered!\n");
            continue;
        }

        try stdout.writeAll("Enter second number: ");

        var second_input_buffer: [16]u8 = undefined;
        const num2 = try std.fmt.parseFloat(f64, try stdin.readUntilDelimiter(&second_input_buffer, '\n'));

        const result = calculate(num1, num2, op[0]) catch |err| {
            switch (err) {
                error.DivisionByZero => try stdout.writeAll("Error: Division by zero!\n"),
                error.InvalidOperation => try stdout.print("Error: Invalid operation '{s}'!\n", .{op}),
                else => return err,
            }
            continue;
        };

        try stdout.print("Result: {d}\n", .{result});
    }
}
