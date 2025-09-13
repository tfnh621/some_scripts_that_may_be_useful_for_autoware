#!/usr/bin/env bash
# chrony のウォッチドッグ: 定期的に `chronyc tracking` を実行し、異常なら chrony.service を再起動します。
# 使い方: ./chrony-watchdog.sh [間隔秒]  (デフォルト: 60)

set -u

INTERVAL="${1:-60}"

while true; do
    # chronyc の出力を取得（エラーも含む）
    OUTPUT="$(LC_ALL=C chronyc tracking 2>&1 || true)"

    # 異常条件を個別に判定してメッセージを明確化
    if grep -q '506 Cannot talk to daemon' <<<"$OUTPUT"; then
        echo "chronyc: cannot talk to daemon (506). Restarting chrony.service"
        sudo systemctl restart chrony.service
    elif grep -Eq 'Leap status[[:space:]]*: Not synchronised' <<<"$OUTPUT"; then
        echo "chronyc: leap status is Not synchronised. Restarting chrony.service"
        sudo systemctl restart chrony.service
    fi

    sleep "$INTERVAL"
done
