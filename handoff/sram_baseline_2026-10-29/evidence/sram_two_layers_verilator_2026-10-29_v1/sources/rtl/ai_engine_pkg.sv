package ai_engine_pkg;
  parameter int DEFAULT_DATA_WIDTH = 32;
  parameter int DEFAULT_ACC_WIDTH  = 64;
  parameter int ARRAY_ROWS         = 8;
  parameter int ARRAY_COLS         = 16;
  parameter int MAX_M              = 99;
  parameter int MAX_K              = 256;
  parameter int MAX_N              = 256;

  typedef enum logic [2:0] {
    PE_IDLE  = 3'b000,
    PE_RUN   = 3'b001,
    PE_HOLD  = 3'b010,
    PE_DONE  = 3'b011,
    PE_ERROR = 3'b100
  } pe_state_t;
endpackage
