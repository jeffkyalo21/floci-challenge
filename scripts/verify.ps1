<#
.SYNOPSIS
    Floci Environment Verification Script (PowerShell)
.DESCRIPTION
    Run this after 'docker compose up -d' to confirm all services work.
#>
$ErrorActionPreference = "Continue"

$EP = "--endpoint-url=http://localhost:4566"
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

$Pass = 0; $Fail = 0

function Test-Pass($msg) { Write-Host "  [PASS] $msg" -ForegroundColor Green; $script:Pass++ }
function Test-Fail($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red; $script:Fail++ }

Write-Host "============================================"
Write-Host "  Floci Environment Verification"
Write-Host "============================================"
Write-Host ""

# --- Health ---
Write-Host "[1/6] Health Check"
try {
    $health = Invoke-RestMethod -Uri http://localhost:4566/_floci/health -TimeoutSec 5
    if ($health.services.s3 -eq "running") { Test-Pass "Floci is healthy" }
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
Write-Host "[2/6] S3"
aws s3 mb s3://verify-bucket $EP 2>&1 | Out-Null
"test-content" | Out-File -FilePath verify-tmp.txt -Encoding ascii -NoNewline
aws s3 cp verify-tmp.txt s3://verify-bucket/test.txt $EP 2>&1 | Out-Null
aws s3 cp s3://verify-bucket/test.txt verify-dl.txt $EP 2>&1 | Out-Null
$s3Content = Get-Content verify-dl.txt -Raw
if ($s3Content.Trim() -eq "test-content") { Test-Pass "S3: create, upload, download" }
else { Test-Fail "S3: content mismatch" }
aws s3 rb s3://verify-bucket --force $EP 2>&1 | Out-Null
Remove-Item verify-tmp.txt, verify-dl.txt -ErrorAction SilentlyContinue
Write-Host ""

# --- DynamoDB ---
Write-Host "[3/6] DynamoDB"
aws dynamodb create-table --table-name verify-table --attribute-definitions AttributeName=pk,AttributeType=S --key-schema AttributeName=pk,KeyType=HASH --billing-mode PAY_PER_REQUEST $EP 2>&1 | Out-Null
aws dynamodb put-item --table-name verify-table --item '{\"pk\":{\"S\":\"k1\"},\"val\":{\"S\":\"hello\"}}' $EP 2>&1 | Out-Null
$got = aws dynamodb get-item --table-name verify-table --key '{\"pk\":{\"S\":\"k1\"}}' $EP --query 'Item.val.S' --output text 2>&1
if ($got.Trim() -eq "hello") { Test-Pass "DynamoDB: put + get item" }
else { Test-Fail "DynamoDB: got '$got' instead of 'hello'" }

$condResult = aws dynamodb put-item --table-name verify-table --item '{\"pk\":{\"S\":\"k1\"},\"val\":{\"S\":\"overwrite\"}}' --condition-expression 'attribute_not_exists(pk)' $EP 2>&1 | Out-String
if ($condResult -match "ConditionalCheckFailed") { Test-Pass "DynamoDB: conditional write correctly rejected" }
else { Test-Fail "DynamoDB: conditional write should have failed" }
aws dynamodb delete-table --table-name verify-table $EP 2>&1 | Out-Null
Write-Host ""

# --- SQS ---
Write-Host "[4/6] SQS"
$stdUrl = (aws sqs create-queue --queue-name verify-queue $EP --query 'QueueUrl' --output text 2>&1).Trim()
aws sqs send-message --queue-url $stdUrl --message-body 'hello-std' $EP 2>&1 | Out-Null
$stdBody = (aws sqs receive-message --queue-url $stdUrl $EP --query 'Messages[0].Body' --output text 2>&1).Trim()
if ($stdBody -eq "hello-std") { Test-Pass "SQS standard: send + receive" }
else { Test-Fail "SQS standard: got '$stdBody'" }

$fifoUrl = (aws sqs create-queue --queue-name verify-queue.fifo --attributes FifoQueue=true,ContentBasedDeduplication=true $EP --query 'QueueUrl' --output text 2>&1).Trim()
aws sqs send-message --queue-url $fifoUrl --message-body 'hello-fifo' --message-group-id grp1 $EP 2>&1 | Out-Null
$fifoBody = (aws sqs receive-message --queue-url $fifoUrl $EP --query 'Messages[0].Body' --output text 2>&1).Trim()
if ($fifoBody -eq "hello-fifo") { Test-Pass "SQS FIFO: send + receive" }
else { Test-Fail "SQS FIFO: got '$fifoBody'" }
aws sqs delete-queue --queue-url $stdUrl $EP 2>&1 | Out-Null
aws sqs delete-queue --queue-url $fifoUrl $EP 2>&1 | Out-Null
Write-Host ""

# --- Lambda ---
Write-Host "[5/6] Lambda"
New-Item -ItemType Directory -Force -Path verify-lambda | Out-Null
$pyCode = "import json`ndef handler(event, context):`n    return {`"statusCode`": 200, `"body`": json.dumps({`"msg`": `"ok`"})}"
[System.IO.File]::WriteAllText("$PWD\verify-lambda\lambda_function.py", $pyCode)
Push-Location verify-lambda
Compress-Archive -Path lambda_function.py -DestinationPath ..\verify-lambda.zip -Force
Pop-Location

aws lambda create-function --function-name verify-fn --runtime python3.12 --handler lambda_function.handler --role arn:aws:iam::000000000000:role/test-role --zip-file fileb://verify-lambda.zip $EP 2>&1 | Out-Null

Write-Host "  (First invoke may take 30-60s to pull runtime image...)"
aws lambda invoke --function-name verify-fn --payload '{}' --cli-binary-format raw-in-base64-out verify-response.json $EP 2>&1 | Out-Null
$lambdaResp = Get-Content verify-response.json -Raw -ErrorAction SilentlyContinue
if ($lambdaResp -match "msg") { Test-Pass "Lambda: deploy + invoke (python3.12)" }
else { Test-Fail "Lambda: unexpected response" }
aws lambda delete-function --function-name verify-fn $EP 2>&1 | Out-Null
Remove-Item -Recurse -Force verify-lambda, verify-lambda.zip, verify-response.json -ErrorAction SilentlyContinue
Write-Host ""

# --- API Gateway ---
Write-Host "[6a/6] API Gateway"
New-Item -ItemType Directory -Force -Path verify-apigw | Out-Null
$apigwCode = "import json`ndef handler(event, context):`n    return {`"statusCode`": 200, `"headers`": {`"Content-Type`": `"application/json`"}, `"body`": json.dumps({`"apigw`": `"ok`"})}"
[System.IO.File]::WriteAllText("$PWD\verify-apigw\lambda_function.py", $apigwCode)
Push-Location verify-apigw
Compress-Archive -Path lambda_function.py -DestinationPath ..\verify-apigw.zip -Force
Pop-Location

$fnArn = (aws lambda create-function --function-name verify-apigw-fn --runtime python3.12 --handler lambda_function.handler --role arn:aws:iam::000000000000:role/test-role --zip-file fileb://verify-apigw.zip $EP --query 'FunctionArn' --output text 2>&1).Trim()
$apiId = (aws apigateway create-rest-api --name verify-api $EP --query 'id' --output text 2>&1).Trim()
$rootId = (aws apigateway get-resources --rest-api-id $apiId $EP --query 'items[0].id' --output text 2>&1).Trim()
$resId = (aws apigateway create-resource --rest-api-id $apiId --parent-id $rootId --path-part ping $EP --query 'id' --output text 2>&1).Trim()
aws apigateway put-method --rest-api-id $apiId --resource-id $resId --http-method GET --authorization-type NONE $EP 2>&1 | Out-Null

$integUri = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/$fnArn/invocations"
aws apigateway put-integration --rest-api-id $apiId --resource-id $resId --http-method GET --type AWS_PROXY --integration-http-method POST --uri $integUri $EP 2>&1 | Out-Null
aws apigateway create-deployment --rest-api-id $apiId --stage-name test $EP 2>&1 | Out-Null

try {
    $apigwUrl = "http://localhost:4566/restapis/$apiId/test/_user_request_/ping"
    $apigwResp = Invoke-RestMethod -Uri $apigwUrl -TimeoutSec 30
    if ($apigwResp.apigw -eq "ok") { Test-Pass "API Gateway: REST to Lambda over HTTP" }
    else { Test-Fail "API Gateway: unexpected response" }
} catch { Test-Fail "API Gateway: HTTP request failed" }

aws apigateway delete-rest-api --rest-api-id $apiId $EP 2>&1 | Out-Null
aws lambda delete-function --function-name verify-apigw-fn $EP 2>&1 | Out-Null
Remove-Item -Recurse -Force verify-apigw, verify-apigw.zip -ErrorAction SilentlyContinue
Write-Host ""

# --- Cognito ---
Write-Host "[6b/6] Cognito"
$poolId = (aws cognito-idp create-user-pool --pool-name verify-pool --policies 'PasswordPolicy={MinimumLength=8,RequireUppercase=false,RequireLowercase=false,RequireNumbers=false,RequireSymbols=false}' $EP --query 'UserPool.Id' --output text 2>&1).Trim()
$clientId = (aws cognito-idp create-user-pool-client --user-pool-id $poolId --client-name verify-client --explicit-auth-flows ALLOW_USER_PASSWORD_AUTH ALLOW_REFRESH_TOKEN_AUTH --no-generate-secret $EP --query 'UserPoolClient.ClientId' --output text 2>&1).Trim()
aws cognito-idp admin-create-user --user-pool-id $poolId --username verifyuser --temporary-password 'TempPass1!' $EP 2>&1 | Out-Null
aws cognito-idp admin-set-user-password --user-pool-id $poolId --username verifyuser --password 'VerifyPass1!' --permanent $EP 2>&1 | Out-Null
$authResult = aws cognito-idp initiate-auth --client-id $clientId --auth-flow USER_PASSWORD_AUTH --auth-parameters USERNAME=verifyuser,PASSWORD='VerifyPass1!' $EP 2>&1 | Out-String
if ($authResult -match "AccessToken") { Test-Pass "Cognito: pool, user, auth with JWT" }
else { Test-Fail "Cognito: auth failed" }
aws cognito-idp delete-user-pool --user-pool-id $poolId $EP 2>&1 | Out-Null
Write-Host ""

# --- Summary ---
Write-Host "============================================"
Write-Host "  Results: $Pass passed, $Fail failed"
Write-Host "============================================"
if ($Fail -gt 0) {
    Write-Host "Some checks failed. Review output above." -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "All checks passed! Environment is ready." -ForegroundColor Green
    exit 0
}
