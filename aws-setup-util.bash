#!/usr/bin/env bash
#
# The following script mostly automates the setup and configuration of the Segrt AWS pipeline
#
# Each step must be run in the correct sequence on the command line
# In some cases the input of a step requires part of the output of an earlier step
# Gathering this output is a manual process of copy/paste
#
# There are two other manual steps
# 1. One that must be run by Ops because of permissions
# 2. Another that must be done manually in the UI
#
# The script is based on these tutorials
#
# API GW tutorial - https://docs.aws.amazon.com/apigateway/latest/developerguide/create-api-using-awscli.html
# API Logging - https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html
#
# LICENSE
#
# Copyright (c) 2020 Nav Inc. Matthew Throley, other authors
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.


## Setup the API Gateway

# You will use this name for find your API Gateway in AWS: like Secure Proxy, Pet Store API, My App
API_NAME="Your API Name"
create-api() {
  aws apigateway create-rest-api --name "$API_NAME" --region us-west-2
}
# API_ID is returned in the response to create-api
# After running create-api copy the api_id from the response and paste it here: like API_ID=poh397i1g4
API_ID=yourapiid
get-root() {
  aws apigateway get-resources --rest-api-id $API_ID --region us-west-2
}

# ROOT_RESOURCE is returned in the response to get-root
# After running get-root copy the root resource id from the response and paste it here: like ROOT_RESOURCE=si1o0d8eqj
ROOT_RESOURCE=pj1f0d8evj

## Setup the web-hook endpoint and method
#
# The end-point is part of the url like a rest resource e.g. /books or /my-endpoint
# An http method must be assigned to an endpoint e.g. POST, GET, etc

END_POINT_NAME=your-endpoint-name
create-resource() {
  aws apigateway create-resource --rest-api-id $API_ID \
      --region us-west-2 \
      --parent-id $ROOT_RESOURCE \
      --path-part $END_POINT_NAME
}

# END_POINT_ID is returned in the response to create-resource
# After running create-resource copy the end point id from the response and paste it here: like END_POINT_ID=b8so3q
END_POINT_ID=yourendpointid

create-post-method() {
  aws apigateway put-method --rest-api-id $API_ID \
         --resource-id $END_POINT_ID \
         --http-method  POST \
         --authorization-type "NONE" \
         --region us-west-2
}

# Setup the SNS topic
# I recommend making the topic root similar to the API name like TOPIC_ROOT=your-api-name

TOPIC_ROOT=your-topic-root
TOPIC_NAME=$TOPIC_ROOT-$END_POINT_NAME
create-sns-topic() {
  TOPIC_ARN=$(aws sns create-topic \
    --name $TOPIC_NAME \
    --output text \
    --query 'TopicArn')
  echo $TOPIC_ARN
}

# TOPIC_ARN is returned in the response to create-sns-topic
# After running create-sns-topic copy the topic arn from the response and paste it here: like TOPIC_ARN=arn:aws:sns:us-west-2:328473910721:your-topic-root-your-end-point-name

TOPIC_ARN=arn:your-arn

# Setup role

ROLE_NAME=$API_NAME-pipeline
create-pipeline-role() {
  role_arn=$(aws iam create-role \
    --role-name $ROLE_NAME \
    --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": {
      "Effect": "Allow",
      "Principal": {"Service": [
        "apigateway.amazonaws.com", "lambda.amazonaws.com", "sqs.amazonaws.com", "sns.amazonaws.com"
        ]},
        "Action": "sts:AssumeRole"
      }
    }' \
    --output text \
    --query 'Role.Arn')
  echo $role_arn
}

# ROLE_ARN is returned in the response to create-pipeline-role
# After running create-pipeline-role copy the role arn from the response and paste it here: like ROLE_ARN=arn:aws:iam::4892741693l2:role/...
ROLE_ARN=arn:your-role-arn

# Topic ARN contains wildcard so policy will work for multiple integration end points
# On policy wildcards https://docs.aws.amazon.com/AmazonS3/latest/dev/s3-arn-format.html

update-pipeline-role() {
  topic_arn=$TOPIC_ARN
  topic_arn=arn:aws:sns:us-west-2:482072481827:your-api-base-*
  aws iam put-role-policy \
  --role-name $ROLE_NAME \
  --policy-name 'sns-publish' \
  --policy-document '{
  "Version": "2012-10-17",
  "Statement": { "Effect": "Allow", "Action": "sns:Publish", "Resource": "'$topic_arn'" }
  }'

  aws iam attach-role-policy \
    --role-name $ROLE_NAME \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs
  aws iam attach-role-policy \
    --role-name $ROLE_NAME \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
  aws iam attach-role-policy \
    --role-name $ROLE_NAME \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole
}

# Setup the api / sns integration

REGION=$(aws configure get region)
_sns-put-integration() {
  aws apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $END_POINT_ID \
    --http-method POST \
    --type AWS \
    --integration-http-method POST \
    --uri 'arn:aws:apigateway:'$REGION':sns:path//' \
    --credentials $ROLE_ARN \
    --request-parameters '{
          "integration.request.header.Content-Type": "'\'application/x-www-form-urlencoded\''"
      }' \
    --request-templates '{
      "application/json": "Action=Publish&TopicArn=$util.urlEncode('\'$TOPIC_ARN\'')&Message=$util.urlEncode($input.body)"
    }' \
    --passthrough-behavior NEVER
}

_sns-put-integration-response() {
  aws apigateway put-integration-response \
  --rest-api-id $API_ID \
  --resource-id $END_POINT_ID \
  --http-method POST \
  --status-code 200 \
  --selection-pattern "" \
  --response-templates '{"application/json": "{\"body\": \"Message received.\"}"}'
}

_sns-put-method-response() {
  aws apigateway put-method-response \
  --rest-api-id $API_ID \
  --resource-id $END_POINT_ID \
  --http-method POST \
  --status-code 200 \
  --response-models '{"application/json": "Empty" }'
}

create-sns-integration() {
  _sns-put-integration
  _sns-put-integration-response
  _sns-put-method-response
}

# Because Segment webhooks stop publishing after the first successful http response from any end-point we send all
# events to one production end-point with a single prd deploy stage. After events are received by SNS they may be
# published to dev or prd queues as needed.
#
# You must deploy everytime you add or make a change to an endpoint

DEPLOY_STAGE=prd
create-deployment() {
  aws apigateway create-deployment \
    --rest-api-id $API_ID \
    --stage-name $DEPLOY_STAGE
}

# Create an SMS subscription to the SNS topic and send a message to ensure the topic is correctly configured
# You can also run test-pipeline at this step to ensure the API and SNS have been configured correctly

_create-sms-subscription() {
  SMS_ENDPOINT=+1YOUR_NUM_HERE
  aws sns subscribe --topic-arn $TOPIC_ARN \
      --protocol sms \
      --notification-endpoint $SMS_ENDPOINT
}

_sms-test() {
  aws sns publish --topic-arn $TOPIC_ARN \
    --message 'This is a test'
}

# Set up the queue
QUEUE_NAME=$TOPIC_NAME
ACCT_ID=YOUR_NUMERIC_AWS_ACCOUNT_ID
QUEUE_URL=https://$REGION.queue.amazonaws.com/$ACCT_ID/$QUEUE_NAME
QUEUE_ARN=arn:aws:sqs:$REGION:$ACCT_ID:$QUEUE_NAME

_create-queue() {
  aws sqs create-queue \
    --queue-name $QUEUE_NAME
}

# https://docs.aws.amazon.com/cli/latest/reference/sqs/set-queue-attributes.html
_set-queue-attributes() {
  twelve_hours=43200 # in seconds
  aws sqs set-queue-attributes --queue-url $QUEUE_URL --attributes MessageRetentionPeriod=$twelve_hours
}

create-queue() {
  _create-queue
  _set-queue-attributes
}

# SNS and SQS https://docs.aws.amazon.com/sns/latest/dg/sns-sqs-as-subscriber.html
# Queue subscription is MANUAL for now.
#
# Visit the SQS ui, select the queue, and from queue actions choose subscribe, then choose the sns topic
# https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-subscribe-queue-sns-topic.html
#
# I have not been able to automate attching the policy with either set-queue-attributes or add-permission
#
# set-queue-policy() {
#   aws sqs set-queue-attributes --queue-url $QUEUE_URL --attributes file://set-queue-attributes.json
# }
#
# add-queue-perm() {
#   aws sqs add-permission --queue-url $QUEUE_URL --label SendMessagesFromMyQueue --aws-account-ids '{ "AWS" : "*" }' --actions SendMessage
# }
#
# subscribe-queue() {
#   aws sns subscribe \
#     --topic-arn $TOPIC_ARN \
#     --protocol sqs \
#     --notification-endpoint $QUEUE_ARN
# }

# Setup Lambda

stub-lambda() {
  mkdir -p stub-function
cat << EOF > stub-function/lambda_function.py
def lambda_handler(event, context):
  """ Lambda example
  """
  print("Received event: {}".format(event))
EOF
  cd stub-function
  zip ../stub-function.zip lambda_function.py
  cd -
}

# Simple lambda from CLI - http://www.zakariaamine.com/2019-02-17/lambda-with-sqs-eventsource-cli
# More complete lambda from CLI - https://medium.com/@jacobsteeves/aws-lambda-from-the-command-line-7efab7f3ebd9

LAMBDA_NAME=$QUEUE_NAME
LAMBDA_ROLE=$ROLE_ARN

_create-lambda() {
  aws lambda create-function \
    --function-name  $LAMBDA_NAME \
    --zip-file fileb://stub-function.zip \
    --runtime python3.6 \
    --role $LAMBDA_ROLE \
    --handler lambda_function.lambda_handler
}

# Set the concurrency to 1 to reduce costs and run away execution in the event of error
_set-lambda-concurrency() {
  aws lambda put-function-concurrency \
    --function-name  $LAMBDA_NAME \
    --reserved-concurrent-executions 1
}

create-lambda() {
  _create-lambda
  _set-lambda-concurrency
}

# Lambda and SQS - https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html
# Lambda execution roles - https://docs.aws.amazon.com/lambda/latest/dg/lambda-intro-execution-role.html
create-lambda-sqs-mapping() {
  aws lambda create-event-source-mapping \
    --function-name $LAMBDA_NAME \
    --event-source-arn $QUEUE_ARN
}

test-pipeline() {
  echo https://$API_ID.execute-api.$REGION.amazonaws.com/$DEPLOY_STAGE/$END_POINT_NAME
  curl -X POST https://$API_ID.execute-api.$REGION.amazonaws.com/$DEPLOY_STAGE/$END_POINT_NAME \
    --data '{"msg": "Hello from the CLI"}' \
    -H 'Content-Type: application/json'
}

# If you get the error {"message":"Missing Authentication Token"}
# This message could mean you made a change to the API Gateway but did not do a deployment
