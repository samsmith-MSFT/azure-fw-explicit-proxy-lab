echo "=== HTTP via proxy 8080 (allowed: ifconfig.me) ==="
curl -sS --max-time 20 -x http://10.0.0.4:8080 http://ifconfig.me ; echo
echo "=== HTTPS via proxy 8443 (allowed: www.microsoft.com) ==="
curl -sS --max-time 20 -x http://10.0.0.4:8443 https://www.microsoft.com -o /dev/null -w "HTTP_CODE=%{http_code}\n"
echo "=== HTTPS via proxy 8443 (NOT allowed: www.google.com -> expect deny) ==="
curl -sS --max-time 20 -x http://10.0.0.4:8443 https://www.google.com -o /dev/null -w "HTTP_CODE=%{http_code}\n" || echo "BLOCKED_OR_FAILED"
echo "=== Direct (no proxy) to internet -> expect timeout/no route ==="
curl -sS --max-time 12 http://ifconfig.me -o /dev/null -w "HTTP_CODE=%{http_code}\n" || echo "NO_DIRECT_EGRESS"
