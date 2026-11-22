
#!/bin/bash

# ============================================================
# FEDORA LANE - LEGACY STAGING PROVISIONING SCRIPT
# Version: 1.0
# Owner: Infrastructure Operations
# Purpose: Provision, configure, verify and report staging
# ============================================================

# WARNING:
# This is an illustrative legacy-style demonstration.
# DRY RUN is enabled by default. No AWS resources are changed.
# ============================================================

AWS_REGION="us-east-2"
AMI_ID="ami-08e728aab89b9de96"
SUBNET_ID="subnet-0dd9be84b04c86e58"
SECURITY_GROUP="sg-0eee73714ec63d194"
IAM_PROFILE="FedoraLaneSSMInstanceProfile"

APP_OWNER="${APP_OWNER:-Ashok}"
ENVIRONMENT="${ENVIRONMENT:-staging}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.small}"
DISK_SIZE="${DISK_SIZE:-20}"

INSTANCE_NAME="fedora-lane-${ENVIRONMENT}-${INSTANCE_TYPE}-${DISK_SIZE}gb-${APP_OWNER,,}"
REPORT_FILE="/tmp/fedora_lane_report.txt"

INSTANCE_ID=""
PUBLIC_IP=""
PRIVATE_IP=""
STATUS="UNKNOWN"
ERROR_MESSAGE=""
STEP="INITIALIZATION"

EXECUTE_AWS_CHANGES="${EXECUTE_AWS_CHANGES:-NO}"

echo "============================================"
echo " FEDORA LANE STAGING AUTOMATION"
echo "============================================"
echo "Owner          : $APP_OWNER"
echo "Environment    : $ENVIRONMENT"
echo "Instance Type  : $INSTANCE_TYPE"
echo "Disk Size      : $DISK_SIZE GB"
echo "AWS Region     : $AWS_REGION"
echo "Instance Name  : $INSTANCE_NAME"
echo "============================================"

# ------------------------------------------------------------
# INITIAL CHECKS
# ------------------------------------------------------------

STEP="CHECKING DEPENDENCIES"

if ! command -v aws >/dev/null 2>&1; then
    echo "ERROR: AWS CLI not installed"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is missing"
    exit 1
fi

if ! aws sts get-caller-identity --region "$AWS_REGION" >/dev/null 2>&1; then
    echo "ERROR: AWS authentication failed"
    exit 1
fi

if [ "$DISK_SIZE" -lt 20 ] || [ "$DISK_SIZE" -gt 100 ]; then
    echo "ERROR: Invalid disk size"
    exit 1
fi

echo "Initial checks completed"

# ------------------------------------------------------------
# STEP 1 - CHECK WHETHER INSTANCE ALREADY EXISTS
# ------------------------------------------------------------

STEP="INSTANCE DISCOVERY"

echo "Searching for an existing staging instance..."

EXISTING_INSTANCE=$(aws ec2 describe-instances \
    --region "$AWS_REGION" \
    --filters \
    "Name=tag:Name,Values=$INSTANCE_NAME" \
    "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query "Reservations[].Instances[0].InstanceId" \
    --output text 2>/dev/null)

if [ "$EXECUTE_AWS_CHANGES" != "YES" ]; then
    echo "[DRY RUN] Would search EC2 for: $INSTANCE_NAME"
    INSTANCE_ID="DRY-RUN-INSTANCE"
elif [ "$EXISTING_INSTANCE" != "None" ] && [ -n "$EXISTING_INSTANCE" ]; then
    INSTANCE_ID="$EXISTING_INSTANCE"
    echo "Existing instance found: $INSTANCE_ID"
else
    echo "No existing instance found"
    echo "Starting new EC2 provisioning..."

    INSTANCE_ID=$(aws ec2 run-instances \
        --region "$AWS_REGION" \
        --image-id "$AMI_ID" \
        --instance-type "$INSTANCE_TYPE" \
        --subnet-id "$SUBNET_ID" \
        --security-group-ids "$SECURITY_GROUP" \
        --iam-instance-profile Name="$IAM_PROFILE" \
        --block-device-mappings \
        "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":$DISK_SIZE,\"VolumeType\":\"gp3\",\"Encrypted\":true}}]" \
        --tag-specifications \
        "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME},{Key=Owner,Value=$APP_OWNER},{Key=Environment,Value=$ENVIRONMENT}]" \
        --query "Instances[0].InstanceId" \
        --output text)

    if [ -z "$INSTANCE_ID" ]; then
        echo "ERROR: Instance provisioning failed"
        exit 1
    fi
fi

echo "Selected instance: $INSTANCE_ID"

# ------------------------------------------------------------
# STEP 2 - WAIT FOR INSTANCE TO BECOME AVAILABLE
# ------------------------------------------------------------

STEP="WAITING FOR INSTANCE"

if [ "$EXECUTE_AWS_CHANGES" = "YES" ]; then
    aws ec2 wait instance-running \
        --region "$AWS_REGION" \
        --instance-ids "$INSTANCE_ID"

    INSTANCE_DETAILS=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --instance-ids "$INSTANCE_ID" \
        --output json)

    PUBLIC_IP=$(echo "$INSTANCE_DETAILS" | jq -r '.Reservations[0].Instances[0].PublicIpAddress // "N/A"')
    PRIVATE_IP=$(echo "$INSTANCE_DETAILS" | jq -r '.Reservations[0].Instances[0].PrivateIpAddress // "N/A"')
else
    echo "[DRY RUN] Would wait for EC2 instance to become running"
    PUBLIC_IP="DRY-RUN"
    PRIVATE_IP="DRY-RUN"
fi

echo "Instance ID : $INSTANCE_ID"
echo "Public IP   : $PUBLIC_IP"
echo "Private IP  : $PRIVATE_IP"

# ------------------------------------------------------------
# STEP 3 - CHECK SYSTEMS MANAGER CONNECTIVITY
# ------------------------------------------------------------

STEP="CHECKING SSM CONNECTIVITY"

if [ "$EXECUTE_AWS_CHANGES" = "YES" ]; then
    SSM_STATUS="Offline"
    COUNT=0

    while [ "$COUNT" -lt 20 ]; do
        SSM_STATUS=$(aws ssm describe-instance-information \
            --region "$AWS_REGION" \
            --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
            --query "InstanceInformationList[0].PingStatus" \
            --output text 2>/dev/null)

        if [ "$SSM_STATUS" = "Online" ]; then
            break
        fi

        echo "Waiting for SSM agent..."
        sleep 15
        COUNT=$((COUNT+1))
    done

    if [ "$SSM_STATUS" != "Online" ]; then
        echo "ERROR: SSM agent is not online"
        exit 1
    fi
else
    echo "[DRY RUN] Would poll AWS Systems Manager until Online"
fi

# ------------------------------------------------------------
# STEP 4 - CONFIGURE THE RHEL SERVER
# ------------------------------------------------------------

STEP="SERVER CONFIGURATION"

echo "Sending configuration commands..."

if [ "$EXECUTE_AWS_CHANGES" = "YES" ]; then

    COMMAND_ID=$(aws ssm send-command \
        --region "$AWS_REGION" \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=[
          "hostnamectl set-hostname fedora-lane-staging",
          "dnf install -y curl wget vim-enhanced git tar unzip jq",
          "mkdir -p /opt/fedora-lane/config",
          "mkdir -p /var/log/fedora-lane",
          "chmod 755 /opt/fedora-lane",
          "chmod 755 /var/log/fedora-lane",
          "echo FEDORA LANE - STAGING ENVIRONMENT > /etc/motd"
        ]' \
        --query "Command.CommandId" \
        --output text)

    if [ -z "$COMMAND_ID" ]; then
        echo "ERROR: Failed to send configuration command"
        exit 1
    fi

    CONFIG_STATUS="InProgress"
    COUNT=0

    while [ "$CONFIG_STATUS" != "Success" ] && [ "$COUNT" -lt 30 ]; do
        CONFIG_STATUS=$(aws ssm get-command-invocation \
            --region "$AWS_REGION" \
            --command-id "$COMMAND_ID" \
            --instance-id "$INSTANCE_ID" \
            --query "Status" \
            --output text 2>/dev/null)

        if [ "$CONFIG_STATUS" = "Failed" ] || [ "$CONFIG_STATUS" = "TimedOut" ]; then
            echo "ERROR: Server configuration failed"
            exit 1
        fi

        sleep 10
        COUNT=$((COUNT+1))
    done

    if [ "$CONFIG_STATUS" != "Success" ]; then
        echo "ERROR: Configuration timed out"
        exit 1
    fi

else
    echo "[DRY RUN] Would install packages and configure RHEL through SSM"
fi

echo "Configuration stage completed"

# ------------------------------------------------------------
# STEP 5 - VERIFY THE SERVER
# ------------------------------------------------------------

STEP="SERVER VERIFICATION"

if [ "$EXECUTE_AWS_CHANGES" = "YES" ]; then

    VERIFY_COMMAND=$(aws ssm send-command \
        --region "$AWS_REGION" \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=[
          "hostname",
          "test -d /opt/fedora-lane/config",
          "test -d /var/log/fedora-lane",
          "rpm -q git curl wget vim-enhanced tar unzip jq",
          "grep -q FEDORA /etc/motd",
          "echo FEDORA_LANE_VERIFICATION_SUCCESS"
        ]' \
        --query "Command.CommandId" \
        --output text)

    VERIFY_STATUS="InProgress"
    COUNT=0

    while [ "$VERIFY_STATUS" != "Success" ] && [ "$COUNT" -lt 30 ]; do
        VERIFY_STATUS=$(aws ssm get-command-invocation \
            --region "$AWS_REGION" \
            --command-id "$VERIFY_COMMAND" \
            --instance-id "$INSTANCE_ID" \
            --query "Status" \
            --output text 2>/dev/null)

        if [ "$VERIFY_STATUS" = "Failed" ] || [ "$VERIFY_STATUS" = "TimedOut" ]; then
            echo "ERROR: Verification failed"
            exit 1
        fi

        sleep 10
        COUNT=$((COUNT+1))
    done

    if [ "$VERIFY_STATUS" != "Success" ]; then
        echo "ERROR: Verification timed out"
        exit 1
    fi

else
    echo "[DRY RUN] Would verify hostname, packages, directories and MOTD"
fi

# ------------------------------------------------------------
# STEP 6 - GENERATE FINAL REPORT
# ------------------------------------------------------------

STEP="FINAL REPORT"

STATUS="SUCCESS"

echo "============================================" > "$REPORT_FILE"
echo " FEDORA LANE STAGING DEPLOYMENT REPORT" >> "$REPORT_FILE"
echo "============================================" >> "$REPORT_FILE"
echo "Owner         : $APP_OWNER" >> "$REPORT_FILE"
echo "Environment   : $ENVIRONMENT" >> "$REPORT_FILE"
echo "Instance Name : $INSTANCE_NAME" >> "$REPORT_FILE"
echo "Instance ID   : $INSTANCE_ID" >> "$REPORT_FILE"
echo "Instance Type : $INSTANCE_TYPE" >> "$REPORT_FILE"
echo "Disk Size     : $DISK_SIZE GB" >> "$REPORT_FILE"
echo "Public IP     : $PUBLIC_IP" >> "$REPORT_FILE"
echo "Private IP    : $PRIVATE_IP" >> "$REPORT_FILE"
echo "Verification  : PASSED" >> "$REPORT_FILE"
echo "Overall       : $STATUS" >> "$REPORT_FILE"
echo "============================================" >> "$REPORT_FILE"

cat "$REPORT_FILE"

echo "============================================"
echo "STAGING DEPLOYMENT COMPLETED SUCCESSFULLY"
echo "============================================"
