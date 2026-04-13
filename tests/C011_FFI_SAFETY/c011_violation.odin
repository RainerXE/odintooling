package test_c011

test_missing_cleanup :: proc() {
    parser := ts_parser_new()         // VIOLATION: no defer ts_parser_delete
    cursor := ts_query_cursor_new()   // VIOLATION: no defer ts_query_cursor_delete
    _ = parser
    _ = cursor
}
