# cli: Command-line argument parsing for Zig. `just --list` shows the recipes.
# AGENTS.md holds the working conventions.

[private]
default:
    @just --list

[doc("Unit tests")]
[group("test")]
test *ARGS:
    zig build test --summary all -- {{ ARGS }}

[private]
api:
    docgen --root src/root.zig --title cli --repo-url https://github.com/baskingspot/cli --rev main --format json --out docs/data

[doc("Build the site into zig-out/site/cli/: docgen JSON rendered by the theme's api.html")]
[group("docs")]
doc: api
    baskingspot-docs build cli

[doc("Edit the guide with live reload (http://127.0.0.1:1111)")]
[group("docs")]
guide: api
    baskingspot-docs serve cli

[doc("Deploy the rendered site to Cloudflare as an assets-only Worker (config in wrangler.jsonc). Needs CLOUDFLARE_API_TOKEN in the environment, plus CLOUDFLARE_ACCOUNT_ID if the token can see more than one account")]
[group("docs")]
doc-deploy: doc
    wrangler deploy

[doc("Lint Zig, Nix, Markdown, the workflows, and this justfile: ziglint, the ast-grep rules, zig fmt, nix fmt, oxfmt, actionlint, zizmor, and just --fmt")]
[group("lint")]
lint:
    ziglint
    baskingspot-lint src
    zig fmt --check src build.zig
    nix fmt -- --ci
    oxfmt --check README.md AGENTS.md docs/content docs/config.toml wrangler.jsonc .github
    actionlint
    zizmor .
    just --fmt --check

[doc("Format everything lint checks")]
[group("lint")]
fmt:
    zig fmt src build.zig
    nix fmt
    oxfmt README.md AGENTS.md docs/content docs/config.toml wrangler.jsonc .github
    just --fmt

[doc("Everything CI runs")]
[group("ci")]
ci: test lint doc
