`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/17/2026 05:33:25 PM
// Design Name: 
// Module Name: bramstorage
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


module bramstorage(
    input onebyteoutFLAG,
    input [DATA_WIDTH+4-1:0] compressedin,
    input largebyteoutFLAG,
    input clk,
    input reset_n,
    input uncompressedflag,
    input [DATA_WIDTH*SIGNAL_NUMBER-1:0] uncompressedin,
    output logic compressedfull,
    output logic uncompressedfull
);
    
    import parameters::DATA_WIDTH;
    import parameters::SIGNAL_NUMBER;
    localparam MEMSIZE = 2048;
    localparam BYTES_PER_SAMPLE = (DATA_WIDTH*SIGNAL_NUMBER)/8;  // = 8
    localparam SAMPLE_MEMSIZE = MEMSIZE/BYTES_PER_SAMPLE;        // = 256 samples
    
    // Compressed storage (single BRAM)
    logic [7:0] compressedstorage [0:MEMSIZE-1];
    
    // Uncompressed storage (8 separate BRAMs, one per byte position)
    logic [7:0] uncomp_mem0 [0:SAMPLE_MEMSIZE-1];
    logic [7:0] uncomp_mem1 [0:SAMPLE_MEMSIZE-1];
    logic [7:0] uncomp_mem2 [0:SAMPLE_MEMSIZE-1];
    logic [7:0] uncomp_mem3 [0:SAMPLE_MEMSIZE-1];
    logic [7:0] uncomp_mem4 [0:SAMPLE_MEMSIZE-1];
    logic [7:0] uncomp_mem5 [0:SAMPLE_MEMSIZE-1];
    logic [7:0] uncomp_mem6 [0:SAMPLE_MEMSIZE-1];
    logic [7:0] uncomp_mem7 [0:SAMPLE_MEMSIZE-1];
    
    reg [$clog2(MEMSIZE)-1:0] compmem_counter;
    reg [$clog2(SAMPLE_MEMSIZE)-1:0] uncompmem_counter;
    
    logic [39:0] bit_buf;
    reg [5:0] bit_count;
    
    // Full flags - conservative thresholds
    assign compressedfull = (compmem_counter >= MEMSIZE-3);
    assign uncompressedfull = (uncompmem_counter >= SAMPLE_MEMSIZE-1);
    
    // Compressed data storage - can accept input AND drain buffer in same cycle
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            bit_buf <= 0;
            bit_count <= 0;
            compmem_counter <= 0;
        end 
        else begin
            // Determine operations (all use CURRENT values for decisions)
            logic will_drain = (bit_count >= 8) && (compmem_counter < MEMSIZE);
            logic will_add_1byte = onebyteoutFLAG && (compmem_counter < MEMSIZE-1);
            logic will_add_2p5byte = largebyteoutFLAG && (compmem_counter < MEMSIZE-3) && !will_add_1byte;
            
            // Calculate shifts for drain operation
            logic [39:0] shifted_buf = will_drain ? (bit_buf >> 8) : bit_buf;
            logic [5:0] reduced_count = will_drain ? (bit_count - 6'd8) : bit_count;
            
            // Perform drain (write to memory)
            if (will_drain) begin
                compressedstorage[compmem_counter] <= bit_buf[7:0];
                compmem_counter <= compmem_counter + 1;
            end
            
            // Add new data to the (potentially drained) buffer
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
    
    // Uncompressed data storage - writes all 8 bytes in parallel to separate BRAMs
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
