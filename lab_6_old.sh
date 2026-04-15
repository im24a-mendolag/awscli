#!/bin/bash
# Lab 6 (old): Scale and Load Balance Your Architecture
# Automates ELB + Auto Scaling lab via AWS CLI

source ./common.sh

set -e

REGION="us-east-1"

echo "==> Verifying AWS CLI..."
aws --version

# -------------------------------------------------------
# Lookups: VPC, subnets, security group
# -------------------------------------------------------

echo ""
echo "==> Looking up Lab VPC..."
VPC_ID=$(aws ec2 describe-vpcs --region $REGION \
  --filters "Name=tag:Name,Values=Lab VPC" \
  --query 'Vpcs[0].VpcId' --output text)
echo "    VPC_ID: $VPC_ID"

PUB1=$(aws ec2 describe-subnets --region $REGION \
  --filters "Name=tag:Name,Values=Public Subnet 1" \
  --query 'Subnets[0].SubnetId' --output text)
PUB2=$(aws ec2 describe-subnets --region $REGION \
  --filters "Name=tag:Name,Values=Public Subnet 2" \
  --query 'Subnets[0].SubnetId' --output text)
PRIV1=$(aws ec2 describe-subnets --region $REGION \
  --filters "Name=tag:Name,Values=Private Subnet 1" \
  --query 'Subnets[0].SubnetId' --output text)
PRIV2=$(aws ec2 describe-subnets --region $REGION \
  --filters "Name=tag:Name,Values=Private Subnet 2" \
  --query 'Subnets[0].SubnetId' --output text)
echo "    Public: $PUB1 $PUB2"
echo "    Private: $PRIV1 $PRIV2"

SG_ID=$(aws ec2 describe-security-groups --region $REGION \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=Web Security Group" \
  --query 'SecurityGroups[0].GroupId' --output text)
echo "    SG_ID: $SG_ID"

# -------------------------------------------------------
# Task 1: Create AMI from Web Server 1
# -------------------------------------------------------

echo ""
echo "==> [Task 1] Finding Web Server 1 instance..."
WEB1_ID=$(aws ec2 describe-instances --region $REGION \
  --filters "Name=tag:Name,Values=Web Server 1" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
echo "    Web Server 1: $WEB1_ID"

AMI_ID=$(aws ec2 describe-images --region $REGION --owners self \
  --filters "Name=name,Values=WebServerAMI" \
  --query 'Images[0].ImageId' --output text)

if [ "$AMI_ID" = "None" ] || [ -z "$AMI_ID" ]; then
  echo "==> Creating AMI WebServerAMI..."
  AMI_ID=$(aws ec2 create-image --region $REGION \
    --instance-id $WEB1_ID \
    --name "WebServerAMI" \
    --description "Lab AMI for Web Server" \
    --query 'ImageId' --output text)
  echo "    AMI_ID: $AMI_ID"
else
  echo "    AMI WebServerAMI already exists: $AMI_ID"
fi

echo "==> Waiting for AMI to become available..."
aws ec2 wait image-available --region $REGION --image-ids $AMI_ID
echo "    AMI available."

# -------------------------------------------------------
# Task 2: Target group + ALB
# -------------------------------------------------------

echo ""
echo "==> [Task 2] Creating target group LabGroup..."
TG_ARN=$(aws elbv2 describe-target-groups --region $REGION \
  --names LabGroup --query 'TargetGroups[0].TargetGroupArn' \
  --output text 2>/dev/null || true)

if [ -z "$TG_ARN" ] || [ "$TG_ARN" = "None" ]; then
  TG_ARN=$(aws elbv2 create-target-group --region $REGION \
    --name LabGroup \
    --protocol HTTP --port 80 \
    --target-type instance \
    --vpc-id $VPC_ID \
    --query 'TargetGroups[0].TargetGroupArn' --output text)
fi
echo "    TG_ARN: $TG_ARN"

echo "==> Creating ALB LabELB..."
ALB_ARN=$(aws elbv2 describe-load-balancers --region $REGION \
  --names LabELB --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text 2>/dev/null || true)

if [ -z "$ALB_ARN" ] || [ "$ALB_ARN" = "None" ]; then
  ALB_ARN=$(aws elbv2 create-load-balancer --region $REGION \
    --name LabELB \
    --subnets $PUB1 $PUB2 \
    --security-groups $SG_ID \
    --scheme internet-facing \
    --type application \
    --query 'LoadBalancers[0].LoadBalancerArn' --output text)
fi
echo "    ALB_ARN: $ALB_ARN"

ALB_DNS=$(aws elbv2 describe-load-balancers --region $REGION \
  --load-balancer-arns $ALB_ARN \
  --query 'LoadBalancers[0].DNSName' --output text)
echo "    ALB_DNS: $ALB_DNS"

echo "==> Waiting for ALB to become active..."
aws elbv2 wait load-balancer-available --region $REGION --load-balancer-arns $ALB_ARN

echo "==> Creating HTTP:80 listener..."
LISTENER_EXISTS=$(aws elbv2 describe-listeners --region $REGION \
  --load-balancer-arn $ALB_ARN \
  --query "Listeners[?Port==\`80\`].ListenerArn" --output text)
if [ -z "$LISTENER_EXISTS" ]; then
  aws elbv2 create-listener --region $REGION \
    --load-balancer-arn $ALB_ARN \
    --protocol HTTP --port 80 \
    --default-actions Type=forward,TargetGroupArn=$TG_ARN > /dev/null
  echo "    Listener created."
else
  echo "    Listener already exists."
fi

# -------------------------------------------------------
# Task 3: Launch template + Auto Scaling group
# -------------------------------------------------------

echo ""
echo "==> [Task 3] Creating launch template LabConfig..."
LT_EXISTS=$(aws ec2 describe-launch-templates --region $REGION \
  --query "LaunchTemplates[?LaunchTemplateName=='LabConfig'].LaunchTemplateId" \
  --output text 2>/dev/null || true)

if [ -z "$LT_EXISTS" ]; then
  LT_DATA="{\"ImageId\":\"$AMI_ID\",\"InstanceType\":\"t2.micro\",\"KeyName\":\"vockey\",\"SecurityGroupIds\":[\"$SG_ID\"],\"Monitoring\":{\"Enabled\":true}}"
  aws ec2 create-launch-template --region $REGION \
    --launch-template-name LabConfig \
    --launch-template-data "$LT_DATA" > /dev/null
  echo "    Launch template created."
else
  echo "    Launch template LabConfig already exists."
fi

echo "==> Creating Auto Scaling group..."
ASG_EXISTS=$(aws autoscaling describe-auto-scaling-groups --region $REGION \
  --auto-scaling-group-names "Lab Auto Scaling Group" \
  --query 'AutoScalingGroups[0].AutoScalingGroupName' --output text 2>/dev/null || true)

if [ "$ASG_EXISTS" = "None" ] || [ -z "$ASG_EXISTS" ]; then
  aws autoscaling create-auto-scaling-group --region $REGION \
    --auto-scaling-group-name "Lab Auto Scaling Group" \
    --launch-template "LaunchTemplateName=LabConfig,Version=\$Latest" \
    --min-size 2 --max-size 6 --desired-capacity 2 \
    --vpc-zone-identifier "$PRIV1,$PRIV2" \
    --target-group-arns $TG_ARN \
    --health-check-type ELB --health-check-grace-period 300 \
    --tags "Key=Name,Value=Lab Instance,PropagateAtLaunch=true"
  echo "    ASG created."
else
  echo "    ASG already exists."
fi

echo "==> Enabling group metrics collection..."
aws autoscaling enable-metrics-collection --region $REGION \
  --auto-scaling-group-name "Lab Auto Scaling Group" \
  --granularity "1Minute"

echo "==> Creating target tracking scaling policy LabScalingPolicy..."
aws autoscaling put-scaling-policy --region $REGION \
  --auto-scaling-group-name "Lab Auto Scaling Group" \
  --policy-name LabScalingPolicy \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{"PredefinedMetricSpecification":{"PredefinedMetricType":"ASGAverageCPUUtilization"},"TargetValue":60.0}' > /dev/null
echo "    Scaling policy set."

# -------------------------------------------------------
# Task 4: Verify
# -------------------------------------------------------

echo ""
echo "==> [Task 4] Waiting for targets to become healthy..."
while true; do
  HEALTHY=$(aws elbv2 describe-target-health --region $REGION \
    --target-group-arn $TG_ARN \
    --query "length(TargetHealthDescriptions[?TargetHealth.State=='healthy'])" \
    --output text)
  TOTAL=$(aws elbv2 describe-target-health --region $REGION \
    --target-group-arn $TG_ARN \
    --query "length(TargetHealthDescriptions)" --output text)
  echo "    healthy: $HEALTHY / $TOTAL"
  if [ "$HEALTHY" -ge 2 ]; then break; fi
  sleep 15
done

# -------------------------------------------------------
# Task 6: Terminate Web Server 1
# -------------------------------------------------------

echo ""
echo "==> [Task 6] Terminating Web Server 1 ($WEB1_ID)..."
aws ec2 terminate-instances --region $REGION --instance-ids $WEB1_ID > /dev/null
echo "    Termination initiated."

# -------------------------------------------------------
# Done
# -------------------------------------------------------

echo ""
echo "==> All tasks completed successfully!"
echo ""
echo "    AMI_ID:      $AMI_ID"
echo "    TG_ARN:      $TG_ARN"
echo "    ALB DNS:     http://$ALB_DNS/"
echo "    ASG:         Lab Auto Scaling Group"
echo ""
echo "    [Task 5 — manual] Open http://$ALB_DNS/ in a browser,"
echo "    click 'Load Test' to drive CPU, then watch CloudWatch alarms"
echo "    trigger Auto Scaling to add instances (up to 6)."
