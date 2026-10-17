#include "kwt_driver.h"

static int valid_job(const kwt_job_t *job)
{
    return job != NULL && job->input != NULL && job->input_bytes != 0u &&
           job->weights != NULL && job->weights_bytes != 0u &&
           job->bias != NULL && job->bias_bytes != 0u &&
           job->output != NULL && job->output_bytes != 0u &&
           job->layer_index < KWT_LAYERS;
}

static int valid_transport(const kwt_transport_t *transport)
{
    return transport != NULL && transport->write != NULL &&
           transport->read != NULL && transport->configure != NULL &&
           transport->start != NULL && transport->status != NULL &&
           transport->fence != NULL && transport->now_us != NULL;
}

kwt_result_t kwt_run_job(const kwt_transport_t *transport,
                         const kwt_job_t *job,
                         uint64_t timeout_us,
                         uint32_t max_polls)
{
    kwt_job_config_t config;
    kwt_device_status_t state;
    uint64_t start_us;
    uint32_t poll;

    if (!valid_transport(transport) || !valid_job(job) ||
        timeout_us == 0u || max_polls == 0u) {
        return KWT_BAD_ARGUMENT;
    }

    if (transport->write(transport->context, KWT_REGION_INPUT,
                         job->input, job->input_bytes) != 0 ||
        transport->write(transport->context, KWT_REGION_WEIGHTS,
                         job->weights, job->weights_bytes) != 0 ||
        transport->write(transport->context, KWT_REGION_BIAS,
                         job->bias, job->bias_bytes) != 0) {
        return KWT_IO_ERROR;
    }

    transport->fence(transport->context);
    config.rows = KWT_ROWS;
    config.depth = KWT_DEPTH;
    config.cols = KWT_COLS;
    config.layer_index = job->layer_index;
    config.input_bytes = job->input_bytes;
    config.weights_bytes = job->weights_bytes;
    config.bias_bytes = job->bias_bytes;
    config.output_bytes = job->output_bytes;

    if (transport->configure(transport->context, &config) != 0) {
        return KWT_IO_ERROR;
    }
    transport->fence(transport->context);
    if (transport->start(transport->context) != 0) {
        return KWT_IO_ERROR;
    }

    start_us = transport->now_us(transport->context);
    for (poll = 0u; poll < max_polls; ++poll) {
        if (transport->status(transport->context, &state) != 0) {
            return KWT_IO_ERROR;
        }
        if (state == KWT_DEVICE_DONE) {
            transport->fence(transport->context);
            if (transport->read(transport->context, KWT_REGION_OUTPUT,
                                job->output, job->output_bytes) != 0) {
                return KWT_IO_ERROR;
            }
            return KWT_OK;
        }
        if (state == KWT_DEVICE_FAULT) {
            return KWT_DEVICE_ERROR;
        }
        if (state != KWT_DEVICE_READY && state != KWT_DEVICE_BUSY) {
            return KWT_DEVICE_ERROR;
        }
        if ((transport->now_us(transport->context) - start_us) >= timeout_us) {
            return KWT_TIMEOUT;
        }
        if (transport->wait_hint != NULL) {
            transport->wait_hint(transport->context);
        }
    }
    return KWT_TIMEOUT;
}
