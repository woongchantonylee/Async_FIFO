// ================================================================
// Asynchronous FIFO (8-bit), dual-clock, active-low async reset
//  - Gray-coded read/write pointers
//  - Two-flop synchronizers for CDC of Gray pointers
//  - Full/Empty detection with extra pointer MSB
// Notes:
//   * DEPTH must be a power of two
//   * dout is registered and becomes valid one rd_clk cycle after a successful read
// ================================================================
module async_fifo #(
    parameter int DATA_W = 8,
    parameter int DEPTH  = 16,           // power of two: 4,8,16,32...
    localparam int ADDR_W = $clog2(DEPTH),
    localparam int PTR_W  = ADDR_W + 1   // extra bit to detect wrap
)(
    input  logic               wr_clk,   // clock A (write domain)
    input  logic               rd_clk,   // clock B (read domain)
    input  logic               rst_n,    // active-low async reset

    // Write side
    input  logic               wr_en,
    input  logic [DATA_W-1:0]  din,
    output logic               full,

    // Read side
    input  logic               rd_en,
    output logic [DATA_W-1:0]  dout,
    output logic               empty
);

    // -------------- Storage --------------
    logic [DATA_W-1:0] mem [0:DEPTH-1];

    // -------------- Pointers --------------
    // Binary & Gray-coded pointers for each domain
    logic [PTR_W-1:0] wptr_bin, wptr_bin_nxt;
    logic [PTR_W-1:0] rptr_bin, rptr_bin_nxt;
    logic [PTR_W-1:0] wptr_gray, wptr_gray_nxt;
    logic [PTR_W-1:0] rptr_gray, rptr_gray_nxt;

    // Synchronized Gray pointers crossing domains
    logic [PTR_W-1:0] wptr_gray_rdclk_ff1, wptr_gray_rdclk_ff2;
    logic [PTR_W-1:0] rptr_gray_wrclk_ff1, rptr_gray_wrclk_ff2;

    // -------------- Helpers --------------
    function automatic logic [PTR_W-1:0] bin2gray (input logic [PTR_W-1:0] b);
        return (b >> 1) ^ b;
    endfunction

    // (Only needed if you want binary form after sync; not strictly required for full/empty logic)
    function automatic logic [PTR_W-1:0] gray2bin (input logic [PTR_W-1:0] g);
        logic [PTR_W-1:0] b;
        for (int i = PTR_W-1; i >= 0; i--) begin
            if (i == PTR_W-1) b[i] = g[i];
            else               b[i] = b[i+1] ^ g[i];
        end
        return b;
    endfunction

    // -------------- Write domain --------------
    // Next-state logic
    assign wptr_bin_nxt  = wptr_bin + (wr_en && !full);
    assign wptr_gray_nxt = bin2gray(wptr_bin_nxt);

    // Write memory
    always_ff @(posedge wr_clk or negedge rst_n) begin
        if (!rst_n) begin
            // no mem init required for synthesis; okay to leave X in sim
        end else if (wr_en && !full) begin
            mem[wptr_bin[ADDR_W-1:0]] <= din;
        end
    end

    // Write pointer registers
    always_ff @(posedge wr_clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr_bin  <= '0;
            wptr_gray <= '0;
        end else begin
            wptr_bin  <= wptr_bin_nxt;
            wptr_gray <= wptr_gray_nxt;
        end
    end

    // Synchronize read pointer (Gray) into write clock domain
    always_ff @(posedge wr_clk or negedge rst_n) begin
        if (!rst_n) begin
            rptr_gray_wrclk_ff1 <= '0;
            rptr_gray_wrclk_ff2 <= '0;
        end else begin
            rptr_gray_wrclk_ff1 <= rptr_gray;
            rptr_gray_wrclk_ff2 <= rptr_gray_wrclk_ff1;
        end
    end

    // FULL: next write Gray equals synced read Gray with inverted top two bits
    // This is the standard full condition for Gray pointers with extra MSB
    assign full = (wptr_gray_nxt == {~rptr_gray_wrclk_ff2[PTR_W-1:PTR_W-2],
                                     rptr_gray_wrclk_ff2[PTR_W-3:0]});

    // -------------- Read domain --------------
    // Next-state logic
    assign rptr_bin_nxt  = rptr_bin + (rd_en && !empty);
    assign rptr_gray_nxt = bin2gray(rptr_bin_nxt);

    // Read data: register output one cycle after a successful read
    always_ff @(posedge rd_clk or negedge rst_n) begin
        if (!rst_n) begin
            dout <= '0;
        end else if (rd_en && !empty) begin
            dout <= mem[rptr_bin[ADDR_W-1:0]];
        end
    end

    // Read pointer registers
    always_ff @(posedge rd_clk or negedge rst_n) begin
        if (!rst_n) begin
            rptr_bin  <= '0;
            rptr_gray <= '0;
        end else begin
            rptr_bin  <= rptr_bin_nxt;
            rptr_gray <= rptr_gray_nxt;
        end
    end

    // Synchronize write pointer (Gray) into read clock domain
    always_ff @(posedge rd_clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr_gray_rdclk_ff1 <= '0;
            wptr_gray_rdclk_ff2 <= '0;
        end else begin
            wptr_gray_rdclk_ff1 <= wptr_gray;
            wptr_gray_rdclk_ff2 <= wptr_gray_rdclk_ff1;
        end
    end

    // EMPTY: next read Gray equals synced write Gray
    assign empty = (rptr_gray_nxt == wptr_gray_rdclk_ff2);

endmodule
