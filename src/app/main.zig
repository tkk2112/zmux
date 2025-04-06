const std = @import("std");
const zmux = @import("zmux.lib");

pub fn main() void {
    std.debug.print("zmux v{s}\n", .{zmux.version});
}
