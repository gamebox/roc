use crate::annotation::{Formattable, MigrationFlags, Newlines, Parens};
use crate::expr::{fmt_str_literal, format_sq_literal, is_str_multiline};
use crate::spaces::{fmt_comments_only, fmt_spaces, NewlineAt, INDENT};
use crate::Buf;
use roc_parse::ast::{Base, CommentOrNewline, Pattern, PatternAs};

pub fn fmt_pattern<'a>(
    buf: &mut Buf,
    pattern: &'a Pattern<'a>,
    flags: &MigrationFlags,
    indent: u16,
    parens: Parens,
) {
    pattern.format_with_options(buf, parens, Newlines::No, flags, indent);
}

impl<'a> Formattable for PatternAs<'a> {
    fn is_multiline(&self) -> bool {
        self.spaces_before.iter().any(|s| s.is_comment())
    }

    fn format_with_options(
        &self,
        buf: &mut Buf,
        _parens: Parens,
        _newlines: Newlines,
        _flags: &MigrationFlags,
        indent: u16,
    ) {
        buf.indent(indent);

        if !buf.ends_with_space() {
            buf.spaces(1);
        }

        buf.push_str("as");
        buf.spaces(1);

        // these spaces "belong" to the identifier, which can never be multiline
        fmt_comments_only(buf, self.spaces_before.iter(), NewlineAt::Bottom, indent);

        buf.indent(indent);
        buf.push_str(self.identifier.value);
    }
}

impl<'a> Formattable for Pattern<'a> {
    fn is_multiline(&self) -> bool {
        // Theory: a pattern should only be multiline when it contains a comment
        match self {
            Pattern::SpaceBefore(pattern, spaces) | Pattern::SpaceAfter(pattern, spaces) => {
                debug_assert!(
                    !spaces.is_empty(),
                    "spaces is empty in pattern {:#?}",
                    pattern
                );

                spaces.iter().any(|s| s.is_comment()) || pattern.is_multiline()
            }

            Pattern::RecordDestructure(fields) => fields.iter().any(|f| f.is_multiline()),
            Pattern::RequiredField(_, subpattern) => subpattern.is_multiline(),

            Pattern::OptionalField(_, expr) => expr.is_multiline(),

            Pattern::As(pattern, pattern_as) => pattern.is_multiline() || pattern_as.is_multiline(),
            Pattern::ListRest(opt_pattern_as) => match opt_pattern_as {
                None => false,
                Some((list_rest_spaces, pattern_as)) => {
                    list_rest_spaces.iter().any(|s| s.is_comment()) || pattern_as.is_multiline()
                }
            },
            Pattern::StrLiteral(literal) => is_str_multiline(literal),
            Pattern::Apply(pat, args) => {
                pat.is_multiline() || args.iter().any(|a| a.is_multiline())
            }

            Pattern::Identifier { .. }
            | Pattern::Tag(_)
            | Pattern::OpaqueRef(_)
            | Pattern::NumLiteral(..)
            | Pattern::NonBase10Literal { .. }
            | Pattern::FloatLiteral(..)
            | Pattern::SingleQuote(_)
            | Pattern::Underscore(_)
            | Pattern::Malformed(_)
            | Pattern::MalformedIdent(_, _)
            | Pattern::QualifiedIdentifier { .. } => false,

            Pattern::Tuple(patterns) | Pattern::List(patterns) => {
                patterns.iter().any(|p| p.is_multiline())
            }
        }
    }

    fn format_with_options(
        &self,
        buf: &mut Buf,
        parens: Parens,
        newlines: Newlines,
        flags: &MigrationFlags,
        indent: u16,
    ) {
        use self::Pattern::*;

        match self {
            Identifier { ident: string } => {
                buf.indent(indent);
                snakify_camel_ident(buf, string, flags);
            }
            Tag(name) | OpaqueRef(name) => {
                buf.indent(indent);
                buf.push_str(name);
            }
            Apply(loc_pattern, loc_arg_patterns) => {
                buf.indent(indent);
                // Sometimes, an Apply pattern needs parens around it.
                // In particular when an Apply's argument is itself an Apply (> 0) arguments
                let parens = !loc_arg_patterns.is_empty() && (parens == Parens::InApply);

                let indent_more = if self.is_multiline() {
                    indent + INDENT
                } else {
                    indent
                };

                if parens {
                    buf.push('(');
                }

                loc_pattern.format_with_options(buf, Parens::InApply, Newlines::No, flags, indent);

                for loc_arg in loc_arg_patterns.iter() {
                    buf.spaces(1);
                    loc_arg.format_with_options(
                        buf,
                        Parens::InApply,
                        Newlines::No,
                        flags,
                        indent_more,
                    );
                }

                if parens {
                    buf.push(')');
                }
            }
            RecordDestructure(loc_patterns) => {
                buf.indent(indent);
                buf.push_str("{");

                if !loc_patterns.is_empty() {
                    buf.spaces(1);
                    let mut it = loc_patterns.iter().peekable();
                    while let Some(loc_pattern) = it.next() {
                        loc_pattern.format(buf, flags, indent);

                        if it.peek().is_some() {
                            buf.push_str(",");
                            buf.spaces(1);
                        }
                    }
                    buf.spaces(1);
                }

                buf.push_str("}");
            }

            RequiredField(name, loc_pattern) => {
                buf.indent(indent);
                snakify_camel_ident(buf, name, flags);
                buf.push_str(":");
                buf.spaces(1);
                loc_pattern.format(buf, flags, indent);
            }

            OptionalField(name, loc_pattern) => {
                buf.indent(indent);
                snakify_camel_ident(buf, name, flags);
                buf.push_str(" ?");
                buf.spaces(1);
                loc_pattern.format(buf, flags, indent);
            }

            &NumLiteral(string) => {
                buf.indent(indent);
                buf.push_str(string);
            }
            &NonBase10Literal {
                base,
                string,
                is_negative,
            } => {
                buf.indent(indent);
                if is_negative {
                    buf.push('-');
                }

                match base {
                    Base::Hex => buf.push_str("0x"),
                    Base::Octal => buf.push_str("0o"),
                    Base::Binary => buf.push_str("0b"),
                    Base::Decimal => { /* nothing */ }
                }

                buf.push_str(string);
            }
            &FloatLiteral(string) => {
                buf.indent(indent);
                buf.push_str(string);
            }
            StrLiteral(literal) => fmt_str_literal(buf, *literal, flags, indent),
            SingleQuote(string) => {
                buf.indent(indent);
                format_sq_literal(buf, string);
            }
            Underscore(name) => {
                buf.indent(indent);
                buf.push('_');
                buf.push_str(name);
            }
            Tuple(loc_patterns) => {
                buf.indent(indent);
                buf.push_str("(");

                let mut it = loc_patterns.iter().peekable();
                while let Some(loc_pattern) = it.next() {
                    loc_pattern.format(buf, flags, indent);

                    if it.peek().is_some() {
                        buf.push_str(",");
                        buf.spaces(1);
                    }
                }

                buf.push_str(")");
            }
            List(loc_patterns) => {
                buf.indent(indent);
                buf.push_str("[");

                let mut it = loc_patterns.iter().peekable();
                while let Some(loc_pattern) = it.next() {
                    loc_pattern.format(buf, flags, indent);

                    if it.peek().is_some() {
                        buf.push_str(",");
                        buf.spaces(1);
                    }
                }

                buf.push_str("]");
            }
            ListRest(opt_pattern_as) => {
                buf.indent(indent);
                buf.push_str("..");

                if let Some((list_rest_spaces, pattern_as)) = opt_pattern_as {
                    // these spaces "belong" to the `..`, which can never be multiline
                    fmt_comments_only(buf, list_rest_spaces.iter(), NewlineAt::Bottom, indent);

                    pattern_as.format(buf, flags, indent + INDENT);
                }
            }

            As(pattern, pattern_as) => {
                let needs_parens = parens == Parens::InAsPattern;

                if needs_parens {
                    buf.push('(');
                }

                fmt_pattern(buf, &pattern.value, flags, indent, parens);

                pattern_as.format(buf, flags, indent + INDENT);

                if needs_parens {
                    buf.push(')');
                }
            }

            // Space
            SpaceBefore(sub_pattern, spaces) => {
                if !sub_pattern.is_multiline() {
                    fmt_comments_only(buf, spaces.iter(), NewlineAt::Bottom, indent)
                } else {
                    fmt_spaces(buf, spaces.iter(), indent);
                }

                sub_pattern.format_with_options(buf, parens, newlines, flags, indent);
            }
            SpaceAfter(sub_pattern, spaces) => {
                sub_pattern.format_with_options(buf, parens, newlines, flags, indent);

                if starts_with_inline_comment(spaces.iter()) {
                    buf.spaces(1);
                }

                if !sub_pattern.is_multiline() {
                    fmt_comments_only(buf, spaces.iter(), NewlineAt::Bottom, indent)
                } else {
                    fmt_spaces(buf, spaces.iter(), indent);
                }
            }

            // Malformed
            Malformed(string) | MalformedIdent(string, _) => {
                buf.indent(indent);
                buf.push_str(string);
            }
            QualifiedIdentifier { module_name, ident } => {
                buf.indent(indent);
                if !module_name.is_empty() {
                    buf.push_str(module_name);
                    buf.push('.');
                }

                snakify_camel_ident(buf, ident, flags);
            }
        }
    }
}

fn starts_with_inline_comment<'a, I: IntoIterator<Item = &'a CommentOrNewline<'a>>>(
    spaces: I,
) -> bool {
    matches!(
        spaces.into_iter().next(),
        Some(CommentOrNewline::LineComment(_))
    )
}

fn snakify_camel_ident(buf: &mut Buf, string: &str, flags: &MigrationFlags) {
    let chars: Vec<char> = string.chars().collect();
    if !flags.snakify || (string.contains('_') && !string.ends_with('_')) {
        buf.push_str(string);
        return;
    }
    let mut index = 0;
    let len = chars.len();

    while index < len {
        let prev = if index == 0 {
            None
        } else {
            Some(chars[index - 1])
        };
        let c = chars[index];
        let next = chars.get(index + 1);
        let boundary = match (prev, c, next) {
            // LUU, LUN, and LUL (simplified to LU_)
            (Some(p), curr, _) if !p.is_ascii_uppercase() && curr.is_ascii_uppercase() => true,
            // UUL
            (Some(p), curr, Some(n))
                if p.is_ascii_uppercase()
                    && curr.is_ascii_uppercase()
                    && n.is_ascii_lowercase() =>
            {
                true
            }
            _ => false,
        };
        // those are boundary transitions - should push _ and curr
        if boundary {
            buf.push('_');
        }
        buf.push(c.to_ascii_lowercase());
        index = index + 1;
    }
}

#[cfg(test)]
mod snakify_test {
    use bumpalo::Bump;

    use super::snakify_camel_ident;
    use crate::{annotation::MigrationFlags, Buf};

    fn check_snakify(arena: &Bump, original: &str) -> String {
        let mut buf = Buf::new_in(arena);
        buf.indent(0);
        let flags = MigrationFlags::new(true);
        snakify_camel_ident(&mut buf, original, &flags);
        buf.text.to_string()
    }

    #[test]
    fn test_snakify_camel_ident() {
        let arena = Bump::new();
        assert_eq!(check_snakify(&arena, "A"), "a");
        assert_eq!(check_snakify(&arena, "Ba"), "ba");
        assert_eq!(check_snakify(&arena, "aB"), "a_b");
        assert_eq!(check_snakify(&arena, "aBa"), "a_ba");
        assert_eq!(check_snakify(&arena, "mBB"), "m_bb");
        assert_eq!(check_snakify(&arena, "NbA"), "nb_a");
        assert_eq!(check_snakify(&arena, "doIT"), "do_it");
        assert_eq!(check_snakify(&arena, "ROC"), "roc");
        assert_eq!(
            check_snakify(&arena, "someHTTPRequest"),
            "some_http_request"
        );
        assert_eq!(check_snakify(&arena, "usingXML"), "using_xml");
        assert_eq!(check_snakify(&arena, "some123"), "some123");
        assert_eq!(
            check_snakify(&arena, "theHTTPStatus404"),
            "the_http_status404"
        );
        assert_eq!(
            check_snakify(&arena, "inThe99thPercentile"),
            "in_the99th_percentile"
        );
        assert_eq!(
            check_snakify(&arena, "all400SeriesErrorCodes"),
            "all400_series_error_codes",
        );
        assert_eq!(check_snakify(&arena, "number4Yellow"), "number4_yellow");
        assert_eq!(check_snakify(&arena, "useCases4Cobol"), "use_cases4_cobol");
        assert_eq!(check_snakify(&arena, "c3PO"), "c3_po")
    }
}
