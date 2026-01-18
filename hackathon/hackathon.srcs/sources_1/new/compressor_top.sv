`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/17/2026 09:19:32 PM
// Design Name: 
// Module Name: compressor_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// FIXED: Test signal generation with proper bit widths
// 
//////////////////////////////////////////////////////////////////////////////////

module compressor_top (
    input wire clk,
    input wire rst,
    
    // Buttons
    input wire btn_start_capture,
    input wire btn_start_readout,
    
    // UART
    output wire uart_tx,
    
    // Status LEDs
    output wire [15:0] led
);
    
    import parameters::DATA_WIDTH;
    import parameters::SIGNAL_NUMBER;
    
    localparam MEMSIZE = 2048;
    
    // Button debouncing (simple - you may want better)
    reg [19:0] btn_readout_counter;
    reg btn_readout_sync;
    reg btn_readout_prev;
    wire btn_readout_pulse = btn_readout_sync && !btn_readout_prev;
    
    always @(posedge clk) begin
        if (rst) begin
            btn_readout_counter <= 0;
            btn_readout_sync <= 0;
            btn_readout_prev <= 0;
        end else begin
            if (btn_start_readout) 
                btn_readout_counter <= btn_readout_counter + 1;
            else 
                btn_readout_counter <= 0;
            
            if (btn_readout_counter == 20'hFFFFF) 
                btn_readout_sync <= 1;
            else if (!btn_start_readout) 
                btn_readout_sync <= 0;
            
            btn_readout_prev <= btn_readout_sync;
        end
    end
    
    // Signals from compression module
    wire onebyteoutFLAG;
    wire [DATA_WIDTH+4-1:0] bytesout;
    wire largebyteoutFLAG;
    wire uncompressedFLAG;
    wire [DATA_WIDTH*SIGNAL_NUMBER-1:0] uncompressed;
    wire compressedready;
    wire uncompressedfull;
    
    // BRAM storage signals
    wire [$clog2(MEMSIZE)-1:0] compmem_counter;  // Bytes stored
    
    // UART signals
    wire [7:0] uart_tx_data;
    wire uart_tx_valid;
    wire uart_tx_ready;
    
    // Readout signals
    wire reading_out;
    wire [$clog2(MEMSIZE)-1:0] bytes_sent;
    wire [$clog2(MEMSIZE)-1:0] rd_addr;
    wire [7:0] rd_data;
    
    // =========================================================================
    // IMPROVED Test Signal Generation
    // =========================================================================
    
    // Sample tick generation (1kHz sampling rate)
    reg [31:0] sample_tick_counter;
    wire sample_tick = (sample_tick_counter == 100000 - 1); // 1kHz at 100MHz
    
    always @(posedge clk) begin
        if (rst)
            sample_tick_counter <= 0;
        else
            sample_tick_counter <= sample_tick ? 0 : sample_tick_counter + 1;
    end
    
    // Sample counter - increments on each sample tick
    reg [31:0] sample_count;
    always @(posedge clk) begin
        if (rst)
            sample_count <= 0;
        else if (sample_tick && !reading_out)
            sample_count <= sample_count + 1;
    end
    
    // Generate test signals with predictable, compressible patterns
    wire [15:0] test_counter;     // Increments every sample: perfect for DeltaRLE
    wire [15:0] test_fsm;         // Changes every 256 samples: perfect for RLE
    wire [15:0] test_random;      // Pseudo-random: low compression
    wire [15:0] test_slow;        // Changes every 4096 samples: extreme RLE
    
    // Signal 0: Pure counter (0, 1, 2, 3, 4, ...)
    // Should compress ~8x with DeltaRLE (delta = +1, +1, +1...)
    assign test_counter = sample_count[15:0];
    
    // Signal 1: FSM state (changes every 256 samples)
    // Should compress ~20-50x with RLE
    assign test_fsm = {12'h0, sample_count[11:8]};  // Changes when sample_count[7:0] wraps
    
    // Signal 2: Pseudo-random using LFSR
    // Low compression (almost incompressible)
    reg [7:0] lfsr;
    always @(posedge clk) begin
        if (rst)
            lfsr <= 8'hA5;  // Seed value
        else if (sample_tick && !reading_out)
            lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};  // Galois LFSR
    end
    assign test_random = {8'h00, lfsr};  // Zero-pad to 16 bits
    
    // Signal 3: Very slow counter (changes every 4096 samples)
    // Should compress ~100x+ with RLE
    assign test_slow = {4'h0, sample_count[23:12]};  // Changes when sample_count[11:0] wraps
    
    // Pack signals into array
    wire [DATA_WIDTH-1:0] signals [SIGNAL_NUMBER-1:0];
    assign signals[0] = test_counter;
    assign signals[1] = test_fsm;
    assign signals[2] = test_random;
    assign signals[3] = test_slow;
    
    // =========================================================================
    // Debug output (only in simulation)
    // =========================================================================
    `ifdef SIMULATION
    always @(posedge clk) begin
        if (sample_tick && !reading_out && !rst) begin
            $display("T=%0t Sample %0d: sig0=%0d sig1=%0d sig2=%0d sig3=%0d", 
                     $time, sample_count, 
                     signals[0], signals[1], signals[2], signals[3]);
        end
        
        if (onebyteoutFLAG) begin
            $display("  -> 1-byte packet: 0x%02X", bytesout[7:0]);
        end
        
        if (largebyteoutFLAG) begin
            $display("  -> RAW packet: 0x%05X (type=%02b sig=%02b data=0x%04X)",
                     bytesout[19:0],
                     bytesout[19:18],
                     bytesout[17:16],
                     bytesout[15:0]);
        end
    end
    `endif
    
    // =========================================================================
    // Compression and Storage
    // =========================================================================
    
    // Compression module instance
    compression comp (
        .in(signals),
        .start(sample_tick && !reading_out),  // Don't capture during readout
        .clk(clk),
        .reset_n(!rst),
        .compressedready(compressedready),
        .uncompressedfull(uncompressedfull),
        .onebyteoutFLAG(onebyteoutFLAG),
        .bytesout(bytesout),
        .largebyteoutFLAG(largebyteoutFLAG),
        .uncompressedFLAG(uncompressedFLAG),
        .uncompressed(uncompressed)
    );
    
    // Modified BRAM storage with read port
    bramstorage storage (
        .onebyteoutFLAG(onebyteoutFLAG),
        .compressedin(bytesout),
        .largebyteoutFLAG(largebyteoutFLAG),
        .clk(clk),
        .reset_n(!rst),
        .uncompressedflag(uncompressedFLAG),
        .uncompressedin(uncompressed),
        .compressedready(compressedready),
        .uncompressedfull(uncompressedfull),
        .compmem_counter(compmem_counter),
        
        // Read port for UART readout
        .rd_addr(rd_addr),
        .rd_data(rd_data)
    );
    
    // UART readout controller
    bram_readout #(
        .MEMSIZE(MEMSIZE)
    ) readout (
        .clk(clk),
        .rst(rst),
        .start_readout(btn_readout_pulse),
        .bytes_stored(compmem_counter),
        .rd_addr(rd_addr),
        .rd_data(rd_data),
        .tx_data(uart_tx_data),
        .tx_valid(uart_tx_valid),
        .tx_ready(uart_tx_ready),
        .reading_out(reading_out),
        .bytes_sent(bytes_sent)
    );
    
    // UART TX
    uart_tx uart (
        .clk(clk),
        .rst(rst),
        .data(uart_tx_data),
        .valid(uart_tx_valid),
        .ready(uart_tx_ready),
        .tx(uart_tx)
    );
    
    // LED status display
    // [15] = reading out
    // [14] = compressed BRAM almost full
    // [13:0] = bytes stored / bytes sent
    assign led = {reading_out, 
                  (compmem_counter > MEMSIZE - 100),
                  reading_out ? bytes_sent : compmem_counter};
    
endmodule