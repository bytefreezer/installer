# ByteFreezer ECS Deployments

Deploy ByteFreezer on Amazon ECS Fargate using CloudFormation or Terraform.

## Deployment Options

| Tool | Directory | Description |
|------|-----------|-------------|
| CloudFormation | `*/cloudformation.yaml` | AWS-native infrastructure as code |
| Terraform | `*/terraform/` | HashiCorp Terraform modules |

## Components

| Directory | Description |
|-----------|-------------|
| [bytefreezer](./bytefreezer/) | Processing stack (receiver, piper, packer) - deploy centrally |
| [proxy](./proxy/) | Edge data collection - deploy at data source locations |

## Architecture

```
   Edge Sites (ECS)                        Central Processing (ECS)
                                       ┌─────────────────────────┐
┌─────────────────┐                    │                         │
│  Site A         │                    │  ┌──────────┐           │
│  ┌───────────┐  │   ┌────────────────┼─►│ Receiver │           │
│  │   Proxy   │──┼───┤                │  │   ALB    │           │
│  │   NLB     │  │   │                │  └────┬─────┘           │
│  └───────────┘  │   │                │       │                 │
└─────────────────┘   │                │       ▼                 │
                      │                │  ┌─────────┐            │
┌─────────────────┐   │                │  │   S3    │            │
│  Site B         │   │                │  └────┬────┘            │
│  ┌───────────┐  │   │                │       │                 │
│  │   Proxy   │──┼───┤                │       ▼                 │
│  │   NLB     │  │   │                │  ┌─────────┐            │
│  └───────────┘  │   │                │  │  Piper  │            │
└─────────────────┘   │                │  └────┬────┘            │
                      │                │       │                 │
                      │                │       ▼                 │
                      │                │  ┌─────────┐            │
                      └────────────────┼──│ Packer  │            │
                                       │  └─────────┘            │
                                       └─────────────────────────┘
```

## Prerequisites

- AWS CLI configured with appropriate credentials
- VPC with at least 2 subnets (for load balancer requirements)
- AWS Secrets Manager secret containing your control service API key
- **For Terraform**: Terraform >= 1.0

### Create API Key Secret

```bash
aws secretsmanager create-secret \
  --name bytefreezer/control-api-key \
  --secret-string "your-api-key-here"
```

Note the ARN returned - you'll need it for deployment.

## Quick Start

Choose either CloudFormation or Terraform below.

---

## CloudFormation

### 1. Deploy Processing Stack (Central)

```bash
cd bytefreezer

aws cloudformation create-stack \
  --stack-name bytefreezer-processing \
  --template-body file://cloudformation.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameters \
    ParameterKey=VpcId,ParameterValue=vpc-xxxxxxxx \
    ParameterKey=SubnetIds,ParameterValue="subnet-xxxxxxxx,subnet-yyyyyyyy" \
    ParameterKey=ControlServiceUrl,ParameterValue=https://api.bytefreezer.com \
    ParameterKey=ControlServiceApiKeyArn,ParameterValue=arn:aws:secretsmanager:region:account:secret:bytefreezer/control-api-key-xxxxx
```

Get the receiver URL:
```bash
aws cloudformation describe-stacks \
  --stack-name bytefreezer-processing \
  --query 'Stacks[0].Outputs[?OutputKey==`ReceiverUrl`].OutputValue' \
  --output text
```

### 2. Deploy Proxy (Edge Sites)

```bash
cd proxy

# Site A
aws cloudformation create-stack \
  --stack-name bytefreezer-proxy-site-a \
  --template-body file://cloudformation.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameters \
    ParameterKey=SiteName,ParameterValue=site-a \
    ParameterKey=VpcId,ParameterValue=vpc-xxxxxxxx \
    ParameterKey=SubnetIds,ParameterValue="subnet-xxxxxxxx,subnet-yyyyyyyy" \
    ParameterKey=ReceiverUrl,ParameterValue=http://RECEIVER_ALB_DNS:8080 \
    ParameterKey=ControlServiceUrl,ParameterValue=https://api.bytefreezer.com \
    ParameterKey=ControlServiceApiKeyArn,ParameterValue=arn:aws:secretsmanager:region:account:secret:bytefreezer/control-api-key-xxxxx
```

---

## Terraform

### 1. Deploy Processing Stack (Central)

```bash
cd bytefreezer/terraform

# Copy and configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your settings

# Initialize and deploy
terraform init
terraform plan
terraform apply
```

Get the receiver URL:
```bash
terraform output receiver_url
```

### 2. Deploy Proxy (Edge Sites)

```bash
cd proxy/terraform

# Copy and configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars - set receiver_url from processing stack output

# Initialize and deploy
terraform init
terraform plan
terraform apply
```

### Terraform State Management

For production, configure remote state backend:

```hcl
# Add to main.tf
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "bytefreezer/processing/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

---

## Parameters (CloudFormation)

### Processing Stack (bytefreezer/)

| Parameter | Required | Description | Default |
|-----------|----------|-------------|---------|
| `Environment` | No | Deployment environment | `production` |
| `VpcId` | Yes | VPC ID | - |
| `SubnetIds` | Yes | Comma-separated subnet IDs | - |
| `ImageTag` | No | Docker image tag | `latest` |
| `ImageRegistry` | No | Docker registry | `ghcr.io/bytefreezer` |
| `ControlServiceUrl` | Yes | Control service URL | - |
| `ControlServiceApiKeyArn` | Yes | Secrets Manager ARN | - |
| `S3BucketPrefix` | No | S3 bucket name prefix | `bytefreezer` |
| `ReceiverDesiredCount` | No | Receiver task count | `1` |
| `PiperDesiredCount` | No | Piper task count | `1` |
| `PackerDesiredCount` | No | Packer task count | `1` |

### Proxy (proxy/)

| Parameter | Required | Description | Default |
|-----------|----------|-------------|---------|
| `Environment` | No | Deployment environment | `production` |
| `SiteName` | Yes | Site identifier (e.g., us-east) | - |
| `VpcId` | Yes | VPC ID | - |
| `SubnetIds` | Yes | Comma-separated subnet IDs | - |
| `ImageTag` | No | Docker image tag | `latest` |
| `ImageRegistry` | No | Docker registry | `ghcr.io/bytefreezer` |
| `ReceiverUrl` | Yes | Receiver webhook URL | - |
| `ControlServiceUrl` | Yes | Control service URL | - |
| `ControlServiceApiKeyArn` | Yes | Secrets Manager ARN | - |
| `DesiredCount` | No | Proxy task count | `1` |
| `UdpPort` | No | UDP listening port | `5514` |

## Variables (Terraform)

See `terraform.tfvars.example` in each module for all available variables.

### Processing Stack (bytefreezer/terraform/)

| Variable | Required | Description | Default |
|----------|----------|-------------|---------|
| `environment` | No | Deployment environment | `production` |
| `vpc_id` | Yes | VPC ID | - |
| `subnet_ids` | Yes | List of subnet IDs | - |
| `control_service_url` | Yes | Control service URL | - |
| `control_service_api_key_arn` | Yes | Secrets Manager ARN | - |
| `image_tag` | No | Docker image tag | `latest` |
| `receiver_desired_count` | No | Receiver task count | `1` |
| `piper_desired_count` | No | Piper task count | `1` |
| `packer_desired_count` | No | Packer task count | `1` |

### Proxy (proxy/terraform/)

| Variable | Required | Description | Default |
|----------|----------|-------------|---------|
| `environment` | No | Deployment environment | `production` |
| `site_name` | Yes | Site identifier | - |
| `vpc_id` | Yes | VPC ID | - |
| `subnet_ids` | Yes | List of subnet IDs | - |
| `receiver_url` | Yes | Receiver webhook URL | - |
| `control_service_url` | Yes | Control service URL | - |
| `control_service_api_key_arn` | Yes | Secrets Manager ARN | - |
| `desired_count` | No | Proxy task count | `1` |
| `udp_port` | No | UDP listening port | `5514` |

## Resources Created

### Processing Stack

- ECS Cluster
- S3 Buckets (intake, piper, packer, geoip)
- Application Load Balancer (for receiver)
- ECS Services (receiver, piper, packer)
- IAM Roles (task execution, task)
- Security Groups
- CloudWatch Log Groups

### Proxy

- ECS Cluster
- Network Load Balancer (for UDP support)
- ECS Service (proxy)
- IAM Roles (task execution, task)
- Security Group
- CloudWatch Log Group

## Scaling

### CloudFormation - Update Service Desired Count

```bash
# Processing stack
aws cloudformation update-stack \
  --stack-name bytefreezer-processing \
  --use-previous-template \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameters \
    ParameterKey=VpcId,UsePreviousValue=true \
    ParameterKey=SubnetIds,UsePreviousValue=true \
    ParameterKey=ControlServiceUrl,UsePreviousValue=true \
    ParameterKey=ControlServiceApiKeyArn,UsePreviousValue=true \
    ParameterKey=ReceiverDesiredCount,ParameterValue=3 \
    ParameterKey=PiperDesiredCount,ParameterValue=2 \
    ParameterKey=PackerDesiredCount,ParameterValue=2

# Proxy
aws cloudformation update-stack \
  --stack-name bytefreezer-proxy-site-a \
  --use-previous-template \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameters \
    ParameterKey=SiteName,UsePreviousValue=true \
    ParameterKey=VpcId,UsePreviousValue=true \
    ParameterKey=SubnetIds,UsePreviousValue=true \
    ParameterKey=ReceiverUrl,UsePreviousValue=true \
    ParameterKey=ControlServiceUrl,UsePreviousValue=true \
    ParameterKey=ControlServiceApiKeyArn,UsePreviousValue=true \
    ParameterKey=DesiredCount,ParameterValue=3
```

### Terraform - Update Service Desired Count

```bash
# Processing stack
cd bytefreezer/terraform
terraform apply -var="receiver_desired_count=3" -var="piper_desired_count=2" -var="packer_desired_count=2"

# Proxy
cd proxy/terraform
terraform apply -var="desired_count=3"
```

Or update `terraform.tfvars` and run `terraform apply`.

### Auto Scaling (Optional)

Add Application Auto Scaling to your stack:

```yaml
# Add to CloudFormation template
ScalableTarget:
  Type: AWS::ApplicationAutoScaling::ScalableTarget
  Properties:
    ServiceNamespace: ecs
    ResourceId: !Sub 'service/${ECSCluster}/${ServiceName}'
    ScalableDimension: ecs:service:DesiredCount
    MinCapacity: 1
    MaxCapacity: 10
    RoleARN: !Sub 'arn:aws:iam::${AWS::AccountId}:role/aws-service-role/ecs.application-autoscaling.amazonaws.com/AWSServiceRoleForApplicationAutoScaling_ECSService'

ScalingPolicy:
  Type: AWS::ApplicationAutoScaling::ScalingPolicy
  Properties:
    PolicyName: cpu-scaling
    PolicyType: TargetTrackingScaling
    ScalingTargetId: !Ref ScalableTarget
    TargetTrackingScalingPolicyConfiguration:
      TargetValue: 70
      PredefinedMetricSpecification:
        PredefinedMetricType: ECSServiceAverageCPUUtilization
```

## Monitoring

### View Logs

```bash
# Receiver logs
aws logs tail /ecs/bytefreezer-receiver-production --follow

# Piper logs
aws logs tail /ecs/bytefreezer-piper-production --follow

# Packer logs
aws logs tail /ecs/bytefreezer-packer-production --follow

# Proxy logs
aws logs tail /ecs/bytefreezer-proxy-site-a-production --follow
```

### Check Service Status

```bash
# List services
aws ecs list-services --cluster bytefreezer-production

# Describe service
aws ecs describe-services \
  --cluster bytefreezer-production \
  --services bytefreezer-receiver-production
```

### Health Checks

```bash
# Get receiver ALB DNS
RECEIVER_DNS=$(aws cloudformation describe-stacks \
  --stack-name bytefreezer-processing \
  --query 'Stacks[0].Outputs[?OutputKey==`ReceiverUrl`].OutputValue' \
  --output text)

# Check health (note: health endpoint is on port 8081)
curl ${RECEIVER_DNS%:8080}:8081/api/v1/health
```

## Troubleshooting

### Task Not Starting

Check task stopped reason:
```bash
aws ecs describe-tasks \
  --cluster bytefreezer-production \
  --tasks $(aws ecs list-tasks --cluster bytefreezer-production --query 'taskArns[0]' --output text)
```

### Container Logs

```bash
aws logs get-log-events \
  --log-group-name /ecs/bytefreezer-receiver-production \
  --log-stream-name "receiver/receiver/$(aws ecs list-tasks --cluster bytefreezer-production --query 'taskArns[0]' --output text | cut -d/ -f3)"
```

### Secrets Access Issues

Verify the task execution role has access to the secret:
```bash
aws secretsmanager get-secret-value \
  --secret-id bytefreezer/control-api-key
```

## Cleanup

### CloudFormation

```bash
# Delete proxy stacks first
aws cloudformation delete-stack --stack-name bytefreezer-proxy-site-a

# Wait for deletion
aws cloudformation wait stack-delete-complete --stack-name bytefreezer-proxy-site-a

# Delete processing stack (will also delete S3 buckets if empty)
aws cloudformation delete-stack --stack-name bytefreezer-processing
```

Note: S3 buckets must be empty before stack deletion. Empty them first:
```bash
aws s3 rm s3://bytefreezer-intake-ACCOUNT_ID --recursive
aws s3 rm s3://bytefreezer-piper-ACCOUNT_ID --recursive
aws s3 rm s3://bytefreezer-packer-ACCOUNT_ID --recursive
aws s3 rm s3://bytefreezer-geoip-ACCOUNT_ID --recursive
```

### Terraform

```bash
# Delete proxy first
cd proxy/terraform
terraform destroy

# Delete processing stack
cd ../../bytefreezer/terraform
terraform destroy
```

Note: Terraform will prompt before deleting S3 buckets. Empty them first if they contain data.

## Cost Considerations

- **Fargate**: Pay per vCPU and memory per second
- **ALB/NLB**: Hourly charge plus LCU charges
- **S3**: Storage and request charges
- **CloudWatch Logs**: Ingestion and storage charges
- **Secrets Manager**: Per secret per month plus API calls

For cost optimization:
- Use Fargate Spot for non-critical workloads
- Right-size task CPU/memory based on actual usage
- Set appropriate log retention periods
- Use S3 lifecycle policies for data retention
