# Build Log v2: GitLab + CI/CD on AWS

Date: 10 Oct 2026. Region: ap-southeast-1. Built manually in the AWS Console and over SSH.

Note: the app is called `hello-devops-app` in the README. The GitLab project was created as `test-devops-app`, which is the name visible in the screenshots.

## Phases completed

| Phase | What | Result |
|---|---|---|
| 1 | VPC, subnets, IGW, route tables, security groups, NAT gateway, 3 instances | All servers reachable via bastion; NAT verified with `curl -I https://google.com` from both private servers |
| 2 | Hardening on bastion, app-server, git-server | `sshd -T` shows `permitrootlogin no`, `passwordauthentication no`; fail2ban `sshd` jail active |
| 3 | GitLab CE on git-server, Node.js/Express app with Dockerfile | GitLab reachable through SSH tunnel; app pushed to GitLab over SSH |
| 4 | GitLab Runner (shell executor) on app-server, `.gitlab-ci.yml` | Push to `main` triggers build, redeploy and `/health` check; v1 to v2 verified live |

## Key commands

```bash
# Access a private server through the bastion (Windows PowerShell)
ssh -i .\New-Project-Key.pem -o ProxyCommand="ssh -i .\New-Project-Key.pem -W %h:%p ubuntu@<bastion-public-ip>" ubuntu@<private-ip>

# GitLab UI through a tunnel, then open http://localhost:8080
ssh -i .\New-Project-Key.pem -o ProxyCommand="..." -L 8080:localhost:80 ubuntu@<git-server-private-ip>

# SSH hardening drop-in
sudo mkdir -p /run/sshd
sudo tee /etc/ssh/sshd_config.d/10-hardening.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication no
EOF
sudo sshd -t && sudo systemctl restart ssh

# Runner registration
sudo gitlab-runner register --url http://<git-server-private-ip> --token <glrt-token> --executor shell --description app-server-runner
```

## Issues and resolutions

### 1. SSH `Permission denied (publickey)` on the bastion
- **Symptom:** connection made, key rejected, even after fixing file permissions with `icacls`.
- **Cause:** the `.pem` I was using belonged to a different key pair than the one attached to the instance (EC2 > Details > "Key pair assigned at launch").
- **Fix:** used the correct `.pem`. Lesson: check the key pair name on the instance first, then permissions.

### 2. `ssh -J` failed for private servers
- **Symptom:** `Permission denied` on the jump hop with `ssh -i key -J ubuntu@bastion ubuntu@private`.
- **Cause:** `-i` applies to the final host, not the jump host.
- **Fix:** `-o ProxyCommand="ssh -i key -W %h:%p ubuntu@bastion"`. An `~/.ssh/config` with `ProxyJump` and `IdentityFile` per host also works.

### 3. `sshd -t`: Missing privilege separation directory `/run/sshd`
- **Cause:** the directory is created when the SSH service starts; running the config test before that fails on Ubuntu 24.04.
- **Fix:** `sudo mkdir -p /run/sshd` before `sshd -t`.

### 4. `PermitRootLogin` still commented out
- **Cause:** `PasswordAuthentication no` was already set by `/etc/ssh/sshd_config.d/60-cloudimg-settings.conf`, but root login was only a commented default.
- **Fix:** added an explicit drop-in `10-hardening.conf` and verified with `sshd -T`.

### 5. Instance type for GitLab
- **Cause:** only a few types were selectable on the account (t3/t8i micro and small, c7i-flex.large, m7i-flex.large). GitLab needs about 4 GB RAM.
- **Fix:** c7i-flex.large (4 GB), 30 GB disk, plus a 2 GB swapfile as a safety net.

### 6. GitLab memory pressure
- **Symptom:** `free -h` showed 773 MB available and 1.1 GB swap used with no users.
- **Cause:** GitLab's bundled Prometheus, Alertmanager and exporters.
- **Fix:** in `/etc/gitlab/gitlab.rb`: `prometheus_monitoring['enable'] = false`, `puma['worker_processes'] = 0`, `sidekiq['concurrency'] = 5`, `gitlab_kas['enable'] = false`, `postgresql['shared_buffers'] = "128MB"`, then `gitlab-ctl reconfigure`.
- **Result:** available memory 1.6 GB, swap use 141 MB.

### 7. Browser timeout after creating the runner
- **Symptom:** `ERR_CONNECTION_TIMED_OUT` on `10.0.2.116/...`.
- **Cause:** GitLab was installed with `EXTERNAL_URL=http://10.0.2.116`, so redirects point to a private IP that the laptop cannot reach.
- **Fix:** replace the host with `localhost:8080` (the tunnel). Server-to-server traffic correctly keeps using the private IP.

### 8. `git push` rejected as non-fast-forward
- **Cause:** the initial commit was rewritten locally (`--amend --reset-author`), so local and remote histories diverged.
- **Fix:** `git pull --rebase origin main`, then `git push`.

### 9. Pipeline did not appear, then runner Docker permissions
- **Cause:** the push containing `.gitlab-ci.yml` had been rejected (issue 8), so GitLab never saw it. Separately, `gitlab-runner` was not in the `docker` group.
- **Fix:** `sudo usermod -aG docker gitlab-runner` and restart the runner; `sudo -u gitlab-runner docker ps` confirmed access.

### 10. Auto DevOps pipeline failed on the first commit
- **Cause:** with no `.gitlab-ci.yml` yet, GitLab ran its default Auto DevOps pipeline, which failed.
- **Fix:** disabled "Default to Auto DevOps pipeline" in Settings > CI/CD and deleted the failed pipeline.

## Verification

- `docker ps` shows the container recreated by the pipeline after each push.
- `curl http://localhost:3000` returned `Hello from DevOps Lab - v1`, then `v2` after a code change and push.
- `curl http://localhost:3000/health` returns `{"status":"ok"}`, and the pipeline's own `curl -f` check passes.

Screenshots: `docs/screenshots/v2/`.

## Cost control

NAT gateway and instances are billable. When a session ends: stop the instances, delete the NAT gateway and release its Elastic IP. VPC, subnets, route tables, IGW and security groups are free and stay in place.
