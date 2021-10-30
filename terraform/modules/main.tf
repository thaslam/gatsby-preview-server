terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

# configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

# create public s3 bucket website for graphql model
resource "aws_s3_bucket" "gatsby_website_bucket" {
  bucket        = "gatsby-website.${var.app_name}.com"
  acl           = "public-read"
  policy        = file("policy.json")
  tags          = {
    Name        = "gatsby_preview_website"
    Environment = "dev"
  }
  website {
    index_document = "index.html"
    error_document = "error.html"

    routing_rules = <<EOF
    [{
    "Condition": {
        "KeyPrefixEquals": "docs/"
    },
    "Redirect": {
        "ReplaceKeyPrefixWith": "documents/"
    }
    }]
    EOF
  }
}

# create vpc to host efs and gatsby lambda
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc
resource "aws_vpc" "gatsby_server_vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"
  tags = {
    Name = "${var.app_name}_vpc"
  }
}

# create efs file system to host gatsby server
# https://github.com/philips-software/terraform-aws-efs/blob/develop/main.tf
# can replace this with direct reference to vpc create above, leaving for for testing purposes
data "aws_vpc" "selected" {
  id = aws_vpc.gatsby_server_vpc.id
}

resource "aws_security_group" "efs_sg" {
  name        = "${var.environment}-efs-sg"
  description = "controls access to efs"

  vpc_id = aws_vpc.gatsby_server_vpc.id

  ingress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  tags = merge(
    {
      "Name" = format("%s", "${var.environment}-efs-sg")
    },
    {
      "Environment" = format("%s", var.environment)
    },
    {
      "Project" = format("%s", var.app_name)
    },
    var.tags,
  )
}

resource "aws_efs_file_system" "efs" {
  encrypted        = var.encrypted
  performance_mode = var.performance_mode
  creation_token   = var.creation_token

  dynamic "lifecycle_policy" {
    for_each = var.transition_to_ia != null ? [var.transition_to_ia] : []

    content {
      transition_to_ia = lifecycle_policy.value
    }
  }

  tags = merge(
    {
      "Name" = format("%s", "${var.environment}-efs")
    },
    {
      "Environment" = format("%s", var.environment)
    },
    {
      "Project" = format("%s", var.project)
    },
    var.tags,
  )
}

resource "aws_efs_mount_target" "efs_mount_target" {
  count = length(var.subnet_ids)

  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = element(var.subnet_ids, count.index)
  security_groups = [aws_security_group.efs_sg.id]
}

data "template_file" "amazon_linux_cloud_init_part" {
  template = <<EOL
# Install nfs-utils
cloud-init-per once yum_update yum update -y
cloud-init-per once install_nfs_utils yum install -y nfs-utils

# Create $${mount_location} folder
cloud-init-per once mkdir_efs mkdir $${mount_location}

# Mount $${mount_location}
cloud-init-per once mount_efs echo -e '$${efs_dns}:/ $${mount_location} nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 0 0' >> /etc/fstab
mount -a
EOL

  vars = {
    efs_dns        = element(aws_efs_mount_target.efs_mount_target.*.dns_name, 0)
    mount_location = var.mount_location
  }
}

# create public s3 bucket for graphql model
resource "aws_s3_bucket" "lambda_bucket" {
  bucket        = "${var.app_name}-gatsby-preview-server-lambda"
  acl           = "public-read"
  tags          = {
    Name        = "gatsby_preview_server_lambda_bucket"
    Environment = "dev"
  }
}

# zip lambda and upload to S3, the pathing and collectiong of lambda function should be made generic
data "archive_file" "lambda_hello_world" {
  type = "zip"
  source_dir  = "${var.lambda_path_helloword}"
  output_path = "${path.module}/helloworld_function.zip"
}

# zip lambda and upload to S3, the pathing and collectiong of lambda function should be made generic
data "archive_file" "lambda_preview" {
  type = "zip"
  source_dir  = "${var.lambda_path_preview}"
  output_path = "${path.module}/preview_function.zip"
}

resource "aws_s3_bucket_object" "lambda_hello_world" {
  bucket = aws_s3_bucket.lambda_bucket.id
  key    = "helloworld_function.zip"
  source = data.archive_file.lambda_hello_world.output_path
  etag   = filemd5(data.archive_file.lambda_hello_world.output_path)
}

# create the lambda function
resource "aws_lambda_function" "hello_world" {
  function_name = "hello_world_gatsby_preview_server"

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_bucket_object.lambda_hello_world.key

  runtime = "nodejs12.x"
  handler = "index.handler"

  source_code_hash = data.archive_file.lambda_hello_world.output_base64sha256
  role = aws_iam_role.lambda_exec.arn
}

resource "aws_cloudwatch_log_group" "hello_world" {
  name = "/aws/lambda/${aws_lambda_function.hello_world.function_name}"
  retention_in_days = 30
}

resource "aws_iam_role" "lambda_exec" {
  name = "serverless_lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# create api gateway endpoint
resource "aws_apigatewayv2_api" "gatsby_preview_server" {
  name          = "serverless_gatsby_preview_server_gw"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "gatsby_preview_server" {
  api_id = aws_apigatewayv2_api.gatsby_preview_server.id

  name        = "serverless_gatsby_preview_server_stage"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}

resource "aws_apigatewayv2_integration" "hello_world" {
  api_id = aws_apigatewayv2_api.gatsby_preview_server.id

  integration_uri    = aws_lambda_function.hello_world.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "hello_world" {
  api_id = aws_apigatewayv2_api.gatsby_preview_server.id

  route_key = "GET /hello"
  target    = "integrations/${aws_apigatewayv2_integration.hello_world.id}"
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/api_gw/${aws_apigatewayv2_api.gatsby_preview_server.name}"

  retention_in_days = 30
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello_world.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.gatsby_preview_server.execution_arn}/*/*"
}
