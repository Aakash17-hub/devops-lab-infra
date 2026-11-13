# Terraform: the whole lab (`terraform-v2`)

Describes the whole v2 lab: one VPC with a public and a private subnet, an internet gateway, two route tables,
three security groups, five EC2 instances, the Jenkins server's IAM role and the key pair. It builds the lab in
an empty account and was used to rebuild it from scratch on 13 Nov 2026 (see [`../REBUILD.md`](../REBUILD.md)).

| Resource | What |
|---|---|
| `aws_vpc.lab`, `aws_subnet.public` / `private`, `aws_internet_gateway.lab` | `10.0.0.0/16`, a public `/24` and a private `/24` in one availability zone |
| `aws_route_table.public` / `private` + routes and associations | public route to the internet gateway; the private table has no route unless NAT is enabled |
| `aws_security_group.bastion` | SSH from one admin address only |
| `aws_security_group.private` | SSH and HTTP from the bastion and the Minikube host, everything inside the group |
| `aws_security_group.shopsphere` | SSH from the bastion and from the Jenkins server's `/32` |
| `aws_instance.lab[...]` | bastion, Minikube host, Git server, app server, Jenkins server (fixed private IPs, IMDSv2 only, gp3 root volumes) |
| `aws_iam_role.jenkins` + policies + `aws_iam_instance_profile.jenkins` | `AmazonEC2ContainerRegistryPowerUser` and an inline `eks:DescribeCluster` / `eks:ListClusters` policy for the Jenkins server |
| `aws_key_pair.lab` | created from your public key (`public_key_path`), so nothing has to exist in the account beforehand |
| `aws_eip.nat`, `aws_nat_gateway.lab`, `aws_route.private_nat` | only with `enable_nat = true` |

## Portable to any account and region

| Input | Default |
|---|---|
| `ami_id` | latest Canonical Ubuntu 24.04 (`data.aws_ami.ubuntu`) |
| `az` | the region's first availability zone |
| `admin_cidr` | your current public IP, read from `checkip.amazonaws.com` on every plan, so a dynamic IP is picked up again by the next apply instead of being edited by hand |
| `key_name` | `devops-lab-key` |
| `public_key_path` | none: set it in `terraform.tfvars` (not committed) |
| `region` | `ap-southeast-1` |

## How it got here

1. The lab was first built by hand in the console (for practice). Terraform **adopted** it with `import` blocks
   instead of recreating it: 17 imports and 5 in-place changes (termination protection only), then a clean plan.
   The Jenkins IAM role was adopted the same way later (4 imports).
2. The fixed inputs (AMI ID, existing key pair name, admin IP) were replaced with the lookups above.
3. The lab was backed up, destroyed (21 resources) and rebuilt from this code: 25 resources created with
   `enable_nat = true`, then configured by `../ansible/`.

## Safety choices

- `ignore_changes` on `ami`, `user_data` and `associate_public_ip_address`, so a newer AMI or a restart can never replace a server that holds state (GitLab, Jenkins, Minikube).
- `protect_instances` (default `true`) turns on EC2 termination protection. Set it to `false` and apply before a destroy.
- `enable_nat` (default `false`) creates a NAT gateway and a route for the private subnet. It costs money per hour, so it is on only while packages are installed.

## Use

```powershell
Set-Content -Encoding ascii terraform.tfvars 'public_key_path = "C:/path/to/key.pub"'
terraform init
terraform plan -var enable_nat=true -out tfplan     # read it before applying
terraform apply tfplan
```

Afterwards run `terraform plan -out tfplan` / `terraform apply tfplan` without the variable to remove the NAT gateway.

Destroy:

```powershell
terraform apply -var protect_instances=false
terraform plan -destroy -var protect_instances=false -out tfplan
terraform apply tfplan
```

## Not managed

- The default VPC, the VPC's default security group and main route table.
- What runs on the servers: that is [`../ansible/`](../ansible/) (and the ShopSphere repository for the Minikube host).
- State is local, with no remote backend and no locking.
