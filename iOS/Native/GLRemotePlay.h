// SPDX-License-Identifier: LicenseRef-AGPL-3.0-only-OpenSSL
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct GLDiscovery GLDiscovery;
typedef struct GLRegistration GLRegistration;
typedef struct GLSession GLSession;
typedef void (*GLHostCallback)(const char *host, const char *name, int state, void *context);
typedef void (*GLRegistrationCallback)(int result, const uint8_t *registration_key, const uint8_t *key, const char *name, void *context);
typedef void (*GLSessionCallback)(int event, int reason, void *context); // 1 connected, 2 quit, 3 login PIN
typedef bool (*GLVideoCallback)(const uint8_t *bytes, size_t count, void *context);

int GLInitialize(void);
GLDiscovery *GLDiscoveryCreate(GLHostCallback callback, void *context, int *error);
void GLDiscoveryDestroy(GLDiscovery *discovery);
GLRegistration *GLRegistrationCreate(const char *host, const uint8_t *account, size_t account_size, uint32_t pin,
    GLRegistrationCallback callback, void *context, int *error);
void GLRegistrationDestroy(GLRegistration *registration);
GLSession *GLSessionCreate(const char *host, const uint8_t *registration_key, size_t registration_size,
    const uint8_t *key, size_t key_size, GLSessionCallback event, GLVideoCallback video, void *context, int *error);
int GLSessionStart(GLSession *session);
void GLSessionDestroy(GLSession *session);
void GLSessionRequestRecovery(GLSession *session);
int GLSessionLoginPIN(GLSession *session, const char *pin);
