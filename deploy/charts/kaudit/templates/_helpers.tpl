{{/* ssl.enabled and connectionPool.* are for cassandra */}}
{{/* security.protocol, ssl.keystore.* and ssl.truststore.* are for kafka */}}
{{/* javax.net.ssl.* are for etcd */}}
{{- define "commonJavaFlags" -}}
-Dsecurity.protocol=SSL
-Dssl.keystore.location=/keystore/keystore.jks
-Dssl.keystore.password=abcdef
-Dssl.truststore.location=/keystore/truststore.jks
-Dssl.truststore.password=abcdef
-Djavax.net.ssl.keyStore=/keystore/keystore.jks
-Djavax.net.ssl.keyStorePassword=abcdef
-Djavax.net.ssl.trustStore=/keystore/truststore.jks
-Djavax.net.ssl.trustStorePassword=abcdef
{{- end -}}