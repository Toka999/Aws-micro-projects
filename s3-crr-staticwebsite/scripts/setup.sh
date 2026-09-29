#!/usr/bin/env bash
set -euo pipefail


# Dynamic Path Resolution (Finds index.html automatically relative to script location)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
WEBSITE_DIR="${PROJECT_ROOT}/website"
INDEX_FILE="${WEBSITE_DIR}/index.html"

# Verify index.html exists
if [[ ! -f "$INDEX_FILE" ]]; then
  echo "[ERROR] index.html not found at: ${INDEX_FILE}"
  exit 1
fi

echo "------------------------------------------"
echo " Project Root : ${PROJECT_ROOT}"
echo " Website File : ${INDEX_FILE}"
echo


#---Configuration---
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
SOURCE_REGION="us-east-1"
DEST_REGION="us-east-2"
SOURCE_BUCKET="crr-site-source-${AWS_ACCOUNT_ID}-9988"
DEST_BUCKET="crr-site-dest-${AWS_ACCOUNT_ID}-9988"
ROLE_NAME="s3-crr-replication-role-9988"

echo "Source Region : ${SOURCE_REGION} | Bucket: ${SOURCE_BUCKET}"
echo "Dest Region   : ${DEST_REGION} | Bucket: ${DEST_BUCKET}"
echo "--------------------------------------------------"

echo "Creating S3 Buckets..."

# us-east-1 doesn't accept LocationConstraint in create-bucket
aws s3api create-bucket \
  --bucket "${SOURCE_BUCKET}" \
  --region "${SOURCE_REGION}" > /dev/null

aws s3api create-bucket \
  --bucket "${DEST_BUCKET}" \
  --region "${DEST_REGION}" \
  --create-bucket-configuration LocationConstraint="${DEST_REGION}" > /dev/null

echo " Enabling Versioning & Encryption..."

# versioning
aws s3api put-bucket-versioning \
  --bucket "${SOURCE_BUCKET}" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-versioning \
  --bucket "${DEST_BUCKET}" \
  --versioning-configuration Status=Enabled

# enable public access on s3 buckets
aws s3api put-public-access-block \
  --bucket "${SOURCE_BUCKET}" \
  --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

aws s3api put-public-access-block \
  --bucket "${DEST_BUCKET}" \
  --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

# enable website hosting endpoint
aws s3 website "s3://${SOURCE_BUCKET}" --index-document index.html
aws s3 website "s3://${DEST_BUCKET}" --index-document index.html

# make public read bucket policy
SOURCE_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${SOURCE_BUCKET}/*"
    }
  ]
}
EOF
)

DEST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${DEST_BUCKET}/*"
    }
  ]
}
EOF
)

# attach policies
aws s3api put-bucket-policy \
  --bucket "${SOURCE_BUCKET}" \
  --policy "${SOURCE_POLICY}"

aws s3api put-bucket-policy \
  --bucket "${DEST_BUCKET}" \
  --policy "${DEST_POLICY}"



# IAM ROLE FOR S3 CROSS-REGION REPLICATION


echo "Creating IAM Role for S3 Cross-Region Replication..."

# Trust policy allowing S3 to assume the replication role
REPLICATION_TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3ToAssumeRole",
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)

aws iam create-role \
  --role-name "${ROLE_NAME}" \
  --assume-role-policy-document "${REPLICATION_TRUST_POLICY}" \
  --description "IAM role for S3 Cross-Region Replication" \
  > /dev/null

ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"

echo "Replication Role ARN: ${ROLE_ARN}"



# IAM POLICY FOR S3 CROSS-REGION REPLICATION


echo "Creating replication permissions policy..."

REPLICATION_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [

    {
      "Sid": "SourceBucketPermissions",
      "Effect": "Allow",
      "Action": [
        "s3:GetReplicationConfiguration",
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::${SOURCE_BUCKET}"
    },

    {
      "Sid": "SourceObjectPermissions",
      "Effect": "Allow",
      "Action": [
        "s3:GetObjectVersionForReplication",
        "s3:GetObjectVersionAcl",
        "s3:GetObjectVersionTagging"
      ],
      "Resource": "arn:aws:s3:::${SOURCE_BUCKET}/*"
    },

    {
      "Sid": "DestinationBucketPermissions",
      "Effect": "Allow",
      "Action": [
        "s3:ReplicateObject",
        "s3:ReplicateDelete",
        "s3:ReplicateTags"
      ],
      "Resource": "arn:aws:s3:::${DEST_BUCKET}/*"
    }

  ]
}
EOF
)

# Attach the replication policy directly to the IAM role
aws iam put-role-policy \
  --role-name "${ROLE_NAME}" \
  --policy-name "S3CRRReplicationPolicy" \
  --policy-document "${REPLICATION_POLICY}"


echo "Waiting for IAM role propagation..."
sleep 10



# CONFIGURE S3 CROSS-REGION REPLICATION


echo "Configuring S3 Cross-Region Replication..."

REPLICATION_CONFIG=$(cat <<EOF
{
  "Role": "${ROLE_ARN}",
  "Rules": [
    {
      "ID": "ReplicateWebsite",
      "Status": "Enabled",
      "Priority": 1,
      "Filter": {},
      "DeleteMarkerReplication": {
        "Status": "Enabled"
      },
      "Destination": {
        "Bucket": "arn:aws:s3:::${DEST_BUCKET}"
      }
    }
  ]
}
EOF
)

aws s3api put-bucket-replication \
  --bucket "${SOURCE_BUCKET}" \
  --replication-configuration "${REPLICATION_CONFIG}"

echo "Cross-Region Replication configured successfully."


# UPLOAD STATIC WEBSITE TO SOURCE BUCKET

echo "Uploading index.html to source bucket..."

aws s3 cp \
  "${INDEX_FILE}" \
  "s3://${SOURCE_BUCKET}/index.html" \
  --region "${SOURCE_REGION}"

echo "index.html uploaded successfully."



# WAIT FOR CROSS-REGION REPLICATION

echo
echo "Waiting for index.html to be replicated to destination bucket..."
echo "Replication can take some time because S3 Cross-Region Replication is asynchronous."

REPLICATION_ATTEMPTS=30
REPLICATION_COUNT=0

while [[ ${REPLICATION_COUNT} -lt ${REPLICATION_ATTEMPTS} ]]; do

  if aws s3api head-object \
      --bucket "${DEST_BUCKET}" \
      --key "index.html" \
      --region "${DEST_REGION}" \
      > /dev/null 2>&1; then

    echo "index.html has been replicated successfully."
    break
  fi

  REPLICATION_COUNT=$((REPLICATION_COUNT + 1))

  echo "Waiting for replication... (${REPLICATION_COUNT}/${REPLICATION_ATTEMPTS})"

  sleep 10
done

if [[ ${REPLICATION_COUNT} -eq ${REPLICATION_ATTEMPTS} ]]; then
  echo
  echo "[WARNING] index.html has not appeared in the destination bucket yet."
  echo "S3 replication may still be in progress."
  echo "You can check the destination bucket manually."
else
  echo "Destination website is ready."
fi



# OUTPUT WEBSITE URLS


echo
echo "--------------------------------------------------"
echo " Deployment Complete"
echo "--------------------------------------------------"

echo
echo "Source Website:"
echo "http://${SOURCE_BUCKET}.s3-website-${SOURCE_REGION}.amazonaws.com"

echo
echo "Destination Website:"
echo "http://${DEST_BUCKET}.s3-website.${DEST_REGION}.amazonaws.com"

echo
echo "Source Bucket:"
echo "s3://${SOURCE_BUCKET}"

echo
echo "Destination Bucket:"
echo "s3://${DEST_BUCKET}"

echo
echo "Replication Role:"
echo "${ROLE_ARN}"

echo
echo "--------------------------------------------------"
echo " CRR is configured."
echo " Uploading index.html will trigger replication."
echo "--------------------------------------------------"