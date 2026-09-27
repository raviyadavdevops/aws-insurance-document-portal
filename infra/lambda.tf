data "archive_file" "lambda_package" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/lambda_package.zip"
  excludes    = ["requirements.txt"]
}

resource "aws_lambda_function" "metadata_processor" {
  function_name = "${local.name_prefix}-metadata-processor"
  role          = aws_iam_role.lambda.arn
  handler       = "handler.handler"
  runtime       = "python3.11"
  timeout       = 30

  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

  # psycopg2-binary is not part of the base runtime — bundled as a Lambda Layer built
  # automatically by infra/lambda_layer.tf from lambda/requirements.txt.
  layers = [aws_lambda_layer_version.psycopg2.arn]

  vpc_config {
    subnet_ids         = aws_subnet.private_app[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DB_HOST     = aws_db_instance.postgres.address
      DB_PORT     = tostring(aws_db_instance.postgres.port)
      DB_NAME     = var.db_name
      DB_USER     = var.db_username
      DB_PASSWORD = var.db_password
    }
  }

  tags = local.common_tags
}

resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.metadata_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.documents.arn
}
