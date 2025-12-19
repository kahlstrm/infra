# Show available commands
[no-cd]
help:
    #!/usr/bin/env bash
    SECRET_NAME=$(basename $(pwd))
    echo "Secret Management Commands:"
    echo "  just edit              - Edit the secret for current folder ($SECRET_NAME)"
    echo "  just view              - View current secret value"
    echo "  just list-versions     - List all versions of the secret"
    echo "  just clean             - Clean old versions (keep latest 2)"
    echo "  just clean --dry-run   - Dry run: show what would be deleted"
    echo ""
    echo "Current secret: $SECRET_NAME"

# Edit secret
[no-cd]
edit:
    #!/usr/bin/env bash
    set -euo pipefail
    SECRET_NAME=$(basename $(pwd))
    echo "Editing secret: $SECRET_NAME"
    TEMP_FILE=$(mktemp --suffix=.json)
    trap 'rm -f $TEMP_FILE' EXIT

    echo "Downloading current secret..."
    if gcloud secrets versions access latest --secret="$SECRET_NAME" > "${TEMP_FILE}.raw" 2>/dev/null; then
        jq . "${TEMP_FILE}.raw" > "$TEMP_FILE"
        rm -f "${TEMP_FILE}.raw"
    else
        echo "Warning: Could not fetch latest version (might be new). Initializing with empty JSON."
        echo "{}" > "$TEMP_FILE"
    fi
    ${EDITOR:-vim} $TEMP_FILE

    echo "Validating and formatting JSON..."
    if [ ! -s "$TEMP_FILE" ]; then
        echo "File is empty. Skipping upload."
        exit 0
    fi

    if ! jq empty < "$TEMP_FILE"; then
        echo "Error: Invalid JSON format! Skipping upload."
        exit 1
    fi

    # Format the JSON properly
    jq . < $TEMP_FILE > ${TEMP_FILE}.formatted
    mv ${TEMP_FILE}.formatted $TEMP_FILE

    echo "Uploading new version..."
    gcloud secrets versions add $SECRET_NAME --data-file=$TEMP_FILE

    # Show final version count
    FINAL_VERSIONS=$(gcloud secrets versions list $SECRET_NAME --filter="state:ENABLED" --format="value(name)" | wc -l)
    echo "Active versions: $FINAL_VERSIONS"
    echo "Secret $SECRET_NAME updated successfully!"

# View secret
[no-cd]
view:
    #!/usr/bin/env bash
    SECRET_NAME=$(basename $(pwd))
    echo "Current value of $SECRET_NAME:" >&2
    gcloud secrets versions access latest --secret="$SECRET_NAME" | jq .

# List all versions
[no-cd]
list-versions:
    #!/usr/bin/env bash
    SECRET_NAME=$(basename $(pwd))
    echo "All versions of $SECRET_NAME:"
    gcloud secrets versions list $SECRET_NAME --format="table(name,state,createTime)"

# Clean old versions (keep latest 2)
[no-cd]
clean dry_run="false":
    #!/usr/bin/env bash
    set -euo pipefail
    SECRET_NAME=$(basename $(pwd))

    # Normalize dry_run to true if it's not false
    DRY_RUN=false
    if [ "{{dry_run}}" != "false" ]; then
        DRY_RUN=true
    fi

    if [ "$DRY_RUN" = "true" ]; then
        echo "DRY RUN: What would be deleted from $SECRET_NAME (keeping latest 2)..."
    else
        echo "Cleaning old versions of $SECRET_NAME (keeping latest 2)..."
    fi

    # Get version IDs (basename) only
    OLD_VERSIONS=$(gcloud secrets versions list $SECRET_NAME --filter="state:ENABLED" --format="value(name.basename())" --sort-by="~createTime" | tail -n +3)

    if [ -n "$OLD_VERSIONS" ]; then
        if [ "$DRY_RUN" = "true" ]; then
            echo "Would destroy versions:"
            for version in $OLD_VERSIONS; do
                echo "  - $version"
            done
            
            KEEP_VERSIONS=$(gcloud secrets versions list $SECRET_NAME --filter="state:ENABLED" --format="value(name.basename())" --sort-by="~createTime" | head -n 2)
            echo "Would keep versions:"
            for version in $KEEP_VERSIONS; do
                echo "  - $version"
            done
        else
            echo "Destroying versions..."
            for version in $OLD_VERSIONS; do
                echo "  - Destroying version $version..."
                gcloud secrets versions destroy "$version" --secret="$SECRET_NAME" --quiet
            done
            echo "Cleanup complete"
        fi
    else
        echo "No old versions to clean up (<= 2 versions exist)."
    fi

