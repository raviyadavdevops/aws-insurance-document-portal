data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

locals {
  user_data = <<-EOF
    #!/bin/bash
    set -e
    dnf install -y python3.12 python3.12-pip unzip

    # Fetch and unpack the current application code (app.py, templates/, static/,
    # requirements.txt) from S3. Runs on every boot, so new/replacement ASG instances
    # always pick up the latest deployed artifact — no CodeDeploy needed.
    mkdir -p /opt/app
    aws s3 cp "s3://${aws_s3_bucket.documents.bucket}/app-artifacts/app_package.zip" /opt/app_package.zip --region ${var.aws_region}
    unzip -o /opt/app_package.zip -d /opt/app
    python3.12 -m pip install -r /opt/app/requirements.txt

    cat > /etc/systemd/system/flask-app.service <<'UNIT'
    [Unit]
    Description=Flask insurance document upload portal
    After=network.target

    [Service]
    WorkingDirectory=/opt/app
    Environment=DOCUMENT_BUCKET_NAME=${aws_s3_bucket.documents.bucket}
    Environment=AWS_DEFAULT_REGION=${var.aws_region}
    ExecStart=/usr/bin/python3.12 -m gunicorn -b 0.0.0.0:8000 app:app
    Restart=always

    [Install]
    WantedBy=multi-user.target
    UNIT
    systemctl daemon-reload
    systemctl enable flask-app.service
    # Started only now, after app files (unzip) and Python dependencies (pip install)
    # above have completed successfully — `set -e` aborts the script before this line
    # if either step fails, so the service never starts against a half-deployed app.
    systemctl start flask-app.service

    # Ship application logs to CloudWatch (NFR-005 — operator-visible failure detail).
    dnf install -y amazon-cloudwatch-agent
    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWAGENT'
    {
      "logs": {
        "logs_collected": {
          "files": {
            "collect_list": [
              {
                "file_path": "/var/log/messages",
                "log_group_name": "/${local.name_prefix}/app",
                "log_stream_name": "{instance_id}"
              }
            ]
          }
        }
      }
    }
    CWAGENT
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config -m ec2 -s \
      -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
  EOF
}

resource "aws_launch_template" "app" {
  name_prefix   = "${local.name_prefix}-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  vpc_security_group_ids = [aws_security_group.ec2.id]
  user_data               = base64encode(local.user_data)

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.common_tags, { Name = "${local.name_prefix}-app" })
  }
}

resource "aws_autoscaling_group" "app" {
  name                = "${local.name_prefix}-asg"
  vpc_zone_identifier = aws_subnet.private_app[*].id
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  desired_capacity    = var.asg_desired_capacity

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.app.arn]

  health_check_type         = "ELB"
  health_check_grace_period = 120

  depends_on = [aws_s3_object.app_package]

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-app"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "${local.name_prefix}-cpu-scaling"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60.0
  }
}
