#!/bin/bash

# Display banner
banner="
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|      ..| search crt.sh v2.4 |..      |
+    site: crt.sh Certificate Search   +
|           Twitter: az7rb             |
|         Modified by: Arqsz           |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
"

show_help() {
    echo "A script to query the crt.sh certificate transparency log."
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -d, --domain <domain>        Search for a specific domain name (e.g., hackerone.com)"
    echo "      --org <organization>     Search for a specific organization name (e.g., 'HackerOne, Inc.')"
    echo "  -o, --output <file>          File to save results. If not set, results are printed to stdout."
    echo "  -s, --silent                 Suppress banner and non-essential output."
    echo "  -h, --help                   Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --domain hackerone.com"
    echo "  $0 --org 'HackerOne, Inc.' --output ./results.txt"
    echo "  $0 -d example.com -s | grep '.com'"
}

# Purpose: Clean and filter the results by removing unwanted characters and duplicates.
# - Converts escaped newlines to actual newlines.
# - Removes wildcard characters (*).
# - Filters out email addresses.
# - Sorts the results and removes duplicates.
clean_results() {
    sed 's/\\n/\n/g' | \
    sed 's/\*.//g' | \
    # Filter out entries that are likely email addresses
    grep -v '@' | \
    # Filter out lines with spaces (e.g., certificate names)
    grep -v ' ' | \
    # Filter out entries that do not contain a dot (i.e., not a full domain)
    grep '\.' | \
    # Remove any leading/trailing whitespace
    sed 's/^[ \t]*//;s/[ \t]*$//' | \
    sort -u
}

# This function's only output to stdout is the list of results.
domain_search() {
    local domain_req="$1"
    local silent_mode="$2"

    if [[ "$silent_mode" = false ]]; then
        # Print status messages to stderr to not interfere with stdout
        echo "[*] Searching for domain: $domain_req" >&2
    fi
    
    local response
    response=$(curl -fs "https://crt.sh?q=%.$domain_req&output=json")

    # If request fails or returns no data, return nothing.
    if [[ $? -ne 0 || -z "$response" || "$response" == "[]" ]]; then
        return
    fi

    local results
    results=$(echo "$response" | jq -r '.[].common_name, .[].name_value' | clean_results)

    # Return the results
    echo "$results"
}

# Purpose: Search for certificates associated with a specific organization name.
org_search() {
    local org_req="$1"
    local silent_mode="$2"

    if [[ "$silent_mode" = false ]]; then
        # Print status messages to stderr
        echo "[*] Searching for organization: $org_req" >&2
    fi

    local response
    response=$(curl -fs "https://crt.sh?q=$org_req&output=json")
    
    # If request fails or returns no data, return nothing.
    if [[ $? -ne 0 || -z "$response" || "$response" == "[]" ]]; then
        return
    fi

    local results
    results=$(echo "$response" | jq -r '.[].common_name, .[].name_value' | clean_results)

    # Return the results
    echo "$results"
}

# Main Script Logic

DOMAIN_SEARCH=""
ORG_SEARCH=""
OUTPUT_FILE=""
SILENT_MODE=false

# Display help if no arguments are given
if [[ "$#" -eq 0 ]]; then
    show_help
    exit 0
fi

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -s|--silent)
            SILENT_MODE=true
            ;;
        -d|--domain)
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                DOMAIN_SEARCH="$2"
                shift # consume value
            else
                echo "Error: Missing argument for $1" >&2
                exit 1
            fi
            ;;
        --org)
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                ORG_SEARCH="$2"
                shift # consume value
            else
                echo "Error: Missing argument for $1" >&2
                exit 1
            fi
            ;;
        -o|--output)
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                OUTPUT_FILE="$2"
                shift # consume value
            else
                echo "Error: Missing argument for $1" >&2
                exit 1
            fi
            ;;
        *)
            echo "Error: Unknown parameter passed: $1" >&2
            show_help
            exit 1
            ;;
    esac
    shift
done

# Display banner unless in silent mode
if [[ "$SILENT_MODE" = false ]]; then
    echo "${banner}" >&2
fi

# Display help if no action is specified
if [[ -z "$DOMAIN_SEARCH" && -z "$ORG_SEARCH" ]]; then
    show_help
    exit 0
fi

# --- Argument Validation and Execution ---

if [[ -n "$DOMAIN_SEARCH" && -n "$ORG_SEARCH" ]]; then
    echo "Error: Please specify either a domain (-d) or an organization (--org), not both." >&2
    exit 1
elif [[ -z "$DOMAIN_SEARCH" && -z "$ORG_SEARCH" ]]; then
    echo "Error: You must specify a domain (-d) or an organization (--org) to search." >&2
    show_help
    exit 1
fi

# Execute the appropriate function and capture its output
RESULTS=""
if [[ -n "$DOMAIN_SEARCH" ]]; then
    RESULTS=$(domain_search "$DOMAIN_SEARCH" "$SILENT_MODE")
elif [[ -n "$ORG_SEARCH" ]]; then
    # URL-encode the organization string for the query
    ORG_SEARCH_ENCODED=$(echo -n "$ORG_SEARCH" | jq -sRr @uri)
    RESULTS=$(org_search "$ORG_SEARCH_ENCODED" "$SILENT_MODE")
fi

# Check if any results were returned
if [[ -z "$RESULTS" ]]; then
    if [[ "$SILENT_MODE" = false ]]; then
        echo "[-] No results found." >&2
    fi
    exit 1
fi

# Decide where to send the output based on whether -o was used
if [[ -n "$OUTPUT_FILE" ]]; then
    # User specified a file, so save it there
    output_dir=$(dirname "$OUTPUT_FILE")
    mkdir -p "$output_dir"
    if [[ ! -d "$output_dir" ]]; then
        echo "Error: Could not create output directory for: $OUTPUT_FILE" >&2
        exit 1
    fi
    echo "$RESULTS" > "$OUTPUT_FILE"
    
    if [[ "$SILENT_MODE" = false ]]; then
        printf "[+] Total of %s unique domains found.\n" "$(echo "$RESULTS" | wc -l)" >&2
        printf "[+] Results saved to %s\n" "$OUTPUT_FILE" >&2
    fi
else
    # No output file specified, so print to stdout
    echo "$RESULTS"
fi