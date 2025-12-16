
#!/bin/bash
set -e

LOG_FILE="/var/log/nginx_after_deploy.log"
PREV_TIMESTAMP_FILE="/var/log/prev_index_timestamp"
EXPECTED_CHECKSUM_FILE="/var/www/html/index.html.sha256"
HEALTHCHECK_URL="http://localhost"

echo "===== NGINX After Deploy Script Started =====" | tee -a $LOG_FILE
date | tee -a $LOG_FILE

####################################
# 1. Install NGINX if not present
####################################
if ! command -v nginx &> /dev/null; then
    echo "NGINX not found. Installing..." | tee -a $LOG_FILE
    yum install -y nginx
else
    echo "NGINX already installed" | tee -a $LOG_FILE
fi

####################################
# 2. Detect NGINX document root
####################################
NGINX_ROOT=$(nginx -T 2>/dev/null | grep -m1 "root " | awk '{print $2}' | sed 's/;//')
DEPLOY_DIR="${NGINX_ROOT:-/var/www/html}"

echo "Detected NGINX root: $DEPLOY_DIR" | tee -a $LOG_FILE

####################################
# 3. Validate & restart NGINX
####################################
nginx -t | tee -a $LOG_FILE
systemctl enable nginx
systemctl restart nginx
sleep 3

systemctl is-active --quiet nginx || {
    echo "❌ NGINX failed to start" | tee -a $LOG_FILE
    exit 1
}

####################################
# 4. Verify deployment files
####################################
[ -d "$DEPLOY_DIR" ] || {
    echo "❌ Deployment directory missing" | tee -a $LOG_FILE
    exit 1
}

FILE_COUNT=$(find "$DEPLOY_DIR" -type f | wc -l)
echo "📄 Total files deployed: $FILE_COUNT" | tee -a $LOG_FILE

ls -lh --time-style=long-iso "$DEPLOY_DIR" | tee -a $LOG_FILE

####################################
# 5. index.html checks
####################################
INDEX_FILE="$DEPLOY_DIR/index.html"

[ -f "$INDEX_FILE" ] || {
    echo "❌ index.html missing" | tee -a $LOG_FILE
    exit 1
}

CURRENT_TS=$(stat -c %Y "$INDEX_FILE")
echo "index.html timestamp: $CURRENT_TS" | tee -a $LOG_FILE

####################################
# 6. Rollback if index.html is older
####################################
if [ -f "$PREV_TIMESTAMP_FILE" ]; then
    PREV_TS=$(cat "$PREV_TIMESTAMP_FILE")
    if [ "$CURRENT_TS" -le "$PREV_TS" ]; then
        echo "❌ index.html is older than previous deployment — rolling back" | tee -a $LOG_FILE
        exit 1
    fi
fi

echo "$CURRENT_TS" > "$PREV_TIMESTAMP_FILE"

####################################
# 7. Checksum validation
####################################
if [ -f "$EXPECTED_CHECKSUM_FILE" ]; then
    echo "Performing checksum validation..." | tee -a $LOG_FILE
    sha256sum -c "$EXPECTED_CHECKSUM_FILE" | tee -a $LOG_FILE || {
        echo "❌ Checksum validation failed" | tee -a $LOG_FILE
        exit 1
    }
else
    echo "⚠️ No checksum file found — skipping checksum validation" | tee -a $LOG_FILE
fi

####################################
# 8. HTTP 200 health check
####################################
HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}" "$HEALTHCHECK_URL")

if [ "$HTTP_STATUS" -ne 200 ]; then
    echo "❌ HTTP health check failed (Status: $HTTP_STATUS)" | tee -a $LOG_FILE
    exit 1
fi

echo "🌐 HTTP health check passed (200 OK)" | tee -a $LOG_FILE

echo "===== NGINX After Deploy Script Completed Successfully =====" | tee -a $LOG_FILE
