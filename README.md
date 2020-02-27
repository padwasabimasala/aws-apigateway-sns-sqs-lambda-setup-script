# aws-apigateway-sns-sqs-lambda-setup-script

Some shell functions to aid in the setup an AWS API Gateway to SNS to SQS to Lambda pipeline

Not all steps are automated. Read thru the entire script before running
anything. After that, source the script in your terminal and run commands one
at a time, copying the output of earlier commands into variables to be used by
later commands as you go.

The util provides the following functions

* create-api()
* get-root()
* create-resource()
* create-post-method()
* create-sns-topic()
* create-pipeline-role()
* update-pipeline-role()
* create-sns-integration()
* create-deployment()
* create-queue()
* stub-lambda()
* create-lambda()
* create-lambda-sqs-mapping()
* test-pipeline()

Example usage

```
$ source aws-setup-util.bash
$ export API_NAME="My API"
$ create-api
{
    "id": "rb2pmsba11",
    "name": "My API"
    "createdDate": 1582846780,
    "apiKeySource": "HEADER",
    "endpointConfiguration": {
        "types": [
            "EDGE"
        ]
    }
}
$ export API_ID=rb2pmsba11
$ get-root
```

Happy hacking
--pwm
