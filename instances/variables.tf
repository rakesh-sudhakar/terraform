variable "region" {
  default            = "eu-west-1"
  description        = "AWS Region"
}

variable "remote_state_bucket" {
  description        = "Bucket name for layer 1 Remote state"
}

variable "remote_state_key" {
  description        = "Key name for layer 1 Remote state"
}

variable "ec2_instance_type" {
  description       = "EC2 Instance type to launch"
}

variable "key_pair_name" {
  default           = "Test-Key.pem"
  description       = "Key pair to use to connect to EC2"
}

variable "max_instance_size" {
  description       = "Max instances to launch in ASG"
}

variable "min_instance_size" {
  description       = "Min instance to launch in ASG"
}

