`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/17/2026 09:18:17 PM
// Design Name: 
// Module Name: bram_readout
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
    
    localparam IDLE = 0, READ_BRAM = 1, WAIT_BRAM = 2, SEND_BYTE = 3, DONE = 4;
    reg [2:0] state;
    
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
                    // Issue BRAM read address
                    rd_addr <= read_ptr;
                    state <= WAIT_BRAM;
                end
                
                WAIT_BRAM: begin
                    // Wait 1 cycle for BRAM data to arrive (registered output)
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
