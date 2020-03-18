# Alcide Audit Analyzer - AWS EKS Audit Log Setup

In order to consume EKS logs Alcide Audit Analyzer needs some additional configuration of on the AWS account(s). <br />
The following example will deploy two AWS CloudFormation stacks which will provision the required infrastructure for consuming EKS logs with Alcide Audit Analyzer. The following setup assumes a scenario in which logs are shipped from the EKS cluster account to a seperate (logs account) from which Audit Analyzer will consume them. This setup will also works in cases where CloudWatch EKS logs and kinesis are in the same account<br />

**Notice:** Turning on EKS logging is currently not available in CloudFormation. This should be done by AWS cli (covered in this guide), or console.

the following resources will be created by this CloudFormation stacks:<br />
EKS account:
  - CloudWatch logs subscription filter with destination in the Logs account

Logs account:
  - CloudWatch logs destination with Kinesis stream target
  - Kinesis stream
  - IAM user with read access to the Kinesis stream
  - relevant IAM roles and policies


---
### Configuration

> the source (EKS) account id is required

It is suggested (but not mandatory) to name the CloudFormation stacks after the EKS cluster name. This can be very helpful when trying to determine which resources belongs to which audit log stream.  


#### Audit Analyzer Account

  * deploy the CloudFormation stack
  > SourceAccount is the only mandatory parameter. the rest will be used for tagging the resources created by this stack <br />

    ```
    AWS_PROFILE=<logs account profile name> AWS_REGION=<AWS region> aws cloudformation create-stack --stack-name <eks cluster name> /
    --template-body file://PATH/TO/AUDIT-ANALYZER/CLOUDFORMATION/logsAccount.json /
    --capabilities CAPABILITY_IAM /
    --parameters ParameterKey="SourceAccount",ParameterValue="<EKS Account ID>" \
                 ParameterKey="ApplicationComponent",ParameterValue="audit-analyzer" \
                 ParameterKey="ApplicationOwner",ParameterValue="<OWNER>" \
    --tags "Key=alcide,Value=audit-analyzer" "Key=stage,Value=<STAGE>" \
            "Key=owner,Value=<OWNER>"
    ```
  * get the logs destination's ARN (required for the next step), and the IAM user to use with Audit-Analyzer

    ```
    AWS_PROFILE=<logs account profile name> AWS_REGION=<AWS region> aws cloudformation describe-stacks --stack-name <eks cluster name> \
    --query "Stacks[].Outputs[*]" --output json
    ```
---
### EKS account

  * Turn on EKS logging
    > \* This option is not available in CloudFormation yet

    ```
    AWS_PROFILE=<eks account profile name> AWS_REGION=<AWS region> aws eks \
        update-cluster-config \
        --name <Cluster Name> \
        --logging '{"clusterLogging":[{"types":["audit"],"enabled":true}]}')
    ```

  * deploy the CloudFormation stack
    > DestinationARN and EKSClusterName are mandatory paramater.<br />

    ```
    AWS_PROFILE=<eks account profile name> AWS_REGION=<AWS region> aws cloudformation create-stack --stack-name <eks cluster name> /
    --template-body file://PATH/TO/AUDIT-ANALYZER/CLOUDFORMATION/eksAccount.json /
    --parameters ParameterKey="DestinationARN",ParameterValue="<Logs Destination ARN>" \
                 ParameterKey="EKSClusterName",ParameterValue="<eks cluster name>" \
    --tags "Key=alcide,Value=audit-analyzer" "Key=stage,Value=<STAGE>" \
            "Key=owner,Value=<OWNER>"
    ```
---
### verification
after the setups is complete it is possible to view the messages on the kinesis stream.
  ```
    SHARD_ITERATOR=$(AWS_PROFILE=<logs account profile name> AWS_REGION=<AWS region> aws kinesis get-shard-iterator \
    --shard-id shardId-000000000000 \
    --shard-iterator-type TRIM_HORIZON \
    --stream-name <eks cluster name>-Stream \
    --query 'ShardIterator')
  ```
  ```
    AWS_PROFILE=<logs account profile name> AWS_REGION=<AWS region> aws kinesis get-records --shard-iterator $SHARD_ITERATOR --limit 10 | jq
  ```

  The Kinesis record is Base64 encoded and compressed in gzip format. The record’s actual
  content of a message can be decoded
  ```
    echo -n '<Content of Data>' | base64 -d | zcat
  ```
---

### Audit Analyzer

installation of Audit Analyzer should be preformed according to documentation.
Access-Key-ID, Access-Key-Secret and Kinesis stream name which are required in order to complete the installation process can be obtained from the logsAccount CloudFormation stack outputs.
```
  AWS_PROFILE=<logs account profile name> AWS_REGION=<AWS region> aws cloudformation describe-stacks --stack-name <eks cluster name> \
  --query "Stacks[].Outputs[*]" --output json
```
