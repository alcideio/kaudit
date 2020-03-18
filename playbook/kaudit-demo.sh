#!/bin/bash

#
# Running test scenario for Alcide KAudit.
#

CTXT=`kubectl config current-context`

DELAY=30 # Number of seconds to display results
PROFILE_PERIOD=30 # period used in profile building

# silent remote shell command execution
function do-pod-exec () {
  echo executing command in $1 $2
  kubectl exec -n $1 $2 -- ls > /dev/null 2>&1
}

function random-in-list () {
  local options=($1)
  local num_options=${#options[@]}
  echo ${options[$((RANDOM%num_options))]}
}

while true; do
  clear
  cat << _EOF_
Alcide's KAudit demonstration
Kubernetes context: $CTXT

Please Select:

1. Policy violation: principal opens remote shells to some pods
2. Policy violation: principal accesses secrets in 'kube-system' namespace (policy configuration required)
3. Principal detection: unusual access pattern
4. Principal detection: using unauthorized APIs
5. Principal detection: access with multiple user-agents and to unusual URIs
0. Quit

_EOF_

  read -p "Enter selection [0-5] > "

  if [[ $REPLY =~ ^[0-5]$ ]]; then
    case $REPLY in
      1)
        # Policy: principal open remote shells to some (random) pods
        # select namespace
        NS="kube-system"
        # get existing pods in namespace
        ns_pods=`kubectl get pods -n $NS -o=name`

        # Do X times: select random pod and exec remote command
        for (( i = 0; i < 5; i++ )); do
          some_pod=$(random-in-list "$ns_pods")
          pod=${some_pod#pod/}
          do-pod-exec $NS $pod
        done

        echo test scenario finished
        sleep $DELAY
        continue
        ;;

      2)
        # Policy: principal accesses secrets in 'kube-system' namespace
        # select namespace
        NS="kube-system"
        # get secrets in 'kube-system' namespace
        ns_secrets=`kubectl get secrets -n $NS -o=name`

        options=($ns_secrets)
        echo accessing some of the ${#options[@]} secrets in $NS

        # access aome random secrets
        for (( i = 0; i < 5; i++ )); do
          some_secret=$(random-in-list "$ns_secrets")
          kubectl get $some_secret -n $NS > /dev/null
        done

        echo test scenario finished
        sleep $DELAY
        continue
        ;;


      3)
        # Principal: unusual access pattern

        namespaces=`kubectl get namespaces -o=name`

        # Do X times:
        for (( i = 0; i < 5; i++ )); do
          # select namespace
          some_ns=$(random-in-list "$namespaces")
          ns=${some_ns#namespace/}
          echo namespace $ns
          # get service-accounts, secrets and config-maps
          kubectl get serviceaccounts -n $ns > /dev/null
          kubectl get secrets -n $ns > /dev/null
          kubectl get configmaps -n $ns > /dev/null

          ns_pods=(`kubectl get pods -n $ns -o=name`)
          # for every pod in namespace - open remote shell
          for pod in "${ns_pods[@]}"; do
            do-pod-exec $ns ${pod#pod/}
          done
          echo waiting for next principal activity...
          sleep $PROFILE_PERIOD
        done

        echo test scenario finished
        sleep $DELAY
        continue
        ;;

      4)
        # Principal: using unauthorized APIs
        # setup
        kubectl create namespace demo-ns

        kubectl create serviceaccount demo-user -n demo-ns
        kubectl create role demo-role --verb=get,list,watch --resource=configmaps
        kubectl create rolebinding demo-role-binding --role=demo-role --serviceaccount=demo-ns:demo-user --user=test@example.com

        # execute X times:
        # unauthorized operations using a service-account and user having a limited-permissions role
        secret_name=`kubectl get serviceaccount demo-user -n demo-ns -o=jsonpath='{.secrets[0].name}'`
        bearer_token=`kubectl get secret $secret_name -n demo-ns -o=jsonpath='{.data.token}' | base64 --decode`
        #  --user='test@example.com' --token='$bearer_token'
        for (( i = 0; i < 3; i++ )); do
          kubectl create configmap demo-config -n demo-ns --as='test@example.com' --from-literal=key1=value1 --from-literal=key2=value2
          kubectl create configmap demo-config -n demo-ns --as='demo-user' --from-literal=key1=value1 --from-literal=key2=value2
          kubectl delete configmap demo-config -n demo-ns
          echo waiting for next principal activity...
          sleep $PROFILE_PERIOD
        done

        # cleanup
        kubectl delete rolebinding demo-role-binding
        kubectl delete role demo-role
        kubectl delete serviceaccount demo-user -n demo-ns
        kubectl delete namespace demo-ns

        echo test scenario finished
        sleep $DELAY
        continue
        ;;

      5)
        # Principal: access with multiple user-agents and to unusual URIs, via web API & proxy
        # setup web proxy
        port=8009
        kubectl proxy --port "$port" &   # e.g. http://127.0.0.1:8009/
        sleep 3
        server=http://127.0.0.1:"$port"

        uas=(
          "test Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/74.0.3729.169 Safari/537.36"
          "test Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/44.0.2403.157 Safari/537.36"
          "test Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/74.0.3729.169 Safari/537.36,gzip(gfe),gzip(gfe)"
          "test Mozilla/5.0 (X11; OpenBSD i386) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/36.0.1985.125 Safari/537.36"
          "test Mozilla/5.0 (Windows NT 6.1; WOW64; Trident/7.0; rv:11.0) like Gecko"
          "test Mozilla/5.0 (iPhone; CPU iPhone OS 12_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
          "test PycURL/7.43.0.2 libcurl/7.47.0 OpenSSL/1.0.2g zlib/1.2.8 libidn/1.32 librtmp/2.3"
          "test curl/7.20.0 (x86_64-redhat-linux-gnu) libcurl/7.20.0 OpenSSL/0.9.8b zlib/1.2.3 libidn/0.6.5"
          "test Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
          "test Java/1.8.0_121"
          "test Mozilla/5.0 (compatible; Nmap Scripting Engine; https://nmap.org/book/nse.html)"
          "test Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 5.1; SV1; .NET CLR 2.0.50727) Havij"
          "test sqlmap/1.0-dev"
        )
        num_uas=${#uas[*]}
        scan_uris=(
          "/login/test"
          "/web/resources"
          "/debug/pprof"
          "/secrets/admin"
          "/configs"
        )
        num_scan_uris=${#scan_uris[*]}

        for (( i = 0; i < 5; i++ )); do

          # access with configured user-agents
          ua=${uas[$((RANDOM%num_uas))]}
          echo using user-agent: $ua
          curl -A "$ua" ${server}/api/v1/namespaces/ > /dev/null
          curl -A "$ua" ${server}/api/v1/configmaps/ > /dev/null
          curl -A "$ua" ${server}/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/ > /dev/null
          # access unusual URIs
          uri=${scan_uris[$((RANDOM%num_scan_uris))]}
          echo access to: ${server}${uri} using user-agent: ${ua}
          curl -A "$ua" ${server}${uri} > /dev/null

          echo waiting for next principal activity...
          sleep $((RANDOM%PROFILE_PERIOD))
        done

        # cleanup web proxy
        kill $! > /dev/null

        echo test scenario finished
        sleep $DELAY
        continue
        ;;

      0)
        break
        ;;
    esac
  else
    echo "Invalid entry."
    sleep $DELAY
  fi
done
echo "Program terminated."



######################################

# Currently unused.
# May be used to run test scenario within the cluster (from within a pod).

function in-cluster-api {
  # access from within a pod in the cluster
  # arguments: HTTP Method (e.g. "GET")
  #            API path (e.g. "configmaps")
  #            API argument

  # Point to the internal API server hostname
  local APISERVER=https://kubernetes.default.svc

  # Path to ServiceAccount token
  local SERVICEACCOUNT=/var/run/secrets/kubernetes.io/serviceaccount

  # Read this Pod's namespace
  local NAMESPACE=$(cat ${SERVICEACCOUNT}/namespace)

  # Read the ServiceAccount bearer token
  local TOKEN=$(cat ${SERVICEACCOUNT}/token)

  # Reference the internal certificate authority (CA)
  local CACERT=${SERVICEACCOUNT}/ca.crt

  # Explore the API with TOKEN
  curl --cacert ${CACERT} --header "Authorization: Bearer ${TOKEN}" -X $1 ${APISERVER}/api/${$2} $3
}

######################################
