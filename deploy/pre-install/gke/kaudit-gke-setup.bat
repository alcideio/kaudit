@echo off
setlocal

REM ######################################################
REM #       GKE Audit Log Setup for Alcide kAudit        #
REM ######################################################

REM mandatory user-defined script parameters
REM may be provided in the command line: -GKE_PROJECT GKE-project -KEY_FILE_NAME output key file
REM GKE project
set GKE_PROJECT=
REM name of created file containing the credentials for the service account
set KEY_FILE_NAME=

echo GKE Audit Log Setup for Alcide kAudit

set ARGSSET=%GKE_PROJECT%%KEY_FILE_NAME%%1
if "x%ARGSSET%"=="x" (
  echo Command line options^: -GKE_PROJECT=^<GKE project^> -KEY_FILE_NAME=^<output key file^>
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
if "x%GKE_PROJECT%"=="x" (
  echo GKE project is not configured
  goto EOF
)
if "x%KEY_FILE_NAME%"=="x" (
  echo Key file name is not configured
  goto EOF
)

REM optional user-defined script parameters
REM service account name
set KAUDIT_SERVICE_ACCOUNT_NAME=kaudit-logs-viewer
REM service account display name
set KAUDIT_SERVICE_ACCOUNT_DISPLAY_NAME=kaudit-logs-viewer
REM name uninstall script
set UNINSTALL_SCRIPT_FILE=kaudit-gke-uninstall-%GKE_PROJECT%.sh

echo Preparing StackDriver for collecting GKE audit logs in project %GKE_PROJECT%

REM 1. create service account that will be used by kAudit
gcloud iam service-accounts create %KAUDIT_SERVICE_ACCOUNT_NAME% ^
      --display-name %KAUDIT_SERVICE_ACCOUNT_DISPLAY_NAME%

if not %errorlevel% EQU 0 (
  echo FAILED
  goto UNINSTALLER
)

REM 2. add permissions to the service account to view GKE audit logs
gcloud projects add-iam-policy-binding %GKE_PROJECT% ^
  --member serviceAccount:%KAUDIT_SERVICE_ACCOUNT_NAME%@%GKE_PROJECT%.iam.gserviceaccount.com ^
  --role roles/logging.privateLogViewer

if not %errorlevel% EQU 0 (
  echo FAILED
  goto UNINSTALLER
)

REM 3. create access key for the service
gcloud iam service-accounts keys create ^
      --iam-account %KAUDIT_SERVICE_ACCOUNT_NAME%@%GKE_PROJECT%.iam.gserviceaccount.com %KEY_FILE_NAME%

if not %errorlevel% EQU 0 (
  echo FAILED
  goto UNINSTALLER
)

echo Parameters for kAudit setup:
echo ---------------------------
echo credentials in file: %KEY_FILE_NAME%
echo.
echo GKE Audit Log Setup for Alcide kAudit complete!
echo Please follow Alcide kAudit installation guide to verify the EKS setup and integrate with kAudit.

:UNINSTALLER
REM 4. create uninstall script

(
echo @echo off
echo setlocal
echo set GKE_KEY_ID=
echo gcloud projects remove-iam-policy-binding %GKE_PROJECT% ^^
echo   --member serviceAccount:%KAUDIT_SERVICE_ACCOUNT_NAME%@%GKE_PROJECT%.iam.gserviceaccount.com ^^
echo   --role roles/logging.privateLogViewer
echo gcloud iam service-accounts keys delete %%GKE_KEY_ID%% ^^
echo   --iam-account %KAUDIT_SERVICE_ACCOUNT_NAME%@%GKE_PROJECT%.iam.gserviceaccount.com
echo gcloud iam service-accounts delete %KAUDIT_SERVICE_ACCOUNT_NAME%@%GKE_PROJECT%.iam.gserviceaccount.com
) > "%UNINSTALL_SCRIPT_FILE%"

echo Setup may be reverted using the script at: %UNINSTALL_SCRIPT_FILE%

:EOF