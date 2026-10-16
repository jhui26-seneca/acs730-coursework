# Task 6: the database password is created OUT OF BAND, once per environment,
# by scripts/create-ssm-parameters.sh (aws ssm put-parameter). Terraform only
# READS it. There is deliberately no aws_ssm_parameter resource anywhere:
# creating and reading the same name in one graph breaks on a fresh environment.
data "aws_ssm_parameter" "db_password" {
  name            = var.db_password_parameter_name
  with_decryption = true
}
