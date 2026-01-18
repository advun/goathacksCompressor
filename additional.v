`timescale 1ns / 1ps

// UART Transmitter - sends one byte at a time
module uart_tx #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD_RATE = 115200
)(
    input wire clk,
    input wire rst,
    input wire [7:0] data,
    input wire valid,       // Assert to send data
    output reg ready,       // High when ready for new data
    output reg tx           // UART TX line
);
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    
    localparam IDLE = 0, START = 1, DATA = 2, STOP = 3;
    reg [1:0] state;
    reg [15:0] clk_count;
    reg [2:0] bit_index;
    reg [7:0] data_reg;
    
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            tx <= 1;
            ready <= 1;
            clk_count <= 0;
            bit_index <= 0;
        end else begin
            case (state)
                IDLE: begin
                    tx <= 1;
                    ready <= 1;
                    if (valid && ready) begin
                        data_reg <= data;
                        ready <= 0;
                        state <= START;
                        clk_count <= 0;
                    end
                end
                
                START: begin
                    tx <= 0;
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        state <= DATA;
                        bit_index <= 0;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
                
                DATA: begin
                    tx <= data_reg[bit_index];
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        if (bit_index == 7) begin
                            state <= STOP;
                        end else begin
                            bit_index <= bit_index + 1;
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
                
                STOP: begin
                    tx <= 1;
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        state <= IDLE;
                        ready <= 1;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
            endcase
        end
    end
endmodule


// BRAM Readout Controller - dumps compressed BRAM to UART
module bram_readout #(
    parameter MEMSIZE = 2048
)(
    input wire clk,
    input wire rst,
    
    // Control
    input wire start_readout,           // Pulse to start transfer
    input wire [$clog2(MEMSIZE)-1:0] bytes_stored,  // How many bytes to send
    
    // BRAM interface (read)
    output reg [$clog2(MEMSIZE)-1:0] rd_addr,
    input wire [7:0] rd_data,
    
    // UART TX interface
    output reg [7:0] tx_data,
    output reg tx_valid,
    input wire tx_ready,
    
    // Status
    output reg reading_out,
    output reg [$clog2(MEMSIZE)-1:0] bytes_sent
);
    
    localparam IDLE = 0, READ_BRAM = 1, SEND_BYTE = 2, DONE = 3;
    reg [1:0] state;
    
    reg [$clog2(MEMSIZE)-1:0] bytes_to_send;
    reg [$clog2(MEMSIZE)-1:0] read_ptr;
    
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            reading_out <= 0;
            bytes_sent <= 0;
            rd_addr <= 0;
            tx_valid <= 0;
            read_ptr <= 0;
            bytes_to_send <= 0;
            
        end else begin
            case (state)
                IDLE: begin
                    reading_out <= 0;
                    bytes_sent <= 0;
                    tx_valid <= 0;
                    
                    if (start_readout && bytes_stored > 0) begin
                        bytes_to_send <= bytes_stored;
                        read_ptr <= 0;
                        rd_addr <= 0;
                        reading_out <= 1;
                        state <= READ_BRAM;
                    end
                end
                
                READ_BRAM: begin
                    // BRAM has 1-cycle latency
                    rd_addr <= read_ptr;
                    state <= SEND_BYTE;
                end
                
                SEND_BYTE: begin
                    if (!tx_valid) begin
                        // Load data from BRAM (arrives this cycle)
                        tx_data <= rd_data;
                        tx_valid <= 1;
                    end else if (tx_ready) begin
                        // UART accepted the byte
                        tx_valid <= 0;
                        bytes_sent <= bytes_sent + 1;
                        read_ptr <= read_ptr + 1;
                        
                        // Check if done
                        if (read_ptr >= bytes_to_send - 1) begin
                            state <= DONE;
                        end else begin
                            state <= READ_BRAM;
                        end
                    end
                end
                
                DONE: begin
                    reading_out <= 0;
                    tx_valid <= 0;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule


// Top-level integration example
// This shows how to connect everything together
module readout_top (
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
    bramstorage_with_readout #(
        .MEMSIZE(MEMSIZE)
    ) storage (
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
                  reading_out ? bytes_sent[13:0] : compmem_counter[13:0]};
    
endmodule


// Modified BRAM storage with read port added
module bramstorage_with_readout #(
    parameter MEMSIZE = 2048
)(
    input onebyteoutFLAG,
    input [19:0] compressedin,  // DATA_WIDTH+4-1 with DATA_WIDTH=16
    input largebyteoutFLAG,
    input clk,
    input reset_n,
    input uncompressedflag,
    input [63:0] uncompressedin,  // DATA_WIDTH*SIGNAL_NUMBER-1 with params
    output logic compressedready,
    output logic uncompressedfull,
    output logic [$clog2(MEMSIZE)-1:0] compmem_counter,
    
    // Read port for UART readout
    input wire [$clog2(MEMSIZE)-1:0] rd_addr,
    output logic [7:0] rd_data
);
    
    localparam DATA_WIDTH = 16;
    localparam SIGNAL_NUMBER = 4;
    localparam BYTES_PER_SAMPLE = (DATA_WIDTH*SIGNAL_NUMBER)/8;
    localparam SAMPLE_MEMSIZE = MEMSIZE/BYTES_PER_SAMPLE;
    
    // Compressed storage (single BRAM with read port)
    logic [7:0] compressedstorage [0:MEMSIZE-1];
    
    // Uncompressed storage
    logic [7:0] uncomp_mem0 [0:SAMPLE_MEMSIZE-1];
    logic [7:0] uncomp_mem1 [0:SAMPLE_MEMSIZE-1];
    logic [7:0] uncomp_mem2 [0:SAMPLE_MEMSIZE-1];
    logic [7:0] uncomp_mem3 [0:SAMPLE_MEMSIZE-1];
    logic [7:0] uncomp_mem4 [0:SAMPLE_MEMSIZE-1];
    logic [7:0] uncomp_mem5 [0:SAMPLE_MEMSIZE-1];
    logic [7:0] uncomp_mem6 [0:SAMPLE_MEMSIZE-1];
    logic [7:0] uncomp_mem7 [0:SAMPLE_MEMSIZE-1];
    
    reg [$clog2(SAMPLE_MEMSIZE)-1:0] uncompmem_counter;
    
    logic [39:0] bit_buf;
    reg [5:0] bit_count;
    
    logic compressedfull;
    
    assign compressedfull = (compmem_counter >= MEMSIZE-3); 
    assign uncompressedfull = (uncompmem_counter >= SAMPLE_MEMSIZE-1);
    assign compressedready = (bit_count <= 20) && !compressedfull;
    
    // Read port - combinational
    assign rd_data = compressedstorage[rd_addr];
    
    // Compressed data storage
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            bit_buf <= 0;
            bit_count <= 0;
            compmem_counter <= 0;
        end 
        else begin
            logic will_drain;
            logic will_add_1byte;
            logic will_add_2p5byte;
            
            will_drain       = (bit_count >= 8) && !compressedfull;
            will_add_1byte   = onebyteoutFLAG  && (bit_count <= 40-8);
            will_add_2p5byte = largebyteoutFLAG && !will_add_1byte && (bit_count <= 40-20);
            
            logic [39:0] shifted_buf;
            logic [5:0]  reduced_count;
            
            shifted_buf   = will_drain ? (bit_buf >> 8) : bit_buf;
            reduced_count = will_drain ? (bit_count - 6'd8) : bit_count;
            
            if (will_drain) begin
                compressedstorage[compmem_counter] <= bit_buf[7:0];
                compmem_counter <= compmem_counter + 1;
            end
            
            if (will_add_1byte) begin
                bit_buf <= shifted_buf | (compressedin[7:0] << reduced_count);
                bit_count <= reduced_count + 6'd8;
            end
            else if (will_add_2p5byte) begin
                bit_buf <= shifted_buf | (compressedin[19:0] << reduced_count);
                bit_count <= reduced_count + 6'd20;
            end
            else if (will_drain) begin
                bit_buf <= shifted_buf;
                bit_count <= reduced_count;
            end
        end
    end
    
    // Uncompressed data storage
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            uncompmem_counter <= 0;
        end
        else begin
            if (uncompressedflag && !uncompressedfull) begin
                uncomp_mem0[uncompmem_counter] <= uncompressedin[7:0];
                uncomp_mem1[uncompmem_counter] <= uncompressedin[15:8];
                uncomp_mem2[uncompmem_counter] <= uncompressedin[23:16];
                uncomp_mem3[uncompmem_counter] <= uncompressedin[31:24];
                uncomp_mem4[uncompmem_counter] <= uncompressedin[39:32];
                uncomp_mem5[uncompmem_counter] <= uncompressedin[47:40];
                uncomp_mem6[uncompmem_counter] <= uncompressedin[55:48];
                uncomp_mem7[uncompmem_counter] <= uncompressedin[63:56];
                uncompmem_counter <= uncompmem_counter + 1;
            end
        end
    end
    
endmodule
