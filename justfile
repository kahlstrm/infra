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
    echo "RouterOS REST API Commands:"
    echo "  just rest <router> <method> <path>  - Debug RouterOS REST API"
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

# RouterOS REST API debug
[no-cd]
rest router method path +curl_args='':
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -f .env ]; then
        set -a
        source .env
        set +a
    fi
    if [ -z "${MT_PASSWORD:-}" ]; then
        case "{{router}}" in
            rb5009) MT_PASSWORD=${MT_PASSWORD_RB5009:-} ;;
            hex_s)  MT_PASSWORD=${MT_PASSWORD_HEX_S:-} ;;
        esac
    fi
    if [ -z "${MT_PASSWORD:-}" ]; then
        echo "Error: no password set for router '{{router}}'. Run 'just env' to materialize MT_PASSWORD_HEX_S / MT_PASSWORD_RB5009 or export MT_PASSWORD manually." >&2
        exit 1
    fi
    case "{{router}}" in
        rb5009)
            ROUTER_URL="https://kuberack-rb5009.networking.kalski.xyz"
            ;;
        hex_s)
            ROUTER_URL="https://stationary-hex-s.networking.kalski.xyz"
            ;;
        *)
            ROUTER_URL="http://{{router}}"
            ;;
    esac
    METHOD="{{method}}"
    curl -sk -u "admin:$MT_PASSWORD" -X "${METHOD^^}" {{curl_args}} "$ROUTER_URL/rest/{{path}}"

# Generate a local .env with RouterOS passwords from the `local-networking` secret
[no-cd]
env outfile=".env":
    #!/usr/bin/env bash
    set -euo pipefail
    SECRET_NAME=$(basename "$(pwd)")
    SECRET_JSON=$(gcloud secrets versions access latest --secret="$SECRET_NAME")
    HEX_S_PASSWORD=$(echo "$SECRET_JSON" | jq -r '.hex_s.password // empty')
    RB5009_PASSWORD=$(echo "$SECRET_JSON" | jq -r '.rb5009.password // empty')
    if [ -z "$HEX_S_PASSWORD" ] && [ -z "$RB5009_PASSWORD" ]; then
        echo "Error: no hex_s.password or rb5009.password fields found in secret $SECRET_NAME" >&2
        exit 1
    fi
    {
      echo "# generated $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      [ -n "$HEX_S_PASSWORD" ] && echo "MT_PASSWORD_HEX_S=$HEX_S_PASSWORD"
      [ -n "$RB5009_PASSWORD" ] && echo "MT_PASSWORD_RB5009=$RB5009_PASSWORD"
    } > "{{outfile}}"
    chmod 600 "{{outfile}}"
    echo "Wrote {{outfile}} from secret $SECRET_NAME"
