#!/usr/bin/env bash
# ============================================================================
# Floci Environment Verification Script
# Run this after 'docker compose up -d' to confirm all services work.
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
echo "  Floci Environment Verification"
echo "============================================"
echo ""

# --- Health Check ---
echo "🔍 Health Check"
HEALTH=$(curl -sf http://localhost:4566/_floci/health 2>/dev/null || echo "UNREACHABLE")
if echo "$HEALTH" | grep -q "running"; then
  pass "Floci is healthy and services are running"
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
aws s3 mb s3://verify-bucket $EP >/dev/null 2>&1
echo "test-content" | aws s3 cp - s3://verify-bucket/test.txt $EP >/dev/null 2>&1
RESULT=$(aws s3 cp s3://verify-bucket/test.txt - $EP 2>/dev/null)
if [ "$RESULT" = "test-content" ]; then
  pass "S3: create bucket, upload, download — content matches"
else
  fail "S3: content mismatch (got: '$RESULT')"
fi
aws s3 rb s3://verify-bucket --force $EP >/dev/null 2>&1
echo ""

# --- DynamoDB ---
echo "📊 DynamoDB"
aws dynamodb create-table \
  --table-name verify-table \
  --attribute-definitions AttributeName=pk,AttributeType=S \
  --key-schema AttributeName=pk,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  $EP >/dev/null 2>&1

aws dynamodb put-item --table-name verify-table \
  --item '{"pk":{"S":"k1"},"val":{"S":"hello"}}' $EP >/dev/null 2>&1

GOT=$(aws dynamodb get-item --table-name verify-table \
  --key '{"pk":{"S":"k1"}}' $EP --query 'Item.val.S' --output text 2>/dev/null)
if [ "$GOT" = "hello" ]; then
  pass "DynamoDB: create table, put item, get item"
else
  fail "DynamoDB: get-item returned '$GOT' instead of 'hello'"
fi

# Conditional write test — this MUST fail
aws dynamodb put-item --table-name verify-table \
  --item '{"pk":{"S":"k1"},"val":{"S":"overwrite"}}' \
  --condition-expression 'attribute_not_exists(pk)' $EP >/dev/null 2>&1 \
  && fail "DynamoDB: conditional write should have been rejected but succeeded" \
  || pass "DynamoDB: conditional write correctly rejected (ConditionalCheckFailedException)"

aws dynamodb delete-table --table-name verify-table $EP >/dev/null 2>&1
echo ""

# --- SQS ---
echo "📨 SQS"
STD_URL=$(aws sqs create-queue --queue-name verify-queue $EP --query 'QueueUrl' --output text 2>/dev/null)
aws sqs send-message --queue-url "$STD_URL" --message-body 'hello-std' $EP >/dev/null 2>&1
STD_BODY=$(aws sqs receive-message --queue-url "$STD_URL" $EP --query 'Messages[0].Body' --output text 2>/dev/null)
if [ "$STD_BODY" = "hello-std" ]; then
  pass "SQS standard queue: send + receive"
else
  fail "SQS standard queue: got '$STD_BODY'"
fi

FIFO_URL=$(aws sqs create-queue --queue-name verify-queue.fifo \
  --attributes FifoQueue=true,ContentBasedDeduplication=true $EP \
  --query 'QueueUrl' --output text 2>/dev/null)
aws sqs send-message --queue-url "$FIFO_URL" --message-body 'hello-fifo' \
  --message-group-id grp1 $EP >/dev/null 2>&1
FIFO_BODY=$(aws sqs receive-message --queue-url "$FIFO_URL" $EP \
  --query 'Messages[0].Body' --output text 2>/dev/null)
if [ "$FIFO_BODY" = "hello-fifo" ]; then
  pass "SQS FIFO queue: send + receive"
else
  fail "SQS FIFO queue: got '$FIFO_BODY'"
fi

aws sqs delete-queue --queue-url "$STD_URL" $EP >/dev/null 2>&1
aws sqs delete-queue --queue-url "$FIFO_URL" $EP >/dev/null 2>&1
echo ""

# --- Lambda ---
echo "⚡ Lambda"
TMPDIR=$(mktemp -d)
cat > "$TMPDIR/lambda_function.py" << 'PYEOF'
import json
def handler(event, context):
    return {"statusCode": 200, "body": json.dumps({"msg": "ok"})}
PYEOF
(cd "$TMPDIR" && zip -q ../verify-lambda.zip lambda_function.py)
LAMBDA_ZIP="$TMPDIR/../verify-lambda.zip"

aws lambda create-function \
  --function-name verify-fn \
  --runtime python3.12 \
  --handler lambda_function.handler \
  --role arn:aws:iam::000000000000:role/test-role \
  --zip-file "fileb://$LAMBDA_ZIP" \
  $EP >/dev/null 2>&1

INVOKE_OUT=$(aws lambda invoke --function-name verify-fn \
  --payload '{}' --cli-binary-format raw-in-base64-out \
  "$TMPDIR/response.json" $EP --query 'StatusCode' --output text 2>/dev/null)
LAMBDA_BODY=$(cat "$TMPDIR/response.json" 2>/dev/null)

if [ "$INVOKE_OUT" = "200" ] && echo "$LAMBDA_BODY" | grep -q 'msg'; then
  pass "Lambda: deploy + invoke (python3.12)"
else
  fail "Lambda: StatusCode=$INVOKE_OUT, body=$LAMBDA_BODY"
fi

aws lambda delete-function --function-name verify-fn $EP >/dev/null 2>&1
rm -rf "$TMPDIR" "$LAMBDA_ZIP"
echo ""

# --- API Gateway ---
echo "🌐 API Gateway"
# Reuse a Lambda for the integration
TMPDIR2=$(mktemp -d)
cat > "$TMPDIR2/lambda_function.py" << 'PYEOF'
import json
def handler(event, context):
    return {"statusCode": 200, "headers": {"Content-Type": "application/json"}, "body": json.dumps({"apigw": "ok"})}
PYEOF
(cd "$TMPDIR2" && zip -q ../verify-apigw.zip lambda_function.py)
APIGW_ZIP="$TMPDIR2/../verify-apigw.zip"

FN_ARN=$(aws lambda create-function \
  --function-name verify-apigw-fn \
  --runtime python3.12 \
  --handler lambda_function.handler \
  --role arn:aws:iam::000000000000:role/test-role \
  --zip-file "fileb://$APIGW_ZIP" \
  $EP --query 'FunctionArn' --output text 2>/dev/null)

API_ID=$(aws apigateway create-rest-api --name verify-api $EP --query 'id' --output text 2>/dev/null)
ROOT_ID=$(aws apigateway get-resources --rest-api-id "$API_ID" $EP --query 'items[0].id' --output text 2>/dev/null)
RES_ID=$(aws apigateway create-resource --rest-api-id "$API_ID" --parent-id "$ROOT_ID" --path-part ping $EP --query 'id' --output text 2>/dev/null)

aws apigateway put-method --rest-api-id "$API_ID" --resource-id "$RES_ID" --http-method GET --authorization-type NONE $EP >/dev/null 2>&1
aws apigateway put-integration --rest-api-id "$API_ID" --resource-id "$RES_ID" --http-method GET \
  --type AWS_PROXY --integration-http-method POST \
  --uri "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/$FN_ARN/invocations" $EP >/dev/null 2>&1
aws apigateway create-deployment --rest-api-id "$API_ID" --stage-name test $EP >/dev/null 2>&1

APIGW_RESP=$(curl -sf "http://localhost:4566/restapis/$API_ID/test/_user_request_/ping" 2>/dev/null || echo "UNREACHABLE")
if echo "$APIGW_RESP" | grep -q '"apigw"'; then
  pass "API Gateway: REST API → Lambda integration over HTTP"
else
  fail "API Gateway: response was '$APIGW_RESP'"
fi

aws apigateway delete-rest-api --rest-api-id "$API_ID" $EP >/dev/null 2>&1
aws lambda delete-function --function-name verify-apigw-fn $EP >/dev/null 2>&1
rm -rf "$TMPDIR2" "$APIGW_ZIP"
echo ""

# --- Cognito ---
echo "🔐 Cognito"
POOL_ID=$(aws cognito-idp create-user-pool --pool-name verify-pool \
  --policies 'PasswordPolicy={MinimumLength=8,RequireUppercase=false,RequireLowercase=false,RequireNumbers=false,RequireSymbols=false}' \
  $EP --query 'UserPool.Id' --output text 2>/dev/null)

CLIENT_ID=$(aws cognito-idp create-user-pool-client --user-pool-id "$POOL_ID" \
  --client-name verify-client \
  --explicit-auth-flows ALLOW_USER_PASSWORD_AUTH ALLOW_REFRESH_TOKEN_AUTH \
  --no-generate-secret $EP --query 'UserPoolClient.ClientId' --output text 2>/dev/null)

aws cognito-idp admin-create-user --user-pool-id "$POOL_ID" \
  --username verifyuser --temporary-password 'TempPass1!' $EP >/dev/null 2>&1

aws cognito-idp admin-set-user-password --user-pool-id "$POOL_ID" \
  --username verifyuser --password 'VerifyPass1!' --permanent $EP >/dev/null 2>&1

AUTH_RESULT=$(aws cognito-idp initiate-auth --client-id "$CLIENT_ID" \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=verifyuser,PASSWORD='VerifyPass1!' $EP 2>/dev/null)

if echo "$AUTH_RESULT" | grep -q "AccessToken"; then
  pass "Cognito: create pool, create user, authenticate — JWT tokens received"
else
  fail "Cognito: authentication failed"
fi

aws cognito-idp delete-user-pool --user-pool-id "$POOL_ID" $EP >/dev/null 2>&1
echo ""

# --- Summary ---
echo "============================================"
echo "  Results: $PASS passed, $FAIL failed, $WARN warnings"
echo "============================================"
if [ "$FAIL" -gt 0 ]; then
  echo "⚠️  Some checks failed. Review output above."
  exit 1
else
  echo "🎉 All checks passed! Environment is ready."
  exit 0
fi
