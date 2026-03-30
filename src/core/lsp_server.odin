package core

import "core:fmt"
import "core:os"
import "core:strings"

// Full LSP Server implementation for odin-lint
// This enables odin-lint to act as a standalone Language Server

// LSP Server State
LSPServerState :: struct {
    initialized: bool,
    root_uri: string,
    capabilities: map[string]any,
}

// Global server state
server_state: LSPServerState

// runLSPServer runs odin-lint as a standalone LSP server
runLSPServer :: proc() {
    fmt.println("=== odin-lint LSP Server ===")
    fmt.println("Listening for LSP messages on stdin...")
    fmt.println("Ready to accept connections from editors")
    
    // Initialize server state
    server_state = LSPServerState{
        initialized = false,
        root_uri = "",
        capabilities = {},
    }
    
    // Start message processing loop
    processLSPMessages()
}

// processLSPMessages main message loop
processLSPMessages :: proc() {
    for {
        // Read message headers
        headers, err := readLSPHeaders()
        if err != nil {
            fmt.fprintln(os.stderr, "Error reading headers:", err)
            continue
        }
        
        if headers.content_length == 0 {
            // No more messages, exit
            break
        }
        
        // Read message body
        message := readLSPMessage(headers.content_length)
        if len(message) == 0 {
            fmt.fprintln(os.stderr, "Empty message received")
            continue
        }
        
        // Debug output
        fmt.println("\n=== Received LSP Message ===")
        fmt.println("Content-Type:", headers.content_type)
        fmt.println("Content-Length:", headers.content_length)
        fmt.println("Message:", message)
        
        // Parse and handle message
        method, id, params := parseLSPMessage(message)
        
        if method == "" {
            fmt.fprintln(os.stderr, "Invalid LSP message format")
            sendErrorResponse(id, -32600, "Invalid Request")
            continue
        }
        
        fmt.println("Handling method:", method)
        
        // Route to appropriate handler
        response := handleLSPMethod(method, id, params)
        
        // Send response if needed
        if response != "" {
            sendLSPResponse(response)
        }
    }
    
    fmt.println("LSP Server shutting down")
}

// LSPHeaders represents message headers
LSPHeaders :: struct {
    content_length: int,
    content_type: string,
}

// readLSPHeaders reads LSP message headers from stdin
readLSPHeaders :: proc() -> (LSPHeaders, error) {
    headers := LSPHeaders{}
    
    for {
        line, err := fmt.scanf("%s")
        if err != nil {
            return LSPHeaders{}, error("EOF")
        }
        
        // Empty line means end of headers
        if line == "" {
            break
        }
        
        // Parse Content-Length
        if strings.has_prefix(line, "Content-Length:") {
            parts := strings.split(line, ":")
            if len(parts) == 2 {
                headers.content_length = string.to_int(strings.trim(parts[1]))
            }
        }
        
        // Parse Content-Type
        if strings.has_prefix(line, "Content-Type:") {
            parts := strings.split(line, ":")
            if len(parts) == 2 {
                headers.content_type = strings.trim(parts[1])
            }
        }
    }
    
    return headers, nil
}

// readLSPMessage reads message body
readLSPMessage :: proc(length: int) -> string {
    if length <= 0 {
        return ""
    }
    
    buffer := make([]u8, length)
    bytes_read, err := os.input.read(buffer)
    if err != nil || bytes_read != length {
        fmt.fprintln(os.stderr, "Error reading message body:", err)
        return ""
    }
    
    return string(buffer)
}

// parseLSPMessage parses LSP JSON message
parseLSPMessage :: proc(message: string) -> (string, string, string) {
    // Simple parsing - look for method, id, and params
    method := ""
    id := "1"  // Default ID
    params := "{}"
    
    // Find method
    method_start := strings.index(message, "\"method\":"")
    if method_start != -1 {
        method_start += 10  // Skip "\"method\":"
        method_end := strings.index_from(message, "\"", method_start)
        if method_end != -1 {
            method = message[method_start..method_end]
        }
    }
    
    // Find id (simplified)
    id_start := strings.index(message, "\"id\":")
    if id_start != -1 {
        id_start += 5  // Skip "\"id\":"
        id_end := strings.index_from(message, ",", id_start)
        if id_end == -1 {
            id_end = strings.index_from(message, "}", id_start)
        }
        if id_end != -1 {
            id = strings.trim(message[id_start..id_end])
        }
    }
    
    // For now, extract params as the object after method
    params_start := strings.index(message, "\"params\":")
    if params_start != -1 {
        params_start += 9  // Skip "\"params\":"
        // Find the opening brace
        brace_start := strings.index_from(message, "{", params_start)
        if brace_start != -1 {
            // Find matching closing brace
            brace_count := 1
            pos := brace_start + 1
            while pos < len(message) && brace_count > 0 {
                if message[pos] == '{' {
                    brace_count += 1
                } else if message[pos] == '}' {
                    brace_count -= 1
                }
                pos += 1
            }
            if brace_count == 0 {
                params = message[brace_start..pos]
            }
        }
    }
    
    return method, id, params
}

// handleLSPMethod routes LSP methods to handlers
handleLSPMethod :: proc(method: string, id: string, params: string) -> string {
    when method {
    "initialize":
        return handleInitialize(id, params)
    "initialized":
        return handleInitialized(id, params)
    "textDocument/didOpen":
        handleDidOpen(params)
        return ""  // Notification, no response
    "textDocument/didChange":
        handleDidChange(params)
        return ""  // Notification, no response
    "textDocument/didSave":
        handleDidSave(params)
        return ""  // Notification, no response
    "textDocument/didClose":
        handleDidClose(params)
        return ""  // Notification, no response
    "shutdown":
        return handleShutdown(id, params)
    "exit":
        os.exit(0)
    default:
        fmt.println("Unknown LSP method:", method)
        return createErrorResponse(id, -32601, "Method not found")
    }
}

// handleInitialize handles initialize request
handleInitialize :: proc(id: string, params: string) -> string {
    fmt.println("Processing initialize request")
    
    // Extract rootUri if present
    root_uri_start := strings.index(params, "\"rootUri\":"")
    if root_uri_start != -1 {
        root_uri_start += 11  // Skip "\"rootUri\":"
        root_uri_end := strings.index_from(params, "\"", root_uri_start)
        if root_uri_end != -1 {
            server_state.root_uri = params[root_uri_start..root_uri_end]
        }
    }
    
    // Create response
    response := `{
`
    response += `  "jsonrpc": "2.0",
`
    response += `  "id": ` + id + `,
`
    response += `  "result": {
`
    response += `    "capabilities": {
`
    response += `      "textDocumentSync": 1,
`
    response += `      "diagnosticProvider": {
`
    response += `        "interFileDependencies": false,
`
    response += `        "workspaceDiagnostics": false
`
    response += `      },
`
    response += `      "hoverProvider": false,
`
    response += `      "definitionProvider": false,
`
    response += `      "referencesProvider": false,
`
    response += `      "documentSymbolProvider": false
`
    response += `    }
`
    response += `  }
`
    response += `}
`
    
    server_state.initialized = true
    return response
}

// handleInitialized handles initialized notification
handleInitialized :: proc(id: string, params: string) -> string {
    fmt.println("Processing initialized notification")
    
    // Send our capabilities info
    return `{
` +
           `  "jsonrpc": "2.0",
` +
           `  "id": ` + id + `,
` +
           `  "result": {
` +
           `    "serverInfo": {
` +
           `      "name": "odin-lint",
` +
           `      "version": "0.1.0"
` +
           `    }
` +
           `  }
` +
           `}
`
}

// handleDidOpen handles document opened notification
handleDidOpen :: proc(params: string) {
    fmt.println("Processing textDocument/didOpen")
    
    file_path := extractFilePathFromParams(params)
    if file_path == "" {
        fmt.fprintln(os.stderr, "Could not extract file path from didOpen params")
        return
    }
    
    fmt.println("Analyzing opened file:", file_path)
    analyzeAndSendDiagnostics(file_path)
}

// handleDidChange handles document changed notification
handleDidChange :: proc(params: string) {
    fmt.println("Processing textDocument/didChange")
    
    file_path := extractFilePathFromParams(params)
    if file_path == "" {
        fmt.fprintln(os.stderr, "Could not extract file path from didChange params")
        return
    }
    
    fmt.println("Analyzing changed file:", file_path)
    analyzeAndSendDiagnostics(file_path)
}

// handleDidSave handles document saved notification
handleDidSave :: proc(params: string) {
    fmt.println("Processing textDocument/didSave")
    
    file_path := extractFilePathFromParams(params)
    if file_path == "" {
        fmt.fprintln(os.stderr, "Could not extract file path from didSave params")
        return
    }
    
    fmt.println("Analyzing saved file:", file_path)
    analyzeAndSendDiagnostics(file_path)
}

// handleDidClose handles document closed notification
handleDidClose :: proc(params: string) {
    fmt.println("Processing textDocument/didClose")
    
    file_path := extractFilePathFromParams(params)
    if file_path == "" {
        fmt.fprintln(os.stderr, "Could not extract file path from didClose params")
        return
    }
    
    fmt.println("Clearing diagnostics for closed file:", file_path)
    
    // Send empty diagnostics to clear
    file_uri := "file://" + strings.replace(file_path, "\\", "/", -1)
    sendDiagnosticsNotification(file_uri, []Diagnostic{})
}

// handleShutdown handles shutdown request
handleShutdown :: proc(id: string, params: string) -> string {
    fmt.println("Processing shutdown request")
    
    return `{
` +
           `  "jsonrpc": "2.0",
` +
           `  "id": ` + id + `,
` +
           `  "result": null
` +
           `}
`
}

// extractFilePathFromParams extracts file URI from LSP params
extractFilePathFromParams :: proc(params: string) -> string {
    // Look for "uri": "file://"
    uri_start := strings.index(params, "\"uri\": \"file://")
    if uri_start == -1 {
        return ""
    }
    
    uri_start += 10  // Skip "\"uri\": \""
    uri_end := strings.index_from(params, "\"", uri_start)
    if uri_end == -1 {
        return ""
    }
    
    file_uri := params[uri_start..uri_end]
    
    // Convert file:// URI to local path
    if strings.has_prefix(file_uri, "file://") {
        return strings.replace(file_uri, "file://", "", -1)
    }
    
    return file_uri
}

// analyzeAndSendDiagnostics analyzes file and sends diagnostics
analyzeAndSendDiagnostics :: proc(file_path: string) {
    // Run odin-lint analysis
    ts_parser, ts_ok := initTreeSitterParser()
    if !ts_ok {
        fmt.fprintln(os.stderr, "Failed to initialize tree-sitter parser")
        return
    }
    defer deinitTreeSitterParser(ts_parser)
    
    // Parse file to get AST
    ast_root, parse_ok := parseFile(ts_parser, file_path)
    if !parse_ok {
        fmt.fprintln(os.stderr, "Failed to parse file:", file_path)
        return
    }
    
    // Apply rules and collect diagnostics
    diagnostics := []Diagnostic{}
    
    // Apply C001 rule
    c001_rule := C001Rule()
    diag := c001_rule.matcher(file_path, &ast_root)
    if diag.message != "" {
        diagnostics = append(diagnostics, diag)
    }
    
    // Apply C002 rule
    c002_rule := C002Rule()
    diag2 := c002_rule.matcher(file_path, &ast_root)
    if diag2.message != "" {
        diagnostics = append(diagnostics, diag2)
    }
    
    // Convert file path to URI
    file_uri := "file://" + strings.replace(file_path, "\\", "/", -1)
    
    // Send diagnostics
    sendDiagnosticsNotification(file_uri, diagnostics)
}

// sendDiagnosticsNotification sends diagnostics to client
sendDiagnosticsNotification :: proc(uri: string, diagnostics: []Diagnostic) {
    notification := `{
`
    notification += `  "jsonrpc": "2.0",
`
    notification += `  "method": "textDocument/publishDiagnostics",
`
    notification += `  "params": {
`
    notification += `    "uri": "` + uri + `",
`
    notification += `    "diagnostics": [
`
    
    // Add each diagnostic
    for i, diag in diagnostics {
        notification += `      {
`
        notification += `        "range": {
`
        notification += `          "start": {"line": ` + fmt.tostr(diag.line - 1) + `, "character": ` + fmt.tostr(diag.column - 1) + `},
`
        notification += `          "end": {"line": ` + fmt.tostr(diag.line - 1) + `, "character": ` + fmt.tostr(diag.column - 1 + 10) + `}
`
        notification += `        },
`
        notification += `        "severity": ` + fmt.tostr(get_severity_from_tier(diag.tier)) + `,
`
        notification += `        "code": "` + diag.rule_id + `",
`
        notification += `        "source": "odin-lint",
`
        notification += `        "message": "` + escape_json(diag.message) + `"
`
        if diag.fix != "" {
            notification += `,
        "fix": "` + escape_json(diag.fix) + `"`
        }
        notification += `
      }`
        if i < len(diagnostics) - 1 {
            notification += `,`
        }
        notification += `
`
    }
    
    notification += `    ]
`
    notification += `  }
`
    notification += `}
`
    
    sendLSPResponse(notification)
}

// sendLSPResponse sends response to client
sendLSPResponse :: proc(response: string) {
    if response == "" {
        return
    }
    
    content := []u8(response)
    fmt.printf("Content-Length: %d\r\n", len(content))
    fmt.println("Content-Type: application/vscode-lsp-jsonrpc; charset=utf-8\r")
    fmt.println("\r")
    fmt.print(response)
    fmt.flush()
}

// createErrorResponse creates LSP error response
createErrorResponse :: proc(id: string, code: int, message: string) -> string {
    return `{
` +
           `  "jsonrpc": "2.0",
` +
           `  "id": ` + id + `,
` +
           `  "error": {
` +
           `    "code": ` + fmt.tostr(code) + `,
` +
           `    "message": "` + message + `"
` +
           `  }
` +
           `}
`
}

// get_severity_from_tier converts tier to LSP severity
get_severity_from_tier :: proc(tier: string) -> int {
    if tier == "correctness" {
        return 1  // Error
    } else if tier == "style" {
        return 2        // Warning
    } else if tier == "performance" {
        return 3  // Information
    } else if tier == "pedantic" {
        return 4     // Hint
    }
    return 2              // Warning (default)
}

// escape_json escapes special characters for JSON
escape_json :: proc(text: string) -> string {
    result := text
    result = strings.replace(result, `\`, `\\`, -1)
    result = strings.replace(result, `"`, `\"`, -1)
    result = strings.replace(result, `\n`, `\\n`, -1)
    result = strings.replace(result, `\r`, `\\r`, -1)
    result = strings.replace(result, `\t`, `\\t`, -1)
    return result
}
