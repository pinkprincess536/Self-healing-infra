# DAY 4 — Alertmanager + Ansible Recovery

Date:

## Daily build goals
- [ ] Run Alertmanager.
- [ ] Connect Prometheus alerts to Alertmanager.
- [ ] Configure a webhook receiver.
- [ ] Create the recovery trigger.
- [ ] Write Ansible playbook to restart NGINX.
- [ ] Test recovery manually first.
- [ ] Verify service after recovery.

## Topics to refer to
- Alertmanager routing
- Receivers
- Webhooks
- Ansible inventory
- Playbooks
- Modules/tasks
- Idempotence

## Interview questions
- Why use Alertmanager?
- What is a webhook?
- How does Ansible know which machine to configure?
- Why is idempotence useful?
- How should automated recovery be limited?
- How do you verify recovery?

## Extra related topics — only if core work is stable
- Ansible handlers
- Vault/secret handling
- Retries/timeouts
- Alert grouping/inhibition

## Commands I actually learned / used
1.
2.
3.
4.
5.
6.
7.
8.
9.
10.
11.
12.
13.
14.
15.

## What I achieved today
_features, commands, experiments, screenshots, breakthroughs_



## What I learned / what broke / what I want to remember

Alertmanager's job: NOTIFY + MANAGE

Alertmanager receives:

🚨 NginxDown
severity = critical

Then it can decide what to do with it:

Send a Slack notification
Send an email
Send a PagerDuty alert
Group several alerts together
Avoid sending the exact same alert repeatedly
Temporarily silence an alert during maintenance
Route different alerts to different teams

A webhook receiver is simply a URL that waits to receive messages from another system.
