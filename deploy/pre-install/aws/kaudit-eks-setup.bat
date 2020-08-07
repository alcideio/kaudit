@echo off
setlocal

REM ######################################################
REM #       EKS Audit Log Setup for Alcide kAudit        #
REM ######################################################

REM mandatory user-defined script parameters
REM may be provided in the command line: -CLOUDWATCH_ACCOUNT_ID CloudWatch-account-id -KINESIS_ACCOUNT_ID Kinesis-account-id -CLUSTER_NAME EKS-cluster-name -REGION region
REM ----------------------------------------
REM AWS REGION
SET REGION=
REM EKS cluster name
SET CLUSTER_NAME=
REM CloudWatch account ID
SET CLOUDWATCH_ACCOUNT_ID=
REM Kinesis account ID, may or may not be the same as the CloudWatch account ID
SET KINESIS_ACCOUNT_ID=

echo EKS Audit Log Setup for Alcide kAudit

set ARGSSET=%REGION%%CLUSTER_NAME%%CLOUDWATCH_ACCOUNT_ID%%1
if "x%ARGSSET%"=="x" (
  echo Command line options^: -CLOUDWATCH_ACCOUNT_ID=^<CloudWatch ^(sending^) account-id^> -KINESIS_ACCOUNT_ID=^<Kinesis ^(receiving^) account-id, defaults to CloudWatch account^> -CLUSTER_NAME=^<EKS-cluster name^> -REGION=^<region^>
  goto EOF
)

REM Given command line args - parse them:
:argsinitial
if "%1"=="" goto argsdone
set aux=%1
if "%aux:~0,1%"=="-" (
   set nome=%aux:~1,250%
) else (
   set "%nome%=%1"
   set nome=
)
shift
goto argsinitial
:argsdone

REM 0. validate user-provided parameters
if "x%CLOUDWATCH_ACCOUNT_ID%"=="x" (
  echo CloudWatch account ID is not configured
  goto EOF
)

if "x%REGION%"=="x" (
  echo Region is not configured
  goto EOF
)

if "x%CLUSTER_NAME%"=="x" (
  echo EKS cluster name is not configured
  goto EOF
)

if "x%KINESIS_ACCOUNT_ID%"=="x" (
  echo Kinesis account ID is the same as CloudWatch account ID
  SET KINESIS_ACCOUNT_ID=%CLOUDWATCH_ACCOUNT_ID%
)

REM optional script parameters, can leave default values
REM name of Kinesis stream
SET STREAM_NAME=KAuditStream-%CLUSTER_NAME%
REM name of Kinesis destination
SET DESTINATION_NAME=kAuditLogsDestination-%CLUSTER_NAME%
REM name of Kinesis filter
SET STREAM_FILTER_NAME=KAuditStreamFilter-%CLUSTER_NAME%
REM name of role used to send from CloudWatch to Kinesis
SET SENDING_ROLE_NAME=CWLtoKinesisRole-%CLUSTER_NAME%
REM name of policy for sendingm in CloudWatch account
SET PERMISSION_POLICY_FOR_ROLE_NAME=Permissions-Policy-For-CWL-%CLUSTER_NAME%
REM name of kAudit user, used to read from Kinesis
SET KAUDIT_USER_NAME=KAuditReadKinesis-%STREAM_NAME%
REM name of kAudit user policy
SET PERMISSION_POLICY_FOR_KAUDIT_USER_NAME=Permissions-Policy-For-%KAUDIT_USER_NAME%
REM name uninstall script
SET UNINSTALL_SCRIPT_FILE=kaudit-eks-uninstall-%CLUSTER_NAME%.bat
REM name validation script
SET VALIDATION_SCRIPT_FILE=kaudit-eks-validation-%CLUSTER_NAME%.bat

REM Variables that should not be changed
REM CloudWatch EKS audit log group
SET LOG_GROUP_NAME=/aws/eks/%CLUSTER_NAME%/cluster
REM Kinesis filter pattern
SET FILTER_PATTERN=""

echo Preparing Kinesis Stream %STREAM_NAME% at account %KINESIS_ACCOUNT_ID% for EKS cluster %CLUSTER_NAME% in region %REGION% and account %CLOUDWATCH_ACCOUNT_ID%

REM 1. enable cluster audit log
echo enable audit logging of EKS cluster: %CLUSTER_NAME% region %REGION%

REM TODO: check if cluster audit logging already enabled

aws eks ^
  --region %REGION% ^
  update-cluster-config ^
  --name %CLUSTER_NAME% ^
  --logging "{\"clusterLogging\":[{\"types\":[\"audit\"],\"enabled\":true}]}"

REM TODO if audit logging needed to be enabled, check that the command succeeded

timeout 10 > NUL

REM 2. create Kinesis Stream
echo creating Kinesis Stream: %STREAM_NAME%

aws kinesis ^
    create-stream ^
    --region %REGION% ^
    --stream-name %STREAM_NAME% ^
    --shard-count 1

REM TODO validate stream created before additional operations on it: creating destination, destination policy, destination filter
if not %errorlevel% EQU 0 (
  echo FAILED
  goto UNINSTALLER
)

REM 3. create Role that will be used for putting filtered records from CloudWatch, the cluster audit entries, on the Kinesis Stream
echo creating role %SENDING_ROLE_NAME% that can be assumed by CloudWatch for putting records on Kinesis Stream

echo { ^
  "Statement": { ^
    "Effect": "Allow", ^
    "Principal": { "Service": "logs.%REGION%.amazonaws.com" }, ^
    "Action": "sts:AssumeRole" ^
  } ^
} > TrustPolicyForCWL.json
aws iam ^
    create-role ^
    --role-name %SENDING_ROLE_NAME% ^
    --assume-role-policy-document file://TrustPolicyForCWL.json
if not %errorlevel% EQU 0 (
  echo FAILED
  goto UNINSTALLER
)
SET CLOUDWATCH_ROLE_ARN=arn:aws:iam::%KINESIS_ACCOUNT_ID%:role/%SENDING_ROLE_NAME%

REM 4. create Policy for the Role that will be used for putting filtered records from CloudWatch, the cluster audit entries, on the Kinesis Stream

REM Waiting for Stream to be active and Role to exist
timeout 30 > NUL

echo creating policy %PERMISSION_POLICY_FOR_ROLE_NAME% for role %SENDING_ROLE_NAME% to enable it to put filtered records from CloudWatch on the Kinesis Stream

echo { ^
  "Statement": [ ^
    { ^
      "Effect": "Allow", ^
      "Action": "kinesis:PutRecord", ^
      "Resource": "arn:aws:kinesis:%REGION%:%KINESIS_ACCOUNT_ID%:stream/%STREAM_NAME%" ^
    } ^
  ] ^
} > PermissionsForCWL.json
aws iam ^
    put-role-policy ^
    --role-name %SENDING_ROLE_NAME% ^
    --policy-name %PERMISSION_POLICY_FOR_ROLE_NAME% ^
    --policy-document file://PermissionsForCWL.json
if not %errorlevel% EQU 0 (
  echo FAILED
  goto UNINSTALLER
)

REM Waiting for Policy
timeout 30 > NUL

REM SET KINESIS_ROLE_ARN=arn:aws:iam::%KINESIS_ACCOUNT_ID%:role/%SENDING_ROLE_NAME%

REM 5. create Kinesis Stream Destination

echo creating Kinesis stream destination %DESTINATION_NAME% on stream %STREAM_NAME%

aws logs ^
    put-destination ^
    --region %REGION% ^
    --destination-name %DESTINATION_NAME% ^
    --target-arn arn:aws:kinesis:%REGION%:%KINESIS_ACCOUNT_ID%:stream/%STREAM_NAME% ^
    --role-arn %CLOUDWATCH_ROLE_ARN%
if not %errorlevel% EQU 0 (
  echo FAILED
  goto UNINSTALLER
)
SET DESTINATION_ARN=arn:aws:logs:%REGION%:%KINESIS_ACCOUNT_ID%:destination:%DESTINATION_NAME%

REM 6. create policy for the CloudWatch account on the Kinesis Stream destination

echo creating policy for to enable %CLOUDWATCH_ACCOUNT_ID% to set Kinesis subscription filter on destination %DESTINATION_NAME% of stream %STREAM_NAME%

echo { ^
  "Statement" : [ ^
    { ^
      "Sid" : "", ^
      "Effect" : "Allow", ^
      "Principal" : { ^
        "AWS" : "%CLOUDWATCH_ACCOUNT_ID%" ^
      }, ^
      "Action" : "logs:PutSubscriptionFilter", ^
      "Resource" : "%DESTINATION_ARN%" ^
    } ^
  ] ^
} > AccessPolicy.json
aws logs ^
    put-destination-policy ^
    --region %REGION% ^
    --destination-name %DESTINATION_NAME% ^
    --access-policy file://AccessPolicy.json
if not %errorlevel% EQU 0 (
  echo FAILED
  goto UNINSTALLER
)

REM 7. create Kinesis Stream subscription filter from the CloudWatch cluster audit to the Kinesis stream destination

echo creating Kinesis subscription filter on destination %DESTINATION_NAME% of stream %STREAM_NAME%

if not "%KINESIS_ACCOUNT_ID%"=="%CLOUDWATCH_ACCOUNT_ID%" (
  aws logs ^
      put-subscription-filter ^
      --region %REGION% ^
      --log-group-name %LOG_GROUP_NAME% ^
      --filter-name %STREAM_FILTER_NAME% ^
      --filter-pattern "%FILTER_PATTERN%" ^
      --destination-arn %DESTINATION_ARN% ^
      --role-arn %CLOUDWATCH_ROLE_ARN%
) else (
  aws logs ^
    put-subscription-filter ^
    --region %REGION% ^
    --log-group-name %LOG_GROUP_NAME% ^
    --filter-name %STREAM_FILTER_NAME% ^
    --filter-pattern %FILTER_PATTERN% ^
    --destination-arn %DESTINATION_ARN%
)
if not %errorlevel% EQU 0 (
  echo FAILED
  goto UNINSTALLER
)

REM 8. create User that will be used by kAudit to read from the Kinesis Stream
echo creating role %KAUDIT_USER_NAME% that will be used by kAudit to read from the Kinesis Stream

aws iam ^
    create-user ^
    --user-name %KAUDIT_USER_NAME%
if not %errorlevel% EQU 0 (
  echo FAILED
  goto UNINSTALLER
)

echo { ^
  "Statement": [ ^
    { ^
      "Effect": "Allow", ^
      "Action": ["kinesis:GetRecords", "kinesis:GetShardIterator"], ^
      "Resource": "arn:aws:kinesis:%REGION%:%KINESIS_ACCOUNT_ID%:stream/%STREAM_NAME%" ^
    } ^
  ] ^
} > PermissionsForKinesisRead.json
aws iam ^
    put-user-policy ^
    --user-name %KAUDIT_USER_NAME% ^
    --policy-name %PERMISSION_POLICY_FOR_KAUDIT_USER_NAME% ^
    --policy-document file://PermissionsForKinesisRead.json

if not %errorlevel% EQU 0 (
  echo FAILED
  goto UNINSTALLER
)

REM 9. report setup configuration
echo Parameters for kAudit setup:
echo ---------------------------
echo user credentials:
aws iam ^
    create-access-key ^
    --user-name %KAUDIT_USER_NAME%

if not %errorlevel% EQU 0 (
  echo FAILED
  goto UNINSTALLER
)

echo region=%REGION%
echo kinesis stream name=%STREAM_NAME%

echo EKS Audit Log Setup for Alcide kAudit complete!
echo Please follow Alcide kAudit installation guide to verify the EKS setup and integrate with kAudit.

REM 10. create validation script
(
echo @echo off
echo setlocal
echo FOR /F "tokens=*" %%%%g IN ^('aws kinesis ^^
echo       get-shard-iterator ^^
echo       --region %REGION% ^^
echo       --stream-name %STREAM_NAME% ^^
echo       --shard-id shardId-000000000000 ^^
echo       --shard-iterator-type TRIM_HORIZON ^^
echo       --output text ^^
echo       --query "ShardIterator"'^) DO set result=%%%%g
echo echo stream %STREAM_NAME% shard iterator "%%result%%"
echo aws kinesis get-records ^^
echo       --region %REGION% ^^
echo       --limit 2 ^^
echo       --shard-iterator "%%result%%"
) > "%VALIDATION_SCRIPT_FILE%"

:UNINSTALLER
REM 11. create uninstall script

(
echo @echo off
echo setlocal
echo SET KAUDIT_ACCESS_KEY_ID=
echo :argsinitial
echo if "%%1"=="" goto argsdone
echo set aux=%%1
echo if "%%aux:~0,1%%"=="-" ^(
echo    set nome=%%aux:~1,250%%
echo ^) else ^(
echo    set "%%nome%%=%%1"
echo    set nome=
echo ^)
echo shift
echo goto argsinitial
echo :argsdone
echo aws eks ^^
echo    --region %REGION% ^^
echo    update-cluster-config ^^
echo    --name %CLUSTER_NAME% ^^
echo    --logging "{\"clusterLogging\":[{\"types\":[\"audit\"],\"enabled\":false}]}"
echo aws logs ^^
echo    delete-subscription-filter ^^
echo    --region %REGION% ^^
echo    --log-group-name %LOG_GROUP_NAME% ^^
echo    --filter-name %STREAM_FILTER_NAME%
echo aws logs ^^
echo    delete-destination ^^
echo    --region %REGION% ^^
echo    --destination-name %DESTINATION_NAME%
echo aws kinesis ^^
echo    delete-stream ^^
echo    --region %REGION% ^^
echo    --stream-name %STREAM_NAME%
echo aws iam ^^
echo    delete-role-policy ^^
echo    --role-name %SENDING_ROLE_NAME% ^^
echo    --policy-name %PERMISSION_POLICY_FOR_ROLE_NAME%
echo aws iam ^^
echo    delete-role ^^
echo    --role-name %SENDING_ROLE_NAME%
echo aws iam ^^
echo    delete-user-policy ^^
echo    --user-name %KAUDIT_USER_NAME% ^^
echo    --policy-name %PERMISSION_POLICY_FOR_KAUDIT_USER_NAME%
echo if "%%KAUDIT_ACCESS_KEY_ID%%"=="" ^(
echo   echo Skipping deletion of access key and user, to delete re-run with argument: -KAUDIT_ACCESS_KEY_ID=^^^<key ID^^^>
echo ^) else ^(
echo   aws iam ^^
echo      delete-access-key ^^
echo      --user-name %KAUDIT_USER_NAME% ^^
echo      --access-key-id %%KAUDIT_ACCESS_KEY_ID%%
echo   aws iam ^^
echo      delete-user ^^
echo      --user-name %KAUDIT_USER_NAME%
echo ^)
) > "%UNINSTALL_SCRIPT_FILE%"

echo Setup may be reverted using the script at: %UNINSTALL_SCRIPT_FILE%
echo Setup may be validated using the script at: %VALIDATION_SCRIPT_FILE%


:EOF