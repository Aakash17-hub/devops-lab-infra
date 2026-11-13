# Rebuild the lab from scratch

Runbook for building the whole v2 lab in an empty AWS account (or after `terraform destroy`) and restoring
GitLab and Jenkins from backups. Last run end to end on 13 Nov 2026: about two hours, including fixing the
four bugs listed in the main README.

Everything below runs from a Windows PC (PowerShell), the bastion (Ansible control node) or a server reached
through the bastion. Private IPs are fixed by Terraform, so the addresses below stay the same on every build.

| Host | Private IP |
|---|---|
| bastion | 10.0.1.163 (plus a public IP) |
| shopsphere-minikube | 10.0.1.237 |
| app-server | 10.0.2.37 |
| git-server | 10.0.2.116 |
| jenkins-server | 10.0.2.160 |

## 0. What you need

- AWS CLI with credentials, Terraform 1.7 or newer, Git, OpenSSH with `ssh-agent` running
- The SSH private key (`.pem`) and its public half: `ssh-keygen -y -f key.pem | Set-Content -Encoding ascii key.pub`
  (PowerShell's `>` writes UTF-16, which AWS rejects)
- Backups, kept **outside** any repository because they contain secrets:
  - GitLab: `<id>_gitlab_backup.tar` (`gitlab-backup create SKIP=artifacts,registry`), `gitlab-secrets.json`
  - Jenkins: `jenkins-home.tgz` (`/var/lib/jenkins` without `workspace`, `jobs/*/builds`, `plugins`, `war`, `caches`, `logs`) and `plugins.txt` (one plugin name per line)
- The Slack incoming-webhook URL (api.slack.com/apps → the app → Incoming Webhooks)

## 1. Infrastructure (Terraform)

```powershell
cd terraform-v2
Set-Content -Encoding ascii terraform.tfvars 'public_key_path = "C:/path/to/key.pub"'
terraform init
terraform plan -var enable_nat=true -out tfplan     # 25 to add on an empty account
terraform apply tfplan
$b = terraform output -raw bastion_public_ip
```

The AMI (latest Canonical Ubuntu 24.04), the availability zone and your public IP are looked up automatically.
`enable_nat=true` gives the private servers internet access for the installs; turn it off at the end (step 8).

If you rebuilt into the same IPs before, clear old host keys first:
`ssh-keygen -R 10.0.2.37; ssh-keygen -R 10.0.2.116; ssh-keygen -R 10.0.2.160; ssh-keygen -R 10.0.1.237`.

## 2. Configure the servers (Ansible, from the bastion)

```powershell
ssh-add C:\path\to\key.pem
ssh -A ubuntu@$b
```

```bash
sudo apt update && sudo apt install -y ansible-core
ansible-galaxy collection install ansible.posix
git clone https://github.com/Aakash17-hub/devops-lab-infra && cd devops-lab-infra/ansible
cp inventory.ini.example inventory.ini
sed -i 's/APP_PRIVATE_IP/10.0.2.37/; s/GIT_PRIVATE_IP/10.0.2.116/; s/JENKINS_PRIVATE_IP/10.0.2.160/' inventory.ini
ssh-keyscan 10.0.2.37 10.0.2.116 10.0.2.160 >> ~/.ssh/known_hosts 2>/dev/null
ansible -i inventory.ini all -m ping
ansible-playbook -i inventory.ini site.yml        # 15-20 min, GitLab is the slow part
ansible-playbook -i inventory.ini site.yml        # expect changed=0 on every host
```

## 3. Restore GitLab

From Windows:

```powershell
scp -J ubuntu@$b <id>_gitlab_backup.tar gitlab-secrets.json ubuntu@10.0.2.116:/tmp/
```

On git-server (`ssh 10.0.2.116` from the bastion). The backup must come from the same GitLab version, which the
role pins (19.4.1):

```bash
B=<id>        # file name without _gitlab_backup.tar
sudo mv /tmp/${B}_gitlab_backup.tar /var/opt/gitlab/backups/
sudo chown git:git /var/opt/gitlab/backups/${B}_gitlab_backup.tar && sudo chmod 600 /var/opt/gitlab/backups/${B}_gitlab_backup.tar
sudo install -o root -g root -m 600 /tmp/gitlab-secrets.json /etc/gitlab/gitlab-secrets.json && rm /tmp/gitlab-secrets.json
sudo gitlab-ctl reconfigure
sudo gitlab-ctl stop puma && sudo gitlab-ctl stop sidekiq
sudo GITLAB_ASSUME_YES=1 gitlab-backup restore BACKUP=$B
sudo gitlab-ctl reconfigure && sudo gitlab-ctl restart
```

Check after 2-3 minutes:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1/users/sign_in          # 200
sudo gitlab-rails runner 'puts "projects=#{Project.count} users=#{User.count}"'
sudo gitlab-rake gitlab:doctor:secrets                                           # 0 failures
```

The secrets file goes in before the restore; without it the encrypted columns (CI variables, tokens) cannot be read.

## 4. Restore Jenkins

From Windows:

```powershell
scp -J ubuntu@$b jenkins-home.tgz plugins.txt ubuntu@10.0.2.160:/tmp/
```

On jenkins-server (`ssh 10.0.2.160` from the bastion):

```bash
sudo systemctl stop jenkins
sudo tar xzf /tmp/jenkins-home.tgz -C /var/lib/jenkins

# Plugins: the official Plugin Installation Manager picks versions that work with the installed (pinned) WAR
URL=$(curl -s https://api.github.com/repos/jenkinsci/plugin-installation-manager-tool/releases/latest | grep -o 'https://[^"]*jenkins-plugin-manager-[0-9.]*\.jar' | head -1)
curl -sL -o /tmp/jpm.jar "$URL"
sudo java -jar /tmp/jpm.jar --war /usr/share/java/jenkins.war --plugin-download-directory /var/lib/jenkins/plugins --plugin-file /tmp/plugins.txt
sudo chown -R jenkins:jenkins /var/lib/jenkins
sudo systemctl start jenkins

# The restored known_hosts has the old servers' host keys
for ip in 10.0.2.37 10.0.1.237; do sudo -u jenkins ssh-keygen -R $ip -f /var/lib/jenkins/.ssh/known_hosts; done
sudo -u jenkins sh -c 'ssh-keyscan 10.0.2.37 10.0.1.237 >> /var/lib/jenkins/.ssh/known_hosts 2>/dev/null'
```

Open the UI through a tunnel on the port that matches Jenkins' configured URL (`http://localhost:8081/`).
A different port makes the CLI and some pages fail with "Unexpected request origin".

```powershell
ssh -J ubuntu@$b -L 8081:localhost:8080 ubuntu@10.0.2.160
```

Run `app-server-ssh-check` (expects `SSH_AND_DOCKER_OK`), then `test-devops-app-pipeline` with `ACTION=deploy`.

## 5. Register the GitLab runners

The old runners show as offline after the restore; their tokens were in the old servers' `config.toml`.
Delete them in GitLab and create new project runners (UI on `http://localhost:8082` via
`ssh -J ubuntu@$b -L 8082:localhost:80 ubuntu@10.0.2.116`):

| Project | Runner | Tag | Host |
|---|---|---|---|
| `test-devops-app` | `app-server-runner` | untagged | app-server |
| `shopsphere` | `minikube-runner` | `minikube` | Minikube host |

On the host (the token is read without echo and is not kept in shell history):

```bash
read -s -p "Runner token: " T; echo
sudo gitlab-runner register --non-interactive --url http://10.0.2.116 --token "$T" --executor shell --description <runner-name>
unset T; sudo gitlab-runner verify
```

## 6. ShopSphere on Minikube

On the bastion, run the ShopSphere playbook against the Minikube host. `deploy_public_key` is Jenkins'
`/var/lib/jenkins/.ssh/minikube_deploy.pub` (restored with the Jenkins home).

```bash
cd ~ && git clone https://github.com/Aakash17-hub/shopsphere && cd shopsphere/infra/ansible
ssh-keyscan 10.0.1.237 >> ~/.ssh/known_hosts 2>/dev/null
echo 'deploy_public_key: "<contents of minikube_deploy.pub>"' > vars.local.yml
ansible-playbook -i '10.0.1.237,' -u ubuntu site.yml -e @vars.local.yml -e minikube_start=true
```

On the Minikube host (`ssh 10.0.1.237`), bootstrap what the least-privilege CI identity is not allowed to create:

```bash
git clone https://github.com/Aakash17-hub/shopsphere && cd shopsphere
kubectl apply -f k8s/00-namespace.yaml -f k8s/01-rbac.yaml
kubectl apply -f bootstrap/ci-deployer.yaml -f bootstrap/jenkins-deployer.yaml
```

Back on the bastion, build the Jenkins kubeconfig:

```bash
ansible-playbook -i '10.0.1.237,' -u ubuntu site.yml -e @vars.local.yml -e build_deploy_kubeconfig=true --tags kubeconfig
```

On the Minikube host, build the GitLab Runner kubeconfig from the `ci-deployer` token (not in the playbook yet):

```bash
NS=shopsphere
TOKEN=$(kubectl -n $NS get secret ci-deployer-token -o jsonpath='{.data.token}' | base64 -d)
CA=$(kubectl -n $NS get secret ci-deployer-token -o jsonpath='{.data.ca\.crt}')
sudo mkdir -p /home/gitlab-runner/.kube
sudo tee /home/gitlab-runner/.kube/config >/dev/null <<EOF
apiVersion: v1
kind: Config
clusters:
- name: minikube
  cluster:
    server: https://192.168.49.2:8443
    certificate-authority-data: ${CA}
users:
- name: ci-deployer
  user:
    token: ${TOKEN}
contexts:
- name: ci
  context:
    cluster: minikube
    namespace: ${NS}
    user: ci-deployer
current-context: ci
EOF
unset TOKEN
sudo chown -R gitlab-runner:gitlab-runner /home/gitlab-runner/.kube && sudo chmod 600 /home/gitlab-runner/.kube/config
sudo -u gitlab-runner kubectl auth can-i create deployments -n $NS   # yes
sudo -u gitlab-runner kubectl auth can-i get secrets -n $NS          # no
```

Register `minikube-runner` (step 5), then run the `shopsphere` pipeline on `main` in GitLab. Expect 11 pods
`Running` in the `shopsphere` namespace. The Jenkins job `shopsphere-deploy` should also pass.

Monitoring (on the Minikube host, in `~/shopsphere`). The Slack secret must exist before Alertmanager starts:

```bash
kubectl create namespace monitoring
read -s -p "Slack webhook URL: " W; echo
kubectl -n monitoring create secret generic slack-webhook --from-literal=url="$W"; unset W
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack --version 92.17.0 -n monitoring -f monitoring/monitoring-values.yaml --wait --timeout 10m
helm install blackbox prometheus-community/prometheus-blackbox-exporter --version 11.20.2 -n monitoring -f monitoring/blackbox-values.yaml --wait
kubectl apply -f monitoring/alert-sink.yaml -f monitoring/shopsphere-alerts.yaml -f monitoring/shopsphere-probe.yaml
```

Test the alert path to Slack:

```bash
kubectl -n monitoring exec alertmanager-monitoring-kube-prometheus-alertmanager-0 -c alertmanager -- \
  amtool alert add RebuildTest severity=warning --annotation=summary="rebuild test" --alertmanager.url=http://localhost:9093
```

## 7. Checklist

- [ ] Second `ansible-playbook site.yml` run: `changed=0` on all four hosts
- [ ] GitLab: sign-in page 200, projects and users back, `gitlab:doctor:secrets` clean
- [ ] Jenkins: jobs listed, no plugin errors, `app-server-ssh-check` green
- [ ] `test-devops-app-pipeline` deploy: `/health` on app-server port 8080 shows the new build
- [ ] `shopsphere` pipeline and `shopsphere-deploy` green, 11 pods `Running`
- [ ] Test alert arrives in Slack

## 8. Finish

Turn the NAT gateway off (the servers keep running, without internet access):

```powershell
terraform plan -out tfplan        # enable_nat defaults to false: 3 to destroy
terraform apply tfplan
```

Tear everything down:

```powershell
terraform apply -var protect_instances=false        # turns termination protection off
terraform plan -destroy -var protect_instances=false -out tfplan
terraform apply tfplan
```

Take fresh GitLab and Jenkins backups first (section 0) if anything changed since the last ones.
