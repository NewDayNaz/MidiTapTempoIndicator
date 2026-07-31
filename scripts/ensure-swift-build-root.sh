#!/usr/bin/env bash
# Ensure Swift's .build cache matches the current project directory.
# Swift embeds absolute paths in its module cache; renaming or moving the
# project folder leaves stale artifacts that break the next build.

ensure_swift_build_root() {
    local root="$1"
    local marker="${root}/.build/.project-root"
    local needs_clean=false

    if [[ -d "${root}/.build" ]]; then
        if [[ -f "$marker" ]] && [[ "$(<"$marker")" != "$root" ]]; then
            needs_clean=true
            echo "==> Project path changed (was $(<"$marker")); cleaning stale Swift build cache..."
        elif [[ ! -f "$marker" ]]; then
            local desc
            desc="$(find "${root}/.build" -name description.json 2>/dev/null | head -1)"
            if [[ -n "$desc" ]] && ! grep -Fq "${root}/" "$desc"; then
                needs_clean=true
                echo "==> Stale Swift build cache detected; cleaning..."
            fi
        fi

        if $needs_clean; then
            rm -rf "${root}/.build"
        fi
    fi

    mkdir -p "${root}/.build"
    printf '%s\n' "$root" > "$marker"
}
