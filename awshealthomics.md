# nf-core/rarevariantburden (CoCoRV-nf): AWSHealthOmics Implementation

## Introduction

This documentation will guide you how to implement **nf-core/rarevariantburden (CoCoRV-nf)** pipeline on AWS HealthOmics cloud platform.

## Prerequisites

1. Have a Amazon AWS account (visit https://aws.amazon.com/ to create an account and login)
2. AWS CLI v2 installed and configured
3. Appropriate IAM permissions for ECR and HealthOmics
4. Have a Docker Hub account (visit https://hub.docker.com/ to create an Docker Hub account)

## Regions

You should configure your ECR registry and HealthOmics workflows in the same region. If you will use multiple regions then repeat these steps in each region.

## Step 1: Create Secrets in Secrets Manager (For Authenticated Docker Hub Registries)

Some registries such as Docker Hub or private registries will require authentication. To use pull through cache, you must create a secret in Secrets Manager that contains the credentials for the Docker Hub registry. In these examples the region us-east-1 is specified. You should change this as needed.

To obtain a Docker Hub token refer to https://docs.docker.com/security/access-tokens/

To create a Secret for Docker Hub, run the following command:

```bash
aws secretsmanager create-secret \
    --name "ecr-pullthroughcache/docker-hub" \
    --description "Docker Hub credentials for ECR pull through cache" \
    --secret-string '{
        "username": "your-docker-username",
        "accessToken": "your-docker-access-token"
    }' \
    --region us-east-1
```

## Step 2: Create ECR Pull Through Cache Rules

Docker Hub Pull Through Cache (replace the 'YOUR-ACCOUNT-ID' text with you account id):

```bash
aws ecr create-pull-through-cache-rule \
    --ecr-repository-prefix docker-hub \
    --upstream-registry-url registry-1.docker.io \
    --credential-arn arn:aws:secretsmanager:us-east-1:YOUR-ACCOUNT-ID:secret:ecr-pullthroughcache/docker-hub-AbCdEf \
    --region us-east-1
```

## Step 3: Configure Registry Permissions

Create a registry permissions policy to allow HealthOmics to use pull through cache:

Create a file `registry-policy.json` and copy the following text in there (replace the 'YOUR-ACCOUNT-ID' text with you account id, if you want to give permission to any im-user then replace "YOUR-IM-USER" text with your im user id, if there is no im-user you can delete the im-user line):

```bash
{
  "Sid": "AllowPTCinRegPermissions",
  "Effect": "Allow",
  "Principal": {
    "AWS": [
      "arn:aws:iam::YOUR-ACCOUNT-ID:root",
      "arn:aws:iam::YOUR-ACCOUNT-ID:user/YOUR-IM-USER"
    ],
    "Service": "omics.amazonaws.com"
  },
  "Action": [
    "ecr:CreateRepository",
    "ecr:BatchImportUpstreamImage"
  ],
  "Resource": [
    "arn:aws:ecr:us-east-1:YOUR-ACCOUNT-ID:repository/*",
    "arn:aws:ecr:us-east-1:YOUR-ACCOUNT-ID:repository/ecr-public/*",
    "arn:aws:ecr:us-east-1:YOUR-ACCOUNT-ID:repository/docker-hub/*"
  ]
}
```

Apply the policy:

```bash
aws ecr put-registry-policy \
    --policy-text file://registry-policy.json \
    --region us-east-1
```

## Step 4: Create Repository Creation Templates

Docker Hub Template

```bash
aws ecr create-repository-creation-template \
    --prefix docker-hub \
    --applied-for PULL_THROUGH_CACHE \
    --repository-policy '{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Sid": "PTCRepoCreationTemplate",
          "Effect": "Allow",
          "Principal": {
            "AWS": [
              "arn:aws:iam::YOUR-ACCOUNT-ID:root",
              "arn:aws:iam::YOUR-ACCOUNT-ID:user/YOUR-IM-USER"
            ],
            "Service": "omics.amazonaws.com"
          },
          "Action": [
            "ecr:BatchGetImage",
            "ecr:GetDownloadUrlForLayer",
            "ecr:CreateRepository",
            "ecr:ReplicateImage",
            "ecr:TagResource"
          ]
        }
      ]
    }' \
    --region us-east-1
```

## Step 5: Configure HealthOmics Service Role

The HealthOmics service role used during workflow runs must have ECR permissions to pull container images from your pull through cache repositories.

Create Trust Policy File, copy the following text in a `trust-policy.json` file:

```bash
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "omics.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
```

Create Service Role Policy File, copy the following text in a `service-role-policy.json` file (replace 'YOUR-WORKFLOW-BUCKET' with a s3 bucket name under your account, you can use this bucket to create a folder for workflow input files, or to create a folder to save workflow output files):

```bash
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject"
            ],
            "Resource": [
                "arn:aws:s3:::YOUR-WORKFLOW-BUCKET/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::YOUR-WORKFLOW-BUCKET"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:DescribeLogStreams",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:CreateLogGroup"
            ],
            "Resource": [
                "arn:aws:logs:us-east-1:YOUR-ACCOUNT-ID:log-group:/aws/omics/WorkflowLog*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "ecr:BatchGetImage",
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchCheckLayerAvailability"
            ],
            "Resource": [
                "arn:aws:ecr:us-east-1:YOUR-ACCOUNT-ID:repository/docker-hub/*",
                "arn:aws:ecr:us-east-1:YOUR-ACCOUNT-ID:repository/quay/*",
                "arn:aws:ecr:us-east-1:YOUR-ACCOUNT-ID:repository/ecr-public/*"
            ]
        }
    ]
}
```

Create the Service Role:

```bash
aws iam create-role \
    --role-name HealthOmicsWorkflowRole \
    --assume-role-policy-document file://trust-policy.json \
    --description "Service role for HealthOmics workflows with container registry mappings"
```

Create the policy:

```bash
aws iam create-policy \
    --policy-name HealthOmicsWorkflowPolicy \
    --policy-document file://service-role-policy.json \
    --description "Policy for HealthOmics workflows with ECR pull through cache access"
```

Attach the policy:

```bash
aws iam attach-role-policy \
    --role-name HealthOmicsWorkflowRole \
    --policy-arn arn:aws:iam::YOUR-ACCOUNT-ID:policy/HealthOmicsWorkflowPolicy
```

## Step 6: Create nf-core/rarevariantburden (CoCoRV-nf) workflow

Pull the workflow code from github repository:

```bash
git clone https://github.com/nf-core/rarevariantburden.git
```

Compress the 'rarevariantburden' folder to create the zip file (rarevariantburden.zip).

Run the following command to create our workflow on AWS HealthOmics platform with name 'cocorv-nf':

```bash
aws omics create-workflow \
    --name cocorv-nf \
    --region us-east-1 \
    --definition-zip fileb://rarevariantburden.zip \
    --parameter-template file://rarevariantburden/aws.parameter.template.json \
    --container-registry-map file://rarevariantburden/aws.container-registry-map.json \
    --readme-markdown file://rarevariantburden/README.md \
    --engine NEXTFLOW \
    --no-verify-ssl
```

The create-workflow request responds with the following:

```bash
{
  "arn": "arn:aws:omics:us-east-1:....",
  "id": "1234567",
  "status": "CREATING",
  "tags": {
      "resourceArn": "arn:aws:omics:us-east-1:...."
  },
  "uuid": "64c9a39e-8302-cc45-0262-2ea7116d854f"
}
```

Now you can login to your AWS HealthOmics console and on the left panel, click on the 'Private workflows' tab, you will see a new workflow called 'cocorv-nf' is created there with status 'Active'.

## Step 7: Run the nf-core/rarevariantburden (CoCoRV-nf) workflow with our test files:

Click on the newly created workflow, it will open a window similar to this:

<picture align="center">
<img alt="AWS HealthOmics workflow launch page" src="images/aws-healthomics-workflow-launch-page.png">
</picture>

Click on the 'Start run' button, type a run name for your test run, select a s3 bucket to save the run output, and in the Service role section, choose the HeathOmics role we have created before (HealthOmicsWorkflowRole), click 'Next' to go to the next page. In the 'Add parameters value' section you can upload the test json file provided with the nf-core code base, `aws-testrun-parameters.json`. It will automatically fill all the necessary input parameters to run a test case, this is a test case containing 25 WGS samples from 1000 Genomes Project (you can check the test files for this test case from this public s3 bucket: s3://cocorv-1kg-grch37-data/). Click 'Next'. You can leave all the default settings in the 'Add run group, run cache and tags' section. Then go the final step 'Review and start run' and then start running the workflow.

After the run finished, you will see a run status page like this, which contains all the run information, output folder link, all the run logs link.

<picture align="center">
<img alt="AWS HealthOmics workflow complete page" src="images/aws-workflow-complete-page.png">
</picture>
