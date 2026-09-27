# Packages app/ (app.py, templates/, static/, requirements.txt) into a zip and uploads
# it to a dedicated prefix in the document bucket. Every ASG instance's user-data (see
# asg.tf) downloads and unpacks this artifact on boot, so new/replacement instances
# always receive the current application code without needing CodeDeploy or a separate
# deployment service.

data "archive_file" "app_package" {
  type        = "zip"
  source_dir  = "${path.module}/../app"
  output_path = "${path.module}/build/app_package.zip"
}

resource "aws_s3_object" "app_package" {
  bucket = aws_s3_bucket.documents.id
  key    = "app-artifacts/app_package.zip"
  source = data.archive_file.app_package.output_path
  etag   = data.archive_file.app_package.output_md5
}
