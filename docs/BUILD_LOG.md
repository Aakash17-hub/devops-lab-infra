# Build Log — Phases 1 through 4

A full record of what was built, what went wrong, and how each issue was
resolved, across the network setup, hardening, service deployment, and
CI/CD stages of this AWS lab. Built manually through the AWS Console,
specifically for hands-on AWS SAA exam practice.

---

## Phase 1: Network Foundation

### What was built

| Component | Detail |
|---|---|
| VPC | `devops-lab-vpc`, CIDR `10.0.0.0/16` |
| Public subnet | `public-subnet`, `10.0.1.0/24`, AZ ap-south-1a |
| Private subnet | `private-subnet`, `10.0.2.0/24`, AZ ap-south-1a |
| Internet Gateway | Attached to the VPC, routed from `public-rt` |
| NAT Gateway | `devops-NATGW`, Zonal mode, sitting in `public-subnet` |
| Route tables | `public-rt` (0.0.0.0/0 → IGW), `private-rt` (0.0.0.0/0 → NAT) |
| Security groups | `bastion-sg` (SSH from admin IP only), `private-sg` (SSH from `bastion-sg`, plus app-specific rules added in later phases) |
| EC2 instances | `bastion` (public), `app-server` (private), `git-server` (private) — Ubuntu 22.04/26.04, t3.micro |
| Cost safety net | AWS Budget set to $20/month, alerts at 50/80/100% |

### Problems faced and resolutions

**1. NAT Gateway "Regional" mode risked multiplying cost**
AWS's newer "Regional - new" availability mode for NAT gateways auto-scales
across every AZ in the region, which could have silently created multiple
NAT gateways and multiplied the hourly charge for a single-AZ lab.
**Fix:** switched to **Zonal** mode, explicitly tied to `public-subnet`.

**2. Windows: `ssh` not recognized**
`Get-WindowsCapability` showed `OpenSSH.Client` was already `Installed`,
but its folder was missing from `PATH`.
**Fix:** added `C:\Windows\System32\OpenSSH\` to the system `PATH` via
`[Environment]::SetEnvironmentVariable(...)` in an elevated PowerShell
session, then opened a fresh terminal.

**3. "Identity file not accessible" on first SSH attempt**
The terminal wasn't in the folder where the `.pem` key was downloaded.
**Fix:** `cd` into the correct folder, or use the full path to the key.

**4. "Permission denied (publickey)" despite a valid key**
After copying the `.pem` onto the bastion, SSH refused it:
`Permissions 0664 for 'devops-project-key.pem' are too open`.
**Fix:** `chmod 400 devops-project-key.pem`.

### Verification
SSH chain confirmed working: local machine → bastion (public IP) → both
private servers (via `bastion-sg` security-group reference rule).

---

## Phase 2: Server Hardening

Applied manually to both `app-server` and `git-server`, mirroring the
hardening checklist used in production at work.

### What was built
- Role-named admin group (`labadmins`), `ubuntu` user added to it and `sudo`
- `PermitRootLogin no` and `PasswordAuthentication no` enforced
- `fail2ban` with an `sshd` jail (`maxretry=5`, `bantime=1800s`, `findtime=600s`)

### Problems faced and resolutions

**1. `usermod` command split across two lines during paste**
`sudo usermod -aG labadmins,sudo ubuntu` got split, causing `ubuntu` to run
as its own (invalid) command.
**Fix:** re-ran as a single line — group list and username must be together.

**2. Hardening directives had no effect at first**
`PermitRootLogin no` / `PasswordAuthentication no` were present in
`sshd_config` but commented out with `#`, so Ubuntu's compiled-in defaults
were actually in effect.
**Fix:** uncommented both lines, verified with `grep` before restarting `sshd`.

**3. SSH restart discipline**
Every `sshd` restart was followed by testing a brand-new connection in a
separate window before closing the original session — never restarting and
immediately closing the only open connection.

**4. `fail2ban` failed to start — corrupted config file**
`jail.local` was created by pasting a multi-line block into `nano`, but the
markdown code-fence markers (`` ``` ``) and all lines merged into one,
which `fail2ban` rejected with `File contains no section headers`.
**Fix:** rewrote the file safely with a single-line `printf` command:
```
sudo bash -c 'printf "[sshd]\nenabled = true\nport = ssh\nmaxretry = 5\nbantime = 1800\nfindtime = 600\n" > /etc/fail2ban/jail.local'
```

**5. Hardening steps skipped on the second server**
When repeating the process on `git-server`, the group/SSH-config steps were
initially skipped — only `fail2ban` got set up.
**Fix:** caught by reviewing terminal output against the full checklist,
then completed the missing steps. This repetition-induced gap is exactly
the kind of thing config-management tooling (Ansible) exists to prevent.

### Verification
Both servers: key-based login works, root login refused, `fail2ban-client
status sshd` shows the jail active with 0 currently banned.

---

## Phase 3: Deploying Real Services

### What was built
- **Docker** installed on both `app-server` and `git-server`
- **app-server**: a self-authored Node.js/Express app (`hello-devops-app`)
  with a hand-written `Dockerfile`, replacing an initial Nginx smoke test
- **git-server**: **Gitea** (self-hosted Git), running via Docker with a
  SQLite backend, set up through its web installation wizard
- Decision made to **not** deploy Plane (self-hosted project-management
  tool) — its multi-container stack needs ~2GB+ RAM, more than a `t3.micro`
  comfortably provides. Documented as an intentional scoping decision
  rather than deployed and risking a flaky demo.

### Problems faced and resolutions

**1. Private-subnet services are unreachable from a browser by design**
`app-server` and `git-server` have no public IP — visiting their IP
directly from a Windows browser does nothing, because there's no route in.
**Fix:** used SSH local port forwarding through the bastion:
```
ssh -i devops-project-key.pem -L 8080:10.0.2.185:80 ubuntu@<bastion_public_ip>
```
then browsed to `http://localhost:8080`. This is the same principle as a
VPN split-tunnel at work — the bastion is the only relay point.

**2. Security group gaps caused silent hangs, not errors**
The first Nginx test and the first `hello-devops-app` container both
"hung" when tunneled to — no error, just an indefinite load. Root cause
both times: `private-sg` only allowed **SSH (22)** from `bastion-sg`, not
the actual application port (80, then 3000). AWS drops disallowed traffic
silently rather than returning a clean "connection refused."
**Fix:** added explicit inbound rules on `private-sg` for each new port,
sourced from `bastion-sg`, before testing.

**3. PowerShell's `curl` alias caused confusion mid-debug**
`curl` in PowerShell is aliased to `Invoke-WebRequest`, which behaves
differently from real curl and produced a security prompt about script
execution. Also, running `curl` from *inside* the bastion's own SSH session
tested the wrong machine's `localhost` (the point of an SSH tunnel is that
`localhost:<port>` refers to *your Windows machine*, not the remote server).
**Fix:** ran test commands from a genuinely separate, non-SSH PowerShell
window on Windows — the actual endpoint of the tunnel.

**4. Gitea's install page appeared to hang on "Installing now, please wait..."**
The page's JS polling was checking the wrong port after the tunnel's local
port didn't match Gitea's configured `ROOT_URL`.
**Fix:** confirmed via `docker logs gitea` that installation had actually
completed successfully, then manually refreshed the browser tab (bypassing
the stuck client-side poll) to reach the real login page.

### Verification
- `hello-devops-app` reachable via tunnel, both `/` and `/health` routes
  confirmed working in-browser
- Gitea installation completed, confirmed via logs and a working login/dashboard

---

## Phase 4: CI/CD with Gitea Actions

### What was built
- Pushed `hello-devops-app`'s existing code into a new Gitea repository
  from `app-server`
- Enabled Gitea Actions (site-wide, already on by default in this version)
- Registered a self-hosted **act_runner** as a Docker container on
  `app-server`, with access to the host's Docker socket so it can build
  and run containers as part of a pipeline
- Wrote `.gitea/workflows/deploy.yml`: on every push to `main`, checks out
  the code, rebuilds the Docker image, stops/removes the old container, and
  starts a fresh one
- **Verified live**: edited `app.js`, pushed, watched the pipeline run in
  Gitea's Actions tab, and confirmed the updated text appeared on the
  running app — with zero manual `docker` commands after initial setup

### Problems faced and resolutions

**1. Cross-server traffic (app-server → git-server) was blocked**
Pushing code from `app-server` to Gitea on `git-server` hung silently —
same pattern as Phase 3's port issue, but this time it was
private-subnet-to-private-subnet traffic, which `private-sg` didn't allow
at all (it only had rules sourced from `bastion-sg`).
**Fix:** added a **self-referencing** rule on `private-sg` — source =
`private-sg` itself, port 3000 — so any instance in that security group
can reach any other instance in the same group. This is a distinct pattern
from the earlier bastion-sourced rules and a good SAA-relevant distinction.

**2. Wrong Gitea username in the remote URL**
`git remote add` used a transposed username (`Aakash7571` instead of the
actual `Aakash7517`), producing a `remote: Not found` error that looked
like a missing-repository problem rather than a typo.
**Fix:** cross-checked the exact username shown in the Gitea web UI against
the command, corrected with `git remote set-url`.

**3. Branch name mismatch**
Local repo initialized as `master` (git's older default); Gitea's own
Quick Guide showed `main`. Not an error, but worth reconciling to avoid
later confusion.
**Fix:** `git branch -m master main` before the first push.

**4. Registration token got corrupted during copy/paste**
Manually re-typing the long Gitea runner registration token produced a
mangled string (`WVnKZ5rWan555rJQn1eWVnKZ5rWan555rJQn1esIi7...`), and long
multi-flag `docker run` commands containing the token failed with
`instance address is empty` — a symptom of shell argument parsing breaking
on the malformed input.
**Fix:** used Gitea's copy-icon (not manual retyping) to get an exact
token, stored it in a shell variable (`TOKEN=...`) and verified with
`echo $TOKEN` before using it in any command — catching corruption before
it caused a confusing downstream error.

**5. Stray containers from failed registration attempts**
Several earlier failed `docker run --rm ... register` attempts, killed via
Ctrl+C, left multiple `act_runner` containers running simultaneously.
**Fix:** `docker ps` to identify them, `docker stop`/`docker rm` to clean
up, keeping only the one successfully running as a persistent daemon.

**6. `sed` silently matched nothing**
A find-and-replace on `app.js` to change the heading text produced "nothing
to commit" — the pattern didn't match because the actual file had an
escaped apostrophe (`Aakash\'s`) that the search string didn't account for.
Also hit bash's history-expansion (`!`) treating `!` as a special character
inside double quotes, breaking an early attempt entirely.
**Fix:** re-verified the exact file content with `cat` first, then wrote a
`sed` pattern matching an unambiguous, character-safe part of the line
(`DevOps Lab</h1>`) instead of guessing at quoting.

### Verification
Full loop confirmed live: code change → `git push` → Gitea Actions run
(visible, green, ~1 minute) → old container replaced → `curl localhost:3000`
shows the new text, with the container's "Created" timestamp matching the
pipeline's run time.

---

## Key takeaways across all four phases

- **Silent hangs almost always meant a security group gap**, not a broken
  service — AWS drops disallowed traffic without an error, so "it's just
  loading forever" is a strong signal to check security group rules before
  anything else.
- **Copy-pasting multi-line content into `nano` is a recurring failure
  point** — markdown formatting artifacts and paste-splitting both caused
  real outages. Single-line `printf`/heredoc commands, or pasting into
  `nano` followed by a `cat`/`grep` verification, are more reliable.
- **Verify tokens and long strings before using them**, not after a
  confusing downstream error. `echo $VAR` is cheap; debugging a garbled
  argument list inside a long command is not.
- **A written checklist matters more on the second and third repetition**
  than the first — the Phase 2 gap on `git-server` happened precisely
  because the steps felt "already known." This is the practical argument
  for moving repeated manual steps into Ansible/CI automation, which this
  project does in its later phases.
- **Dynamic home IPs break "my IP" security group rules silently** —
  after a power outage, a changed ISP-assigned IP caused SSH to time out
  with no useful error, resolved by re-selecting "My IP" in the console to
  refresh the allowed source.
