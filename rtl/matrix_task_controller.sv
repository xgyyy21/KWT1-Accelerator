// Controller boundary for one complete M/N/K task. It advances only after the
// current block reports completion, preserving control/data separation.
module matrix_task_controller #(
  parameter int ROW_TILE=8, parameter int COL_TILE=16, parameter int K_TILE=32
) (
  input logic clk, input logic rst_n, input logic start,
  input logic [15:0] matrix_m, input logic [15:0] matrix_k, input logic [15:0] matrix_n,
  input logic block_done,
  output logic block_start, output logic task_busy, output logic task_done,
  output logic [15:0] row_base, output logic [15:0] col_base, output logic [15:0] k_base,
  output logic [15:0] rows_valid, output logic [15:0] cols_valid, output logic [15:0] k_valid,
  output logic k_first, output logic k_last
);
  typedef enum logic [2:0] {IDLE, INIT, CHECK, ISSUE, WAIT_BLOCK, ADVANCE, FINISH} state_t;
  state_t state;
  logic sched_busy, sched_done;
  logic [15:0] m_q, k_q, n_q;
  assign block_start = (state==ISSUE);
  assign task_busy = (state!=IDLE && state!=FINISH);
  assign task_done = (state==FINISH);
  matrix_task_scheduler #(.ROW_TILE(ROW_TILE),.COL_TILE(COL_TILE),.K_TILE(K_TILE)) u_sched (
    .clk(clk),.rst_n(rst_n),.start(state==INIT),.advance(state==ADVANCE),
    .matrix_m(m_q),.matrix_k(k_q),.matrix_n(n_q),.busy(sched_busy),.done(sched_done),
    .row_base(row_base),.col_base(col_base),.k_base(k_base),.rows_valid(rows_valid),
    .cols_valid(cols_valid),.k_valid(k_valid),.k_first(k_first),.k_last(k_last)
  );
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin state<=IDLE; m_q<=0; k_q<=0; n_q<=0; end
    else case (state)
      IDLE: if(start) begin state<=INIT; m_q<=matrix_m; k_q<=matrix_k; n_q<=matrix_n; end
      INIT: state<=CHECK;
      CHECK: if(sched_done || !sched_busy) state<=FINISH; else state<=ISSUE;
      ISSUE: if(block_done) state<=ADVANCE; else state<=WAIT_BLOCK;
      WAIT_BLOCK: if(block_done) state<=ADVANCE;
      ADVANCE: state<=CHECK;
      FINISH: if(start) begin state<=INIT; m_q<=matrix_m; k_q<=matrix_k; n_q<=matrix_n; end
              else state<=IDLE;
      default: state<=IDLE;
    endcase
  end
endmodule
