pub const packages = struct {
    pub const @"12201fe677e9c7cfb8984a36446b329d5af23d03dc1e4f79a853399529e523a007fa" = struct {
        pub const build_root = "/home/thng292/.cache/zig/p/12201fe677e9c7cfb8984a36446b329d5af23d03dc1e4f79a853399529e523a007fa";
        pub const build_zig = @import("12201fe677e9c7cfb8984a36446b329d5af23d03dc1e4f79a853399529e523a007fa");
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
    pub const @"1220382cf6bc4de7be53ea0b7f0b3657aa23169168b0b91c09bde7c94914a645e7e9" = struct {
        pub const build_root = "/media/gamedisk/Code/zig/nese/libs/zgpu/../zpool";
        pub const build_zig = @import("1220382cf6bc4de7be53ea0b7f0b3657aa23169168b0b91c09bde7c94914a645e7e9");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"12204a3519efd49ea2d7cf63b544492a3a771d37eda320f86380813376801e4cfa73" = struct {
        pub const build_root = "/home/thng292/.cache/zig/p/12204a3519efd49ea2d7cf63b544492a3a771d37eda320f86380813376801e4cfa73";
        pub const build_zig = @import("12204a3519efd49ea2d7cf63b544492a3a771d37eda320f86380813376801e4cfa73");
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
    pub const @"12205cd13f6849f94ef7688ee88c6b74c7918a5dfb514f8a403fcc2929a0aa342627" = struct {
        pub const build_root = "/home/thng292/.cache/zig/p/12205cd13f6849f94ef7688ee88c6b74c7918a5dfb514f8a403fcc2929a0aa342627";
        pub const build_zig = @import("12205cd13f6849f94ef7688ee88c6b74c7918a5dfb514f8a403fcc2929a0aa342627");
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
    pub const @"1220b1f02f2f7edd98a078c64e3100907d90311d94880a3cc5927e1ac009d002667a" = struct {
        pub const build_root = "/home/thng292/.cache/zig/p/1220b1f02f2f7edd98a078c64e3100907d90311d94880a3cc5927e1ac009d002667a";
        pub const build_zig = @import("1220b1f02f2f7edd98a078c64e3100907d90311d94880a3cc5927e1ac009d002667a");
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
    pub const @"1220e3d5313fbf18e0ec03220ad3207f52fd0cf99dbc1a4aad1d702beaf9cd8add38" = struct {
        pub const build_root = "/media/gamedisk/Code/zig/nese/libs/zgpu/../system-sdk";
        pub const build_zig = @import("1220e3d5313fbf18e0ec03220ad3207f52fd0cf99dbc1a4aad1d702beaf9cd8add38");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"1220f9448cde02ef3cd51bde2e0850d4489daa0541571d748154e89c6eb46c76a267" = struct {
        pub const build_root = "/home/thng292/.cache/zig/p/1220f9448cde02ef3cd51bde2e0850d4489daa0541571d748154e89c6eb46c76a267";
        pub const build_zig = @import("1220f9448cde02ef3cd51bde2e0850d4489daa0541571d748154e89c6eb46c76a267");
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "system_sdk", "1220e3d5313fbf18e0ec03220ad3207f52fd0cf99dbc1a4aad1d702beaf9cd8add38" },
    .{ "zpool", "1220382cf6bc4de7be53ea0b7f0b3657aa23169168b0b91c09bde7c94914a645e7e9" },
    .{ "dawn_x86_64_windows_gnu", "1220f9448cde02ef3cd51bde2e0850d4489daa0541571d748154e89c6eb46c76a267" },
    .{ "dawn_x86_64_linux_gnu", "12204a3519efd49ea2d7cf63b544492a3a771d37eda320f86380813376801e4cfa73" },
    .{ "dawn_aarch64_linux_gnu", "12205cd13f6849f94ef7688ee88c6b74c7918a5dfb514f8a403fcc2929a0aa342627" },
    .{ "dawn_aarch64_macos", "12201fe677e9c7cfb8984a36446b329d5af23d03dc1e4f79a853399529e523a007fa" },
    .{ "dawn_x86_64_macos", "1220b1f02f2f7edd98a078c64e3100907d90311d94880a3cc5927e1ac009d002667a" },
};
