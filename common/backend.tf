# Common backend configuration goes here, this will be extended by values from backend.tfvars from
# environment (eg. stage or prod) specific directories

terraform {
  backend "s3" {
    region         = "eu-central-1"
    dynamodb_table = "tf-state-lock"
  }
}
