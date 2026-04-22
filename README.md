# Infrastructure Monitoring Platform

## Project Summary

Custom-built enterprise monitoring platform designed to centralize infrastructure visibility, automate health checks, and improve proactive issue detection across distributed environments.

This project combines PowerShell collectors, SQL Server storage, scheduled automation, and reporting workflows into a single monitoring solution covering infrastructure, identity, security, Microsoft 365, certificates, and backup validation.

## Why This Project Matters

This repository is presented as a standalone showcase project for infrastructure, systems, and automation roles.

It demonstrates:

- end-to-end monitoring design
- practical PowerShell automation at enterprise scale
- SQL-backed analytics and reporting structure
- cross-domain monitoring across AD, DNS, servers, Microsoft 365, and backups
- business-focused operational engineering

## Key Highlights

- built a modular PowerShell-based monitoring platform
- centralized infrastructure telemetry into SQL Server
- designed fact and dimension style storage for analytics-ready reporting
- automated recurring checks through Task Scheduler
- covered both operational and security monitoring scenarios
- created a scalable foundation for future collectors and dashboard expansion

## Monitoring Scope

### Active Directory

- user and group changes
- insecure LDAP authentication events
- AD and LDAPS certificate expiration
- Group Policy change tracking

### DNS

- DNS zone changes
- DNS record changes

### Server Health

- reboot tracking
- firewall status
- installed software inventory

### Microsoft 365

- inactive users
- license cost analytics by department

### Backup Validation

- cloud storage backup checks

### Web and TLS

- web server certificate validation

## Architecture

```text
PowerShell Collectors
        ↓
SQL Server Monitoring Database
        ↓
Dashboard / Reporting Layer
```

## Core Design

The platform is built around a modular collector model:

- PowerShell scripts collect infrastructure and service data
- data is written into a centralized SQL Server database
- fact and dimension tables provide analytics-ready structure
- Task Scheduler jobs ensure automated and continuous execution
- reporting and dashboard layers enable historical analysis and visibility

## Technology Stack

- PowerShell
- SQL Server
- Windows Server
- Active Directory
- Microsoft Graph API
- Task Scheduler
- Cloud storage REST APIs
- .NET / web dashboard layer

## Capabilities

- centralized infrastructure visibility
- proactive issue detection
- historical analytics
- security event monitoring
- license and cost reporting
- backup validation
- automation-first operations

## Example Operational Scenarios

- detect expiring AD and LDAPS certificates before service impact
- identify insecure LDAP usage in domain environments
- track DNS changes for audit and troubleshooting
- monitor server reboot causes and patterns
- analyze Microsoft 365 license allocation and cost by department
- validate SQL backup presence in cloud storage buckets

## Business Value

- reduced manual monitoring effort
- improved incident response time
- better operational visibility
- stronger security and compliance awareness
- scalable foundation for future monitoring expansion

## My Role

Designed and implemented the monitoring architecture, PowerShell collector approach, SQL-backed data model, and automation workflows for centralized infrastructure monitoring and analytics.

## Repository Structure

```text
/PowerShell
/SQL
/Docs
README.md
```

### PowerShell Layout

- `PowerShell/active-directory` for AD change tracking, certificate checks, LDAP event collection, and Group Policy monitoring
- `PowerShell/dns` for DNS change collection
- `PowerShell/server-health` for firewall, reboot, and software inventory monitoring
- `PowerShell/microsoft365` for inactive user reporting and license cost analytics
- `PowerShell/backup` for cloud backup validation workflows
- `PowerShell/web` for web and TLS certificate checks
- `PowerShell/utilities` for helper and diagnostic automation

### SQL Layout

- `SQL/schema` for table creation scripts
- `SQL/migrations` for schema evolution and data model adjustments
- `SQL/permissions` for collector access and least-privilege setup
- `SQL/queries` for operational validation queries
- `SQL/maintenance` for cleanup and lifecycle tasks

## Project Status

Actively developed and extended with new collectors, SQL migrations, and reporting improvements.

## Recruiter-Friendly Positioning

This project is a strong fit for profiles focused on:

- Infrastructure Engineering
- Systems Engineering
- PowerShell Automation
- Microsoft 365 Administration
- Platform Operations
- Monitoring and Observability

## GitHub About

```text
Custom infrastructure monitoring platform built with PowerShell, SQL Server, and automation for AD, DNS, certificates, M365, backups, and server health.
```

## Suggested GitHub Topics

```text
powershell, sql-server, monitoring, infrastructure, active-directory, dns, microsoft365, automation, windows-server
```

## Author

Denys Hrytsai  
Infrastructure / Systems Engineer  
Azure • Microsoft 365 • PowerShell • SQL Server • Automation
