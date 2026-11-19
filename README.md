# Fedora Lane Automation Platform Demonstration

## Overview

This repository contains the Ansible automation assets developed for the Fedora Lane Automation Technology Decision Point (TDP).

The solution demonstrates how Red Hat Ansible Automation Platform (AAP) can help Fedora Lane address three critical business challenges:

1. Complex and brittle automation scripts
2. Decentralized automation and lack of governance
3. Slow, manual service delivery processes

---

## Customer Challenges

### Challenge 1 - Automation Silos

Fedora Lane currently relies on difficult-to-maintain shell scripts and playbooks that are understood and managed by only a small number of engineers.

### Challenge 2 - Security and Governance

Automation runs from individual laptops, credentials are distributed across teams, and there is limited auditability of automation execution.

### Challenge 3 - Slow Service Delivery

Developers depend on multiple teams and approvals before obtaining environments and access needed to become productive.

---

## Solution Overview

This repository provides standardized Ansible automation that:

- Centralizes automation execution through AAP
- Implements role-based access controls
- Enforces security best practices
- Demonstrates repeatable configuration management
- Supports workflow-driven service delivery

---

## Repository Structure

```text
Fedora-lane-repobase

├── playbooks
│   ├── configure_access.yml
│   ├── secure_ssh.yml
│   └── motd.yml
│
├── vars
│   └── users.yml
│
├── templates
│   └── motd.j2
│
├── files
│   ├── alexlee.pub
│   ├── rentanaka.pub
│   ├── caseynovak.pub
│   ├── syseng1.pub
│   ├── cameronshaw.pub
│   └── developer1.pub
│
├── README.md
└── solution-overview.md
```

---

## Components

### configure_access.yml

Creates:

- Fedora Lane user groups
- User accounts
- SSH authorized keys
- Sudo policies

Groups:

- fedoralane-administrators
- fedoralane-support
- fedoralane-developers

---

### secure_ssh.yml

Applies security controls:

- Disable root SSH login
- Disable password authentication
- Restart SSH service

---

### motd.yml

Deploys a standard Fedora Lane login banner using variables supplied from Ansible Automation Platform.

---

## Job Templates

### FL-Configure-Access

Configures Fedora Lane user and group access.

### FL-Harden-SSH

Applies security baseline.

### FL-Configure-MOTD

Configures server ownership and environment information.

---

## Workflow Template

### Fedora Lane Environment Configuration

```text
FL-Configure-Access
        ↓
FL-Harden-SSH
        ↓
FL-Configure-MOTD
```

---

## Security Controls Implemented

- SSH key authentication
- Root SSH login disabled
- Password authentication disabled
- Least privilege access model
- Centralized automation execution

---

## Future Enhancements

- AWS EC2 provisioning
- Azure VM provisioning
- Workflow approvals
- GitLab integration
- ServiceNow integration
- CIS hardening
- Compliance reporting

---

## Platform

- Red Hat Ansible Automation Platform
- Red Hat Enterprise Linux
- GitHub
- Amazon Web Services
