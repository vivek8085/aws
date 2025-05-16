#!/bin/bash

echo "🔧 AWS Caching Lab Setup (Experiment 07)"

# === STEP 1: USER INPUT ===
read -p "Enter ElastiCache cluster name: " CLUSTER_NAME
read -p "Enter VPC ID for ElastiCache: " VPC_ID
read -p "Enter EC2 Security Group ID (with port 11211 open): " SECURITY_GROUP_ID
read -p "Enter Subnet IDs (comma-separated, no spaces): " SUBNET_IDS
read -p "Enter Subnet Group Name (to create): " SUBNET_GROUP_NAME
read -p "Enter AWS Region: " REGION
read -p "Enter your S3 Bucket name for CloudFront: " S3_BUCKET

# === STEP 2: Create ElastiCache Subnet Group ===
echo "📌 Creating ElastiCache Subnet Group..."
aws elasticache create-cache-subnet-group \
    --cache-subnet-group-name "$SUBNET_GROUP_NAME" \
    --cache-subnet-group-description "Subnet group for caching lab" \
    --subnet-ids $(echo $SUBNET_IDS | tr "," " ") \
    --region "$REGION"

# === STEP 3: Create Memcached ElastiCache Cluster ===
echo "🚀 Creating ElastiCache Cluster..."
aws elasticache create-cache-cluster \
    --cache-cluster-id "$CLUSTER_NAME" \
    --engine memcached \
    --cache-node-type cache.t2.micro \
    --num-cache-nodes 3 \
    --port 11211 \
    --cache-subnet-group-name "$SUBNET_GROUP_NAME" \
    --security-group-ids "$SECURITY_GROUP_ID" \
    --region "$REGION"

echo "✅ ElastiCache cluster '$CLUSTER_NAME' is being created. It may take a few minutes."

# === STEP 4: Configure S3 for CloudFront caching ===
echo "☁️ Applying cache-control metadata to S3 objects..."

aws s3 cp "s3://$S3_BUCKET/" "s3://$S3_BUCKET/" \
    --recursive \
    --metadata-directive REPLACE \
    --cache-control max-age=180 \
    --region "$REGION"

echo "✅ S3 metadata updated with Cache-Control: max-age=180"

# === STEP 5: Reminder to Configure CloudFront ===
echo "🧭 Please complete CloudFront setup manually:"
echo "   1. Go to AWS Console > CloudFront > Create Distribution"
echo "   2. Set origin as your S3 bucket ($S3_BUCKET)"
echo "   3. Enable caching behavior and default TTL (e.g., 180 seconds)"
echo "   4. Deploy and wait until status is 'Deployed'"
echo "   5. Access the website via the CloudFront domain"

# === Optional: Verify Headers with curl (requires public URL) ===
read -p "Enter your CloudFront domain (optional for curl check): " CLOUDFRONT_URL

if [ ! -z "$CLOUDFRONT_URL" ]; then
  echo "🧪 Checking Cache Headers..."
  curl -I "$CLOUDFRONT_URL" | grep -iE "cache-control|x-cache"
fi
