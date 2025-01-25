const std = @import("std");
const testing = std.testing;
const calculator = @import("calculator.zig");

test "basic addition" {
    const result = try calculator.calculate(5, 3, '+');
    try testing.expectEqual(@as(f64, 8), result);
}

test "basic subtraction" {
    const result = try calculator.calculate(5, 3, '-');
    try testing.expectEqual(@as(f64, 2), result);
}

test "basic multiplication" {
    const result = try calculator.calculate(5, 3, '*');
    try testing.expectEqual(@as(f64, 15), result);
}

test "basic division" {
    const result = try calculator.calculate(6, 2, '/');
    try testing.expectEqual(@as(f64, 3), result);
}

test "division by zero" {
    const result = calculator.calculate(5, 0, '/');
    try testing.expectError(error.DivisionByZero, result);
}

test "modulus" {
    const result = calculator.calculate(5, 3, '%');
    try testing.expectEqual(@as(f64, 2), result);
}

test "invalid operation" {
    const result = calculator.calculate(5, 3, 'x');
    try testing.expectError(error.InvalidOperation, result);
}
