# Created from your public key, so the lab does not depend on a key pair that
# already exists in the account. The private .pem never leaves your machine.
resource "aws_key_pair" "lab" {
  key_name   = var.key_name
  public_key = file(pathexpand(var.public_key_path))
}