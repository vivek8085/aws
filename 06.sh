#!/bin/bash

# ========= USER INPUT =========
read -p "Enter your MySQL root password: " MYSQL_ROOT_PASSWORD
read -p "Enter the name for your Node.js Docker image: " NODE_IMAGE
read -p "Enter the name for your MySQL Docker image: " MYSQL_IMAGE
read -p "Enter your AWS ECR Repository Name for Node.js App: " ECR_NODE_REPO
read -p "Enter your AWS ECR Repository Name for MySQL: " ECR_MYSQL_REPO
read -p "Enter your AWS Region (e.g., us-east-1): " REGION
read -p "Enter your AWS Account ID: " ACCOUNT_ID

# ========= DIRECTORIES =========
mkdir -p ~/docker_migration/{node_app,mysql_db}
cd ~/docker_migration || exit

# ========= SETUP NODE.JS APP =========
echo "📁 Setting up Node.js app..."
cat <<EOF > node_app/app.js
const express = require('express');
const mysql = require('mysql');
const app = express();
const port = 3000;

const connection = mysql.createConnection({
  host: process.env.APP_DB_HOST || 'localhost',
  user: 'root',
  password: '$MYSQL_ROOT_PASSWORD',
  database: 'COFFEE'
});

connection.connect();

app.get('/', (req, res) => {
  connection.query('SELECT * FROM menu', (err, results) => {
    if (err) throw err;
    res.json(results);
  });
});

app.listen(port, () => console.log(\`Node app running on port \${port}\`));
EOF

cat <<EOF > node_app/package.json
{
  "name": "coffee-app",
  "version": "1.0.0",
  "main": "app.js",
  "dependencies": {
    "express": "^4.17.1",
    "mysql": "^2.18.1"
  }
}
EOF

cat <<EOF > node_app/Dockerfile
FROM node:alpine
WORKDIR /app
COPY . .
RUN npm install
EXPOSE 3000
CMD ["node", "app.js"]
EOF

# ========= SETUP MYSQL =========
echo "📁 Setting up MySQL DB..."
cat <<EOF > mysql_db/my_sql.sql
CREATE DATABASE IF NOT EXISTS COFFEE;
USE COFFEE;
CREATE TABLE menu (
  id INT AUTO_INCREMENT PRIMARY KEY,
  item_name VARCHAR(255),
  price FLOAT
);
INSERT INTO menu (item_name, price) VALUES ('Espresso', 3.0), ('Latte', 4.0), ('Mocha', 4.5);
EOF

cat <<EOF > mysql_db/Dockerfile
FROM mysql:5.7
ENV MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
COPY my_sql.sql /docker-entrypoint-initdb.d/
EXPOSE 3306
EOF

# ========= BUILD & RUN CONTAINERS =========
echo "🐳 Building Docker images..."
cd node_app && docker build -t $NODE_IMAGE . && cd ..
cd mysql_db && docker build -t $MYSQL_IMAGE . && cd ..

echo "🚀 Running MySQL container..."
docker run -d --name mysql_db_1 -p 3306:3306 $MYSQL_IMAGE

MYSQL_CONTAINER_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' mysql_db_1)
echo "✅ MySQL running at $MYSQL_CONTAINER_IP"

echo "🚀 Running Node.js container connected to MySQL..."
docker run -d --name node_app_1 -p 3000:3000 -e APP_DB_HOST=$MYSQL_CONTAINER_IP $NODE_IMAGE

echo "🌐 Visit http://<your-ec2-ip>:3000 to access the app (make sure port 3000 is open in EC2 security group)"

# ========= PUSH TO ECR =========
echo "🔐 Logging into Amazon ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

echo "📦 Creating repositories (if not exists)..."
aws ecr describe-repositories --repository-names $ECR_NODE_REPO > /dev/null 2>&1 || aws ecr create-repository --repository-name $ECR_NODE_REPO
aws ecr describe-repositories --repository-names $ECR_MYSQL_REPO > /dev/null 2>&1 || aws ecr create-repository --repository-name $ECR_MYSQL_REPO

NODE_REPO_URL="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_NODE_REPO"
MYSQL_REPO_URL="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_MYSQL_REPO"

echo "🏷️ Tagging Docker images..."
docker tag $NODE_IMAGE $NODE_REPO_URL:latest
docker tag $MYSQL_IMAGE $MYSQL_REPO_URL:latest

echo "📤 Pushing to ECR..."
docker push $NODE_REPO_URL:latest
docker push $MYSQL_REPO_URL:latest

echo "✅ Docker images successfully pushed to ECR."
