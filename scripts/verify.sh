#!/usr/bin/env bash
# ============================================================================
# Floci Environment Verification Script
# Confirms Floci emulator, Web UI, and AWS service endpoints are reachable.
# ============================================================================
set -euo pipefail

EP="--endpoint-url=http://localhost:4566"
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

PASS=0
FAIL=0
WARN=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }
warn() { echo "  ⚠️  WARN: $1"; WARN=$((WARN+1)); }

echo "============================================"
echo "  Floci Environment Connectivity Check"
echo "============================================"
echo ""

# --- Health Check ---
echo "🔍 Health Check"
HEALTH=$(curl -sf http://localhost:4566/_floci/health 2>/dev/null || echo "UNREACHABLE")
if echo "$HEALTH" | grep -q "running"; then
  pass "Floci emulator is running"
else
  fail "Floci health endpoint unreachable — is the container running?"
  echo "   Run: docker compose up -d"
  exit 1
fi

UI_HEALTH=$(curl -sf http://localhost:9877/api/healthz 2>/dev/null || curl -sf http://floci-dash:3000/api/healthz 2>/dev/null || echo "UNREACHABLE")
if echo "$UI_HEALTH" | grep -q "ok"; then
  pass "Floci Dash Web UI is healthy"
else
  warn "Floci Dash Web UI not reachable"
fi
echo ""

# --- S3 ---
echo "🪣 S3"
if aws s3api list-buckets $EP >/dev/null 2>&1; then
  pass "S3: service reachable (list-buckets responded)"
else
  fail "S3: service unreachable"
fi
echo ""

# --- DynamoDB ---
echo "📊 DynamoDB"
if aws dynamodb list-tables $EP >/dev/null 2>&1; then
  pass "DynamoDB: service reachable (list-tables responded)"
else
  fail "DynamoDB: service unreachable"
fi
echo ""

# --- SQS ---
echo "📨 SQS"
if aws sqs list-queues $EP >/dev/null 2>&1; then
  pass "SQS: service reachable (list-queues responded)"
else
  fail "SQS: service unreachable"
fi
echo ""

# --- Lambda ---
echo "⚡ Lambda"
if aws lambda list-functions $EP >/dev/null 2>&1; then
  pass "Lambda: service reachable (list-functions responded)"
else
  fail "Lambda: service unreachable"
fi
echo ""

# --- API Gateway ---
echo "🌐 API Gateway"
if aws apigateway get-rest-apis $EP >/dev/null 2>&1; then
  pass "API Gateway: service reachable (get-rest-apis responded)"
else
  fail "API Gateway: service unreachable"
fi
echo ""

# --- Cognito ---
echo "🔐 Cognito"
if aws cognito-idp list-user-pools --max-results 10 $EP >/dev/null 2>&1; then
  pass "Cognito: service reachable (list-user-pools responded)"
else
  fail "Cognito: service unreachable"
fi
echo ""

# --- Summary ---
echo "============================================"
echo "  Results: $PASS passed, $FAIL failed, $WARN warnings"
echo "============================================"
if [ "$FAIL" -gt 0 ]; then
  echo "⚠️  Some checks failed. Review output above."
  exit 1
else
  echo "🎉 All service endpoints reachable! Environment is ready."
  exit 0
fi
