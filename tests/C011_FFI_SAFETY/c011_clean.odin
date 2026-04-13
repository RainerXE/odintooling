package test_c011_clean

test_proper_cleanup :: proc() {
    parser := ts_parser_new()
    defer ts_parser_delete(parser)    // OK: paired cleanup

    cursor := ts_query_cursor_new()
    defer ts_query_cursor_delete(cursor)  // OK: paired cleanup

    _ = parser
    _ = cursor
}
