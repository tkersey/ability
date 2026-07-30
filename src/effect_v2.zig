const std = @import("std");

/// Declare one statically known typed residual effect site.
pub fn site(
    comptime ordinal: u32,
    comptime identity: []const u8,
    comptime PayloadType: type,
    comptime ResumeType: type,
) type {
    comptime {
        if (identity.len == 0) {
            @compileError("Boundary effect semantic identity must not be empty");
        }
    }
    return struct {
        pub const id = ordinal;
        pub const site_id = ordinal;
        pub const semantic_identity = identity;
        pub const Payload = PayloadType;
        pub const Resume = ResumeType;
    };
}

/// Preserve a comptime-closed tuple of effect sites as one authored row.
pub fn row(comptime sites: anytype) @TypeOf(sites) {
    return sites;
}

/// Declare one compile-time, type-preserving residual-effect morphism.
///
/// The compiler substitutes `TargetSite` for the source site's external
/// contract before residual-row construction. No runtime handler or closure is
/// retained.
pub fn morphism(
    comptime source_site_id: u32,
    comptime TargetSite: type,
) type {
    return struct {
        pub const source_id = source_site_id;
        pub const Target = TargetSite;
    };
}

/// Eliminate one source effect through a statically known Control IR helper.
///
/// The compiler replaces each suspension at `source_site_id` with a direct
/// call to `helper_function_id`. The helper receives the effect payload and
/// returns its resume value; no handler object or runtime dispatch survives.
pub fn handler(
    comptime source_site_id: u32,
    comptime helper_function_id: u16,
) type {
    return struct {
        pub const source_id = source_site_id;
        pub const function_id = helper_function_id;
    };
}

test "typed effect sites retain only structural compiler inputs" {
    const Lookup = site(0, "research.lookup.v2", u32, bool);
    const sites = row(.{Lookup});
    try std.testing.expectEqual(@as(usize, 1), sites.len);
    try std.testing.expectEqual(@as(u32, 0), sites[0].site_id);
    try std.testing.expectEqualStrings(
        "research.lookup.v2",
        sites[0].semantic_identity,
    );
    try std.testing.expect(sites[0].Payload == u32);
    try std.testing.expect(sites[0].Resume == bool);

    const Routed = site(0, "research.lookup.routed.v2", u32, bool);
    const Route = morphism(0, Routed);
    try std.testing.expectEqual(@as(u32, 0), Route.source_id);
    try std.testing.expect(Route.Target == Routed);

    const Local = handler(0, 1);
    try std.testing.expectEqual(@as(u32, 0), Local.source_id);
    try std.testing.expectEqual(@as(u16, 1), Local.function_id);
}
