/* olt floorplan — a self-contained, read-only view of the code graph. */
(() => {
  "use strict";

  const DATA_EL = document.getElementById("olt-floorplan-data");
  const APP = document.getElementById("app");
  if (!DATA_EL || !APP) return;

  let data;
  try {
    data = JSON.parse(DATA_EL.textContent || "{}");
  } catch (err) {
    APP.textContent = "olt floorplan: the embedded graph data is not valid JSON.";
    return;
  }

  const SCHEMA_VERSION = 1;
  const EMPTY_PACKAGE_DIR = "__olt_unpackaged__";

  const nodeById = new Map();
  const fileNodeByPath = new Map();
  const nodesByFile = new Map();
  const fileByPath = new Map();
  const packageByDir = new Map();
  const filesByDir = new Map();
  const packageOfFile = new Map();
  const importsByFile = new Map();
  const callsOut = new Map();
  const callsIn = new Map();
  const instantiatesTarget = new Map();
  const packageEdges = new Map();
  const externalImports = new Map();
  const findings = [];
  const findingsByNode = new Map();
  const findingsByFile = new Map();
  const ruleCounts = new Map();

  const state = {
    query: "",
    tab: "selection",
    selectedNode: null,
    selectedFile: null,
  };

  /* ----------------------------------------------------------------------- */
  /* Data preparation                                                        */
  /* ----------------------------------------------------------------------- */

  function asArray(value) {
    return Array.isArray(value) ? value : [];
  }

  function basename(path) {
    const value = String(path || "");
    const at = value.lastIndexOf("/");
    return at >= 0 ? value.slice(at + 1) : value;
  }

  function dirname(path) {
    const value = String(path || "");
    const at = value.lastIndexOf("/");
    return at >= 0 ? value.slice(0, at) : "";
  }

  function prettyPackage(dir, name) {
    if (name) return name;
    if (!dir) return "(unpackaged)";
    return basename(dir) || dir;
  }

  function addToMapList(map, key, value) {
    let list = map.get(key);
    if (!list) {
      list = [];
      map.set(key, list);
    }
    list.push(value);
  }

  function uniquePush(list, value) {
    if (!list.includes(value)) list.push(value);
  }

  function classifyImport(path) {
    const value = String(path || "");
    const lower = value.toLowerCase();
    if (lower.startsWith("system:")) return "system";
    const ext = lower.match(/\.([a-z0-9]+)$/);
    if (ext) {
      const native = new Set([
        "c", "h", "cc", "cpp", "cxx", "hpp", "hh", "hxx", "m", "mm",
        "a", "lib", "dylib", "so", "dll", "o", "obj", "wasm",
      ]);
      if (native.has(ext[1])) return "native";
    }
    if (value.includes(":")) return "collection";
    return "external";
  }

  function prepare() {
    data.nodes = asArray(data.nodes);
    data.edges = asArray(data.edges);
    data.files = asArray(data.files);
    data.packages = asArray(data.packages);
    data.imports = asArray(data.imports);
    data.unresolved = asArray(data.unresolved);

    for (const node of data.nodes) nodeById.set(node.id, node);
    for (const file of data.files) fileByPath.set(file.path, file);

    for (const pkg of data.packages) {
      const dir = pkg.dir || EMPTY_PACKAGE_DIR;
      packageByDir.set(dir, {
        dir,
        name: prettyPackage(pkg.dir, pkg.name),
        path: pkg.dir || "",
      });
    }

    for (const file of data.files) {
      const dir = file.dir || EMPTY_PACKAGE_DIR;
      if (!packageByDir.has(dir)) {
        packageByDir.set(dir, {
          dir,
          name: prettyPackage(file.dir, file.package),
          path: file.dir || "",
        });
      }
      packageOfFile.set(file.path, dir);
      addToMapList(filesByDir, dir, file);
    }

    for (const node of data.nodes) {
      if (node.kind === "file") {
        fileNodeByPath.set(node.file, node);
      } else {
        addToMapList(nodesByFile, node.file, node);
      }
    }

    for (const list of nodesByFile.values()) {
      list.sort((a, b) => (a.start_line - b.start_line) || a.name.localeCompare(b.name));
    }

    for (const edge of data.edges) {
      if (edge.kind === "calls") {
        addToMapList(callsOut, edge.source, edge);
        addToMapList(callsIn, edge.target, edge);
      } else if (edge.kind === "instantiates") {
        addToMapList(instantiatesTarget, edge.target, edge);
      }
    }

    for (const imp of data.imports) {
      addToMapList(importsByFile, imp.file, imp);
    }

    for (const node of data.nodes) {
      const rules = asArray(node.lint);
      if (!rules.length) continue;
      const unique = [...new Set(rules.filter(Boolean))];
      if (!unique.length) continue;
      findingsByNode.set(node.id, unique);
      for (const rule of unique) {
        findings.push({ rule, node });
        ruleCounts.set(rule, (ruleCounts.get(rule) || 0) + 1);
      }
      if (node.kind !== "file") {
        findingsByFile.set(node.file, (findingsByFile.get(node.file) || 0) + unique.length);
      }
    }

    for (const imp of data.imports) {
      const sourceDir = packageOfFile.get(imp.file) || EMPTY_PACKAGE_DIR;
      const targetDir = imp.internal ? (imp.dir || EMPTY_PACKAGE_DIR) : "";
      const internal = imp.internal && packageByDir.has(targetDir) && targetDir !== sourceDir;
      if (internal) {
        const key = sourceDir + "\u0000" + targetDir;
        packageEdges.set(key, (packageEdges.get(key) || 0) + 1);
      } else {
        const path = imp.path || "";
        let entry = externalImports.get(path);
        if (!entry) {
          entry = {
            path,
            kind: classifyImport(path),
            count: 0,
            files: [],
          };
          externalImports.set(path, entry);
        }
        entry.count += 1;
        uniquePush(entry.files, imp.file);
      }
    }
  }

  /* ----------------------------------------------------------------------- */
  /* Small DOM helpers                                                       */
  /* ----------------------------------------------------------------------- */

  function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined && text !== null) node.textContent = String(text);
    return node;
  }

  function append(parent, ...children) {
    for (const child of children) {
      if (child === null || child === undefined) continue;
      if (Array.isArray(child)) parent.append(...child);
      else parent.append(child);
    }
    return parent;
  }

  function clear(node) {
    while (node.firstChild) node.removeChild(node.firstChild);
  }

  function button(label, className, onClick) {
    const b = el("button", className, label);
    b.type = "button";
    if (onClick) b.addEventListener("click", onClick);
    return b;
  }

  function badge(text, variant) {
    return el("span", "badge" + (variant ? " " + variant : ""), text);
  }

  function kindBadge(kind) {
    return el("span", "kind " + String(kind || "unknown"), kind || "unknown");
  }

  function plural(count, singular, pluralForm) {
    return `${count} ${count === 1 ? singular : (pluralForm || singular + "s")}`;
  }

  function formatSize(bytes) {
    const n = Number(bytes) || 0;
    if (n < 1024) return `${n} B`;
    if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
    return `${(n / (1024 * 1024)).toFixed(1)} MB`;
  }

  function fileLabel(file) {
    return basename(file.path);
  }

  function nodeLabel(node) {
    return node.qualified || node.name;
  }

  function fileNode(path) {
    return fileNodeByPath.get(path) || null;
  }

  function nodeFor(id) {
    return nodeById.get(id) || null;
  }

  function packageName(dir) {
    const pkg = packageByDir.get(dir);
    return pkg ? pkg.name : prettyPackage(dir, "");
  }

  function packagePath(dir) {
    if (!dir || dir === EMPTY_PACKAGE_DIR) return "";
    return dir;
  }

  function fileImportInfo(path) {
    const imports = importsByFile.get(path) || [];
    let external = false;
    let native = false;
    for (const imp of imports) {
      const target = imp.internal ? (imp.dir || EMPTY_PACKAGE_DIR) : "";
      if (imp.internal && packageByDir.has(target)) continue;
      external = true;
      const kind = classifyImport(imp.path || "");
      if (kind === "native" || kind === "system") native = true;
    }
    return { external, native };
  }

  function nodeFindings(node) {
    return findingsByNode.get(node.id) || [];
  }

  function allFindingsForFile(path) {
    const list = [];
    for (const node of nodesByFile.get(path) || []) {
      for (const rule of nodeFindings(node)) list.push({ rule, node });
    }
    return list;
  }

  function uniqueCallNodes(edges) {
    const out = [];
    const seen = new Set();
    for (const edge of edges || []) {
      const id = edge.target || edge.source;
      if (!id || seen.has(id)) continue;
      const node = nodeFor(id);
      if (!node) continue;
      seen.add(id);
      out.push(node);
    }
    return out;
  }

  /* ----------------------------------------------------------------------- */
  /* Shell                                                                   */
  /* ----------------------------------------------------------------------- */

  function buildShell() {
    clear(APP);

    const project = data.project || {};
    const title = project.name || "Code graph";
    const subtitle = project.stale_file
      ? `Graph snapshot · source changed since export`
      : `Graph snapshot · ${project.olt_version || "olt"}`;

    const topbar = el("header", "topbar");
    const brand = el("div", "brand");
    append(brand, el("h1", null, title), el("div", "subtitle", subtitle));

    const stats = el("div", "stats");
    append(
      stats,
      stat("packages", data.packages.length),
      stat("files", data.files.length),
      stat("symbols", data.summary?.symbols ?? countSymbols()),
      stat("calls", countEdges("calls")),
      stat("findings", findings.length, findings.length ? "warn" : "ok")
    );

    const searchWrap = el("div", "search-wrap");
    const searchIcon = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    searchIcon.setAttribute("viewBox", "0 0 24 24");
    searchIcon.setAttribute("fill", "none");
    searchIcon.setAttribute("stroke", "currentColor");
    searchIcon.setAttribute("stroke-width", "2");
    searchIcon.innerHTML = '<circle cx="11" cy="11" r="7"></circle><path d="m20 20-3.4-3.4"></path>';
    const search = el("input", "search");
    search.type = "search";
    search.placeholder = "Search packages, files, symbols…";
    search.setAttribute("aria-label", "Search packages, files, and symbols");
    search.value = state.query;
    search.addEventListener("input", () => {
      state.query = search.value;
      renderMap();
    });
    const searchHint = el("span", "search-hint", "/");
    append(searchWrap, searchIcon, search, searchHint);

    const toolbar = el("div", "toolbar");
    const findingsBtn = button("Findings", "btn", () => setTab("findings"));
    findingsBtn.append(el("span", "count", findings.length));
    const boundaryBtn = button("Boundary", "btn", () => setTab("boundary"));
    const themeBtn = button("Theme", "btn", toggleTheme);
    themeBtn.setAttribute("aria-label", "Toggle light and dark theme");
    append(toolbar, findingsBtn, boundaryBtn, themeBtn);

    append(topbar, brand, stats, searchWrap, toolbar);

    const workspace = el("main", "workspace");
    const mapPane = el("section", "map-pane");
    mapPane.id = "map-pane";
    const map = el("div", "map");
    map.id = "map";
    append(mapPane, map);

    const details = el("aside", "details");
    details.id = "details";
    const tabs = el("div", "tabs");
    const tabButtons = [
      ["selection", "Selection"],
      ["findings", `Findings${findings.length ? " " + findings.length : ""}`],
      ["boundary", "Boundary"],
    ].map(([id, label]) => {
      const b = button(label, "tab", () => setTab(id));
      b.dataset.tab = id;
      return b;
    });
    append(tabs, tabButtons);
    const detailBody = el("div", "details-body");
    detailBody.id = "details-body";
    append(details, tabs, detailBody);

    append(workspace, mapPane, details);
    append(APP, topbar, workspace);

    search.addEventListener("keydown", (event) => {
      if (event.key === "Escape") {
        search.value = "";
        state.query = "";
        renderMap();
      }
    });

    let resizeTimer = 0;
    window.addEventListener("resize", () => {
      window.clearTimeout(resizeTimer);
      resizeTimer = window.setTimeout(() => renderMap(), 150);
    });

    document.addEventListener("keydown", (event) => {
      const tag = String(event.target?.tagName || "").toLowerCase();
      const typing = tag === "input" || tag === "textarea" || event.target?.isContentEditable;
      if (event.key === "/" && !typing) {
        event.preventDefault();
        search.focus();
        search.select();
      } else if (event.key === "Escape" && !typing) {
        if (state.query) {
          state.query = "";
          search.value = "";
          renderMap();
        } else {
          clearSelection();
        }
      } else if (event.key.toLowerCase() === "f" && !typing) {
        setTab("findings");
      } else if (event.key.toLowerCase() === "b" && !typing) {
        setTab("boundary");
      }
    });
  }

  function stat(label, value, variant) {
    const s = el("span", "stat" + (variant ? " " + variant : ""));
    append(s, el("strong", null, String(value)), el("span", null, label));
    return s;
  }

  function countSymbols() {
    return data.nodes.filter((node) => node.kind !== "file").length;
  }

  function countEdges(kind) {
    return data.edges.filter((edge) => edge.kind === kind).length;
  }

  /* ----------------------------------------------------------------------- */
  /* Map                                                                     */
  /* ----------------------------------------------------------------------- */

  function fileMatches(file) {
    const q = state.query.trim().toLowerCase();
    if (!q) return true;
    const haystack = `${file.path} ${file.dir || ""} ${file.package || ""}`.toLowerCase();
    if (haystack.includes(q)) return true;
    for (const node of nodesByFile.get(file.path) || []) {
      if (`${node.name} ${node.qualified || ""}`.toLowerCase().includes(q)) return true;
    }
    return false;
  }

  function packageStats(dir) {
    const files = filesByDir.get(dir) || [];
    let symbols = 0;
    let calls = 0;
    let findingCount = 0;
    for (const file of files) {
      symbols += (nodesByFile.get(file.path) || []).length;
      findingCount += findingsByFile.get(file.path) || 0;
      for (const node of nodesByFile.get(file.path) || []) {
        calls += (callsOut.get(node.id) || []).filter((edge) => edge.kind === "calls").length;
      }
    }
    return { files: files.length, symbols, calls, findings: findingCount };
  }

  function mapColumnCount(map, count) {
    const width = map.clientWidth || 1000;
    const max = width < 640 ? 1 : width < 1000 ? 2 : 3;
    return Math.max(1, Math.min(count, max));
  }

  function estimateRoomHeight(files) {
    return 62 + files.length * 78;
  }

  function renderMap() {
    const map = document.getElementById("map");
    if (!map) return;
    const scrollTop = map.scrollTop;
    const scrollLeft = map.scrollLeft;
    clear(map);

    const visible = [];
    for (const [dir, files] of filesByDir) {
      const matching = files.filter(fileMatches);
      if (matching.length) visible.push([dir, matching]);
    }

    if (!visible.length) {
      append(
        map,
        el(
          "div",
          "map-empty",
          state.query
            ? `No packages or files match “${state.query}”.`
            : "No indexed files. Build the graph with `olt <target> --export-symbols`."
        )
      );
      return;
    }

    visible.sort((a, b) => {
      const an = packageName(a[0]);
      const bn = packageName(b[0]);
      return an.localeCompare(bn) || a[0].localeCompare(b[0]);
    });

    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.classList.add("edge-layer");
    svg.setAttribute("aria-hidden", "true");

    const rooms = el("div", "rooms");
    const columnCount = mapColumnCount(map, visible.length);
    const columns = [];
    for (let i = 0; i < columnCount; i += 1) {
      const column = el("div", "room-column");
      const entry = { el: column, height: 0 };
      columns.push(entry);
      rooms.append(column);
    }
    const roomEls = new Map();

    for (const [dir, files] of visible) {
      const stats = packageStats(dir);
      const room = el("section", "room");
      room.dataset.dir = dir;
      roomEls.set(dir, room);

      const head = el("div", "room-head");
      const title = el("div", "room-title");
      const name = el("span", "room-name", packageName(dir));
      const path = el("span", "room-path", packagePath(dir) || "project root");
      append(title, name, path);

      const badges = el("div", "room-badges");
      append(
        badges,
        badge(plural(stats.files, "file")),
        badge(plural(stats.symbols, "symbol")),
        stats.findings ? badge(plural(stats.findings, "finding"), "warn") : null
      );
      append(head, title, badges);

      const fileList = el("div", "files");
      files.sort((a, b) => a.path.localeCompare(b.path));
      for (const file of files) {
        const nodeCount = (nodesByFile.get(file.path) || []).length;
        const findingCount = findingsByFile.get(file.path) || 0;
        const importInfo = fileImportInfo(file.path);
        const card = el("button", "file-card");
        card.type = "button";
        card.dataset.file = file.path;
        if (state.selectedFile === file.path) card.classList.add("is-selected");
        append(
          card,
          el("span", "file-name", fileLabel(file)),
          el("span", "file-meta", plural(nodeCount, "symbol")),
          el(
            "span",
            "file-meta" + (importInfo.native ? " ffi" : ""),
            [
              findingCount ? `${findingCount} finding${findingCount === 1 ? "" : "s"}` : "",
              importInfo.native ? "FFI boundary" : "",
            ]
              .filter(Boolean)
              .join(" · ")
          )
        );
        card.addEventListener("click", () => selectFile(file.path));
        fileList.append(card);
      }

      append(room, head, fileList);
      room.addEventListener("mouseenter", () => highlightPackage(dir, roomEls, svg));
      room.addEventListener("mouseleave", () => clearHighlight(roomEls, svg));
      const target = columns.reduce((shortest, column) => (column.height < shortest.height ? column : shortest));
      target.el.append(room);
      target.height += estimateRoomHeight(files) + 18;
    }

    append(map, svg, rooms);
    requestAnimationFrame(() => {
      map.scrollTop = scrollTop;
      map.scrollLeft = scrollLeft;
      drawEdges(svg, map, roomEls);
    });
  }

  function drawEdges(svg, map, roomEls) {
    const width = Math.max(map.scrollWidth, map.clientWidth);
    const height = Math.max(map.scrollHeight, map.clientHeight);
    svg.setAttribute("width", String(width));
    svg.setAttribute("height", String(height));
    svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
    clear(svg);

    const mapRect = map.getBoundingClientRect();

    for (const [key, count] of packageEdges) {
      const [sourceDir, targetDir] = key.split("\u0000");
      const source = roomEls.get(sourceDir);
      const target = roomEls.get(targetDir);
      if (!source || !target) continue;
      const sr = source.getBoundingClientRect();
      const tr = target.getBoundingClientRect();
      const x1 = sr.left - mapRect.left + map.scrollLeft + sr.width / 2;
      const y1 = sr.top - mapRect.top + map.scrollTop + 28;
      const x2 = tr.left - mapRect.left + map.scrollLeft + tr.width / 2;
      const y2 = tr.top - mapRect.top + map.scrollTop + 28;
      if (Math.abs(x1 - x2) < 2 && Math.abs(y1 - y2) < 2) continue;

      const lift = Math.max(26, Math.abs(y2 - y1) * 0.32);
      const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
      path.setAttribute("d", `M ${x1} ${y1} C ${x1} ${y1 + lift}, ${x2} ${y2 - lift}, ${x2} ${y2}`);
      path.setAttribute("stroke-width", String(Math.min(6, 1 + Math.log2(count + 1))));
      path.dataset.source = sourceDir;
      path.dataset.target = targetDir;
      svg.append(path);
    }
  }

  function highlightPackage(dir, roomEls, svg) {
    const connected = new Set([dir]);
    for (const key of packageEdges.keys()) {
      const [source, target] = key.split("\u0000");
      if (source === dir) connected.add(target);
      if (target === dir) connected.add(source);
    }
    for (const [roomDir, room] of roomEls) {
      room.classList.toggle("is-muted", !connected.has(roomDir));
    }
    for (const path of svg.querySelectorAll("path")) {
      const active = path.dataset.source === dir || path.dataset.target === dir;
      path.classList.toggle("is-active", active);
      path.classList.toggle("is-dim", !active);
    }
  }

  function clearHighlight(roomEls, svg) {
    for (const room of roomEls.values()) room.classList.remove("is-muted");
    for (const path of svg.querySelectorAll("path")) {
      path.classList.remove("is-active", "is-dim");
    }
  }

  /* ----------------------------------------------------------------------- */
  /* Details                                                                 */
  /* ----------------------------------------------------------------------- */

  function setTab(tab) {
    state.tab = tab;
    renderDetails();
    if (window.matchMedia("(max-width: 980px)").matches) {
      document.getElementById("details")?.scrollIntoView({ behavior: "smooth", block: "start" });
    }
  }

  function renderDetails() {
    const body = document.getElementById("details-body");
    if (!body) return;

    for (const tab of document.querySelectorAll(".tab")) {
      tab.classList.toggle("is-active", tab.dataset.tab === state.tab);
    }

    clear(body);
    if (state.tab === "findings") {
      renderFindings(body);
    } else if (state.tab === "boundary") {
      renderBoundary(body);
    } else if (state.selectedNode) {
      renderNode(body, state.selectedNode);
    } else if (state.selectedFile) {
      renderFile(body, state.selectedFile);
    } else {
      renderOverview(body);
    }
  }

  function staleBanner(parent) {
    const stale = data.project?.stale_file;
    if (!stale) return;
    append(parent, el("div", "stale", `Graph may be stale: ${stale} changed after export. Re-run the export for current call edges.`));
  }

  function renderOverview(body) {
    const project = data.project || {};
    const summary = data.summary || {};
    const calls = countEdges("calls");

    staleBanner(body);
    append(body, el("p", "detail-kicker", "Code graph"));
    append(body, el("h2", "detail-title", project.name || "Project map"));
    append(body, el("p", "detail-subtitle", project.root || ""));

    const grid = el("div", "overview-grid");
    append(
      grid,
      overviewCard(summary.files ?? data.files.length, "files"),
      overviewCard(summary.packages ?? data.packages.length, "packages"),
      overviewCard(summary.symbols ?? countSymbols(), "symbols"),
      overviewCard(calls, "calls"),
      overviewCard(findings.length, "findings"),
      overviewCard(summary.unresolved ?? data.unresolved.length, "unresolved")
    );
    append(body, section("At a glance", grid));

    const packageList = el("div", "node-list");
    const packages = [...filesByDir.entries()]
      .map(([dir, files]) => ({ dir, files: files.length, stats: packageStats(dir) }))
      .sort((a, b) => b.files - a.files || packageName(a.dir).localeCompare(packageName(b.dir)))
      .slice(0, 8);
    for (const pkg of packages) {
      const row = el("button", "node-row");
      row.type = "button";
      append(
        row,
        el("span", "kind", "pkg"),
        el("span", "name", packageName(pkg.dir)),
        el("span", "where", `${packagePath(pkg.dir) || "root"} · ${plural(pkg.files, "file")}`)
      );
      row.addEventListener("click", () => {
        state.query = packageName(pkg.dir);
        const search = document.querySelector(".search");
        if (search) search.value = state.query;
        renderMap();
      });
      packageList.append(row);
    }
    append(body, section("Packages", packageList));

    const ruleList = el("div", "node-list");
    const rules = [...ruleCounts.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).slice(0, 6);
    if (!rules.length) {
      append(ruleList, el("div", "empty", "No lint findings attached to this graph."));
    } else {
      for (const [rule, count] of rules) {
        const row = el("button", "finding-row");
        row.type = "button";
        append(row, el("span", "rule", rule), el("span", "name", `${count} finding${count === 1 ? "" : "s"}`), el("span", "where", "open"));
        row.addEventListener("click", () => setTab("findings"));
        ruleList.append(row);
      }
    }
    append(body, section("Findings by rule", ruleList));

    const legend = el("div", "legend");
    append(
      legend,
      legendItem("accent", "package / file"),
      legendItem("info", "type"),
      legendItem("warn", "lint finding"),
      legendItem("ok", "FFI boundary")
    );
    const hints = el("div", "hint");
    hints.innerHTML =
      'Click a file card to inspect it. Press <kbd>/</kbd> to search, <kbd>F</kbd> for findings, <kbd>B</kbd> for the FFI boundary, <kbd>Esc</kbd> to clear.';
    append(body, section("Legend", legend), section("Controls", hints));

    append(
      body,
      section(
        "About this map",
        el(
          "p",
          "hint",
          "This view is generated from the exported code graph. It contains paths, symbol names, signatures, call edges and lint facts; source bodies are not embedded. C/C++ sources are not indexed yet, so foreign imports appear as an external boundary."
        )
      )
    );
  }

  function overviewCard(value, label) {
    const card = el("div", "overview-card");
    append(card, el("div", "value", value), el("div", "label", label));
    return card;
  }

  function legendItem(color, label) {
    const s = el("span");
    append(s, el("span", "dot " + color), el("span", null, label));
    return s;
  }

  function section(title, content) {
    const box = el("div", "detail-section");
    const head = el("div", "section-head");
    append(head, el("h3", null, title));
    append(box, head, content);
    return box;
  }

  function selectFile(path) {
    state.selectedFile = path;
    state.selectedNode = null;
    state.tab = "selection";
    renderMap();
    renderDetails();
    if (window.matchMedia("(max-width: 980px)").matches) {
      document.getElementById("details")?.scrollIntoView({ behavior: "smooth", block: "start" });
    }
  }

  function selectNode(id) {
    const node = nodeFor(id);
    if (!node) return;
    if (node.kind === "file") {
      selectFile(node.file);
      return;
    }
    state.selectedNode = id;
    state.selectedFile = node.file;
    state.tab = "selection";
    renderMap();
    renderDetails();
    if (window.matchMedia("(max-width: 980px)").matches) {
      document.getElementById("details")?.scrollIntoView({ behavior: "smooth", block: "start" });
    }
  }

  function clearSelection() {
    state.selectedNode = null;
    state.selectedFile = null;
    state.tab = "selection";
    renderMap();
    renderDetails();
  }

  function focusFileInMap(path) {
    state.query = "";
    const search = document.querySelector(".search");
    if (search) search.value = "";
    renderMap();
    requestAnimationFrame(() => {
      const card = document.querySelector(`.file-card[data-file="${cssEscape(path)}"]`);
      if (!card) return;
      card.scrollIntoView({ behavior: "smooth", block: "center" });
      card.classList.add("is-selected");
    });
  }

  function cssEscape(value) {
    if (window.CSS && typeof window.CSS.escape === "function") return window.CSS.escape(value);
    return String(value).replace(/["\\]/g, "\\$&");
  }

  function renderFile(body, path) {
    const file = fileByPath.get(path);
    const fileNodeValue = fileNode(path);
    const nodes = nodesByFile.get(path) || [];
    const fileFindings = allFindingsForFile(path);
    const importInfo = fileImportInfo(path);
    const imports = (importsByFile.get(path) || []).slice().sort((a, b) => a.line - b.line);

    staleBanner(body);
    append(body, el("p", "detail-kicker", "File"));
    append(body, el("h2", "detail-title", basename(path)));
    append(body, el("p", "detail-subtitle", path));

    const chips = el("div", "pill-row");
    if (file?.package || file?.dir) append(chips, badge(file?.package || packageName(packageOfFile.get(path) || ""), "accent"));
    if (fileNodeValue) append(chips, badge(plural(fileNodeValue.end_line - fileNodeValue.start_line + 1, "line")));
    if (file?.size) append(chips, badge(formatSize(file.size)));
    append(chips, badge(plural(nodes.length, "symbol")));
    if (fileFindings.length) append(chips, badge(plural(fileFindings.length, "finding"), "warn"));
    if (importInfo.native) append(chips, badge("FFI boundary", "info"));
    else if (importInfo.external) append(chips, badge("external imports", "info"));
    append(body, chips);

    const actions = el("div", "detail-actions");
    append(actions, button("Show in map", "btn", () => focusFileInMap(path)), button("Overview", "btn", clearSelection));
    append(body, actions);

    const declList = el("div", "node-list");
    if (!nodes.length) {
      append(declList, el("div", "empty", "No declarations indexed in this file."));
    } else {
      for (const node of nodes) declList.append(nodeRow(node));
    }
    append(body, section("Declarations", declList));

    if (imports.length) {
      const importList = el("div", "node-list");
      for (const imp of imports) {
        const target = imp.internal ? (imp.dir || EMPTY_PACKAGE_DIR) : "";
        const internal = imp.internal && packageByDir.has(target);
        const row = el("div", "boundary-item");
        append(row, el("div", "path", imp.path || "(empty import path)"));
        const meta = el(
          "div",
          "meta",
          `line ${imp.line}${imp.alias ? ` · alias ${imp.alias}` : ""}${internal ? " · internal package" : " · external / FFI"}`
        );
        append(row, meta);
        importList.append(row);
      }
      append(body, section("Imports", importList));
    }

    const callers = new Map();
    const callees = new Map();
    for (const node of nodes) {
      for (const edge of callsIn.get(node.id) || []) {
        const caller = nodeFor(edge.source);
        if (caller) callers.set(caller.id, caller);
      }
      for (const edge of callsOut.get(node.id) || []) {
        const callee = nodeFor(edge.target);
        if (callee) callees.set(callee.id, callee);
      }
    }
    if (callers.size || callees.size) {
      const callBox = el("div", "node-list");
      for (const caller of [...callers.values()].slice(0, 12)) callBox.append(nodeRow(caller));
      for (const callee of [...callees.values()].slice(0, 12)) callBox.append(nodeRow(callee));
      append(body, section(`Call neighbourhood (${callers.size} in · ${callees.size} out)`, callBox));
    }

    if (fileFindings.length) {
      const findingList = el("div", "finding-list");
      for (const finding of fileFindings) findingList.append(findingRow(finding));
      append(body, section("Findings", findingList));
    }
  }

  function renderNode(body, id) {
    const node = nodeFor(id);
    if (!node) {
      clearSelection();
      return;
    }
    const rules = nodeFindings(node);
    const callers = uniqueCallNodes(callsIn.get(node.id));
    const callees = uniqueCallNodes(callsOut.get(node.id));
    const instantiators = uniqueCallNodes(instantiatesTarget.get(node.id));

    staleBanner(body);
    append(body, el("p", "detail-kicker", node.kind || "symbol"));
    append(body, el("h2", "detail-title", node.name));
    append(body, el("p", "detail-subtitle", `${node.qualified || node.name} · ${node.file}:${node.start_line}`));

    const chips = el("div", "pill-row");
    append(chips, kindBadge(node.kind));
    if (node.visibility) append(chips, badge(node.visibility));
    if (node.exported) append(chips, badge("exported", "accent"));
    if (node.memory_role) append(chips, badge(`memory: ${node.memory_role}`, node.memory_role === "allocator" ? "info" : ""));
    if (rules.length) append(chips, badge(plural(rules.length, "finding"), "warn"));
    append(body, chips);

    const actions = el("div", "detail-actions");
    append(
      actions,
      button("Open file", "btn", () => selectFile(node.file)),
      button("Show in map", "btn", () => {
        state.selectedFile = node.file;
        state.selectedNode = null;
        focusFileInMap(node.file);
        renderDetails();
      })
    );
    append(body, actions);

    if (node.signature) append(body, section("Signature", el("pre", "sig", node.signature)));
    if (node.return_type) append(body, section("Return type", el("pre", "sig", node.return_type)));

    if (rules.length) {
      const list = el("div", "finding-list");
      for (const rule of rules) list.append(findingRow({ rule, node }));
      append(body, section("Findings", list));
    }

    if (callers.length) {
      const list = el("div", "node-list");
      for (const caller of callers.slice(0, 24)) list.append(nodeRow(caller));
      append(body, section(`Called by (${callers.length})`, list));
    }

    if (callees.length) {
      const list = el("div", "node-list");
      for (const callee of callees.slice(0, 24)) list.append(nodeRow(callee));
      append(body, section(`Calls (${callees.length})`, list));
    }

    if (instantiators.length) {
      const list = el("div", "node-list");
      for (const proc of instantiators.slice(0, 24)) list.append(nodeRow(proc));
      append(body, section(`Allocated by (${instantiators.length})`, list));
    }

    const imports = (importsByFile.get(node.file) || []).slice().sort((a, b) => a.line - b.line);
    if (imports.length) {
      const list = el("div", "node-list");
      for (const imp of imports) {
        const row = el("div", "boundary-item");
        append(row, el("div", "path", imp.path || "(empty import path)"));
        append(row, el("div", "meta", `line ${imp.line}${imp.alias ? ` · alias ${imp.alias}` : ""}`));
        list.append(row);
      }
      append(body, section("File imports", list));
    }
  }

  function nodeRow(node) {
    const row = el("button", "node-row");
    row.type = "button";
    append(
      row,
      kindBadge(node.kind),
      el("span", "name", node.name),
      el("span", "where", `${basename(node.file)}:${node.start_line}`)
    );
    row.addEventListener("click", () => selectNode(node.id));
    return row;
  }

  function findingRow(finding) {
    const row = el("button", "finding-row");
    row.type = "button";
    append(
      row,
      el("span", "rule", finding.rule),
      el("span", "name", finding.node.name),
      el("span", "where", `${basename(finding.node.file)}:${finding.node.start_line}`)
    );
    row.addEventListener("click", () => selectNode(finding.node.id));
    return row;
  }

  function renderFindings(body) {
    staleBanner(body);
    append(body, el("p", "detail-kicker", "Graph facts"));
    append(body, el("h2", "detail-title", "Findings"));
    append(body, el("p", "detail-subtitle", `${findings.length} rule hit${findings.length === 1 ? "" : "s"} attached to exported nodes`));

    if (!findings.length) {
      append(body, el("div", "empty", "No lint findings attached to this graph."));
      append(body, el("p", "hint", "The map reads the findings the exporter attached to procedures. Re-run the export after fixing code."));
      return;
    }

    const groups = new Map();
    for (const finding of findings) addToMapList(groups, finding.rule, finding);
    const ordered = [...groups.entries()].sort((a, b) => b[1].length - a[1].length || a[0].localeCompare(b[0]));

    for (const [rule, list] of ordered) {
      const card = el("div", "rule-card");
      const head = el("div", "rule-head");
      append(head, el("span", "rule-id", rule), el("span", "rule-count", `${list.length} hit${list.length === 1 ? "" : "s"}`));
      const rows = el("div", "rule-list");
      const max = 80;
      for (const finding of list.slice(0, max)) {
        const b = el("button");
        b.type = "button";
        append(
          b,
          el("span", "name", finding.node.name),
          el("span", "where", `${basename(finding.node.file)}:${finding.node.start_line}`)
        );
        b.addEventListener("click", () => selectNode(finding.node.id));
        rows.append(b);
      }
      if (list.length > max) rows.append(el("div", "hint", `…and ${list.length - max} more. Narrow with search.`));
      append(card, head, rows);
      body.append(card);
    }

    append(
      body,
      el(
        "p",
        "hint",
        "Findings are a snapshot of the exported graph. Re-run the export after code changes; this file is never written back to your source."
      )
    );
  }

  function renderBoundary(body) {
    staleBanner(body);
    append(body, el("p", "detail-kicker", "Outside the Odin graph"));
    append(body, el("h2", "detail-title", "Boundary"));
    append(body, el("p", "detail-subtitle", "Foreign imports, external packages and unresolved calls"));

    const groups = new Map();
    for (const entry of externalImports.values()) {
      const kind = entry.kind;
      if (!groups.has(kind)) groups.set(kind, []);
      groups.get(kind).push(entry);
    }
    const labels = {
      native: "Native / FFI imports",
      system: "System libraries",
      collection: "External collections",
      external: "Other external imports",
    };
    const order = ["native", "system", "collection", "external"];

    let any = false;
    for (const kind of order) {
      const entries = (groups.get(kind) || []).sort((a, b) => b.count - a.count || a.path.localeCompare(b.path));
      if (!entries.length) continue;
      any = true;
      const group = el("div", "boundary-group");
      append(group, el("h4", null, labels[kind] || kind));
      for (const entry of entries) {
        const item = el("div", "boundary-item");
        append(item, el("div", "path", entry.path || "(empty import path)"));
        const files = entry.files.slice(0, 3).map((file) => basename(file)).join(", ");
        append(
          item,
          el(
            "div",
            "meta",
            `${plural(entry.count, "import")} · ${plural(entry.files.length, "file")}${files ? ` · ${files}` : ""}`
          )
        );
        group.append(item);
      }
      body.append(group);
    }

    if (!any) {
      append(body, el("div", "empty", "No external imports recorded."));
    }

    if (data.unresolved.length) {
      const byName = new Map();
      for (const ref of data.unresolved) addToMapList(byName, ref.name, ref);
      const list = el("div", "boundary-list");
      const ordered = [...byName.entries()].sort((a, b) => b[1].length - a[1].length || a[0].localeCompare(b[0]));
      for (const [name, refs] of ordered) {
        const item = el("div", "boundary-item");
        append(item, el("div", "path", name));
        const files = [...new Set(refs.map((ref) => basename(ref.file)))].slice(0, 3).join(", ");
        append(item, el("div", "meta", `${plural(refs.length, "reference")}${files ? ` · ${files}` : ""}`));
        list.append(item);
      }
      append(body, section(`Unresolved calls (${data.unresolved.length})`, list));
    }

    append(
      body,
      section(
        "Not in this graph",
        el(
          "p",
          "hint",
          "C/C++ source bodies, C function definitions, headers and system library internals are not parsed by the Odin exporter yet. Native and system imports are shown here as the exact boundary the graph can see."
        )
      )
    );
  }

  /* ----------------------------------------------------------------------- */
  /* Theme                                                                   */
  /* ----------------------------------------------------------------------- */

  function applySavedTheme() {
    try {
      const saved = localStorage.getItem("olt-floorplan-theme");
      if (saved === "light" || saved === "dark") document.documentElement.dataset.theme = saved;
    } catch (_) {
      /* localStorage can be unavailable on file://; system theme still works. */
    }
  }

  function toggleTheme() {
    const current = document.documentElement.dataset.theme;
    const systemDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
    const next = current ? (current === "dark" ? "light" : "dark") : (systemDark ? "light" : "dark");
    document.documentElement.dataset.theme = next;
    try {
      localStorage.setItem("olt-floorplan-theme", next);
    } catch (_) {
      /* ignore */
    }
  }

  /* ----------------------------------------------------------------------- */
  /* Boot                                                                    */
  /* ----------------------------------------------------------------------- */

  if (data.schema_version !== SCHEMA_VERSION) {
    APP.textContent = `olt floorplan: unsupported data schema ${data.schema_version}; regenerate the map with this olt version.`;
    return;
  }

  prepare();
  applySavedTheme();
  buildShell();
  renderMap();
  renderDetails();
})();
