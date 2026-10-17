#ifndef KWT_DRIVER_H
#define KWT_DRIVER_H

#include <stddef.h>
#include <stdint.h>

/* Mandatory undergraduate FFN first linear layer: Y[99,256] = X[99,64] W[64,256] + b[256]. */
#define KWT_ROWS 99u
#define KWT_DEPTH 64u
#define KWT_COLS 256u
#define KWT_LAYERS 12u

typedef enum {
    KWT_REGION_INPUT,
    KWT_REGION_WEIGHTS,
    KWT_REGION_BIAS,
    KWT_REGION_OUTPUT
} kwt_region_t;

typedef enum {
    KWT_DEVICE_READY,
    KWT_DEVICE_BUSY,
    KWT_DEVICE_DONE,
    KWT_DEVICE_FAULT
} kwt_device_status_t;

typedef enum {
    KWT_OK = 0,
    KWT_BAD_ARGUMENT = -1,
    KWT_IO_ERROR = -2,
    KWT_DEVICE_ERROR = -3,
    KWT_TIMEOUT = -4
} kwt_result_t;

/* Buffers contain already encoded and packed data. The driver never interprets a number. */
typedef struct {
    const void *input;
    size_t input_bytes;
    const void *weights;
    size_t weights_bytes;
    const void *bias;
    size_t bias_bytes;
    void *output;
    size_t output_bytes;
    uint32_t layer_index; /* 0..11, for bookkeeping/configuration, not model computation. */
} kwt_job_t;

typedef struct {
    uint32_t rows;
    uint32_t depth;
    uint32_t cols;
    uint32_t layer_index;
    size_t input_bytes;
    size_t weights_bytes;
    size_t bias_bytes;
    size_t output_bytes;
} kwt_job_config_t;

/*
 * Platform adapter contract:
 * - write/read return 0 only after the whole transfer has completed.
 * - The adapter handles its actual bus or NICE transactions, register map, DMA and cache maintenance.
 * - configure/start/status translate semantic operations into the chosen hardware protocol.
 * - fence orders CPU/adapter accesses; now_us is a monotonic microsecond counter.
 * - Every int callback returns 0 on success; any nonzero value is an I/O error.
 */
typedef struct {
    void *context;
    int (*write)(void *context, kwt_region_t region, const void *src, size_t bytes);
    int (*read)(void *context, kwt_region_t region, void *dst, size_t bytes);
    int (*configure)(void *context, const kwt_job_config_t *config);
    int (*start)(void *context);
    int (*status)(void *context, kwt_device_status_t *status);
    void (*fence)(void *context);
    uint64_t (*now_us)(void *context);
    void (*wait_hint)(void *context); /* Optional: yield, short delay or wait-for-interrupt. */
} kwt_transport_t;

/* Runs one complete layer task. Both timeout_us and max_polls must be nonzero. */
kwt_result_t kwt_run_job(const kwt_transport_t *transport,
                         const kwt_job_t *job,
                         uint64_t timeout_us,
                         uint32_t max_polls);

#endif
