#import "GLTranslation.h"
#include <openssl/evp.h>
#include <openssl/x509.h>
#include <openssl/pkcs12.h>
#include <openssl/rand.h>

NSData *GLCreateIdentityPKCS12(NSString *password,NSError **error) {
    EVP_PKEY_CTX *context=EVP_PKEY_CTX_new_from_name(NULL,"EC",NULL);
    EVP_PKEY *key=NULL;X509 *certificate=NULL;PKCS12 *package=NULL;unsigned char *der=NULL;NSData *result=nil;
    if(!context || EVP_PKEY_keygen_init(context)<=0 || EVP_PKEY_CTX_set_group_name(context,"prime256v1")<=0 || EVP_PKEY_generate(context,&key)<=0)goto done;
    certificate=X509_new();if(!certificate)goto done;
    unsigned char serial[16];if(RAND_bytes(serial,sizeof(serial))!=1)goto done;serial[0]&=0x7f;serial[0]|=1;
    BIGNUM *number=BN_bin2bn(serial,sizeof(serial),NULL);if(!number)goto done;
    ASN1_INTEGER *asn=BN_to_ASN1_INTEGER(number,NULL);BN_free(number);if(!asn)goto done;
    int serial_ok=X509_set_serialNumber(certificate,asn);ASN1_INTEGER_free(asn);if(!serial_ok)goto done;
    if(!X509_set_version(certificate,2) || !X509_gmtime_adj(X509_getm_notBefore(certificate),-86400) || !X509_gmtime_adj(X509_getm_notAfter(certificate),315360000L) || !X509_set_pubkey(certificate,key))goto done;
    X509_NAME *name=X509_get_subject_name(certificate);
    if(!X509_NAME_add_entry_by_txt(name,"CN",MBSTRING_ASC,(const unsigned char *)"GameLingo iPhone",-1,-1,0) || !X509_set_issuer_name(certificate,name) || !X509_sign(certificate,key,EVP_sha256()))goto done;
    // Legacy PKCS#12 encryption/MAC algorithms are selected explicitly for Apple's importer.
    // The entire encrypted package and password are stored only in the device Keychain.
    package=PKCS12_create(password.UTF8String,"GameLingo",key,certificate,NULL,NID_pbe_WithSHA1And3_Key_TripleDES_CBC,NID_pbe_WithSHA1And3_Key_TripleDES_CBC,2048,2048,0);
    if(!package || !PKCS12_set_mac(package,password.UTF8String,-1,NULL,0,2048,EVP_sha1()))goto done;
    int length=i2d_PKCS12(package,&der);if(length<=0)goto done;
    result=[NSData dataWithBytes:der length:length];
done:
    OPENSSL_free(der);PKCS12_free(package);X509_free(certificate);EVP_PKEY_free(key);EVP_PKEY_CTX_free(context);
    if(!result && error)*error=[NSError errorWithDomain:@"GameLingo.Identity" code:1 userInfo:@{NSLocalizedDescriptionKey:@"تعذر إنشاء هوية اتصال التلفزيون"}];
    return result;
}
