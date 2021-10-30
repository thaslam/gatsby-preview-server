
variable "environment" {
  description = "Name of environment"
  type        = string
  default     = "dev"
}
variable "app_name" {
  description = "Name of application"
  type        = string
  default     = "gatsby_preview_server"
}
variable "lambda_path_helloword" {
  description = "Path to Lambda file(s) for helloworld"
  type        = string
  default     = "../../server/dist/helloworld_function"
}
variable "lambda_path_preview" {
  description = "Path to Lambda file(s) for preview function"
  type        = string
  default     = "../../server/dist/preview_function"
}