const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Specify static or dynamic linkage",
    ) orelse .static;

    const std_dep_options = .{ .target = target, .optimize = optimize, .linkage = linkage };
    const std_mod_options: std.Build.Module.CreateOptions = .{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    };

    const upstream = b.dependency("uxr_client", .{});
    const microcdr = b.dependency("microcdr", std_dep_options).artifact("microcdr");

    const std_c_flags: []const []const u8 = &.{
        "--std=c99",
        //"-pthread", // Only if multithreading is added
        "-Wall",
        "-Wextra",
        "-pedantic",
        "-Wcast-align",
        "-Wshadow",
        "-fstrict-aliasing",
        "-DNDEBUG",
        // Required to *actually* bring in the POSIX portions of the C std lib.
        // No idea why 'zig cc' sets this but build.zig does not :shrug:
        "-D_POSIX_C_SOURCE=200112L",
    };

    ////////////////////////////////////////////////////////////////////////////////
    // Micro-XRCE-DDS-Agent Library
    ////////////////////////////////////////////////////////////////////////////////

    const uclient_lib = b.addLibrary(.{
        .name = "micro-xrce-dds-client",
        .root_module = b.createModule(std_mod_options),
        .linkage = linkage,
    });

    const config_h = b.addConfigHeader(.{
        .style = .{ .cmake = upstream.path("include/uxr/client/config.h.in") },
        .include_path = "uxr/client/config.h",
    }, .{
        .PROJECT_VERSION_MAJOR = 3,
        .PROJECT_VERSION_MINOR = 0,
        .PROJECT_VERSION_PATCH = 0,
        .PROJECT_VERSION = "3.0.0",

        .UCLIENT_PROFILE_DISCOVERY = 1,

        .UCLIENT_PROFILE_UDP = 1,
        .UCLIENT_PROFILE_TCP = 1,
        .UCLIENT_PROFILE_SERIAL = 1,
        .UCLIENT_PROFILE_CUSTOM_TRANSPORT = 1,
        .UCLIENT_PROFILE_CAN = null,
        .UCLIENT_PROFILE_MULTITHREAD = null, // Issues with pthread_mutexattr_settype()
        .UCLIENT_PROFILE_SHARED_MEMORY = null, // hmmm...
        .UCLIENT_PROFILE_STREAM_FRAMING = 1,

        .UCLIENT_PLATFORM_LINUX = 1,
        .UCLIENT_PLATFORM_POSIX = 1,
        .UCLIENT_PLATFORM_POSIX_NOPOLL = null,
        .UCLIENT_PLATFORM_WINDOWS = null,
        .UCLIENT_PLATFORM_FREERTOS_PLUS_TCP = null,
        .UCLIENT_PLATFORM_RTEMS_BSD_NET = null,
        .UCLIENT_PLATFORM_ZEPHYR = null,

        .UCLIENT_MAX_OUTPUT_BEST_EFFORT_STREAMS = 1,
        .UCLIENT_MAX_OUTPUT_RELIABLE_STREAMS = 1,
        .UCLIENT_MAX_INPUT_BEST_EFFORT_STREAMS = 1,
        .UCLIENT_MAX_INPUT_RELIABLE_STREAMS = 1,

        .UCLIENT_MAX_SESSION_CONNECTION_ATTEMPTS = 10,
        .UCLIENT_MIN_SESSION_CONNECTION_INTERVAL = 1000,
        .UCLIENT_MIN_HEARTBEAT_TIME_INTERVAL = 100,

        .UCLIENT_UDP_TRANSPORT_MTU = 512,
        .UCLIENT_TCP_TRANSPORT_MTU = 512,
        .UCLIENT_SERIAL_TRANSPORT_MTU = 512,
        .UCLIENT_CUSTOM_TRANSPORT_MTU = 512,

        .UCLIENT_SHARED_MEMORY_MAX_ENTITIES = 4,
        .UCLIENT_SHARED_MEMORY_STATIC_MEM_SIZE = 10,
        .UCLIENT_TWEAK_XRCE_WRITE_LIMIT = 1,
        .UCLIENT_HARD_LIVELINESS_CHECK = null,
        .UCLIENT_HARD_LIVELINESS_CHECK_TIMEOUT = 10000,
    });
    uclient_lib.addConfigHeader(config_h);
    uclient_lib.installHeader(config_h.getOutput(), "uxr/client/config.h");
    uclient_lib.installHeadersDirectory(upstream.path("include"), "", .{});

    uclient_lib.addCSourceFiles(.{
        .root = upstream.path("src/c"),
        .files = source_files ++ transport_files,
        .flags = std_c_flags,
        .language = .c,
    });
    uclient_lib.addIncludePath(upstream.path("include"));

    uclient_lib.linkLibrary(microcdr);
    uclient_lib.linkLibC();

    b.installArtifact(uclient_lib);
}

const source_files: []const []const u8 = &.{
    "core/session/stream/input_best_effort_stream.c",
    "core/session/stream/input_reliable_stream.c",
    "core/session/stream/output_best_effort_stream.c",
    "core/session/stream/output_reliable_stream.c",
    "core/session/stream/stream_storage.c",
    "core/session/stream/stream_id.c",
    "core/session/stream/seq_num.c",
    "core/session/session.c",
    "core/session/session_info.c",
    "core/session/submessage.c",
    "core/session/object_id.c",
    "core/serialization/xrce_types.c",
    "core/serialization/xrce_header.c",
    "core/serialization/xrce_subheader.c",
    "util/time.c",
    "util/ping.c",
    "core/session/common_create_entities.c",
    "core/session/create_entities_ref.c",
    "core/session/create_entities_xml.c",
    "core/session/create_entities_bin.c",
    "core/session/read_access.c",
    "core/session/write_access.c",
    "profile/transport/stream_framing/stream_framing_protocol.c",
    // "profile/multithread/multithread.c", // UCLIENT_PROFILE_MULTITHREAD
    // "profile/shared_memory/shared_memory.c", // UCLIENT_PROFILE_SHARED_MEMORY
    // "profile/matching/matching.c", // UCLIENT_PROFILE_MATCHING
    // "core/log/log.c", // UCLIENT_VERBOSE_MESSAGE or UCLIENT_VERBOSE_SERIALIZATION
};

const transport_files: []const []const u8 = &.{
    "profile/transport/ip/udp/udp_transport.c",
    "profile/transport/ip/udp/udp_transport_posix.c",
    "profile/transport/ip/tcp/tcp_transport.c",
    "profile/transport/ip/tcp/tcp_transport_posix.c",
    "profile/transport/serial/serial_transport.c",
    "profile/transport/serial/serial_transport_posix.c",
    "profile/transport/ip/ip_posix.c",
    "profile/discovery/discovery.c",
    "profile/discovery/transport/udp_transport_datagram_posix.c",
    "profile/transport/custom/custom_transport.c",
};
