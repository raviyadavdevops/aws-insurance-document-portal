# Builds a Lambda Layer containing lambda/requirements.txt (psycopg2-binary) so the
# function can actually `import psycopg2` at runtime. Uses `pip download`-style
# `--platform`/`--only-binary` flags so this works reproducibly from any host OS
# (Windows/macOS/Linux) without needing a native build toolchain or Docker — pip simply
# fetches the prebuilt manylinux wheel for the target Lambda runtime.
#
# Requires `pip` (Python 3.x) to be available on the machine running `terraform apply`.
# Re-runs automatically whenever lambda/requirements.txt changes (see trigger below).

resource "null_resource" "lambda_layer_deps" {
  triggers = {
    requirements_hash = filesha1("${path.module}/../lambda/requirements.txt")
  }

  provisioner "local-exec" {
    # Single-line command (no shell line-continuation) run via bash explicitly, so this
    # behaves identically on Windows (via Git Bash/WSL bash on PATH) and on macOS/Linux —
    # avoids relying on Terraform's default per-OS shell (cmd.exe on Windows, which does
    # not support bash-style trailing-backslash continuation).
    interpreter = ["bash", "-c"]
    command     = "pip install -r \"${path.module}/../lambda/requirements.txt\" --platform manylinux2014_x86_64 --implementation cp --python-version 3.11 --only-binary=:all: --target \"${path.module}/build/layer/python\" --upgrade"
  }
}

data "archive_file" "lambda_layer" {
  type        = "zip"
  source_dir  = "${path.module}/build/layer"
  output_path = "${path.module}/build/lambda_layer.zip"

  depends_on = [null_resource.lambda_layer_deps]
}

resource "aws_lambda_layer_version" "psycopg2" {
  layer_name          = "${local.name_prefix}-psycopg2"
  filename            = data.archive_file.lambda_layer.output_path
  source_code_hash    = data.archive_file.lambda_layer.output_base64sha256
  compatible_runtimes = ["python3.11"]
}
