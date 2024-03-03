provider "aws" {
  region = "eu-central-1"
  access_key = "accesskey"
  secret_key = "secretkey"
}

resource "aws_sqs_queue" "OrdersQueue_SQS" {
  name = "OrdersQueue_SQS"
  delay_seconds = 90
  max_message_size = 2048
  message_retention_seconds = 86400
  receive_wait_time_seconds = 10

  tags = {
    "Receiver" = "OrderLoggingLambda"
  }
}

resource "aws_iam_role" "Lambda_ROLE" {
  name = "LambdaFunctions_ROLE"
  description = "allowing lambda to assume role"
  assume_role_policy = jsonencode({
    Version: "2012-10-17"
    Statement: [
        {
            Action: "sts:AssumeRole"
            Principal: {
                Service: "lambda.amazonaws.com"
            }
            Effect: "Allow"
            Sid: ""
        }
    ]
  })
}

resource "aws_iam_policy" "GenerateCloudWatchLogs_POLICY" {
  name = "GenerateCloudWatchLogs_POLICY"
  description = "granting rights to generate logs on cloudwatch"
  policy = jsonencode({
    Version: "2012-10-17"
    Statement: [{
        Action: [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
        ]
        Effect: "Allow"
        Resource: "*"
    }]
  })
}

resource "aws_iam_policy" "OrderReceivingLambda_POLICY" {
  name = "OrderReceivingLambda_POLICY"
  description = "granting this lambda permission to get invoked from api gateway, send message to sqs and log to cloudwatch"
  policy = jsonencode({
    Version: "2012-10-17"
    Statement: [{
        Action: [
            "sqs:SendMessage"
        ]
        Effect: "Allow"
        Resource: "${aws_sqs_queue.OrdersQueue_SQS.arn}"
    },
    {
        Action: ["lambda:InvokeFunction"]
        Effect: "Allow"
        Resource: "arn:aws:lambda:*:*:*"
    }]
  })
}

resource "aws_iam_policy" "OrderLoggingLambda_POLICY" {
    name = "OrderLoggingLambda_POLICY"
    description = "granting the lambda the permission to get triggered by sqs and create logs in cloudwatch"
    policy = jsonencode({
        Version: "2012-10-17"
        Statement: [{
            Action: [
                "sqs:ReceiveMessage",
                "sqs:ChangeMessageVisibility",
                "sqs:DeleteMessage",
                "sqs:GetQueueAttributes"
            ]
            Effect: "Allow"
            Resource: "${aws_sqs_queue.OrdersQueue_SQS.arn}"
        }]
    })
}

resource "aws_iam_role_policy_attachment" "OrderReceivingLambda_POLICYATTACHMENT" {
    role = aws_iam_role.Lambda_ROLE.name
    policy_arn = aws_iam_policy.OrderReceivingLambda_POLICY.arn
}

resource "aws_iam_role_policy_attachment" "OrderReceivingLambda_CloudWatch_POLICYATTACHMENT" {
    role = aws_iam_role.Lambda_ROLE.name
    policy_arn = aws_iam_policy.GenerateCloudWatchLogs_POLICY.arn
}

resource "aws_iam_role_policy_attachment" "OrderLoggingLambda_POLICYATTACHMENT" {
    role = aws_iam_role.Lambda_ROLE.name
    policy_arn = aws_iam_policy.OrderLoggingLambda_POLICY.arn
}

resource "aws_iam_role_policy_attachment" "OrderLoggingLambda_CloudWatch_POLICYATTACHMENT" {
    role = aws_iam_role.Lambda_ROLE.name
    policy_arn = aws_iam_policy.GenerateCloudWatchLogs_POLICY.arn
}

data "archive_file" "ZipOrderReceivingLambda" {
    type = "zip"
    source_dir = "${path.module}/lambdas/OrderReceivingLambda"
    output_path = "${path.module}/lambdas/OrderReceivingLambda/OrderReceivingLambda.zip"
}

data "archive_file" "ZipOrderLoggingLambda" {
    type = "zip"
    source_dir = "${path.module}/lambdas/OrderLoggingLambda"
    output_path = "${path.module}/lambdas/OrderLoggingLambda/OrderLoggingLambda.zip"
}

resource "aws_lambda_function" "OrderReceivingLambda" {
    filename = data.archive_file.ZipOrderReceivingLambda.output_path
    function_name = "OrderReceivingLambda"
    role = aws_iam_role.Lambda_ROLE.arn
    handler = "main"
    runtime = "go1.x"
    depends_on = [ aws_iam_role_policy_attachment.OrderReceivingLambda_POLICYATTACHMENT ]
    environment {
      variables = {
        "QUEUE_URL" = aws_sqs_queue.OrdersQueue_SQS.url
      }
    }
}

resource "aws_lambda_function" "OrderLoggingLambda" {
    filename = data.archive_file.ZipOrderLoggingLambda.output_path
    function_name = "OrderLoggingLambda"
    role = aws_iam_role.Lambda_ROLE.arn
    handler = "main"
    runtime = "go1.x"
    depends_on = [ aws_iam_role_policy_attachment.OrderLoggingLambda_POLICYATTACHMENT ]
}

resource "aws_lambda_event_source_mapping" "SQSTriggerOrderLoggingLambda" {
    event_source_arn = aws_sqs_queue.OrdersQueue_SQS.arn
    function_name = aws_lambda_function.OrderLoggingLambda.function_name
}

resource "aws_api_gateway_rest_api" "OrdersAPI_RESTAPI" {
    name = "ApiGateway_GATEWAY"
    description = "public facing API to handle incoming orders via the route /order"
}

resource "aws_api_gateway_resource" "APIGatewayResource_RESOURCE" {
    rest_api_id = aws_api_gateway_rest_api.OrdersAPI_RESTAPI.id
    parent_id = aws_api_gateway_rest_api.OrdersAPI_RESTAPI.root_resource_id
    path_part = "order"
}

resource "aws_api_gateway_method" "APIGatewayMethod_METHOD" {
    rest_api_id = aws_api_gateway_rest_api.OrdersAPI_RESTAPI.id
    resource_id = aws_api_gateway_resource.APIGatewayResource_RESOURCE.id
    http_method = "POST"
    authorization = "NONE"
}

resource "aws_lambda_permission" "APIGatewayInvokeLambda_PERMISSION" {
    statement_id = "AlloeExecutionFromAPIGateway"
    action = "lambda:InvokeFunction"
    function_name = aws_lambda_function.OrderReceivingLambda.function_name
    principal = "apigateway.amazonaws.com"
    source_arn = "${aws_api_gateway_rest_api.OrdersAPI_RESTAPI.execution_arn}/*/*"
}

resource "aws_api_gateway_integration" "APIGatewayLambdaIntegration_INTEGRATION" {
    rest_api_id = aws_api_gateway_rest_api.OrdersAPI_RESTAPI.id
    resource_id = aws_api_gateway_resource.APIGatewayResource_RESOURCE.id
    http_method = aws_api_gateway_method.APIGatewayMethod_METHOD.http_method
    integration_http_method = "POST"
    type = "AWS_PROXY"
    uri = aws_lambda_function.OrderReceivingLambda.invoke_arn
}

resource "aws_api_gateway_deployment" "APIGateway_DEPLOYMENT" {
    depends_on = [ aws_api_gateway_integration.APIGatewayLambdaIntegration_INTEGRATION ]
    rest_api_id = aws_api_gateway_rest_api.OrdersAPI_RESTAPI.id
    stage_name = "production"
}

resource "aws_cloudwatch_log_group" "OrderReceivingLambda_LOGGROUP" {
    name = "/aws/lambda/${aws_lambda_function.OrderReceivingLambda.function_name}"
}

resource "aws_cloudwatch_log_group" "OrderLoggingLambda_LOGGROUP" {
    name = "/aws/lambda/${aws_lambda_function.OrderLoggingLambda.function_name}"
}

output "API_Url" {
    value = aws_api_gateway_deployment.APIGateway_DEPLOYMENT.invoke_url
}
