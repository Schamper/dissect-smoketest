# Show available recipes by default.
default:
    @just --list

# Run ruff check+format over all projects.
# Pass fix="true" to auto-fix instead of reporting.
ruff fix="false":
    uv run --group dev ruff check {{ if fix == "true" { "--fix" } else { "" } }}
    uv run --group dev ruff format {{ if fix == "true" { "" } else { "--check" } }}

# Run packer fmt over all templates.
# Pass fix="true" to rewrite files instead of reporting.
packer-fmt fix="false":
    packer fmt -recursive {{ if fix == "true" { "" } else { "-check -diff" } }} templates

# Check formatting and linting (ruff + packer fmt).
lint:
    just ruff
    just packer-fmt

# Auto-fix ruff and packer fmt issues.
fix:
    just ruff true
    just packer-fmt true

# Override the template's headless default, e.g. `just headless=false build pinned/debian-12`
# to watch the install in a QEMU window. Empty means "use the template's own default".
headless := ""

# Build a Packer template by name (e.g. `just build pinned/debian-12`).
# Extra args after the template are forwarded to `packer build` (e.g. `-var ...`).
# Set headless=false to build with a visible display (e.g. `just headless=false build ...`).
build template *args:
    packer init templates/{{template}}/template.pkr.hcl
    {{ if headless == "" { "" } else { "PKR_VAR_headless=" + headless } }} packer build -force {{args}} templates/{{template}}/template.pkr.hcl

# Boot a built image with QEMU (e.g. `just run pinned/debian-12`).
# Builds first if no local image exists. Extra args are forwarded to run.py
# (e.g. `--rebuild`, `--writable`, `--serial`, or `-- <qemu args>`).
run template *args:
    uv run scripts/run.py {{template}} {{args}}

# Print the content hash for a template (the blob-storage key, once wired up).
hash template:
    uv run scripts/hash.py templates/{{template}}

# Emit a JSON matrix of templates for a lifecycle (pinned|rolling|corpus|all).
matrix lifecycle *args:
    @uv run scripts/matrix.py {{lifecycle}} {{args}}

# List all available templates (optionally for one lifecycle: pinned|rolling|corpus|all).
templates lifecycle="all":
    @uv run scripts/matrix.py {{lifecycle}} | uv run python -c 'import json, sys; print("\n".join(e["template"] for e in json.load(sys.stdin)))'

# Upload a built image to S3 and mark it as latest (requires appropriate env vars).
upload template version:
    uv run scripts/storage.py upload {{template}} {{version}}

# Download the latest known-good image for a template from blob storage.
download template:
    uv run scripts/storage.py download {{template}}

# Prune old image versions for one template in the bucket.
prune template *args:
    uv run scripts/storage.py prune {{template}} {{args}}

# Prune old image versions for every template.
prune-all *args:
    #!/usr/bin/env bash
    set -euo pipefail
    for t in $(uv run scripts/matrix.py all | uv run python -c 'import json, sys; print(" ".join(e["template"] for e in json.load(sys.stdin)))'); do
        uv run scripts/storage.py prune "$t" {{args}}
    done

# Fetch external build assets (e.g. ISOs) declared in image.yml.
fetch-assets template:
    uv run scripts/storage.py fetch-assets {{template}}

# Run pytest. Tests against all locally built images.
test *args:
    uv run -p 3.10 pytest {{args}}

# blaze it 4:20
blaze *args:
    @just test {{ if args == "it" { "" } else { trim_start_match(args, "it ") } }}

# Remove all built images.
clean:
    rm -rf local/build
