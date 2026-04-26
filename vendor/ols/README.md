# OLS — Odin Language Server

olt no longer bundles a fork of OLS. The olt-lsp binary wraps **vanilla upstream OLS**
as a transparent proxy, injecting olt lint diagnostics into the editor stream.

## Get OLS

Install the official upstream release:

```
https://github.com/DanielGavin/ols
```

Then configure olt to find it:

```toml
# olt.toml
[tools]
ols_path = "/usr/local/bin/ols"   # or wherever you installed it
```

Or run `olt --init` to detect and configure OLS automatically.
