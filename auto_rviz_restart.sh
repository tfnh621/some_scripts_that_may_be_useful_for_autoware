#!/usr/bin/env bash

# Autoware の RViz2 を定期的に再起動するスクリプト

print_log() { echo "[$(date +"%Y-%m-%dT%H:%M:%S.%3N%:z")] $@"; }
log_debug() { local ESC=$(printf '\033'); print_log "${ESC}[34m[DEBUG]" "$@" "${ESC}[m"; }
log_info() { local ESC=$(printf '\033'); print_log "${ESC}[32m[INFO]" "$@" "${ESC}[m"; }
log_warning() { local ESC=$(printf '\033'); print_log "${ESC}[33m[WARNING]" "$@" "${ESC}[m"; }
log_error() { local ESC=$(printf '\033'); print_log "${ESC}[31m[ERROR]" "$@" "${ESC}[m"; }

find-pkg-share() {
    local prefix
    prefix=$(ros2 pkg prefix "$1" 2>/dev/null) || return 1
    printf "%s/share/%s" "$prefix" "$1"
}

launch_rviz2() {
    local package_name="${1:-autoware_launch}"
    /opt/ros/humble/lib/rviz2/rviz2 \
        -d $(find-pkg-share "$package_name")/rviz/autoware.rviz \
        -s /dev/null \
        --ros-args \
            -r __node:=rviz_ava1 \
            -p use_sim_time:=False \
            -r /perception/traffic_light_recognition/traffic_signals:=/perception/traffic_light_recognition/traffic_signals_rviz \
    > /dev/null 2>&1 &
    echo $!

    # FIXME: topic の rename パラメーターをどうにかする
}

find_rviz2_window() {
    local wid=$(xprop -root _NET_ACTIVE_WINDOW | awk '{print $NF}')
    local pid=$(xprop -id "$wid" _NET_WM_PID | awk '{print $NF}')
    local pname=$(ps -p "$pid" -o comm= 2>/dev/null)
    if [ "$pname" = "rviz2" ]; then
        echo "$wid"
    fi
}

keep_rviz2_window_focused() {
    local TIMEOUT_SECONDS=10
    local INTERVAL_SECONDS=0.01

    local RVIZ2_WINDOW_ID=$(find_rviz2_window)
    if [ -n "$RVIZ2_WINDOW_ID" ]; then
        log_debug "Found focused rviz2 window (ID: $RVIZ2_WINDOW_ID)"
        local START_TIME=$(date +%s)

        while [ $(( $(date +%s) - $START_TIME )) -lt $TIMEOUT_SECONDS ]; do
            local WINDOW_ID=$(xprop -root _NET_ACTIVE_WINDOW | awk '{print $NF}')
            if [ "$WINDOW_ID" != "$RVIZ2_WINDOW_ID" ]; then
                log_debug "New active window detected (ID: $WINDOW_ID)"
                wmctrl -i -a "$RVIZ2_WINDOW_ID"
                log_debug "Focused rviz2 window (ID: $RVIZ2_WINDOW_ID)"
                break   # To avoid tight looping
            fi
            sleep $INTERVAL_SECONDS
        done
    else
        log_debug "No focused rviz2 window found."
    fi
}

pid_to_wid() {
    local PID=$1
    local WID
    for WID in $(xprop -root _NET_CLIENT_LIST | sed 's/.*# //' | tr ',' ' '); do
        if [ "$(xprop -id "$WID" _NET_WM_PID 2>/dev/null | awk '{print $3}')" = "$PID" ]; then
            echo "$WID"
        fi
    done
}

parse_arguments() {
    # デフォルト値
    SLEEP_MINUTES=20
    AUTOWARE_LAUNCH_PACKAGE=autoware_launch

    # 引数解析
    while [[ $# -gt 0 ]]; do
        case $1 in
            --sleep-minutes)
                SLEEP_MINUTES="$2"
                shift 2
                ;;
            --sleep-minutes=*)
                SLEEP_MINUTES="${1#*=}"
                shift
                ;;
            --autoware-launch-package)
                AUTOWARE_LAUNCH_PACKAGE="$2"
                shift 2
                ;;
            --autoware-launch-package=*)
                AUTOWARE_LAUNCH_PACKAGE="${1#*=}"
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --sleep-minutes MINUTES              Set sleep interval in minutes (default: 20)"
                echo "  --sleep-minutes=MINUTES              Alternative syntax"
                echo "  --autoware-launch-package PACKAGE    Set autoware launch package name (default: autoware_launch)"
                echo "  --autoware-launch-package=PACKAGE    Alternative syntax"
                echo "  -h, --help                           Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # 数値チェック
    if ! [[ "$SLEEP_MINUTES" =~ ^[0-9]+$ ]]; then
        log_error "Sleep minutes must be a positive integer: $SLEEP_MINUTES"
        exit 1
    fi
}

check_dependencies() {
    local missing_deps=()
    local dep
    for dep in xprop wmctrl; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_error "Please install the missing dependencies and try again."
        exit 1
    fi
}

main() {
    log_debug "Using sleep interval: ${SLEEP_MINUTES} minutes"
    log_debug "Using autoware launch package: ${AUTOWARE_LAUNCH_PACKAGE}"

    # 最初の rviz2 を起動する
    log_info "Launching first rviz2..."
    local CURRENT_RVIZ2_PID=$(launch_rviz2 "$AUTOWARE_LAUNCH_PACKAGE")
    log_info "Spawned first rviz2 (PID: $CURRENT_RVIZ2_PID)"

    # ループ
    while true; do
        sleep $((60 * $SLEEP_MINUTES))

        # 古い rviz2 がフォーカスを失わないようにする
        keep_rviz2_window_focused &

        # 新しい rviz2 プロセスを起動する
        local NEW_RVIZ2_PID=$(launch_rviz2 "$AUTOWARE_LAUNCH_PACKAGE")
        log_info "Launched new rviz2 (PID: $NEW_RVIZ2_PID)"
        sleep 20    # Wait for the new rviz2 to initialize

        # 新しい rviz2 ウィンドウにフォーカスする
        local NEW_RVIZ2_WINDOW_ID=$(pid_to_wid $NEW_RVIZ2_PID)
        if [ -n "$NEW_RVIZ2_WINDOW_ID" ]; then
            log_debug "Found new rviz2 window (ID: $NEW_RVIZ2_WINDOW_ID)"
            wmctrl -i -a "$NEW_RVIZ2_WINDOW_ID"
            sleep 1
        else
            log_warning "Could not find window for new rviz2 (PID: $NEW_RVIZ2_PID)"
        fi

        # 古い rviz2 を終了する
        kill -9 $CURRENT_RVIZ2_PID
        log_info "Killed old rviz2 (PID: $CURRENT_RVIZ2_PID)"

        # Update variable(s)
        CURRENT_RVIZ2_PID=$NEW_RVIZ2_PID
    done
}

parse_arguments "$@"
check_dependencies
main
