#ifndef TOUCH_BRIDGE_H
#define TOUCH_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*TFMCContactCallback)(int32_t count, double timestamp);

bool TFMCStartMultitouch(TFMCContactCallback callback, char *errorBuffer, size_t errorBufferLength);
void TFMCStopMultitouch(void);

#ifdef __cplusplus
}
#endif

#endif
