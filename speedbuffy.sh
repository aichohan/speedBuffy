#!/usr/bin/env bash
# SpeedBuffy - Zero-install ASCII speed test for Linux/Raspberry Pi systems
# Designed by @ai_chohan

# Strict error handling
set -euo pipefail

# Default values
DEFAULT_DL_SIZE=100 # MB
DEFAULT_DL_CAP=30   # seconds
DEFAULT_UL_CAP=30   # seconds
DEFAULT_IPV="auto"  # IP version preference
USE_COLOR=true      # Default to color if terminal supports it
DEBUG=false         # Debug mode off by default

# File for debug logs
DEBUG_LOG="/tmp/speedbuffy.log"

# Default test servers
DEFAULT_DOWNLOAD_SERVERS=(
    "https://speed.cloudflare.com/__down?bytes=BYTES"
    "https://httpbin.org/stream-bytes/BYTES"
    "http://speedtest.ftp.otenet.gr/files/SIZE_MB.test"
    "http://speedtest.tele2.net/SIZE_MB.zip"
)

DEFAULT_UPLOAD_SERVERS=(
    "https://httpbin.org/post"
    "https://postman-echo.com/post"
)

# Active test servers - will be populated based on selection
DOWNLOAD_SERVERS=()
UPLOAD_SERVERS=()
SELECTED_DOWNLOAD_SERVER=""
SELECTED_UPLOAD_SERVER=""

# Initialize variables to avoid unbound variable errors
LATENCY_LOSS=0
LATENCY_AVG=0
LATENCY_JITTER=0
LATENCY_TARGET="8.8.8.8"  # Default ping target
DOWNLOAD_MBPS=0
DOWNLOAD_MBPS_PRETTY=0
DOWNLOAD_MBPS_BITS=0
DOWNLOAD_SECONDS=0
DOWNLOAD_SERVER=""        # Will store the server used
UPLOAD_MBPS=0
UPLOAD_MBPS_PRETTY=0
UPLOAD_MBPS_BITS=0
UPLOAD_SECONDS=0
UPLOAD_SERVER=""          # Will store the server used

# Terminal dimensions
TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)
TERM_HEIGHT=$(tput lines 2>/dev/null || echo 24)

# Check if stdout is a terminal
if [[ ! -t 1 ]]; then
    USE_COLOR=false
fi

# Color definitions
if [[ "$USE_COLOR" == true ]]; then
    COLOR_RESET=$(tput sgr0)
    COLOR_BOLD=$(tput bold)
    COLOR_RED=$(tput setaf 1)
    COLOR_GREEN=$(tput setaf 2)
    COLOR_YELLOW=$(tput setaf 3)
    COLOR_BLUE=$(tput setaf 4)
    COLOR_MAGENTA=$(tput setaf 5)
    COLOR_CYAN=$(tput setaf 6)
    COLOR_WHITE=$(tput setaf 7)
else
    COLOR_RESET=""
    COLOR_BOLD=""
    COLOR_RED=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_BLUE=""
    COLOR_MAGENTA=""
    COLOR_CYAN=""
    COLOR_WHITE=""
fi

# Function to log debug messages
log_debug() {
    if [[ "$DEBUG" == true ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$DEBUG_LOG"
    fi
}

# Function to display the header with ASCII banner
display_header() {
    clear
    echo
    echo "                         _   ___        __  __       "
    echo " ___ _ __   ___  ___  __| | / __\_   _ / _|/ _|_   _ "
    echo "/ __| '_ \ / _ \/ _ \/ _\` |/__\// | | | |_| |_| | | |"
    echo "\__ \ |_) |  __/  __/ (_| / \/  \ |_| |  _|  _| |_| |"
    echo "|___/ .__/ \___|\___|\__,_\_____/\__,_|_| |_|  \__, |"
    echo "    |_|                                        |___/ "
    echo "         __"
    echo "        /  \__  /\_/\  Buffy"
    echo "       /\_/  _/  \_ _/  the Dog"
    echo "          /  /   / \\"
    echo "          \_/   /_/  "
    echo
    printf '%*s\n' "$TERM_WIDTH" | tr ' ' '-'
    echo
}

# Function to display the footer
display_footer() {
    echo
    printf '%*s\n' "$TERM_WIDTH" | tr ' ' '-'
    printf "%*s\n" "$TERM_WIDTH" "Designed by @ai_chohan"
}

# Function to create a horizontal ASCII progress bar
display_progress_bar() {
    local percent=$1
    local width=$2
    local bar_width=$((width - 7)) # Account for percentage display
    local completed=$((bar_width * percent / 100))
    local remaining=$((bar_width - completed))
    
    printf "["
    printf "%${completed}s" | tr ' ' '#'
    printf "%${remaining}s" | tr ' ' ' '
    printf "] %3d%%\r" "$percent"
}

# Function to run latency test
run_latency_test() {
    local target="${1:-$LATENCY_TARGET}" # Use provided target or default
    local count=10
    local timeout=1
    local results
    
    # Store the target for reporting
    LATENCY_TARGET=$target
    
    echo "${COLOR_CYAN}Starting latency test to $target...${COLOR_RESET}"
    echo
    
    # Try ping with different options based on system
    if ping -c 1 -W 1 "$target" &>/dev/null; then
        log_debug "Using standard ping options"
        results=$(ping -c "$count" -W "$timeout" "$target" 2>/dev/null)
    elif ping -c 1 -w 1 "$target" &>/dev/null; then
        log_debug "Using alternative ping timeout option"
        results=$(ping -c "$count" -w "$timeout" "$target" 2>/dev/null)
    else
        log_debug "Ping failed with both timeout options"
        echo "${COLOR_RED}Ping test failed. Check your network connection.${COLOR_RESET}"
        LATENCY_LOSS=100
        LATENCY_AVG=0
        LATENCY_JITTER=0
        return 1
    fi
    
    # Display live progress
    for i in $(seq 1 "$count"); do
        percent=$((i * 100 / count))
        display_progress_bar "$percent" "$((TERM_WIDTH - 10))"
        sleep 0.1
    done
    echo
    
    # Parse ping results
    if [[ -n "$results" ]]; then
        # Extract packet loss percentage
        local loss
        loss=$(echo "$results" | grep -oP '\d+(?=% packet loss)' || echo "0")
        LATENCY_LOSS=$loss
        
        # Extract average round-trip time
        local avg
        avg=$(echo "$results" | grep -oP 'min/avg/max/(mdev|stddev) = \d+\.\d+/\K\d+\.\d+(?=/\d+\.\d+/\d+\.\d+)' || echo "0")
        LATENCY_AVG=$(echo "$avg" | awk '{printf "%.2f", $1}')
        
        # Extract jitter (mdev or stddev)
        local jitter
        jitter=$(echo "$results" | grep -oP 'min/avg/max/(mdev|stddev) = \d+\.\d+/\d+\.\d+/\d+\.\d+/\K\d+\.\d+' || echo "0")
        LATENCY_JITTER=$(echo "$jitter" | awk '{printf "%.2f", $1}')
        
        echo "${COLOR_GREEN}Latency test completed.${COLOR_RESET}"
        echo "Packet Loss: ${COLOR_BOLD}${LATENCY_LOSS}%${COLOR_RESET}"
        echo "Average Latency: ${COLOR_BOLD}${LATENCY_AVG} ms${COLOR_RESET}"
        echo "Jitter: ${COLOR_BOLD}${LATENCY_JITTER} ms${COLOR_RESET}"
        echo
    else
        echo "${COLOR_RED}Failed to parse ping results.${COLOR_RESET}"
        LATENCY_LOSS=100
        LATENCY_AVG=0
        LATENCY_JITTER=0
        return 1
    fi
    
    return 0
}

# Function to run download test
run_download_test() {
    local size=${1:-$DEFAULT_DL_SIZE}
    local cap=${2:-$DEFAULT_DL_CAP}
    local start_time
    local end_time
    local duration
    local speed_mbps
    local speed_mbps_bits
    
    # Prepare download servers if not already set
    if [[ ${#DOWNLOAD_SERVERS[@]} -eq 0 ]]; then
        # Use default servers with size substituted
        for server in "${DEFAULT_DOWNLOAD_SERVERS[@]}"; do
            # Replace placeholders with actual values
            server="${server//BYTES/$((size * 1000000))}"
            server="${server//SIZE_MB/$size}"
            DOWNLOAD_SERVERS+=("$server")
        done
    fi
    
    # If a specific server is selected, use only that one
    if [[ -n "$SELECTED_DOWNLOAD_SERVER" ]]; then
        local selected_server="$SELECTED_DOWNLOAD_SERVER"
        # Replace placeholders with actual values
        selected_server="${selected_server//BYTES/$((size * 1000000))}"
        selected_server="${selected_server//SIZE_MB/$size}"
        DOWNLOAD_SERVERS=("$selected_server")
    fi
    
    echo "${COLOR_CYAN}Starting download test (${size}MB, ${cap}s cap)...${COLOR_RESET}"
    echo
    
    for server in "${DOWNLOAD_SERVERS[@]}"; do
        echo "Trying server: $server"
        log_debug "Attempting download from: $server"
        
        # Start timer
        start_time=$(date +%s.%N)
        
        # Use curl with progress bar, timeout, and range requests if supported
        if curl -s -I "$server" | grep -q "Accept-Ranges: bytes"; then
            log_debug "Server supports range requests"
            
            # Download with range requests to show progress
            local total_bytes=$((size * 1000000))
            local chunk_size=$((total_bytes / 10))
            local downloaded=0
            local success=true
            
            for i in {0..9}; do
                local start_byte=$((i * chunk_size))
                local end_byte=$(( (i+1) * chunk_size - 1 ))
                if [[ $i -eq 9 ]]; then
                    end_byte=$((total_bytes - 1))
                fi
                
                echo -n "Downloading chunk $((i+1))/10: "
                if ! curl -s -m "$cap" -r "$start_byte-$end_byte" "$server" -o /dev/null; then
                    log_debug "Failed to download chunk $((i+1))"
                    success=false
                    break
                fi
                
                downloaded=$((downloaded + (end_byte - start_byte + 1)))
                percent=$((downloaded * 100 / total_bytes))
                display_progress_bar "$percent" "$((TERM_WIDTH - 10))"
            done
            echo
            
            if [[ "$success" == false ]]; then
                log_debug "Range request download failed, trying next server"
                continue
            fi
        else
            log_debug "Server doesn't support range requests, using regular download"
            if ! curl -s -m "$cap" --progress-bar "$server" -o /dev/null; then
                log_debug "Regular download failed, trying next server"
                continue
            fi
        fi
        
        # End timer
        end_time=$(date +%s.%N)
        
        # Calculate duration and speed
        duration=$(echo "$end_time $start_time" | awk '{printf "%.2f", $1 - $2}')
        
        # Avoid division by zero
        if (( $(echo "$duration < 0.01" | bc -l) )); then
            duration=0.01
        fi
        
        speed_mbps=$(echo "$size $duration" | awk '{printf "%.2f", $1 / $2}')
        speed_mbps_bits=$(echo "$speed_mbps" | awk '{printf "%.2f", $1 * 8}')
        
        DOWNLOAD_MBPS=$speed_mbps
        DOWNLOAD_MBPS_PRETTY=$(printf "%.2f" "$speed_mbps")
        DOWNLOAD_MBPS_BITS=$(printf "%.2f" "$speed_mbps_bits")
        DOWNLOAD_SECONDS=$duration
        DOWNLOAD_SERVER=$server  # Store the server used
        
        echo "${COLOR_GREEN}Download test completed.${COLOR_RESET}"
        echo "Speed: ${COLOR_BOLD}${DOWNLOAD_MBPS_PRETTY} MB/s (${DOWNLOAD_MBPS_BITS} Mb/s)${COLOR_RESET}"
        echo "Time: ${COLOR_BOLD}${DOWNLOAD_SECONDS} seconds${COLOR_RESET}"
        echo
        
        return 0
    done
    
    echo "${COLOR_RED}All download servers failed.${COLOR_RESET}"
    DOWNLOAD_MBPS=0
    DOWNLOAD_MBPS_PRETTY="0.00"
    DOWNLOAD_MBPS_BITS="0.00"
    DOWNLOAD_SECONDS=0
    
    return 1
}

# Function to run upload test
run_upload_test() {
    local size=${1:-$((DEFAULT_DL_SIZE / 10))} # Default to 1/10th of download size
    local cap=${2:-$DEFAULT_UL_CAP}
    local start_time
    local end_time
    local duration
    local speed_mbps
    local speed_mbps_bits
    
    # Prepare upload servers if not already set
    if [[ ${#UPLOAD_SERVERS[@]} -eq 0 ]]; then
        UPLOAD_SERVERS=("${DEFAULT_UPLOAD_SERVERS[@]}")
    fi
    
    # If a specific server is selected, use only that one
    if [[ -n "$SELECTED_UPLOAD_SERVER" ]]; then
        UPLOAD_SERVERS=("$SELECTED_UPLOAD_SERVER")
    fi
    
    echo "${COLOR_CYAN}Starting upload test (${size}MB, ${cap}s cap)...${COLOR_RESET}"
    echo
    
    # Create a temporary file with random data
    local temp_file
    temp_file=$(mktemp)
    
    # Generate random data (in chunks to avoid memory issues)
    local chunk_size=10 # MB
    local chunks=$((size / chunk_size))
    if [[ $chunks -lt 1 ]]; then
        chunks=1
        chunk_size=$size
    fi
    
    echo "Preparing test data..."
    for ((i=0; i<chunks; i++)); do
        dd if=/dev/urandom of="$temp_file" bs=1M count="$chunk_size" conv=notrunc oflag=append 2>/dev/null
        percent=$(( (i+1) * 100 / chunks ))
        display_progress_bar "$percent" "$((TERM_WIDTH - 10))"
    done
    echo
    
    for server in "${UPLOAD_SERVERS[@]}"; do
        echo "Trying server: $server"
        log_debug "Attempting upload to: $server"
        
        # Start timer
        start_time=$(date +%s.%N)
        
        # Upload the file
        if ! curl -s -m "$cap" -X POST -F "file=@$temp_file" "$server" -o /dev/null; then
            log_debug "Upload failed, trying next server"
            continue
        fi
        
        # End timer
        end_time=$(date +%s.%N)
        
        # Calculate duration and speed
        duration=$(echo "$end_time $start_time" | awk '{printf "%.2f", $1 - $2}')
        
        # Avoid division by zero
        if (( $(echo "$duration < 0.01" | awk '{print ($1 < 0.01)}') )); then
            duration=0.01
        fi
        
        speed_mbps=$(echo "$size $duration" | awk '{printf "%.2f", $1 / $2}')
        speed_mbps_bits=$(echo "$speed_mbps" | awk '{printf "%.2f", $1 * 8}')
        
        UPLOAD_MBPS=$speed_mbps
        UPLOAD_MBPS_PRETTY=$(printf "%.2f" "$speed_mbps")
        UPLOAD_MBPS_BITS=$(printf "%.2f" "$speed_mbps_bits")
        UPLOAD_SECONDS=$duration
        UPLOAD_SERVER=$server  # Store the server used
        
        # Clean up
        rm -f "$temp_file"
        
        echo "${COLOR_GREEN}Upload test completed.${COLOR_RESET}"
        echo "Speed: ${COLOR_BOLD}${UPLOAD_MBPS_PRETTY} MB/s (${UPLOAD_MBPS_BITS} Mb/s)${COLOR_RESET}"
        echo "Time: ${COLOR_BOLD}${UPLOAD_SECONDS} seconds${COLOR_RESET}"
        echo
        
        return 0
    done
    
    # Clean up
    rm -f "$temp_file"
    
    echo "${COLOR_RED}All upload servers failed.${COLOR_RESET}"
    UPLOAD_MBPS=0
    UPLOAD_MBPS_PRETTY="0.00"
    UPLOAD_MBPS_BITS="0.00"
    UPLOAD_SECONDS=0
    
    return 1
}

# Function to display test results
display_results() {
    echo "${COLOR_CYAN}${COLOR_BOLD}TEST RESULTS${COLOR_RESET}"
    echo
    echo "${COLOR_YELLOW}Latency:${COLOR_RESET}"
    echo "  Server: ${COLOR_BOLD}${LATENCY_TARGET}${COLOR_RESET}"
    echo "  Packet Loss: ${COLOR_BOLD}${LATENCY_LOSS}%${COLOR_RESET}"
    echo "  Average: ${COLOR_BOLD}${LATENCY_AVG} ms${COLOR_RESET}"
    echo "  Jitter: ${COLOR_BOLD}${LATENCY_JITTER} ms${COLOR_RESET}"
    echo
    echo "${COLOR_YELLOW}Download:${COLOR_RESET}"
    echo "  Server: ${COLOR_BOLD}${DOWNLOAD_SERVER}${COLOR_RESET}"
    echo "  Speed: ${COLOR_BOLD}${DOWNLOAD_MBPS_PRETTY} MB/s (${DOWNLOAD_MBPS_BITS} Mb/s)${COLOR_RESET}"
    echo "  Time: ${COLOR_BOLD}${DOWNLOAD_SECONDS} seconds${COLOR_RESET}"
    echo
    echo "${COLOR_YELLOW}Upload:${COLOR_RESET}"
    echo "  Server: ${COLOR_BOLD}${UPLOAD_SERVER}${COLOR_RESET}"
    echo "  Speed: ${COLOR_BOLD}${UPLOAD_MBPS_PRETTY} MB/s (${UPLOAD_MBPS_BITS} Mb/s)${COLOR_RESET}"
    echo "  Time: ${COLOR_BOLD}${UPLOAD_SECONDS} seconds${COLOR_RESET}"
    echo
}

# Function to generate JSON output
generate_json() {
    # Ensure all values are numeric
    local loss="${LATENCY_LOSS:-0}"
    local avg="${LATENCY_AVG:-0}"
    local jitter="${LATENCY_JITTER:-0}"
    local latency_target="${LATENCY_TARGET:-unknown}"
    local dl_mbps="${DOWNLOAD_MBPS:-0}"
    local dl_mbps_bits="${DOWNLOAD_MBPS_BITS:-0}"
    local dl_seconds="${DOWNLOAD_SECONDS:-0}"
    local dl_server="${DOWNLOAD_SERVER:-unknown}"
    local ul_mbps="${UPLOAD_MBPS:-0}"
    local ul_mbps_bits="${UPLOAD_MBPS_BITS:-0}"
    local ul_seconds="${UPLOAD_SECONDS:-0}"
    local ul_server="${UPLOAD_SERVER:-unknown}"
    
    # Create JSON string
    local json
    json=$(cat <<EOF
{"latency":{"server":"$latency_target","loss_pct":$loss,"avg_ms":$avg,"jitter_ms":$jitter},"download":{"server":"$dl_server","MBps":$dl_mbps,"Mbps":$dl_mbps_bits,"seconds":$dl_seconds},"upload":{"server":"$ul_server","MBps":$ul_mbps,"Mbps":$ul_mbps_bits,"seconds":$ul_seconds}}
EOF
    )
    
    echo "$json"
}

# Function to save JSON to file
save_json() {
    local json="$1"
    local filename="$2"
    
    if [[ -z "$filename" ]]; then
        filename="speedbuffy-$(date '+%Y%m%d-%H%M%S').json"
    fi
    
    echo "$json" > "$filename"
    echo "JSON saved to: $filename"
}

# Function to ask about server selection
ask_server_selection() {
    echo "${COLOR_CYAN}${COLOR_BOLD}SERVER SELECTION${COLOR_RESET}"
    echo
    echo "1. Use default servers"
    echo "2. Select servers for this test"
    echo
    
    read -r -p "Select an option (1-2): " option
    
    case $option in
        2)
            # Ask for latency server
            echo
            echo "Select latency server:"
            echo "1. Google DNS (8.8.8.8)"
            echo "2. Cloudflare DNS (1.1.1.1)"
            echo "3. OpenDNS (208.67.222.222)"
            echo "4. Custom server"
            
            read -r -p "Select an option (1-4): " lat_option
            
            case $lat_option in
                1) LATENCY_TARGET="8.8.8.8" ;;
                2) LATENCY_TARGET="1.1.1.1" ;;
                3) LATENCY_TARGET="208.67.222.222" ;;
                4)
                    read -r -p "Enter custom server IP or hostname: " custom_server
                    if [[ -n "$custom_server" ]]; then
                        LATENCY_TARGET="$custom_server"
                    fi
                    ;;
            esac
            
            # Ask for download server
            echo
            echo "Select download server:"
            echo "1. Cloudflare (https://speed.cloudflare.com/__down)"
            echo "2. HTTPBin (https://httpbin.org/stream-bytes)"
            echo "3. OTEnet (http://speedtest.ftp.otenet.gr/files/)"
            echo "4. Tele2 (http://speedtest.tele2.net/)"
            echo "5. Custom server"
            echo "6. Use all servers (default)"
            
            read -r -p "Select an option (1-6): " dl_option
            
            case $dl_option in
                1) SELECTED_DOWNLOAD_SERVER="https://speed.cloudflare.com/__down?bytes=BYTES" ;;
                2) SELECTED_DOWNLOAD_SERVER="https://httpbin.org/stream-bytes/BYTES" ;;
                3) SELECTED_DOWNLOAD_SERVER="http://speedtest.ftp.otenet.gr/files/SIZE_MB.test" ;;
                4) SELECTED_DOWNLOAD_SERVER="http://speedtest.tele2.net/SIZE_MB.zip" ;;
                5)
                    read -r -p "Enter custom server URL (use BYTES or SIZE_MB as placeholders): " custom_server
                    if [[ -n "$custom_server" ]]; then
                        SELECTED_DOWNLOAD_SERVER="$custom_server"
                    fi
                    ;;
                6) SELECTED_DOWNLOAD_SERVER="" ;;
            esac
            
            # Ask for upload server
            echo
            echo "Select upload server:"
            echo "1. HTTPBin (https://httpbin.org/post)"
            echo "2. Postman Echo (https://postman-echo.com/post)"
            echo "3. Custom server"
            echo "4. Use all servers (default)"
            
            read -r -p "Select an option (1-4): " ul_option
            
            case $ul_option in
                1) SELECTED_UPLOAD_SERVER="https://httpbin.org/post" ;;
                2) SELECTED_UPLOAD_SERVER="https://postman-echo.com/post" ;;
                3)
                    read -r -p "Enter custom server URL: " custom_server
                    if [[ -n "$custom_server" ]]; then
                        SELECTED_UPLOAD_SERVER="$custom_server"
                    fi
                    ;;
                4) SELECTED_UPLOAD_SERVER="" ;;
            esac
            ;;
    esac
}

# Function to run quick test
run_quick_test() {
    display_header
    
    # Ask if user wants to select servers
    ask_server_selection
    
    # Clear screen and show header again
    display_header
    
    # Run tests
    run_latency_test
    run_download_test "$DEFAULT_DL_SIZE" "$DEFAULT_DL_CAP"
    run_upload_test "$((DEFAULT_DL_SIZE / 10))" "$DEFAULT_UL_CAP"
    display_results
    display_footer
}

# Function to run JSON test
run_json_test() {
    # Show minimal real-time info if not piped
    if [[ -t 1 && "$RUN_MODE" != "json" ]]; then
        echo "Running latency test..."
        run_latency_test >/dev/null 2>&1
        echo "Latency: ${COLOR_BOLD}${LATENCY_AVG} ms${COLOR_RESET} (loss: ${LATENCY_LOSS}%, jitter: ${LATENCY_JITTER} ms)"
        
        echo "Running download test..."
        run_download_test "$DEFAULT_DL_SIZE" "$DEFAULT_DL_CAP" >/dev/null 2>&1
        echo "Download: ${COLOR_BOLD}${DOWNLOAD_MBPS_PRETTY} MB/s${COLOR_RESET} (${DOWNLOAD_MBPS_BITS} Mb/s)"
        
        echo "Running upload test..."
        run_upload_test "$((DEFAULT_DL_SIZE / 10))" "$DEFAULT_UL_CAP" >/dev/null 2>&1
        echo "Upload: ${COLOR_BOLD}${UPLOAD_MBPS_PRETTY} MB/s${COLOR_RESET} (${UPLOAD_MBPS_BITS} Mb/s)"
    else
        # Run tests without visual output for pure JSON mode
        run_latency_test >/dev/null 2>&1
        run_download_test "$DEFAULT_DL_SIZE" "$DEFAULT_DL_CAP" >/dev/null 2>&1
        run_upload_test "$((DEFAULT_DL_SIZE / 10))" "$DEFAULT_UL_CAP" >/dev/null 2>&1
    fi
    
    # Generate JSON
    generate_json
}

# Function to select latency server
select_latency_server() {
    display_header
    
    echo "${COLOR_CYAN}${COLOR_BOLD}SELECT LATENCY SERVER${COLOR_RESET}"
    echo
    echo "1. Google DNS (8.8.8.8)"
    echo "2. Cloudflare DNS (1.1.1.1)"
    echo "3. OpenDNS (208.67.222.222)"
    echo "4. Custom server"
    echo "5. Return to Main Menu"
    echo
    
    read -r -p "Select an option (1-5): " option
    
    case $option in
        1)
            LATENCY_TARGET="8.8.8.8"
            echo "Latency server set to Google DNS (${LATENCY_TARGET})"
            ;;
        2)
            LATENCY_TARGET="1.1.1.1"
            echo "Latency server set to Cloudflare DNS (${LATENCY_TARGET})"
            ;;
        3)
            LATENCY_TARGET="208.67.222.222"
            echo "Latency server set to OpenDNS (${LATENCY_TARGET})"
            ;;
        4)
            read -r -p "Enter custom server IP or hostname: " custom_server
            if [[ -n "$custom_server" ]]; then
                LATENCY_TARGET="$custom_server"
                echo "Latency server set to ${LATENCY_TARGET}"
            else
                echo "Invalid input. Using default value."
            fi
            ;;
        5)
            show_menu
            return
            ;;
        *)
            echo "Invalid option. Using default value."
            ;;
    esac
    
    sleep 1
    show_menu
}

# Function to select download server
select_download_server() {
    display_header
    
    echo "${COLOR_CYAN}${COLOR_BOLD}SELECT DOWNLOAD SERVER${COLOR_RESET}"
    echo
    echo "1. Cloudflare (https://speed.cloudflare.com/__down)"
    echo "2. HTTPBin (https://httpbin.org/stream-bytes)"
    echo "3. OTEnet (http://speedtest.ftp.otenet.gr/files/)"
    echo "4. Tele2 (http://speedtest.tele2.net/)"
    echo "5. Custom server"
    echo "6. Use all servers (default)"
    echo "7. Return to Main Menu"
    echo
    
    read -r -p "Select an option (1-7): " option
    
    case $option in
        1)
            SELECTED_DOWNLOAD_SERVER="https://speed.cloudflare.com/__down?bytes=BYTES"
            echo "Download server set to Cloudflare"
            ;;
        2)
            SELECTED_DOWNLOAD_SERVER="https://httpbin.org/stream-bytes/BYTES"
            echo "Download server set to HTTPBin"
            ;;
        3)
            SELECTED_DOWNLOAD_SERVER="http://speedtest.ftp.otenet.gr/files/SIZE_MB.test"
            echo "Download server set to OTEnet"
            ;;
        4)
            SELECTED_DOWNLOAD_SERVER="http://speedtest.tele2.net/SIZE_MB.zip"
            echo "Download server set to Tele2"
            ;;
        5)
            read -r -p "Enter custom server URL (use BYTES or SIZE_MB as placeholders): " custom_server
            if [[ -n "$custom_server" ]]; then
                SELECTED_DOWNLOAD_SERVER="$custom_server"
                echo "Download server set to ${SELECTED_DOWNLOAD_SERVER}"
            else
                echo "Invalid input. Using default value."
            fi
            ;;
        6)
            SELECTED_DOWNLOAD_SERVER=""
            DOWNLOAD_SERVERS=()
            echo "Using all available download servers"
            ;;
        7)
            show_menu
            return
            ;;
        *)
            echo "Invalid option. Using default value."
            ;;
    esac
    
    sleep 1
    show_menu
}

# Function to select upload server
select_upload_server() {
    display_header
    
    echo "${COLOR_CYAN}${COLOR_BOLD}SELECT UPLOAD SERVER${COLOR_RESET}"
    echo
    echo "1. HTTPBin (https://httpbin.org/post)"
    echo "2. Postman Echo (https://postman-echo.com/post)"
    echo "3. Custom server"
    echo "4. Use all servers (default)"
    echo "5. Return to Main Menu"
    echo
    
    read -r -p "Select an option (1-5): " option
    
    case $option in
        1)
            SELECTED_UPLOAD_SERVER="https://httpbin.org/post"
            echo "Upload server set to HTTPBin"
            ;;
        2)
            SELECTED_UPLOAD_SERVER="https://postman-echo.com/post"
            echo "Upload server set to Postman Echo"
            ;;
        3)
            read -r -p "Enter custom server URL: " custom_server
            if [[ -n "$custom_server" ]]; then
                SELECTED_UPLOAD_SERVER="$custom_server"
                echo "Upload server set to ${SELECTED_UPLOAD_SERVER}"
            else
                echo "Invalid input. Using default value."
            fi
            ;;
        4)
            SELECTED_UPLOAD_SERVER=""
            UPLOAD_SERVERS=()
            echo "Using all available upload servers"
            ;;
        5)
            show_menu
            return
            ;;
        *)
            echo "Invalid option. Using default value."
            ;;
    esac
    
    sleep 1
    show_menu
}

# Function to show settings
show_settings() {
    display_header
    
    echo "${COLOR_CYAN}${COLOR_BOLD}SETTINGS${COLOR_RESET}"
    echo
    echo "1. Download Size: ${COLOR_BOLD}${DEFAULT_DL_SIZE} MB${COLOR_RESET}"
    echo "2. Download Time Cap: ${COLOR_BOLD}${DEFAULT_DL_CAP} seconds${COLOR_RESET}"
    echo "3. Upload Time Cap: ${COLOR_BOLD}${DEFAULT_UL_CAP} seconds${COLOR_RESET}"
    echo "4. IP Version: ${COLOR_BOLD}${DEFAULT_IPV}${COLOR_RESET}"
    echo "5. Latency Server: ${COLOR_BOLD}${LATENCY_TARGET}${COLOR_RESET}"
    echo "6. Download Server: ${COLOR_BOLD}${SELECTED_DOWNLOAD_SERVER:-"All Available Servers"}${COLOR_RESET}"
    echo "7. Upload Server: ${COLOR_BOLD}${SELECTED_UPLOAD_SERVER:-"All Available Servers"}${COLOR_RESET}"
    echo "8. Return to Main Menu"
    echo
    
    read -r -p "Select an option (1-8): " option
    
    case $option in
        1)
            read -r -p "Enter new download size (MB): " new_size
            if [[ "$new_size" =~ ^[0-9]+$ ]]; then
                DEFAULT_DL_SIZE=$new_size
                echo "Download size updated to ${DEFAULT_DL_SIZE} MB"
            else
                echo "Invalid input. Using default value."
            fi
            sleep 1
            show_settings
            ;;
        2)
            read -r -p "Enter new download time cap (seconds): " new_cap
            if [[ "$new_cap" =~ ^[0-9]+$ ]]; then
                DEFAULT_DL_CAP=$new_cap
                echo "Download time cap updated to ${DEFAULT_DL_CAP} seconds"
            else
                echo "Invalid input. Using default value."
            fi
            sleep 1
            show_settings
            ;;
        3)
            read -r -p "Enter new upload time cap (seconds): " new_cap
            if [[ "$new_cap" =~ ^[0-9]+$ ]]; then
                DEFAULT_UL_CAP=$new_cap
                echo "Upload time cap updated to ${DEFAULT_UL_CAP} seconds"
            else
                echo "Invalid input. Using default value."
            fi
            sleep 1
            show_settings
            ;;
        4)
            echo "Select IP version:"
            echo "1. IPv4 only"
            echo "2. IPv6 only"
            echo "3. Auto (default)"
            read -r -p "Select an option (1-3): " ip_option
            
            case $ip_option in
                1) DEFAULT_IPV="4" ;;
                2) DEFAULT_IPV="6" ;;
                3) DEFAULT_IPV="auto" ;;
                *) echo "Invalid option. Using default (auto)." ;;
            esac
            
            echo "IP version set to ${DEFAULT_IPV}"
            sleep 1
            show_settings
            ;;
        5)
            select_latency_server
            ;;
        6)
            select_download_server
            ;;
        7)
            select_upload_server
            ;;
        8)
            show_menu
            ;;
        *)
            echo "Invalid option. Returning to settings."
            sleep 1
            show_settings
            ;;
    esac
}

# Function to export JSON
export_json() {
    display_header
    
    echo "${COLOR_CYAN}Running tests for JSON export...${COLOR_RESET}"
    
    # Run tests with real-time stats
    echo "Running latency test..."
    run_latency_test >/dev/null 2>&1
    echo "Latency: ${COLOR_BOLD}${LATENCY_AVG} ms${COLOR_RESET} (loss: ${LATENCY_LOSS}%, jitter: ${LATENCY_JITTER} ms)"
    
    echo "Running download test..."
    run_download_test "$DEFAULT_DL_SIZE" "$DEFAULT_DL_CAP" >/dev/null 2>&1
    echo "Download: ${COLOR_BOLD}${DOWNLOAD_MBPS_PRETTY} MB/s${COLOR_RESET} (${DOWNLOAD_MBPS_BITS} Mb/s)"
    
    echo "Running upload test..."
    run_upload_test "$((DEFAULT_DL_SIZE / 10))" "$DEFAULT_UL_CAP" >/dev/null 2>&1
    echo "Upload: ${COLOR_BOLD}${UPLOAD_MBPS_PRETTY} MB/s${COLOR_RESET} (${UPLOAD_MBPS_BITS} Mb/s)"
    
    # Generate and save JSON
    local json
    json=$(generate_json)
    local filename="speedbuffy-$(date '+%Y%m%d-%H%M%S').json"
    save_json "$json" "$filename"
    
    echo
    echo "${COLOR_GREEN}JSON exported successfully.${COLOR_RESET}"
    display_footer
    echo "Press Enter to return to the main menu..."
    read -r
    
    show_menu
}

# Function to show the main menu
show_menu() {
    display_header
    
    echo "${COLOR_CYAN}${COLOR_BOLD}MAIN MENU${COLOR_RESET}"
    echo
    echo "1. Quick Test (latency + download + upload)"
    echo "2. Latency Test Only"
    echo "3. Download Test Only"
    echo "4. Upload Test Only"
    echo "5. Settings"
    echo "6. Select Latency Server"
    echo "7. Select Download Server"
    echo "8. Select Upload Server"
    echo "9. Export JSON"
    echo "10. Exit"
    echo
    
    read -r -p "Select an option (1-10): " option
    
    case $option in
        1)
            display_header
            run_latency_test
            run_download_test "$DEFAULT_DL_SIZE" "$DEFAULT_DL_CAP"
            run_upload_test "$((DEFAULT_DL_SIZE / 10))" "$DEFAULT_UL_CAP"
            display_results
            display_footer
            echo "Press Enter to return to the main menu..."
            read -r
            show_menu
            ;;
        2)
            display_header
            run_latency_test
            display_footer
            echo "Press Enter to return to the main menu..."
            read -r
            show_menu
            ;;
        3)
            display_header
            run_download_test "$DEFAULT_DL_SIZE" "$DEFAULT_DL_CAP"
            display_footer
            echo "Press Enter to return to the main menu..."
            read -r
            show_menu
            ;;
        4)
            display_header
            run_upload_test "$((DEFAULT_DL_SIZE / 10))" "$DEFAULT_UL_CAP"
            display_footer
            echo "Press Enter to return to the main menu..."
            read -r
            show_menu
            ;;
        5)
            show_settings
            ;;
        6)
            select_latency_server
            ;;
        7)
            select_download_server
            ;;
        8)
            select_upload_server
            ;;
        9)
            export_json
            ;;
        10)
            echo "Exiting SpeedBuffy. Goodbye!"
            exit 0
            ;;
        *)
            echo "Invalid option. Please try again."
            sleep 1
            show_menu
            ;;
    esac
}

# Function to show usage help
show_help() {
    cat <<EOF
SpeedBuffy - Zero-install ASCII speed test for Linux/Raspberry Pi systems

Usage: ./speedbuffy.sh [OPTIONS]

Options:
  --quick               Run full visual test and exit
  --json                Output JSON to stdout only, no visuals
  --save-json           Like --json + save to timestamped file
  --out-json FILE       Like --json + save to specified FILE
  --size MB             Set download size in MB (default: $DEFAULT_DL_SIZE)
  --dlcap SEC           Set download time cap in seconds (default: $DEFAULT_DL_CAP)
  --ulcap SEC           Set upload time cap in seconds (default: $DEFAULT_UL_CAP)
  --ipv 4|6|auto        Set IP version preference (default: $DEFAULT_IPV)
  --no-color            Disable colored output
  --color               Force colored output
  --debug               Write verbose logs to $DEBUG_LOG
  -h, --help            Show this help message

Examples:
  ./speedbuffy.sh                   # Start interactive menu
  ./speedbuffy.sh --quick           # Run quick test with visuals
  ./speedbuffy.sh --json            # Output JSON to stdout
  ./speedbuffy.sh --save-json       # Save JSON to timestamped file
  ./speedbuffy.sh --size 50 --quick # Run quick test with 50MB download

Designed by @ai_chohan
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --quick)
            RUN_MODE="quick"
            shift
            ;;
        --json)
            RUN_MODE="json"
            shift
            ;;
        --save-json)
            RUN_MODE="save-json"
            shift
            ;;
        --out-json)
            RUN_MODE="out-json"
            JSON_OUT_FILE="$2"
            shift 2
            ;;
        --size)
            DEFAULT_DL_SIZE="$2"
            shift 2
            ;;
        --dlcap)
            DEFAULT_DL_CAP="$2"
            shift 2
            ;;
        --ulcap)
            DEFAULT_UL_CAP="$2"
            shift 2
            ;;
        --ipv)
            DEFAULT_IPV="$2"
            shift 2
            ;;
        --no-color)
            USE_COLOR=false
            shift
            ;;
        --color)
            USE_COLOR=true
            shift
            ;;
        --debug)
            DEBUG=true
            # Initialize debug log
            echo "SpeedBuffy Debug Log - $(date)" > "$DEBUG_LOG"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
if [[ -n "${RUN_MODE:-}" ]]; then
    case $RUN_MODE in
        "quick")
            run_quick_test
            ;;
        "json")
            # Pure JSON output, no extra text
            json=$(RUN_MODE="json" run_json_test)
            echo "$json"
            ;;
        "save-json")
            echo "${COLOR_CYAN}Running tests for JSON export...${COLOR_RESET}"
            echo
            
            # Run tests with real-time stats
        echo "Running latency test to ${LATENCY_TARGET}..."
        run_latency_test >/dev/null 2>&1
        echo "Latency: ${COLOR_BOLD}${LATENCY_AVG} ms${COLOR_RESET} (server: ${LATENCY_TARGET}, loss: ${LATENCY_LOSS}%, jitter: ${LATENCY_JITTER} ms)"
            
            echo "Running download test..."
            run_download_test "$DEFAULT_DL_SIZE" "$DEFAULT_DL_CAP" >/dev/null 2>&1
            echo "Download: ${COLOR_BOLD}${DOWNLOAD_MBPS_PRETTY} MB/s${COLOR_RESET} (server: ${DOWNLOAD_SERVER}, ${DOWNLOAD_MBPS_BITS} Mb/s)"
            
            echo "Running upload test..."
            run_upload_test "$((DEFAULT_DL_SIZE / 10))" "$DEFAULT_UL_CAP" >/dev/null 2>&1
            echo "Upload: ${COLOR_BOLD}${UPLOAD_MBPS_PRETTY} MB/s${COLOR_RESET} (server: ${UPLOAD_SERVER}, ${UPLOAD_MBPS_BITS} Mb/s)"
            
            # Generate and save JSON
            json=$(generate_json)
            echo
            echo "$json"
            save_json "$json" ""
            echo
            display_footer
            ;;
        "out-json")
            echo "${COLOR_CYAN}Running tests for JSON export...${COLOR_RESET}"
            echo
            
            # Run tests with real-time stats
            echo "Running latency test..."
            run_latency_test >/dev/null 2>&1
            echo "Latency: ${COLOR_BOLD}${LATENCY_AVG} ms${COLOR_RESET} (loss: ${LATENCY_LOSS}%, jitter: ${LATENCY_JITTER} ms)"
            
            echo "Running download test..."
            run_download_test "$DEFAULT_DL_SIZE" "$DEFAULT_DL_CAP" >/dev/null 2>&1
            echo "Download: ${COLOR_BOLD}${DOWNLOAD_MBPS_PRETTY} MB/s${COLOR_RESET} (${DOWNLOAD_MBPS_BITS} Mb/s)"
            
            echo "Running upload test..."
            run_upload_test "$((DEFAULT_DL_SIZE / 10))" "$DEFAULT_UL_CAP" >/dev/null 2>&1
            echo "Upload: ${COLOR_BOLD}${UPLOAD_MBPS_PRETTY} MB/s${COLOR_RESET} (${UPLOAD_MBPS_BITS} Mb/s)"
            
            # Generate and save JSON
            json=$(generate_json)
            echo
            echo "$json"
            save_json "$json" "$JSON_OUT_FILE"
            echo
            display_footer
            ;;
    esac
else
    # Default to menu mode
    show_menu
fi

exit 0
