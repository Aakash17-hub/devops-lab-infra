# Terraform: the whole lab (`terraform-v2`)

Describes the lab as it runs today: one VPC with a public and a private subnet, an internet gateway,
two route tables, three security groups and five EC2 instances.

| Resource | What |
|---|---|
| `aws_vpc.lab`, `aws_subnet.public` / `private`, `aws_internet_gateway.lab` | `10.0.0.0/16`, a public `/24` and a private `/24` in one availability zone |
| `aws_route_table.public` / `private` + routes and associations | public route to the internet gateway; the private table has no route unless NAT is enabled |
| `aws_security_group.bastion` | SSH from one admin address (`admin_cidr`, not committed) |
| `aws_security_group.private` | SSH and HTTP from the bastion and the Minikube host, everything inside the group |
| `aws_security_group.shopsphere` | SSH from the bastion and from the Jenkins server's `/32` |
| `aws_instance.lab[...]` | bastion, Minikube host, Git server, app server, Jenkins server (fixed private IPs, IMDSv2 only, gp3 root volumes) |

## How it was built

The lab was built by hand first (for practice). Terraform then **adopted** it with `import` blocks instead of recreating it:
the first `terraform plan` showed 17 imports and 5 in-place changes, with no replacements. The only change was turning on
termination protection. After the apply, a second `plan` reported `No changes`. The `imports.tf` file holds the resource IDs
and is not committed.

## Safety choices

- `ignore_changes` on `ami`, `user_data` and `associate_public_ip_address`, so a newer AMI or a restart can never replace a server that holds state (GitLab, Jenkins, Minikube).
- `protect_instances` (default `true`) turns on EC2 termination protection. Set it to `false` and apply before a destroy.
- `enable_nat` (default `false`) creates a NAT gateway and a route for the private subnet. It costs money per hour, so it is off. With it off the private servers have no internet access.
- The admin IP, AMI ID and key pair name come from `terraform.tfvars`, which is not committed.

## Use

```bash
cp terraform.tfvars.example terraform.tfvars   # ami_id, key_name, admin_cidr
terraform init
terraform plan -out=tfplan                      # read it before applying
terraform apply tfplan
```

## Not managed yet

- The Jenkins server's IAM role and policies. The config only refers to the existing instance profile by name, so a fresh build needs the role to exist first.
- The default VPC, the VPC's default security group and main route table, and the key pair.
- What runs on the servers (GitLab, Jenkins, hardening). That is Ansible's job, and only the Minikube host has a playbook so far (see the ShopSphere repository).
- State is local, with no remote backend and no locking.

## Not verified

A from-scratch run (empty account or a second VPC, then destroy) has not been done. Everything above was tested by adopting
the existing lab and checking that the plan stays clean.
