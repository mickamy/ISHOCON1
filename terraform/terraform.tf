terraform {
  backend "s3" {
    region  = "ap-northeast-1"
    bucket  = "ishocon-mickamy"
    key     = "default.tfstate"
    encrypt = true
  }
}
