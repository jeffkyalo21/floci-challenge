# ============================================================================
# Floci Environment Verification Script (Windows PowerShell)
# Confirms Floci emulator, Web UI, and AWS service endpoints are reachable.
# ============================================================================
$ErrorActionPreference = "Continue"

$EP = "--endpoint-url=http://localhost:4566"
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

$Pass = 0
$Fail = 0

function Test-Pass($msg) {
    Write-Host "  [PASS] $msg" -ForegroundColor Green
    $script:Pass++
}

function Test-Fail($msg) {
    Write-Host "  [FAIL] $msg" -ForegroundColor Red
    $script:Fail++
}

Write-Host "============================================"
Write-Host "  Floci Environment Connectivity Check"
Write-Host "============================================"
Write-Host ""

# --- Health Check ---
Write-Host "[1/7] Health Check"
try {
    $health = Invoke-RestMethod -Uri http://localhost:4566/_floci/health -TimeoutSec 5
    if ($health.services.s3 -eq "running") { Test-Pass "Floci emulator is running" }
    else { Test-Fail "Floci health returned unexpected status"; exit 1 }
} catch {
    Test-Fail "Cannot reach Floci at localhost:4566"
    exit 1
}

try {
    $uiHealth = Invoke-RestMethod -Uri http://localhost:9877/api/healthz -TimeoutSec 5
    if ($uiHealth.status -eq "ok") { Test-Pass "Floci Dash Web UI is healthy (http://localhost:9877)" }
    else { Test-Fail "Floci Dash returned unexpected health status" }
} catch {
    Write-Host "  [WARN] Floci Dash Web UI not reachable on port 9877" -ForegroundColor Yellow
}
Write-Host ""

# --- S3 ---
Write-Host "[2/7] S3"
$s3Out = aws s3api list-buckets $EP 2>&1
if ($LASTEXITCODE -eq 0) { Test-Pass "S3: service reachable (list-buckets responded)" }
else { Test-Fail "S3: service unreachable" }
Write-Host ""

# --- DynamoDB ---
Write-Host "[3/7] DynamoDB"
$ddbOut = aws dynamodb list-tables $EP 2>&1
if ($LASTEXITCODE -eq 0) { Test-Pass "DynamoDB: service reachable (list-tables responded)" }
else { Test-Fail "DynamoDB: service unreachable" }
Write-Host ""

# --- SQS ---
Write-Host "[4/7] SQS"
$sqsOut = aws sqs list-queues $EP 2>&1
if ($LASTEXITCODE -eq 0) { Test-Pass "SQS: service reachable (list-queues responded)" }
else { Test-Fail "SQS: service unreachable" }
Write-Host ""

# --- Lambda ---
Write-Host "[5/7] Lambda"
$lambdaOut = aws lambda list-functions $EP 2>&1
if ($LASTEXITCODE -eq 0) { Test-Pass "Lambda: service reachable (list-functions responded)" }
else { Test-Fail "Lambda: service unreachable" }
Write-Host ""

# --- API Gateway ---
Write-Host "[6/7] API Gateway"
$apigwOut = aws apigateway get-rest-apis $EP 2>&1
if ($LASTEXITCODE -eq 0) { Test-Pass "API Gateway: service reachable (get-rest-apis responded)" }
else { Test-Fail "API Gateway: service unreachable" }
Write-Host ""

# --- Cognito ---
Write-Host "[7/7] Cognito"
$cognitoOut = aws cognito-idp list-user-pools --max-results 10 $EP 2>&1
if ($LASTEXITCODE -eq 0) { Test-Pass "Cognito: service reachable (list-user-pools responded)" }
else { Test-Fail "Cognito: service unreachable" }
Write-Host ""

# --- Summary ---
Write-Host "============================================"
Write-Host "  Results: $Pass passed, $Fail failed"
Write-Host "============================================"
if ($Fail -gt 0) {
    Write-Host "Some checks failed. Review output above." -ForegroundColor Red
    exit 1
} else {
    Write-Host "All service endpoints reachable! Environment is ready." -ForegroundColor Green
    exit 0
}
