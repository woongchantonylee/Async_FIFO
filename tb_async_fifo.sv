`timescale 1ns/1ps

module tb_async_fifo;

  localparam int DATA_W = 8;
  localparam int DEPTH  = 16;

  // DUT I/O
  logic wr_clk, rd_clk, rst_n;
  logic wr_en, rd_en;
  logic [DATA_W-1:0] din;
  logic [DATA_W-1:0] dout;
  logic full, empty;

  // Instantiate DUT
  async_fifo #(.DATA_W(DATA_W), .DEPTH(DEPTH)) dut (
    .wr_clk (wr_clk),
    .rd_clk (rd_clk),
    .rst_n  (rst_n),
    .wr_en  (wr_en),
    .din    (din),
    .full   (full),
    .rd_en  (rd_en),
    .dout   (dout),
    .empty  (empty)
  );
  
  initial begin
    wr_en = 1'b0;
    rd_en = 1'b0;
    din   = '0;
  end

  // ----------------------------
  // Clocks (different rates)
  // ----------------------------
  initial wr_clk = 1'b0;
  always  #5 wr_clk = ~wr_clk;   // 100 MHz

  initial rd_clk = 1'b0;
  always  #7 rd_clk = ~rd_clk;   // ~71.4 MHz

  // ----------------------------
  // Reset (hold longer so sync flops settle)
  // ----------------------------
  initial begin
    rst_n = 1'b0;
    #(200);        // 200 ns reset
    rst_n = 1'b1;
  end

  // ----------------------------
  // VCD dump for EPWave
  // ----------------------------
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_async_fifo);   // dump entire TB hierarchy (incl. DUT)
  end

  // ----------------------------
  // Reference model + bookkeeping
  // ----------------------------
  typedef logic [DATA_W-1:0] byte_t;
  byte_t q[$];                   // expected FIFO order

  logic        rd_en_q;          // 1-cycle delayed read-valid (since dout is registered)
  int unsigned write_count = 0;
  int unsigned read_count  = 0;
  int unsigned err_count   = 0;

  // Delay rd_en&&~empty by 1 rd_clk to align with registered dout
  always_ff @(posedge rd_clk or negedge rst_n) begin
    if (!rst_n) rd_en_q <= 1'b0;
    else        rd_en_q <= (rd_en && !empty);
  end

  // Model writes when DUT actually accepts them (posedge wr_clk)
  always @(posedge wr_clk) begin
    if (rst_n && wr_en && !full) begin
      q.push_back(din);
      write_count++;
      // $display("[%0t] WRITE din=%0h (q.size=%0d)", $time, din, q.size());
    end
  end

  // Check data one rd_clk after a valid read
  always_ff @(posedge rd_clk or negedge rst_n) begin
    if (!rst_n) begin
      err_count <= 0;
    end else if (rd_en_q) begin
      if (q.size() == 0) begin
        $display("[%0t] ERROR: Model queue underflow!", $time);
        err_count++;
      end else begin
        byte_t exp;
        exp = q.pop_front();
        if (dout !== exp) begin
          $display("[%0t] ERROR: Data mismatch. DUT=%0h EXP=%0h", $time, dout, exp);
          err_count++;
        end else begin
          // $display("[%0t] READ  dout=%0h (q.size=%0d)", $time, dout, q.size());
        end
        read_count++;
      end
    end
  end

  // Sanity: full & empty must never be 1 at the same time
  always @(posedge wr_clk or posedge rd_clk) begin
    if (full && empty) $display("[%0t] ERROR: full && empty both asserted", $time);
  end

  // ----------------------------
  // Drive enables/data on negedge so DUT samples them on next posedge
  // ----------------------------

  // WRITE PHASE: push exactly DEPTH entries (0..DEPTH-1)
  initial begin
    @(posedge rst_n);
    repeat (2) @(posedge wr_clk);

    for (int i = 0; i < DEPTH; i++) begin
      @(negedge wr_clk);
      if (!full) begin
        din  = i[DATA_W-1:0];
        wr_en = 1'b1;         // visible at next wr_clk posedge
      end else begin
        wr_en = 1'b0;         // if full, retry this index
        i = i - 1;
      end
    end

    @(negedge wr_clk);
    wr_en = 1'b0;
  end

  // Allow write pointer time to cross into read domain
  initial begin
    @(posedge rst_n);
    repeat (10) @(posedge rd_clk);
  end

  // READ PHASE: pop exactly DEPTH entries
  initial begin
    @(posedge rst_n);
    repeat (10) @(posedge rd_clk);  // wait for pointer sync

    for (int j = 0; j < DEPTH; j++) begin
      @(negedge rd_clk);
      if (!empty) begin
        rd_en = 1'b1;               // visible at next rd_clk posedge
      end else begin
        rd_en = 1'b0;               // if empty, retry this index
        j = j - 1;
      end
    end

    @(negedge rd_clk);
    rd_en = 1'b0;
  end

  // ----------------------------
  // Run longer so waves are easy to inspect; then report
  // ----------------------------
  initial begin
    #(1_000_000); // 1 ms
    repeat (DEPTH*2) @(posedge rd_clk);
    $display("===============================================");
    $display("Writes: %0d  Reads: %0d  Errors: %0d  QueueRem: %0d  full=%0b empty=%0b",
             write_count, read_count, err_count, q.size(), full, empty);
    $display("STATUS: %s", (err_count==0) ? "PASS" : "FAIL");
    $display("===============================================");
    $finish;
  end

endmodule
