pipeline {
    agent any

    environment {
        AWS_REGION     = 'us-east-1'
        AWS_ACCOUNT_ID = 'REPLACE_WITH_YOUR_ACCOUNT_ID'
        ECR_REPO       = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/simple-cicd-app"
        EKS_CLUSTER    = 'simple-cicd-eks'
        IMAGE_TAG      = "${BUILD_NUMBER}"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                echo "Checked out build #${BUILD_NUMBER}"
            }
        }

        stage('Build Docker Image') {
            steps {
                sh """
                    cd app
                    docker build -t ${ECR_REPO}:${IMAGE_TAG} -t ${ECR_REPO}:latest .
                """
            }
        }

        stage('Push to ECR') {
            steps {
                sh """
                    aws ecr get-login-password --region ${AWS_REGION} | \
                        docker login --username AWS --password-stdin \
                        ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

                    docker push ${ECR_REPO}:${IMAGE_TAG}
                    docker push ${ECR_REPO}:latest
                """
            }
        }

        stage('Deploy to EKS') {
            steps {
                sh """
                    aws eks update-kubeconfig --region ${AWS_REGION} --name ${EKS_CLUSTER}

                    # Replace image placeholder with actual image
                    sed "s|IMAGE_PLACEHOLDER|${ECR_REPO}:${IMAGE_TAG}|g; s|VERSION_PLACEHOLDER|${IMAGE_TAG}|g" \
                        k8s/app-deployment.yaml | kubectl apply -f -

                    kubectl rollout status deployment/myapp -n myapp --timeout=120s

                    echo "=== Deployment Complete ==="
                    kubectl get pods -n myapp
                    kubectl get svc myapp -n myapp
                """
            }
        }
    }

    post {
        success { echo "Pipeline SUCCESS — Build #${BUILD_NUMBER} deployed!" }
        failure { echo "Pipeline FAILED — Check logs above" }
    }
}
