#!/bin/bash -x
set -eu      

SRCDIR=/input
DSTDIR=/output

echo Copying PEM files to $DSTDIR
cp $SRCDIR/*.pem $DSTDIR/

echo use the jre default cacerts as the base for truststore.jks
cp -f $JAVA_HOME/jre/lib/security/cacerts $DSTDIR/truststore.jks
keytool -storepasswd -storepass changeit -new abcdef -keystore $DSTDIR/truststore.jks

echo Importing ca.pem into $DSTDIR/truststore.jks
keytool -importcert -file $SRCDIR/ca.pem -keystore $DSTDIR/truststore.jks -storepass abcdef -noprompt -alias alcide

echo Importing key.pem and cert.pem into $DSTDIR/keystore.jks
openssl pkcs12 -export -CAfile $SRCDIR/ca.pem -in $SRCDIR/cert.pem -inkey $SRCDIR/key.pem -out $DSTDIR/keystore.p12 -passout pass:abcdef
keytool -importkeystore -srckeystore $DSTDIR/keystore.p12 -srcstorepass abcdef -destkeystore $DSTDIR/keystore.jks -deststorepass abcdef -noprompt

openssl pkcs12 -in $DSTDIR/keystore.p12 -passin pass:abcdef -nodes -nocerts -out $DSTDIR/key.p12
#cat $DSTDIR/key.p12
rm $DSTDIR/keystore.p12

echo Converting key.pem to PKCS#8 as $DSTDIR/key.pk8.pem
openssl pkcs8 -topk8 -in $SRCDIR/key.pem -nocrypt -out $DSTDIR/key.pk8.pem

exit 0   
