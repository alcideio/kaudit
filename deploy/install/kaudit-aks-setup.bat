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
REM EventHub name - using the default (i.e. same as the EventHubs NameSpace)
SET EVENT_HUB=%EVENT_HUBS_NAMESPACE%
REM EventHubs Namespace Authorization Rule name: Using the default rule
SET EVENT_HUBS_NAMESPACE_MANAGE_AUTH_RULE=RootManageSharedAccessKey
REM SET EVENT_HUBS_NAMESPACE_MANAGE_AUTH_RULE=RootManageSharedAccessKey-%AKS_CLUSTER_NAME%
REM EventHub Authorization Rule name
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

REM  3. Create Authorization Rule with Manage,Send,Listen rights on EventHubs Namespace
REM Using default EventHubs Namespace Authorization Rule
REM call az eventhubs namespace authorization-rule create ^
REM   -n %EVENT_HUBS_NAMESPACE_MANAGE_AUTH_RULE% ^
REM   --namespace-name %EVENT_HUBS_NAMESPACE% ^
REM   -g %RESOURCE_GROUP% ^
REM   --rights Manage Send Listen

REM  4. Create Authorization Rule with Listen rights on EventHub
call az eventhubs eventhub authorization-rule create ^
   -n %EVENT_HUB_LISTEN_AUTH_RULE% ^
   --eventhub-name %EVENT_HUB% ^
   --namespace-name %EVENT_HUBS_NAMESPACE% ^
   -g %RESOURCE_GROUP% ^
   --rights Listen

REM  4. Send k8s audit log from the AKS cluster, using the configured Authorization Rule, to created EventHub
call az monitor diagnostic-settings create ^
   -n %DIAGNOSTICS_SETTINGS% ^
   --resource %AKS_CLUSTER_NAME% ^
   --resource-type microsoft.containerservice/managedclusters ^
   -g %RESOURCE_GROUP% ^
   --event-hub %EVENT_HUBS_NAMESPACE% ^
   --event-hub-rule %EVENT_HUBS_NAMESPACE_MANAGE_AUTH_RULE% ^
   --logs "[ { \"category\": \"kube-audit\", \"enabled\": true } ]"

REM  6. Get credential keys for EventHub

echo Parameters for kAudit setup:
echo ---------------------------
echo EventHub name: ${EVENT_HUB}
echo EventHub credentials:
call az eventhubs eventhub authorization-rule keys list ^
   -n %EVENT_HUB_LISTEN_AUTH_RULE% ^
   -g %RESOURCE_GROUP% ^
   --namespace-name %EVENT_HUBS_NAMESPACE% ^
   --eventhub-name %EVENT_HUB%

echo.
echo AKS Audit Log Setup for Alcide kAudit complete!
echo Please follow Alcide kAudit installation guide to verify the AKS setup and integrate with kAudit.

:EOF