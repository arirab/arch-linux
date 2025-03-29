#!/bin/bash

SG_ID="<SECURITY_GROUP_ID>"
OUTPUT_FILE="sg_resources.txt"

# Prepare the output file
echo "Security Group Resource Report for $SG_ID" > $OUTPUT_FILE
echo "=========================================" >> $OUTPUT_FILE

append_output() {
  echo -e "\n$1" >> $OUTPUT_FILE
  echo "----------------------------------------" >> $OUTPUT_FILE
  eval "$2" >> $OUTPUT_FILE
}

# EC2 Instances using the SG
append_output "EC2 Instances Using $SG_ID:" \
  "aws ec2 describe-instances --filters \"Name=instance.group-id,Values=$SG_ID\" \
  --query \"Reservations[*].Instances[*].[InstanceId,PrivateIpAddress,State.Name]\" --output table"

# Load Balancers using the SG
append_output "Load Balancers Using $SG_ID:" \
  "aws elbv2 describe-load-balancers --query \"LoadBalancers[?SecurityGroups[?contains(@, '$SG_ID')]].LoadBalancerName\" --output table"

# RDS Instances using the SG
append_output "RDS Instances Using $SG_ID:" \
  "aws rds describe-db-instances --query \"DBInstances[?VpcSecurityGroups[?GroupId=='$SG_ID']].[DBInstanceIdentifier,Engine,DBInstanceStatus]\" --output table"

# Lambda Functions using the SG
append_output "Lambda Functions Using $SG_ID:" \
  "aws lambda list-functions --query \"Functions[?VpcConfig.SecurityGroupIds[?contains(@, '$SG_ID')]].FunctionName\" --output table"

# EKS Clusters using the SG
append_output "EKS Clusters Using $SG_ID:" \
  "aws eks describe-cluster --name <CLUSTER_NAME> --query \"cluster.resourcesVpcConfig.securityGroupIds\" --output table"

echo -e "\nReport saved to $OUTPUT_FILE"
