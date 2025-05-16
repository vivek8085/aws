#!/bin/bash

# === Prompt for User Input ===
read -p "Enter your S3 bucket name: " S3_BUCKET
# ===Enter your Lambda execution role ARN: arn:aws:iam::123456789012:role/lambda-basic-role
read -p "Enter your Lambda execution role ARN: " LAMBDA_ROLE_ARN

REGION="us-east-1"
ZIP_NAME="get_all_products_code.zip"
FUNCTION_NAME="get_all_products"

# === 1. Download code.zip ===
echo "🔽 Downloading code.zip..."
wget "https://aws-tc-largeobjects.s3.us-west-2.amazonaws.com/CUR-TF-200-ACCDEV-2-91558/05-lab-lambda/code.zip" -P /home/ec2-user/environment

# === 2. Unzip it ===
cd /home/ec2-user/environment || exit
unzip -o code.zip
cd python_3 || exit

# === 3. Create Lambda function code ===
echo "📝 Writing Lambda code..."
cat <<EOF > get_all_products_code.py
import boto3
import json

dynamodb = boto3.client('dynamodb')
TABLE_NAME = 'FoodProducts'

def lambda_handler(event, context):
    response = dynamodb.scan(TableName=TABLE_NAME)
    items = response['Items']
    return {
        "statusCode": 200,
        "body": json.dumps(items)
    }
EOF

# === 4. Zip the Lambda function ===
zip $ZIP_NAME get_all_products_code.py

# === 5. Upload to S3 ===
echo "☁️ Uploading code to S3 bucket: $S3_BUCKET"
aws s3 cp $ZIP_NAME s3://$S3_BUCKET/

# === 6. Create Boto3 wrapper ===
echo "🔧 Creating Boto3 wrapper script..."
cat <<EOF > get_all_products_wrapper.py
import boto3

client = boto3.client('lambda', region_name='$REGION')

response = client.create_function(
    FunctionName='$FUNCTION_NAME',
    Runtime='python3.12',
    Role='$LAMBDA_ROLE_ARN',
    Handler='get_all_products_code.lambda_handler',
    Code={
        'S3Bucket': '$S3_BUCKET',
        'S3Key': '$ZIP_NAME'
    },
    Description='Lambda created via automated script',
    Timeout=15,
    MemorySize=128,
    Publish=True
)

print("✅ Lambda Function ARN:", response['FunctionArn'])
EOF

# === 7. Deploy the Lambda function ===
echo "🚀 Deploying Lambda function..."
python3 get_all_products_wrapper.py

# === 8. Cleanup (optional) ===
echo "🧹 Cleaning up..."
rm $ZIP_NAME get_all_products_code.py get_all_products_wrapper.py

echo "✅ Lambda function '$FUNCTION_NAME' created and deployed successfully."
