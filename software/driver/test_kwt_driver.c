#include "kwt_driver.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

/* One byte per element here only exercises transport. This is not a numeric model. */
#define INPUT_BYTES (KWT_ROWS * KWT_DEPTH)
#define WEIGHTS_BYTES (KWT_DEPTH * KWT_COLS)
#define BIAS_BYTES KWT_COLS
#define OUTPUT_BYTES (KWT_ROWS * KWT_COLS)

static uint8_t input_data[INPUT_BYTES];
static uint8_t weight_data[WEIGHTS_BYTES];
static uint8_t bias_data[BIAS_BYTES];
static uint8_t output_data[OUTPUT_BYTES];

typedef struct {
    char events[64];
    size_t used;
    uint64_t time_us;
    unsigned polls_this_job;
    unsigned waits;
    unsigned output_reads;
    unsigned mode; /* 0: complete after two busy polls; 1: never complete; 2: fault. */
    uint32_t expected_layer;
} mock_t;

static void record(mock_t *mock, char event)
{
    assert(mock->used + 1u < sizeof(mock->events));
    mock->events[mock->used++] = event;
    mock->events[mock->used] = '\0';
}

static int mock_write(void *context, kwt_region_t region, const void *src, size_t bytes)
{
    mock_t *mock = (mock_t *)context;
    assert(src != NULL);
    switch (region) {
    case KWT_REGION_INPUT:
        assert(bytes == INPUT_BYTES);
        record(mock, 'I');
        break;
    case KWT_REGION_WEIGHTS:
        assert(bytes == WEIGHTS_BYTES);
        record(mock, 'W');
        break;
    case KWT_REGION_BIAS:
        assert(bytes == BIAS_BYTES);
        record(mock, 'B');
        break;
    default:
        return -1;
    }
    return 0;
}

static int mock_read(void *context, kwt_region_t region, void *dst, size_t bytes)
{
    mock_t *mock = (mock_t *)context;
    assert(region == KWT_REGION_OUTPUT && bytes == OUTPUT_BYTES);
    memset(dst, 0x5a, bytes);
    ++mock->output_reads;
    record(mock, 'R');
    return 0;
}

static int mock_configure(void *context, const kwt_job_config_t *config)
{
    mock_t *mock = (mock_t *)context;
    assert(config->rows == KWT_ROWS);
    assert(config->depth == KWT_DEPTH);
    assert(config->cols == KWT_COLS);
    assert(config->layer_index == mock->expected_layer);
    assert(config->input_bytes == INPUT_BYTES);
    assert(config->weights_bytes == WEIGHTS_BYTES);
    assert(config->bias_bytes == BIAS_BYTES);
    assert(config->output_bytes == OUTPUT_BYTES);
    record(mock, 'C');
    return 0;
}

static int mock_start(void *context)
{
    mock_t *mock = (mock_t *)context;
    mock->polls_this_job = 0u;
    record(mock, 'S');
    return 0;
}

static int mock_status(void *context, kwt_device_status_t *status)
{
    mock_t *mock = (mock_t *)context;
    ++mock->polls_this_job;
    record(mock, 'P');
    if (mock->mode == 2u) {
        *status = KWT_DEVICE_FAULT;
    } else if (mock->mode == 1u || mock->polls_this_job < 3u) {
        *status = KWT_DEVICE_BUSY;
    } else {
        *status = KWT_DEVICE_DONE;
    }
    return 0;
}

static void mock_fence(void *context)
{
    record((mock_t *)context, 'F');
}

static uint64_t mock_now_us(void *context)
{
    mock_t *mock = (mock_t *)context;
    mock->time_us += 10u;
    return mock->time_us;
}

static void mock_wait_hint(void *context)
{
    ++((mock_t *)context)->waits;
}

static kwt_transport_t transport_for(mock_t *mock)
{
    kwt_transport_t transport;
    transport.context = mock;
    transport.write = mock_write;
    transport.read = mock_read;
    transport.configure = mock_configure;
    transport.start = mock_start;
    transport.status = mock_status;
    transport.fence = mock_fence;
    transport.now_us = mock_now_us;
    transport.wait_hint = mock_wait_hint;
    return transport;
}

static kwt_job_t sample_job(uint32_t layer)
{
    kwt_job_t job;
    job.input = input_data;
    job.input_bytes = sizeof(input_data);
    job.weights = weight_data;
    job.weights_bytes = sizeof(weight_data);
    job.bias = bias_data;
    job.bias_bytes = sizeof(bias_data);
    job.output = output_data;
    job.output_bytes = sizeof(output_data);
    job.layer_index = layer;
    return job;
}

int main(void)
{
    mock_t mock = {0};
    kwt_transport_t transport = transport_for(&mock);
    kwt_job_t job = sample_job(0u);

    assert(kwt_run_job(&transport, &job, 100u, 10u) == KWT_OK);
    assert(strcmp(mock.events, "IWBFCFSPPPFR") == 0);
    assert(mock.waits == 2u && mock.output_reads == 1u);
    assert(output_data[0] == 0x5a && output_data[OUTPUT_BYTES - 1u] == 0x5a);

    memset(&mock, 0, sizeof(mock));
    mock.expected_layer = 11u;
    job = sample_job(11u);
    assert(kwt_run_job(&transport, &job, 100u, 10u) == KWT_OK);
    assert(mock.output_reads == 1u); /* A different layer can run with new parameters. */

    memset(&mock, 0, sizeof(mock));
    mock.mode = 1u;
    job = sample_job(0u);
    assert(kwt_run_job(&transport, &job, 15u, 10u) == KWT_TIMEOUT);
    assert(mock.output_reads == 0u);

    memset(&mock, 0, sizeof(mock));
    mock.mode = 1u;
    assert(kwt_run_job(&transport, &job, 1000u, 2u) == KWT_TIMEOUT);
    assert(mock.polls_this_job == 2u && mock.output_reads == 0u);

    memset(&mock, 0, sizeof(mock));
    mock.mode = 2u;
    job = sample_job(0u);
    assert(kwt_run_job(&transport, &job, 100u, 10u) == KWT_DEVICE_ERROR);
    assert(mock.output_reads == 0u);

    memset(&mock, 0, sizeof(mock));
    job = sample_job(0u);
    job.input = NULL;
    assert(kwt_run_job(&transport, &job, 100u, 10u) == KWT_BAD_ARGUMENT);
    assert(mock.used == 0u);

    puts("kwt_driver mock tests passed");
    return 0;
}
