#!/bin/bash

ROLE_NAME=calc-lambda-role
POLICY_NAME=lambda_execute
FUNCTION_NAME=Calc5
API_NAME=LambdaCalc

POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='$POLICY_NAME'].Arn" --output text --region $REGION)

echo "1 iam detach-role-policy $POLICY_ARN"
aws iam detach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn $POLICY_ARN

echo "2 iam delete-policy $POLICY_ARN"
aws iam delete-policy \
  --policy-arn $POLICY_ARN

echo "3 iam delete-role $ROLE_NAME"
aws iam delete-role \
  --role-name $ROLE_NAME

API_ID=$(aws apigateway get-rest-apis --query "items[?name=='$API_NAME'].id" --output text --region $REGION)

echo "4 iam delete-rest-api API_ID: $API_ID"
aws apigateway delete-rest-api \
  --rest-api-id $API_ID

echo "5 lambda delete-function $FUNCTION_NAME"
aws lambda delete-function \
  --function-name $FUNCTION_NAME

echo "deleting done"

