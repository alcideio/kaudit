@echo off
setlocal

REM ######################################################
REM #       AKS Audit Log Setup for Alcide kAudit        #
REM ######################################################

REM mandatory user-defined script parameters
REM may be provided in the command line: -AKS_CLUSTER_NAME cluster-name -RESOURCE_GROUP resource-group -LOCATION location
REM ----------------------------------------
REM Resource Group of AKS cluster
SET RESOURCE_GROUP=
REM Location of AKS cluster, for example: eastus
SET LOCATION=
REM AKS cluster name
SET AKS_CLUSTER_NAME=

echo AKS Audit Log Setup for Alcide kAudit

set ARGSSET=%RESOURCE_GROUP%%LOCATION%%AKS_CLUSTER_NAME%%1
if "x%ARGSSET%"=="x" (
  echo Command line options^: -RESOURCE_GROUP=^<resource group^> -AKS_CLUSTER_NAME=^<AKS-cluster name^> -LOCATION=^<location^>
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

REM  0. validate user-provided parameters
if "x%RESOURCE_GROUP%"=="x" (
  echo Resource group is not configured
  goto EOF
)

if "x%LOCATION%"=="x" (
  echo Location is not configured
  goto EOF
)

if "x%AKS_CLUSTER_NAME%"=="x" (
  echo AKS cluster name is not configured
  goto EOF
)


REM optional script parameters, can leave default values
REM ----------------------------------------------------
REM EventHubs Namespace name
SET EVENT_HUBS_NAMESPACE=kaudit-eh-%AKS_CLUSTER_NAME%
REM EventHub name
SET EVENT_HUB=kaudit-eh-k8saudit-%EVENT_HUBS_NAMESPACE%
REM EventHub manage Authorization Rule name
SET EVENT_HUBS_NAMESPACE_MANAGE_AUTH_RULE=k8s-audit-manage-%AKS_CLUSTER_NAME%
REM EventHub listen Authorization Rule name
SET EVENT_HUB_LISTEN_AUTH_RULE=k8s-audit-listen-%AKS_CLUSTER_NAME%
REM Diagnostics Settings name
SET DIAGNOSTICS_SETTINGS=k8s-audit-%AKS_CLUSTER_NAME%

echo Preparing EventHub %EVENT_HUBS_NAMESPACE%/%EVENT_HUB% for AKS cluster %AKS_CLUSTER_NAME% in resource group %RESOURCE_GROUP%, location %LOCATION%


REM  1. create EventHubs Namespace
call az eventhubs namespace create ^
   -n %EVENT_HUBS_NAMESPACE% ^
   -g %RESOURCE_GROUP% ^
   -l %LOCATION% ^
   --enable-kafka false ^
   --sku Basic

REM  2. Create EventHub
call az eventhubs eventhub create ^
   -n %EVENT_HUB% ^
   --namespace-name %EVENT_HUBS_NAMESPACE% ^
   -g %RESOURCE_GROUP% ^
   --message-retention 1 ^
   --partition-count 2

REM  3. Create Authorization Rule with Manage,Send,Listen rights on EventHub Namespace
for /f %%i in ('az eventhubs namespace authorization-rule create ^
   -n %EVENT_HUBS_NAMESPACE_MANAGE_AUTH_RULE% ^
   --namespace-name %EVENT_HUBS_NAMESPACE% ^
   -g %RESOURCE_GROUP% ^
   --rights Manage Send Listen ^
   --query id ^
   -o tsv') do set MANAGE_RULE_ID=%%i

REM  4. Create Authorization Rule with Listen rights on EventHub
call az eventhubs eventhub authorization-rule create ^
   -n %EVENT_HUB_LISTEN_AUTH_RULE% ^
   --eventhub-name %EVENT_HUB% ^
   --namespace-name %EVENT_HUBS_NAMESPACE% ^
   -g %RESOURCE_GROUP% ^
   --rights Listen

REM  5. Send k8s audit log from the AKS cluster, using the configured Authorization Rule, to created EventHub
call az monitor diagnostic-settings create ^
   -n %DIAGNOSTICS_SETTINGS% ^
   --resource %AKS_CLUSTER_NAME% ^
   --resource-type microsoft.containerservice/managedclusters ^
   -g %RESOURCE_GROUP% ^
   --event-hub %EVENT_HUB% ^
   --event-hub-rule %MANAGE_RULE_ID% ^
   --logs "[ { \"category\": \"kube-audit\", \"enabled\": true } ]"

REM  6. Get credential keys for EventHub

echo Parameters for kAudit setup
echo ---------------------------
echo EventHub name: %EVENT_HUB%
echo EventHub connection string:
call az eventhubs eventhub authorization-rule keys list ^
   -n %EVENT_HUB_LISTEN_AUTH_RULE% ^
   -g %RESOURCE_GROUP% ^
   --namespace-name %EVENT_HUBS_NAMESPACE% ^
   --eventhub-name %EVENT_HUB% ^
   --query primaryConnectionString ^
   -o tsv

echo.
echo AKS Audit Log Setup for Alcide kAudit complete!
echo Please follow Alcide kAudit installation guide to verify the AKS setup and integrate with kAudit.

:EOF