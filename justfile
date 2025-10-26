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
    gcloud secrets versions access latest --secret="$SECRET_NAME" | jq . > $TEMP_FILE
    ${EDITOR:-vim} $TEMP_FILE

    echo "Validating and formatting JSON..."
    if ! jq empty < $TEMP_FILE; then
        echo "Error: Invalid JSON format!"
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
    echo "{{dry_run}}"

    if [ "{{dry_run}}" != "false" ]; then
        echo "DRY RUN: What would be deleted from $SECRET_NAME (keeping latest 2)..."
        ACTION="Would destroy"
        VERB="would be"
    else
        echo "Cleaning old versions of $SECRET_NAME (keeping latest 2)..."
        ACTION="Destroying"
        VERB="cleanup"
    fi

    OLD_VERSIONS=$(gcloud secrets versions list $SECRET_NAME --filter="state:ENABLED" --format="value(name)" --sort-by="~createTime" | tail -n +3)

    if [ -n "$OLD_VERSIONS" ]; then
        echo "$ACTION versions: $OLD_VERSIONS"
        if [ "{{dry_run}}" = "true" ]; then
            for version in $OLD_VERSIONS; do
                echo "  - $version"
            done
            KEEP_VERSIONS=$(gcloud secrets versions list $SECRET_NAME --filter="state:ENABLED" --format="value(name)" --sort-by="~createTime" | head -n 2)
            echo "Would keep these versions:"
            for version in $KEEP_VERSIONS; do
                echo "  - $version (keep)"
            done
        else
            for version in $OLD_VERSIONS; do
                gcloud secrets versions destroy $version --secret="$SECRET_NAME" --quiet
            done
            echo "Cleanup complete"
        fi
    else
        echo "No old versions to clean up"
    fi

# RouterOS REST API debug
[no-cd]
rest router method path +curl_args='':
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "${MT_PASSWORD:-}" ]; then
        echo "Error: MT_PASSWORD environment variable not set"
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
