# Submissions AWS Shell

## Goals

The Submissions team needs a standard AWS EC2 image and set of local tools to support activities that cannot be done on either their local MacBooks and should not or cannot be done on any of the on-prem clusters.

As is typical, managing direct cost is a high priority that must be balanced against maintaining an efficient and please work environment.

This project defines these primary goals:

- Everything must be compatible with SSO.
- All custom imperative code should be either Python or Bash.
- Infrastructure should be defined in code.
- It should be easy to construct new machine images and VM definitions.
- Each user gets their own private EC2 instance.
- All user files that are not stored in S3 should be stored in a directory on the EC2 instance that is synchronized with a corresponding directory on the MacBook. The synchronization should be trivial for the user.
- If the EC2 instance is "idle" (no user connections and no jobs running), then it should automatically stop, hybernate, or even possibly terminate. A tmux session containing processes like bash, less, and vim, sholud not be sufficient for the EC2 instance to be considered non-idle.

## From Copilot

### Diagram

```text
+-----------------+         +----------------------------+         +-----------------------+
|  MacBook (CLI)  |  SSO    |   AWS IAM Identity Center  |  STS    |  AWS APIs (EC2, SSM)  |
|  aws sso login  +-------->+  (Permission Set + ABAC)   +-------->+  (authZ + auditing)   |
+--------+--------+         +--------------+-------------+         +-----+-----------------+
         |                                 ^                             |
         | aws ec2 run-instances           | evaluates tag-based         | SSM control plane
         | aws ssm start-session           | policies                    | connection
         v                                 |                             v
+--------+---------------------------------------------------------------+---------------+
|                                   VPC                                  |               |
|  Option 1 (simpler): Public subnet, no inbound rules; IMDSv2 required  |               |
|  Option 2 (hardened): Private subnet + VPC endpoints (SSM/EC2msg/      |               |
|   SSMmsg/S3) – no NAT, no public IP                                    |               |
|                                                                        |               |
|     +---------------------+                                            |               |
|     | EC2 “workstation”   | <-------------------------- SSM Agent -----+               |
|     | - Instance profile  |     (outbound only to SSM endpoints)                       |
|     |   with SSM perms    |                                                         +--+--+
|     | - Tag: Owner=<user> |                                                         |Logs |
|     | - No SSH open       |-------- Session logs (optional) ----------------------->|S3/  |
|     +---------------------+                                                         |CWL  |
+-------------------------------------------------------------------------------------+-----+
```

### Project Layout

```
infra/
  scripts/
    bootstrap-iam-for-ssm.sh
    create-workstation.sh
    start-session.sh
    stop-workstation.sh
  policies/
    permission-set-abac.json
    permission-set-abac-explicit-deny.json
```

## Questions

- Which infrastructure as code technology is the right fit?
- Implications of work from home with regard to configuring the security group for our VPC


