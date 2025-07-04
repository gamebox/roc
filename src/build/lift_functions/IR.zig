const std = @import("std");
const base = @import("../../base.zig");
const types_module = @import("../../types.zig");

const collections = @import("../../collections.zig");

const Ident = base.Ident;
const StringLiteral = base.StringLiteral;

const Self = @This();

env: *base.ModuleEnv,
exposed_values: std.AutoHashMap(Ident.Idx, Expr.Idx),
exposed_functions: std.AutoHashMap(Ident.Idx, Function),
types: Type.List,
exprs: Expr.List,
typed_exprs: Expr.Typed.List,
patterns: Pattern.List,
typed_patterns: Pattern.Typed.List,
typed_idents: TypedIdent.List,
when_branches: WhenBranch.List,

pub fn init(env: *base.ModuleEnv) Self {
    return Self{
        .env = env,
        .exposed_values = std.AutoHashMap(Ident.Idx, Expr.Idx).init(env.gpa),
        .exposed_functions = std.AutoHashMap(Ident.Idx, Function).init(env.gpa),
        .types = .{},
        .exprs = .{},
        .typed_exprs = .{},
        .patterns = .{},
        .typed_patterns = .{},
        .typed_idents = .{},
        .when_branches = .{},
    };
}

/// todo
pub fn deinit(self: *Self) void {
    self.exposed_values.deinit(self.env.gpa);
    self.exposed_functions.deinit(self.env.gpa);
    self.types.deinit(self.env.gpa);
    self.exprs.deinit(self.env.gpa);
    self.typed_exprs.deinit(self.env.gpa);
    self.patterns.deinit(self.env.gpa);
    self.typed_patterns.deinit(self.env.gpa);
    self.typed_idents.deinit(self.env.gpa);
    self.when_branches.deinit(self.env.gpa);
}

/// todo
pub const Type = union(enum) {
    primitive: types_module.Primitive,
    box: Type.Idx,
    list: Type.Idx,
    @"struct": Type.NonEmptyRange,
    tag_union: Type.NonEmptyRange,
    func: struct {
        ret_then_args: Type.NonEmptyRange,
    },

    /// todo
    pub const List = collections.SafeList(@This());
    /// todo
    pub const Idx = List.Idx;
    /// todo
    pub const Range = List.Range;
    /// todo
    pub const NonEmptyRange = List.NonEmptyRange;
};

/// todo
pub const Expr = union(enum) {
    let: Def,
    str: StringLiteral,
    number: base.Literal.Num,
    list: struct {
        elem_type: Type.Idx,
        elems: Expr.Range,
    },
    lookup: struct {
        ident: Ident.Idx,
        type: Type.Idx,
    },

    call: struct {
        fn_type: Type.Idx,
        fn_expr: Expr.Idx,
        args: Expr.Typed.Range,
    },

    function_pack: struct {
        ident: Ident.Idx,
        // empty slice means no captures
        captures: Expr.Range,
    },

    unit,

    @"struct": Expr.NonEmptyRange,

    struct_access: struct {
        record_expr: Expr.Idx,
        record_type: Type.Idx,
        field_type: Type.Idx,
        field_id: Ident.Idx,
    },

    tag: struct {
        discriminant: u16,
        tag_union_type: Type.Idx,
        args: Expr.Typed.Range,
    },

    when: struct {
        /// The value being matched on
        value: Expr.Idx,
        /// The type of the value being matched on
        value_type: Type.Idx,
        /// The return type of all branches and thus the whole when expression
        branch_type: Type.Idx,
        /// The branches of the when expression
        branches: WhenBranch.NonEmptyRange,
    },
    /// todo
    pub const List = collections.SafeList(@This());
    /// todo
    pub const Idx = List.Idx;
    /// todo
    pub const Range = List.Range;
    /// todo
    pub const NonEmptyRange = List.NonEmptyRange;
    /// todo
    pub const Typed = struct {
        expr: Expr.Idx,
        type: Type.Idx,
        /// todo
        pub const List = collections.SafeMultiList(@This());
        /// todo
        pub const Range = Typed.List.Range;
    };
};

/// A definition, e.g. `x = foo`
pub const Def = struct {
    pattern: Pattern.Idx,
    /// Named variables in the pattern, e.g. `a` in `Ok a ->`
    pattern_vars: TypedIdent.Range,
    expr: Expr.Idx,
    expr_type: Type.Idx,
    /// todo
    pub const List = collections.SafeMultiList(@This());
    /// todo
    pub const Range = List.Range;
};

/// todo
pub const WhenBranch = struct {
    /// The pattern(s) to match the value against
    patterns: Pattern.NonEmptyRange,
    /// A boolean expression that must be true for this branch to be taken
    guard: ?Expr.Idx,
    /// The expression to produce if the pattern matches
    value: Expr.Idx,
    /// todo
    pub const List = collections.SafeList(@This());
    /// todo
    pub const NonEmptyRange = List.NonEmptyRange;
};
/// todo
pub const Function = struct {
    args: Pattern.Range,
    return_type: Type.Idx,
    expr: Expr.Idx,
};
/// todo
pub const StructDestruct = struct {
    ident: Ident.Idx,
    field: Ident.Idx,
    kind: Kind,
    /// todo
    pub const Kind = union(enum) {
        Required,
        Guard: Pattern.Typed,
    };
    /// todo
    pub const List = collections.SafeMultiList(@This());
    /// todo
    pub const Range = List.Range;
};
/// todo
pub const Pattern = union(enum) {
    identifier: Ident.Idx,
    as: struct {
        pattern: Pattern.Idx,
        ident: Ident.Idx,
    },
    str_literal: StringLiteral.Idx,
    number_literal: base.Literal.Num,
    applied_tag: struct {
        tag_union_type: Type.Idx,
        tag_name: Ident.Idx,
        args: Pattern.Range,
    },
    struct_destructure: struct {
        struct_type: Type.Idx,
        destructs: StructDestruct.Range,
        opt_spread: ?Pattern.Typed,
    },
    list: struct {
        elem_type: Type.Idx,
        patterns: Pattern.Range,

        opt_rest: ?struct {
            offset: u16,
            name: ?Ident.Idx,
        },
    },
    underscore,
    /// todo
    pub const List = collections.SafeList(@This());
    /// todo
    pub const Idx = List.Idx;
    /// todo
    pub const Range = List.Range;
    /// todo
    pub const NonEmptyRange = List.NonEmptyRange;
    /// todo
    pub const Typed = struct {
        pattern: Pattern.Idx,
        type: Type.Idx,
        /// todo
        pub const List = collections.SafeMultiList(@This());
        /// todo
        pub const Range = Typed.List.Range;
    };
};
/// todo
pub const TypedIdent = struct {
    pattern: Pattern.Idx,
    type: Type.Idx,
    /// todo
    pub const List = collections.SafeMultiList(@This());
    /// todo
    pub const Range = List.Range;
};
