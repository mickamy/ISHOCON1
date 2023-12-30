terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "3.37.0"
    }
  }
}

provider "aws" {
  profile = "981618352324_PowerUserAccess"
  region  = "ap-northeast-1"
}
