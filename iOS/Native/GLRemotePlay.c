// SPDX-License-Identifier: LicenseRef-AGPL-3.0-only-OpenSSL
// Compiled inside chiaki-lib, so all conditional native structure layouts agree.
#include "GLRemotePlay.h"
#include <chiaki/discoveryservice.h>
#include <chiaki/session.h>
#include <chiaki/regist.h>
#include <arpa/inet.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

static pthread_once_t once = PTHREAD_ONCE_INIT;
static int init_result;
static void initialize(void) { init_result = chiaki_lib_init(); }
int GLInitialize(void) { pthread_once(&once, initialize); return init_result; }
// Upstream verbose registration logs can include key material. Never forward them.
static void silent_log(ChiakiLogLevel level, const char *text, void *user) { (void)level; (void)text; (void)user; }

struct GLDiscovery { ChiakiDiscoveryService service; ChiakiLog log; GLHostCallback callback; void *context; };
static void discovered(ChiakiDiscoveryHost *hosts, size_t count, void *user) {
    GLDiscovery *d = user;
    for(size_t i=0;i<count;i++) if(chiaki_discovery_host_is_ps5(&hosts[i]) && hosts[i].host_addr)
        d->callback(hosts[i].host_addr, hosts[i].host_name ? hosts[i].host_name : "PS5", (int)hosts[i].state, d->context);
}
GLDiscovery *GLDiscoveryCreate(GLHostCallback callback, void *context, int *error) {
    *error = GLInitialize(); if(*error || !callback) return NULL;
    GLDiscovery *d = calloc(1,sizeof(*d)); if(!d) { *error=CHIAKI_ERR_MEMORY;return NULL; }
    d->callback=callback;d->context=context;chiaki_log_init(&d->log,0,silent_log,NULL);
    struct sockaddr_in address = {0};address.sin_len=sizeof(address);address.sin_family=AF_INET;
    address.sin_addr.s_addr=htonl(INADDR_BROADCAST);
    ChiakiDiscoveryServiceOptions options = {0};options.hosts_max=16;options.host_drop_pings=3;
    options.ping_ms=1000;options.ping_initial_ms=0;options.send_addr=(struct sockaddr_storage *)&address;
    options.send_addr_size=sizeof(address);options.send_host="255.255.255.255";options.cb=discovered;options.cb_user=d;
    *error=chiaki_discovery_service_init(&d->service,&options,&d->log);
    if(*error) { free(d);return NULL; } return d;
}
void GLDiscoveryDestroy(GLDiscovery *d) { if(d) { chiaki_discovery_service_fini(&d->service);free(d); } }

struct GLRegistration { ChiakiRegist registration; ChiakiLog log; char *host; GLRegistrationCallback callback; void *context; };
static void registered(ChiakiRegistEvent *event, void *user) {
    GLRegistration *r=user;
    ChiakiRegisteredHost *h=event->registered_host;
    r->callback((int)event->type,h ? (const uint8_t *)h->rp_regist_key : NULL,h ? h->rp_key : NULL,
        h ? h->server_nickname : "",r->context);
}
GLRegistration *GLRegistrationCreate(const char *host, const uint8_t *account, size_t account_size, uint32_t pin,
    GLRegistrationCallback callback, void *context, int *error) {
    *error=GLInitialize();if(*error)return NULL;
    if(!host || !account || account_size!=8 || pin>99999999 || !callback) { *error=CHIAKI_ERR_INVALID_DATA;return NULL; }
    GLRegistration *r=calloc(1,sizeof(*r));if(!r) { *error=CHIAKI_ERR_MEMORY;return NULL; }
    r->host=strdup(host);if(!r->host) { free(r);*error=CHIAKI_ERR_MEMORY;return NULL; }
    r->callback=callback;r->context=context;chiaki_log_init(&r->log,0,silent_log,NULL);
    ChiakiRegistInfo info={0};info.host=r->host;info.target=CHIAKI_TARGET_PS5_1;info.pin=pin;info.broadcast=false;
    memcpy(info.psn_account_id,account,8);
    *error=chiaki_regist_start(&r->registration,&r->log,&info,registered,r);
    if(*error) { free(r->host);free(r);return NULL; } return r;
}
void GLRegistrationDestroy(GLRegistration *r) {
    if(r) { chiaki_regist_stop(&r->registration);chiaki_regist_fini(&r->registration);free(r->host);free(r); }
}

struct GLSession { ChiakiSession session; ChiakiLog log; char *host; bool started; atomic_bool recovery;
    GLSessionCallback event;GLVideoCallback video;void *context; };
static void session_event(ChiakiEvent *event, void *user) {
    GLSession *s=user;
    if(event->type==CHIAKI_EVENT_CONNECTED)s->event(1,0,s->context);
    else if(event->type==CHIAKI_EVENT_QUIT)s->event(2,(int)event->quit.reason,s->context);
    else if(event->type==CHIAKI_EVENT_LOGIN_PIN_REQUEST)s->event(3,event->login_pin_request.pin_incorrect,s->context);
}
static bool video_sample(uint8_t *bytes,size_t count,int32_t lost,bool recovered,void *user) {
    (void)lost;(void)recovered;GLSession *s=user;
    bool accepted=s->video(bytes,count,s->context);
    return !atomic_exchange(&s->recovery,false) && accepted;
}
GLSession *GLSessionCreate(const char *host,const uint8_t *registration_key,size_t registration_size,
    const uint8_t *key,size_t key_size,GLSessionCallback event,GLVideoCallback video,void *context,int *error) {
    *error=GLInitialize();if(*error)return NULL;
    if(!host || !registration_key || registration_size!=16 || !key || key_size!=16 || !event || !video) {
        *error=CHIAKI_ERR_INVALID_DATA;return NULL;
    }
    GLSession *s=calloc(1,sizeof(*s));if(!s) { *error=CHIAKI_ERR_MEMORY;return NULL; }
    s->host=strdup(host);if(!s->host) { free(s);*error=CHIAKI_ERR_MEMORY;return NULL; }
    s->event=event;s->video=video;s->context=context;atomic_init(&s->recovery,false);chiaki_log_init(&s->log,0,silent_log,NULL);
    ChiakiConnectInfo info={0};info.ps5=true;info.host=s->host;
    memcpy(info.regist_key,registration_key,16);memcpy(info.morning,key,16);
    chiaki_connect_video_profile_preset(&info.video_profile,CHIAKI_VIDEO_RESOLUTION_PRESET_720p,CHIAKI_VIDEO_FPS_PRESET_30);
    info.video_profile.codec=CHIAKI_CODEC_H264;info.video_profile_auto_downgrade=true;
    info.enable_dualsense=false;info.packet_loss_max=0.05;
    *error=chiaki_session_init(&s->session,&info,&s->log);
    if(*error) { free(s->host);free(s);return NULL; }
    chiaki_session_set_event_cb(&s->session,session_event,s);
    chiaki_session_set_video_sample_cb(&s->session,video_sample,s);
    // No controller state is sent by this bridge. Account/controller coexistence still requires a device test.
    return s;
}
int GLSessionStart(GLSession *s) { if(!s)return CHIAKI_ERR_INVALID_DATA;int err=chiaki_session_start(&s->session);if(!err)s->started=true;return err; }
void GLSessionRequestRecovery(GLSession *s) { if(s)atomic_store(&s->recovery,true); }
int GLSessionLoginPIN(GLSession *s,const char *pin) { return s && pin ? chiaki_session_set_login_pin(&s->session,(const uint8_t *)pin,strlen(pin)) : CHIAKI_ERR_INVALID_DATA; }
void GLSessionDestroy(GLSession *s) {
    if(!s)return;
    if(s->started) { chiaki_session_stop(&s->session);chiaki_session_join(&s->session); }
    chiaki_session_fini(&s->session);free(s->host);free(s);
}
