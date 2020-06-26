provider "aws" {
  region = var.region
}

terraform {
  backend "s3" {}
}

##To read the S3 bucket that stores the TF remote state##
data "terraform_remote_state" "network_config" {
  backend = "s3"
  config = {
    bucket        = var.remote_state_bucket
    key           = var.remote_state_key
    region        = var.region
  }
}

resource "aws_security_group" "ec2_public_sg" {
  name           = "Public-SG"
  description    = "Internet access SG"
  vpc_id         = "data.terraform_remote_state.network_config.id"

  ingress {
    from_port     = 80
    protocol      = "TCP"
    to_port       = 80
    cidr_blocks   = ["0.0.0.0/0"]
  }
  ingress {
    from_port     = 22
    protocol      = "TCP"
    to_port       = 22
    cidr_blocks   = ["IP here"]       #My IP
  }
  egress {
    from_port     = 0
    protocol      = "-1"         ##Allow All = -1##
    to_port       = 0
    cidr_blocks   = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ec2_private_sg" {
  name            = "Private-SG"
  description     = "Only allow Public SG resources to access this"
  vpc_id          = "data.terraform_remote_state.network_config.id"

ingress {
  from_port           = 0
  protocol            = "-1"
  to_port             = 0
  security_groups     = [aws_security_group.ec2_public_sg.id]
}
  ingress {
    from_port     = 80
    protocol      = "TCP"
    to_port       = 80
    cidr_blocks   = ["0.0.0.0/0"]
    description   = "Health Checking for this SG"
  }

  egress {
    from_port     = 0
    protocol      = "-1"
    to_port       = 0
    cidr_blocks   = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "elb_sg" {
name              = "ELB-SG"
description       = "ELB SG"
vpc_id            = "data.terraform_remote_state.network_config.id"

  ingress {
    from_port     = 0
    protocol      = "-1"
    to_port       = 0
    cidr_blocks   = ["0.0.0.0/0"]
    description   = "Allow web traffic to LB"
  }
  egress {
    from_port     = 0
    protocol      = "-1"
    to_port       = 0
    cidr_blocks   = ["0.0.0.0/0"]
  }




##Inline resource- JSON IAM policy
}
resource "aws_iam_role" "ec2_iam_role" {
  name                = "EC2-IAM-Role"
  assume_role_policy  = <<EOF
{
"Version"             : "2012-10-17",
"Statement"           :
  [
      {
      "Effect"        :  "Allow",
      "Principal"     : {
        "Service"     : ["ec2.amazonaws.com" , "application-autoscaling.amazonaws.com"]
       },
      "Action"        : "sts.AssumeRole"
      }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ec2_iam_role_policy" {
  name                 = "EC2-IAM-Policy"
  role                 = aws_iam_role.ec2_iam_role.id
  policy               =  <<EOF
{
"Version"              : "2012-10-17",
"Statement"            : [
    {
    "Effect"           : "Allow",
      "Action"           : [
      "ec2:*",
      "elasticloadbalancing:*",
      "cloudwatch:*",
      "logs:*"
      ],
      "Resource" : "*"
    }
 ]
}
EOF
}
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name       = "EC2-IAM-Instance-Profile"
  role       =  aws_iam_role.ec2_iam_role.name
}

data "aws_ami" "launch_config_ami" {
  most_recent     = true
  owners          = ["amazon"]
}

resource "aws_launch_configuration" "ec2_private_launch_config" {
  image_id                    = "ami-0e34e7b9ca0ace12d"            ##Linux AMI- Change for Windows##
  instance_type               = var.ec2_instance_type
  key_name                    = var.key_pair_name
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ec2_instance_profile.name
  security_groups             = [aws_security_group.ec2_private_sg.id]
  user_data = <<EOF
  #!/bin/bash
  yum update -y
  yum install httpd -y
  service httpd start
  chkconfig httpd on
  export INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
  echo "<html> <body> <h1> Hello from Test backend at instance <b>"$INSTANCE_ID"</b></h1></body></html>" > /var/www/html/index.html
  EOF
}

resource "aws_launch_configuration" "ec2_public_launch_config" {
  image_id                    = "ami-0e34e7b9ca0ace12d"            ##Linux AMI- Change for Windows##
  instance_type               = var.ec2_instance_type
  key_name                    = var.key_pair_name
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_instance_profile.name
  security_groups             = [aws_security_group.ec2_public_sg.id]
  user_data = <<EOF
  #!/bin/bash
  yum update -y
  yum install httpd -y
  service httpd start
  chkconfig httpd on
  export INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
  echo "<html> <body> <h1> Hello from Test Web App at instance <b>"$INSTANCE_ID"</b></h1></body></html>" > /var/www/html/index.html
  EOF
}
resource "aws_elb" "web_app_load_balancer" {
  name                  = "Test-WebApp-LoadBalancer"
  internal              = false
  security_groups       = [
    aws_security_group.elb_sg.id]
  subnets               = [
    "data.terraform_remote_state.network_config.public_subnet_1_id",
    "data.terraform_remote_state.network_config.public_subnet_2_id",
    "data.terraform_remote_state.network_config.public_subnet_3_id"
  ]
  listener {
    instance_port       = 80
    instance_protocol   = "HTTP"
    lb_port             = 80
    lb_protocol         = "HTTP"
  }
health_check {
  healthy_threshold     = 5
  interval              = 30
  target                = "HTTP:80/index.html"
  timeout               = 10
  unhealthy_threshold   = 5
}
}
resource "aws_elb" "backend_load_balancer" {
  name                  = "Test-Backend-LB"
  internal              = true
  security_groups       = [aws_security_group.elb_sg.id]
  subnets               = [
  "data.terraform_remote_state.network_config.private_subnet_1_id",
    "data.terraform_remote_state.network_config.private_subnet_2_id",
    "data.terraform_remote_state.network_config.private_subnet_3_id"
  ]
  listener {
    instance_port       = 80
    instance_protocol   = "HTTP"
    lb_port             = 80
    lb_protocol         = "HTTP"
  }
health_check {
  healthy_threshold     = 5
  interval              = 30
  target                = "HTTP:80/index.html"
  timeout               = 10
  unhealthy_threshold   = 5
}
}

##Creating ASG for Private EC2##
resource "aws_autoscaling_group" "ec2_private_asg" {
  name                  = "Test-Backend-ASG"
  vpc_zone_identifier   = [
    "data.terraform_remote_state.network_config.private_subnet_1_id",
    "data.terraform_remote_state.network_config.private_subnet_2_id",
    "data.terraform_remote_state.network_config.private_subnet_3_id"
  ]
  max_size              = var.max_instance_size
  min_size              = var.min_instance_size
  launch_configuration  = aws_launch_configuration.ec2_private_launch_config.name
  health_check_type     = "ELB"
  load_balancers        = [aws_elb.backend_load_balancer.name]

  tag {
    key                 = "Name"
    propagate_at_launch = false
    value               = "Backend-EC2-Instance"
  }
  tag {
    key                 = "Type"
    propagate_at_launch = false
    value               = "Test"
  }
}

##Creating ASG for Public EC2##

resource "aws_autoscaling_group" "ec2_public_asg" {
  name                  = "Test-WebApp-ASG"
  vpc_zone_identifier   = [
    "data.terraform_remote_state.network_config.public_subnet_1_id",
    "data.terraform_remote_state.network_config.public_subnet_2_id",
    "data.terraform_remote_state.network_config.public_subnet_3_id"
  ]
  max_size              = var.max_instance_size
  min_size              = var.min_instance_size
  launch_configuration  = aws_launch_configuration.ec2_public_launch_config.name
  health_check_type     = "ELB"
  load_balancers        = [aws_elb.web_app_load_balancer.name]

  tag {
    key                 = "Name"
    propagate_at_launch = false
    value               = "WebApp-EC2-Instance"
  }
  tag {
    key                 = "Name"
    propagate_at_launch = false
    value               = "WebApp"
  }
}

##Auto Scaling Policy for Public EC2##

resource "aws_autoscaling_policy" "public_test_scaling_policy" {
  autoscaling_group_name      = aws_autoscaling_group.ec2_public_asg.name
  name                        = "Test-WebApp-Autoscaling-Policy"
  policy_type                 = "TargetTrackingScaling"
  min_adjustment_magnitude    = 1

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type  = "ASGAverageCPUUtilization"

    }
    target_value              =  80.0
  }
}
resource "aws_autoscaling_policy" "backend_test_scaling_policy" {
  autoscaling_group_name      = aws_autoscaling_group.ec2_private_asg.name
  name                        = "Production-Backend-AutoScaling-Policy"
  policy_type                 = "TargetTrackingScaling"
  min_adjustment_magnitude    = 1

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type  = "ASGAverageCPUUtilization"

    }
    target_value              =  80.0
  }
}

##Create SNS Topic##

resource "aws_sns_topic" "webapp_test_autoscaling_alert_topic" {
  display_name                = "WebApp-AutoScaling-Topic"
  name                        = "WebApp-AutoScaling-Topic"
}
resource "aws_sns_topic_subscription" "webapp_test_autoscaling_sns_subscription" {
  endpoint                    = "+919353283220"
  protocol                    = "sms"
  topic_arn                   = aws_sns_topic.webapp_test_autoscaling_alert_topic.arn
}

##AS Notification for SNS##

resource "aws_autoscaling_notification" "webapp_autoscaling_notification" {
  group_names                 = [aws_autoscaling_group.ec2_public_asg.name]
  notifications               = [
  "autoscaling:EC2_INSTANCE_LAUNCH",
  "autoscaling:EC2_INSTANCE_TERMINATE",
  "autoscaling:EC2_INSTANCE_LAUNCH_ERROR"
  ]
  topic_arn                   = aws_sns_topic.webapp_test_autoscaling_alert_topic.arn
}
