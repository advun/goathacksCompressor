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
    
    // Test signal generation (replace with your actual signals)
    reg [15:0] test_counter;
    reg [15:0] test_slow;
    reg [15:0] test_fsm;
    reg [15:0] test_random;
    
    reg [31:0] sample_tick_counter;
    wire sample_tick = (sample_tick_counter == 100000 - 1); // 1kHz
    
    always @(posedge clk) begin
        if (rst) begin
            sample_tick_counter <= 0;
            test_counter <= 0;
            test_slow <= 0;
            test_fsm <= 0;
            test_random <= 8'hA5;
        end else begin
            sample_tick_counter <= sample_tick ? 0 : sample_tick_counter + 1;
            
            if (sample_tick) begin
                test_counter <= test_counter + 1;
                if (test_counter[11:0] == 0)
                    test_slow <= test_slow + 1;
                if (test_counter[7:0] == 0)
                    test_fsm <= test_fsm + 1;
                test_random <= {test_random[6:0], test_random[7] ^ test_random[5]};
            end
        end
    end
    
    wire [DATA_WIDTH-1:0] signals [SIGNAL_NUMBER-1:0];
    assign signals[0] = test_counter;
    assign signals[1] = test_fsm;
    assign signals[2] = test_random;
    assign signals[3] = test_slow;
    
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

