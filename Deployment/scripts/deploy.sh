#!/bin/bash

ROLE_NAME=calc-lambda-role
TRUST_POLICY_LAMBDA=policies/trust-policy.json
INVOKE_TRUST_POLICY=policies/invoke-function-role-trust-policy.json
POLICY_NAME=lambda_execute
REGION=eu-north-1
ACCOUNT_ID=395271539316
FUNCTION_NAME=Calc5
API_NAME=LambdaCalc
RESOURCE_NAME=calc5
VALIDATE_REQUEST_PARAMETER_NAME=validate-request-parameters
VALIDATE_REQUEST_BODY_NAME=validate-request-body
INPUT_MODEL_NAME=Input
OUTPUT_MODEL_NAME=Output
RESULT_MODEL_NAME=Result
STAGE=test
REQUEST_TEMPLATES1=templates/request-templates.json
REQUEST_TEMPLATES2=templates/request-templates2.json

function fail() {
    echo $2
    exit $1
}

set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
source $DIR/config.sh

workspace="$DIR/../.."

echo -e "\ndeploying $executable"

$DIR/build-and-package.sh "$executable"

echo "1 iam create-policy..."
aws iam create-policy \
    --policy-name $POLICY_NAME \
    --policy-document file://$INVOKE_TRUST_POLICY \
    > results/create-policy.json

[ $? == 0 ] || fail 1 "Failed: AWS / iam / create-policy"

POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='$POLICY_NAME'].Arn" --output text --region $REGION)

echo "2 iam create-role..."
aws iam create-role \
  --role-name $ROLE_NAME \
  --assume-role-policy-document file://$TRUST_POLICY_LAMBDA \
  > results/create-role.json

[ $? == 0 ] || fail 2 "Failed: AWS / iam / create-role"

echo "3 iam attach-role-policy..."
aws iam attach-role-policy \
    --role-name $ROLE_NAME \
    --policy-arn $POLICY_ARN \
    > results/attach-role-policy.json

[ $? == 0 ] || fail 3 "Failed: AWS / iam / attach-role-policy"

ROLE_ARN=$(aws iam list-roles --query "Roles[?RoleName=='$ROLE_NAME'].Arn" --output text --region $REGION)

sleep 10

echo "4 lambda create-function..."
aws lambda create-function \
    --region $REGION \
    --function-name $FUNCTION_NAME \
    --runtime provided.al2 \
    --handler lambda.run \
    --memory-size 512 \
    --zip-file fileb://../.build/lambda/$RESOURCE_NAME/lambda.zip \
    --role $ROLE_ARN \
    --architecture arm64 \
    > results/lambda-create-function.json

[ $? == 0 ] || fail 4 "Failed: AWS / lambda / create-function"

LAMBDA_ARN=$(aws lambda list-functions --query "Functions[?FunctionName=='$FUNCTION_NAME'].FunctionArn" --output text --region $REGION)

echo "5 apigateway create-rest-api..."
aws apigateway create-rest-api \
    --region $REGION \
    --name $API_NAME \
    --endpoint-configuration types=REGIONAL \
    > results/create-rest-api.json

[ $? == 0 ] || fail 5 "Failed: AWS / apigateway / create-rest-api"

API_ID=$(aws apigateway get-rest-apis --query "items[?name=='$API_NAME'].id" --output text --region $REGION)
PARENT_RESOURCE_ID=$(aws apigateway get-resources --rest-api-id $API_ID --query 'items[?path==`/`].id' --output text --region $REGION)

echo "6 apigateway create-resource..."
aws apigateway create-resource \
    --region $REGION \
    --rest-api-id $API_ID \
    --parent-id $PARENT_RESOURCE_ID \
    --path-part $RESOURCE_NAME \
    > results/create-resource.json

[ $? == 0 ] || fail 6 "Failed: AWS / apigateway / create-resource"

RESOURCE_ID=$(aws apigateway get-resources --rest-api-id $API_ID --query "items[?path=='/$RESOURCE_NAME'].id" --output text --region $REGION)

echo "7 apigateway create-request-validator..."
aws apigateway create-request-validator \
    --region $REGION \
    --rest-api-id $API_ID \
    --name $VALIDATE_REQUEST_PARAMETER_NAME \
    --validate-request-parameters \
    > results/create-request-parameters-validator.json

[ $? == 0 ] || fail 7 "Failed: AWS / apigateway / create-request-validator"

REQUEST_VALIDATOR_PARAMETERS_ID=$(aws apigateway get-request-validators --rest-api-id $API_ID --query "items[?name=='$VALIDATE_REQUEST_PARAMETER_NAME'].id" --output text --region $REGION)

echo "8 apigateway create-request-validator..."
aws apigateway create-request-validator \
    --region $REGION \
    --rest-api-id $API_ID \
    --name $VALIDATE_REQUEST_BODY_NAME \
    --validate-request-body \
    > results/create-request-body-validator.json

[ $? == 0 ] || fail 8 "Failed: AWS / apigateway / create-request-validator"

REQUEST_VALIDATOR_BODY_ID=$(aws apigateway get-request-validators --rest-api-id $API_ID --query "items[?name=='$VALIDATE_REQUEST_BODY_NAME'].id" --output text --region $REGION)

#Integration 1
# Resources /calc/GET

echo "9 apigateway put-method..."
aws apigateway put-method \
    --region $REGION \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method GET \
    --authorization-type NONE \
    --request-validator-id $REQUEST_VALIDATOR_PARAMETERS_ID \
    --request-parameters "method.request.querystring.operand1=true,method.request.querystring.operand2=true,method.request.querystring.operator=true" \
    > results/put-get-method.json

[ $? == 0 ] || fail 9 "Failed: AWS / apigateway / put-method"

echo "10 apigateway put-method-response..."
aws apigateway put-method-response \
    --region $REGION \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method GET \
    --status-code 200 \
    --response-models application/json=Empty \
    > results/put-method-response.json

[ $? == 0 ] || fail 10 "Failed: AWS / apigateway / put-method-response"

echo "11 apigateway put-integration..."
aws apigateway put-integration \
    --region $REGION \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method GET \
    --type AWS \
    --integration-http-method POST \
    --uri arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/$LAMBDA_ARN/invocations \
    --credentials $ROLE_ARN \
    --passthrough-behavior WHEN_NO_TEMPLATES \
    --request-templates file://$REQUEST_TEMPLATES1 \
    > results/put-get-integration.json

[ $? == 0 ] || fail 11 "Failed: AWS / apigateway / put-integration"

echo "12 apigateway put-integration-response..."
aws apigateway put-integration-response \
    --region $REGION \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method GET \
    --status-code 200 \
    --response-templates application/json="" \
    > results/put-get-integration-response.json

[ $? == 0 ] || fail 12 "Failed: AWS / apigateway / put-integration-response"

# Integration 2
# Resources /calc/POST

echo "13 apigateway create-model..."
aws apigateway create-model \
    --rest-api-id $API_ID \
    --name $INPUT_MODEL_NAME \
    --content-type application/json \
    --schema "{\"type\": \"object\", \"properties\": { \"a\" : { \"type\": \"number\" },  \"b\" : { \"type\": \"number\" }, \"op\" : { \"type\": \"string\" }}, \"title\": \"$INPUT_MODEL_NAME\"}" \
    > results/create-input-model.json

[ $? == 0 ] || fail 13 "Failed: AWS / apigateway / create-model"

echo "14 apigateway create-model..."
aws apigateway create-model \
    --rest-api-id $API_ID \
    --name $OUTPUT_MODEL_NAME \
    --content-type application/json \
    --schema "{ \"type\": \"object\", \"properties\": { \"c\" : { \"type\": \"number\"}}, \"title\":\"$OUTPUT_MODEL_NAME\"}" \
    > results/create-output-model.json

[ $? == 0 ] || fail 14 "Failed: AWS / apigateway / create-model"

echo "15 apigateway create-model..."
aws apigateway create-model \
    --rest-api-id $API_ID \
    --name $RESULT_MODEL_NAME \
    --content-type application/json \
    --schema "{ \"type\": \"object\", \"properties\": { \"input\":{ \"\$ref\": \"https://apigateway.amazonaws.com/restapis/$API_ID/models/$INPUT_MODEL_NAME\"}, \"output\":{\"\$ref\": \"https://apigateway.amazonaws.com/restapis/$API_ID/models/Output\"}}, \"title\": \"$OUTPUT_MODEL_NAME\"}" \
    > results/create-result-model.json

[ $? == 0 ] || fail 15 "Failed: AWS / apigateway / create-model"

echo "16 apigateway put-method..."
aws apigateway put-method \
    --region $REGION \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method POST \
    --authorization-type NONE \
    > results/put-post-method.json

[ $? == 0 ] || fail 16 "Failed: AWS / apigateway / put-method"

echo "17 apigateway put-method-response..."
aws apigateway put-method-response \
    --region $REGION \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method POST \
    --status-code 200 \
    --response-models application/json=Empty \
    > results/put-method-response.json

[ $? == 0 ] || fail 17 "Failed: AWS / apigateway / put-method-response"

echo "18 apigateway put-integration..."
aws apigateway put-integration \
    --region $REGION \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method POST \
    --type AWS \
    --integration-http-method POST \
    --uri arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/$LAMBDA_ARN/invocations \
    --credentials $ROLE_ARN \
    --passthrough-behavior WHEN_NO_MATCH \
    > results/put-post-integration.json

[ $? == 0 ] || fail 18 "Failed: AWS / apigateway / put-integration"

echo "19 apigateway put-integration-response..."
aws apigateway put-integration-response \
    --region $REGION \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method POST \
    --status-code 200 \
    --response-templates application/json="" \
    > results/put-post-integration-response.json

[ $? == 0 ] || fail 19 "Failed: AWS / apigateway / put-integration-response"

# Integration 3
# Resources /{operand1}/{operand2}/{operator} GET

echo "20 apigateway create-resource..."
aws apigateway create-resource \
    --region $REGION \
    --rest-api-id $API_ID \
    --parent-id $RESOURCE_ID \
    --path-part {operand1} \
    > results/create-resource-operand1.json

[ $? == 0 ] || fail 20 "Failed: AWS / apigateway / create-resource-operand1"

RESOURCE_OPERAND1_PATH="$RESOURCE_NAME/{operand1}"
RESOURCE_OPERAND1_ID=$(aws apigateway get-resources --rest-api-id $API_ID --query "items[?path=='/$RESOURCE_OPERAND1_PATH'].id" --output text --region $REGION)

echo "21 apigateway create-resource..."
aws apigateway create-resource \
    --region $REGION \
    --rest-api-id $API_ID \
    --parent-id $RESOURCE_OPERAND1_ID \
    --path-part {operand2} \
    > results/create-resource-operand2.json

[ $? == 0 ] || fail 21 "Failed: AWS / apigateway / create-resource-operand2"

RESOURCE_OPERAND2_PATH="$RESOURCE_OPERAND1_PATH/{operand2}"
RESOURCE_OPERAND2_ID=$(aws apigateway get-resources --rest-api-id $API_ID --query "items[?path=='/$RESOURCE_OPERAND2_PATH'].id" --output text --region $REGION)

echo "22 apigateway create-resource..."
aws apigateway create-resource \
    --region $REGION \
    --rest-api-id $API_ID \
    --parent-id $RESOURCE_OPERAND2_ID \
    --path-part {operator} \
    > results/create-resource-operator.json

[ $? == 0 ] || fail 22 "Failed: AWS / apigateway / create-resource-operator"

RESOURCE_OPERATOR_PATH="$RESOURCE_OPERAND2_PATH/{operator}"
RESOURCE_OPERATOR_ID=$(aws apigateway get-resources --rest-api-id $API_ID --query "items[?path=='/$RESOURCE_OPERATOR_PATH'].id" --output text --region $REGION)

echo "23 apigateway put-method..."
aws apigateway put-method \
    --region $REGION \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_OPERATOR_ID \
    --http-method GET \
    --authorization-type NONE \
    --request-parameters "method.request.path.operand1=true,method.request.path.operand2=true,method.request.path.operator=true" \
    > results/put-get-path-method.json

[ $? == 0 ] || fail 23 "Failed: AWS / apigateway / put-method"

echo "24 apigateway put-method-response..."
aws apigateway put-method-response \
    --region $REGION \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_OPERATOR_ID \
    --http-method GET \
    --status-code 200 \
    --response-models application/json=Empty \
    > results/put-method-response2.json

[ $? == 0 ] || fail 24 "Failed: AWS / apigateway / put-method-response"

echo "25 apigateway put-integration..."
aws apigateway put-integration \
    --region $REGION \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_OPERATOR_ID \
    --http-method GET \
    --type AWS \
    --integration-http-method POST \
    --uri arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/$LAMBDA_ARN/invocations \
    --credentials $ROLE_ARN \
    --content-handling CONVERT_TO_TEXT \
    --passthrough-behavior WHEN_NO_TEMPLATES \
    --request-templates file://$REQUEST_TEMPLATES2 \
    > results/put-get-integration2.json

[ $? == 0 ] || fail 25 "Failed: AWS / apigateway / put-integration"

echo "26 apigateway put-integration-response..."
aws apigateway put-integration-response \
    --region $REGION \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_OPERATOR_ID \
    --http-method GET \
    --status-code 200 \
    --response-templates application/json="" \
    > results/put-get-integration-response2.json

[ $? == 0 ] || fail 26 "Failed: AWS / apigateway / put-integration-response"

echo "27 apigateway create-deployment..."
aws apigateway create-deployment \
    --region $REGION \
    --rest-api-id $API_ID \
    --stage-name $STAGE \
    > results/create-deployment.json

[ $? == 0 ] || fail 27 "Failed: AWS / apigateway / create-deployment"

ENDPOINT=https://$API_ID.execute-api.$REGION.amazonaws.com/$STAGE/$RESOURCE_NAME
echo "API available at: $ENDPOINT"

echo
echo "Integration 1"
echo "Testing GET with query parameters:"
echo "27 / 9"
cat << EOF
curl -i --request GET \
$ENDPOINT\?operand1=27&operand2\=9\&operator\=div
EOF
echo

curl -i --request GET \
$ENDPOINT\?operand1\=27\&operand2\=9\&operator\=div

echo
echo
echo "Integration 2"
echo "Testing POST:"
echo "8 + 6"
cat << EOF
curl -i --request POST \
--header "Content-Type: application/json" \
--data '{"a": 8, "b": 6, "op": "add"}' \
$ENDPOINT
EOF
echo

curl -i --request POST \
--header "Content-Type: application/json" \
--data '{"a": 8, "b": 6, "op": "add"}' \
$ENDPOINT

echo
echo
echo "Integration 3"
echo "Testing GET with path parameters:"
echo "5 * 8"
cat << EOF
curl -i --request GET \
$ENDPOINT/5/8/mul
EOF
echo

curl -i --request GET \
$ENDPOINT/5/8/mul