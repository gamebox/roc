const std = @import("std");
const base = @import("../base.zig");
const parse = @import("parse.zig");
const problem = @import("../problem.zig");
const collections = @import("../collections.zig");

const Problem = problem.Problem;
const Ident = base.Ident;
const Scope = @import("./canonicalize/Scope.zig");

const Self = @This();
pub const IR = @import("./canonicalize/IR.zig");

/// After parsing a Roc program, the [ParseIR](src/check/parse/ir.zig) is transformed into a [canonical
/// form](src/check/canonicalize/ir.zig) called CanIR.
///
/// Canonicalization performs analysis to catch user errors, and sets up the state necessary to solve the types in a
/// program. Among other things, canonicalization;
/// - Uniquely identifies names (think variable and function names). Along the way,
///     canonicalization builds a graph of all variables' references, and catches
///     unused definitions, undefined definitions, and shadowed definitions.
/// - Resolves type signatures, including aliases, into a form suitable for type
///     solving.
/// - Determines the order definitions are used in, if they are defined
///     out-of-order.
/// - Eliminates syntax sugar (for example, renaming `+` to the function call `add`).
///
/// The canonicalization occurs on a single module (file) in isolation. This allows for this work to be easily parallelized and also cached. So where the source code for a module has not changed, the CanIR can simply be loaded from disk and used immediately.
pub fn canonicalize(
    can_ir: IR,
    parse_ir: *parse.IR,
    allocator: std.mem.Allocator,
) void {
    var env = can_ir.env;
    const builtin_aliases = [0]Scope.Alias{};
    const imported_idents = [0]Ident.Idx{};
    const scope = Scope.init(&env, &builtin_aliases, &imported_idents, allocator);
    _ = scope;

    const file = parse_ir.store.getFile(parse.IR.NodeStore.FileIdx{ .id = 0 });

    for (file.statements) |stmt_id| {
        const stmt = parse_ir.store.getStatement(stmt_id);
        switch (stmt) {
            .import => |import| {
                const name = parse_ir.resolve(import.module_name_tok);
                const name_region = parse_ir.tokens.resolve(import.module_name_tok);
                const res = env.modules.getOrInsert(name, "todo_shorthand");

                if (res.was_present) {
                    _ = env.problems.append(Problem.Canonicalize.make(.{ .DuplicateImport = .{
                        .duplicate_import_region = name_region,
                    } }));
                }

                // TODO: need to intern the strings; not sure how that works currently?
                // for (import.exposes) |exposed| {
                //     const value_name = parse_ir.resolve(exposed);
                //     env.addExposedIdentForModule(value_name, res.module_idx);
                // }
            },
            else => std.debug.panic("Unhandled statement type: {}", .{stmt}),
        }
    }

    @panic("not implemented");
}
