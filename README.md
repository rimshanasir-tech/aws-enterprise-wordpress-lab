# Deploying a Highly Available WordPress Website on AWS

A hands-on cloud lab: a WordPress site that runs on EC2, stores its data in a separate Amazon RDS database, sits behind an Application Load Balancer, and scales automatically with an Auto Scaling Group.

The lab was originally written for Huawei Cloud (KooLabs). I rebuilt it on **AWS** using a free-plan account, so a few services and settings differ (see [Huawei Cloud → AWS mapping](#huawei-cloud--aws-mapping)).

## Requirements from the lab

1. Database nodes and service (web) nodes run on separate servers.
2. Servers are added or removed automatically as incoming traffic changes.

## Architecture

```mermaid
flowchart LR
    U[User / Browser] --> ALB[Application Load Balancer<br/>elb-mp]
    ALB --> TG[Target Group<br/>tg-mp]
    TG --> W1[EC2 web server<br/>us-east-1a]
    TG --> W2[EC2 web server<br/>us-east-1b]
    ASG[Auto Scaling Group<br/>asg-mp<br/>min 1 / desired 2 / max 3] -. launches from .-> LT[Launch Template lt-mp<br/>AMI ims-mp]
    ASG -. registers .-> TG
    W1 --> RDS[(Amazon RDS MySQL<br/>rds-wordpress)]
    W2 --> RDS
    CW[CloudWatch alarms<br/>CPU 60% target] -. triggers .-> ASG
```

## Huawei Cloud → AWS mapping

| Huawei Cloud | AWS used here |
|---|---|
| VPC | Default VPC |
| Security Group | Security Group (`wordpress_sc`) |
| ECS (s6.small.1, CentOS 7.6) | EC2 `t3.micro`, Amazon Linux 2023 |
| RDS MySQL (primary/standby) | RDS MySQL, single-AZ, `db.t4g.micro` (free tier) |
| ELB (shared) | Application Load Balancer |
| IMS image | AMI |
| AS configuration | Launch Template |
| AS group and policies | Auto Scaling Group + target-tracking policy |
| Cloud Eye | CloudWatch |

Other differences: Amazon Linux 2023 uses `dnf` instead of `yum`, WordPress is installed from the latest release into the web root (`/var/www/html`), and a single target-tracking policy (average CPU 60 %) replaces the two separate "add at ≥ 60 %" and "remove at ≤ 20 %" policies.

## Steps

### 1. Network and security
- Used the **Default VPC** (`vpc-…`) with its public subnets in two Availability Zones.
- Created security group `wordpress_sc` with inbound HTTP (80), SSH (22), HTTPS (443) and MySQL (3306).

| VPC | Security group |
|---|---|
| ![VPC](screenshots/01-vpc.png) | ![Security group](screenshots/02-security-group.png) |

> For a production setup, open 3306 only to the web servers' security group and restrict SSH to your own IP. Open rules were used here only because the environment lives for a few hours.

### 2. Web server (EC2)
- Launched one `t3.micro` instance with Amazon Linux 2023 and connected with EC2 Instance Connect.

![EC2 instance](screenshots/03-ec2-instance.png)

### 3. Database (RDS)
- Created an RDS MySQL instance (`rds-wordpress`), single-AZ, free-tier template, **not** publicly accessible, with initial database name `wordpress`.

![RDS created](screenshots/11-rds-created.png)

### 4. Install LAMP and WordPress
Script: [`scripts/install-lamp-wordpress.sh`](scripts/install-lamp-wordpress.sh)

```bash
sudo dnf install -y httpd php php-fpm php-mysqlnd mariadb105 wget
sudo systemctl enable --now httpd php-fpm
cd /tmp && wget https://wordpress.org/latest.tar.gz && tar -xzf latest.tar.gz
sudo cp -r wordpress/* /var/www/html/
sudo chown -R apache:apache /var/www/html
```

| Install | Services running |
|---|---|
| ![LAMP install](screenshots/05-lamp-install-1.png) | ![httpd](screenshots/08-httpd-start.png) |

### 5. WordPress setup wizard
Entered the RDS endpoint as *Database Host*, then installed WordPress.

| Database details | Site details | Dashboard | Site |
|---|---|---|---|
| ![DB](screenshots/13-wordpress-db-details.png) | ![Site](screenshots/14-wordpress-site-details.png) | ![Dashboard](screenshots/15-wordpress-dashboard.png) | ![Blog](screenshots/16-wordpress-site-ec2-ip.png) |

### 6. Make the site work behind a load balancer
WordPress stores its address in the database, so it would redirect back to the original EC2 IP. Fixed with [`scripts/wp-config-dynamic-url.sh`](scripts/wp-config-dynamic-url.sh), which makes `WP_HOME` / `WP_SITEURL` follow the host name of the request.

### 7. Create an AMI and a Launch Template

| AMI | Launch template |
|---|---|
| ![AMI](screenshots/20-ami-list.png) | ![Launch template](screenshots/22-launch-template-create.png) |

### 8. Target Group and Application Load Balancer
- Target group `tg-mp` (HTTP:80, health check `/`, success codes `200-399`).
- Internet-facing ALB `elb-mp` across two Availability Zones, forwarding HTTP:80 to `tg-mp`.

| Target group | Load balancer |
|---|---|
| ![Target group](screenshots/26-target-group-review.png) | ![ALB](screenshots/29-load-balancer-review.png) |

### 9. Auto Scaling Group
- `asg-mp`: launch template `lt-mp`, attached to `tg-mp`, ELB health checks on.
- Capacity: **min 1 / desired 2 / max 3**.
- Policy: target tracking, **average CPU utilization 60 %**.

| Load balancing | Size and scaling | Two instances running |
|---|---|---|
| ![ASG LB](screenshots/48-asg-wizard-load-balancing.png) | ![ASG scaling](screenshots/34-asg-size-and-scaling.png) | ![ASG instances](screenshots/35-asg-overview-2-instances.png) |

## Results

### Two healthy servers behind the load balancer
![Target group healthy](screenshots/36-target-group-2-healthy.png)

### Website served through the load balancer
![Website via ALB](screenshots/37-website-via-alb.png)

### Which server answered?
A small test page (`/server.php`, see [`scripts/server-name-test.sh`](scripts/server-name-test.sh)) shows the name of the server that handled the request.

![server.php](screenshots/42-server-php-browser.png)

### Auto Scaling scaled in by itself
The servers were idle, so CPU stayed far below the 60 % target. The `AlarmLow` CloudWatch alarm fired and the Auto Scaling Group reduced the desired capacity from **2 to 1**, terminating one instance.

| Activity history | CloudWatch alarms |
|---|---|
| ![Activity](screenshots/43-asg-activity-history.png) | ![Alarm](screenshots/47-cloudwatch-alarm-low.png) |

![Terminated instance](screenshots/44-ec2-instance-terminated.png)

## Cost and clean-up
Everything was created and deleted within a few hours on the AWS free plan (estimated cost well under US$1). Resources were removed in this order:

1. Auto Scaling Group → 2. Load Balancer → 3. Target Group → 4. RDS database (no final snapshot) → 5. EC2 instance → 6. AMI (deregister) and its snapshot → 7. Launch Template → 8. Security group.

## What I learned
- Splitting the web tier and database tier makes each one scale and fail independently.
- An AMI plus a Launch Template lets Auto Scaling create identical servers.
- Applications that store their own URL (like WordPress) need extra configuration to work behind a load balancer.
- Target-tracking policies scale in as well as out, so idle servers are removed automatically.
- Always delete the load balancer, database and snapshots when you finish; these are the resources that keep costing money.

## Repository layout

```
.
├── README.md
├── scripts/
│   ├── install-lamp-wordpress.sh
│   ├── wp-config-dynamic-url.sh
│   └── server-name-test.sh
└── screenshots/        # 48 numbered screenshots (AWS account ID and e-mail hidden)
```
