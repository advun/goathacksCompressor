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
    input onebyteoutFLAG, //flag for memory to say how many bytes are being output
    input [DATA_WIDTH+4-1:0] compressedin, //data output to memory
    input largebyteoutFLAG, //flag for memory to say how many bytes are being output
    input clk,
    input reset_n,
    input uncompressedflag,
    input [DATA_WIDTH*SIGNAL_NUMBER-1:0] uncompressedin,
    output logic compressedfull, //high if compressed storage is full
    output logic uncompressedfull //high if uncompressed storage is full
    );
    
    import parameters::DATA_WIDTH;
    import parameters::SIGNAL_NUMBER;
    localparam MEMSIZE = 2048; //bytes in each memory
    
    logic [7:0] compressedstorage [0:MEMSIZE-1];
    logic [7:0] uncompressedstorage [0:MEMSIZE-1];
    
    reg [$clog2(MEMSIZE)-1:0] compmem_counter; //where in compressed memory we are
    reg [$clog2(MEMSIZE)-1:0] uncompmem_counter; //where in uncompressed memory we are
    
    logic [39:0] bit_buf;
    reg  [5:0]  bit_count; // up to 63 bits
    
    assign compressedfull = (compmem_counter == MEMSIZE-1);
    assign uncompressedfull = (uncompmem_counter == MEMSIZE-1);
    
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            bit_buf   <= 0;
            bit_count <= 0;
            compmem_counter <= 0;
        end 
        else begin
            // Append new bits to buffer
            if (onebyteoutFLAG) begin
                bit_buf   <= bit_buf | (compressedin[7:0] << bit_count);
                bit_count <= bit_count + 8;
            end
            else if (largebyteoutFLAG && !compressedfull) begin
                bit_buf   <= bit_buf | (compressedin[19:0] << bit_count); // 2.5 bytes
                bit_count <= bit_count + 20;
            end
    
            // While there are full bytes, write to memory
            else if (bit_count >= 8) begin
                compressedstorage[compmem_counter] <= bit_buf[7:0];
                compmem_counter <= compmem_counter + 1;
                bit_buf <= bit_buf >> 8;
                bit_count <= bit_count - 8;
            end
        end
    end
    
    always_ff @ (posedge clk or negedge reset_n) begin //stores values to uncompressed memory
        if (!reset_n) begin
            uncompmem_counter <= 0;
        end
        else begin
            if (uncompressedflag && !uncompressedfull) begin
                for (int i = 0; i < ((DATA_WIDTH*SIGNAL_NUMBER)/8); i++) begin //0 to DATA_WIDTH*SIGNAL_NUMBER)/8 -1 
                    uncompressedstorage[uncompmem_counter+i] <= uncompressedin[8*i +: 8];
                end
                uncompmem_counter <= uncompmem_counter + ((DATA_WIDTH*SIGNAL_NUMBER)/8);
            end
        end
    end

    
    
endmodule
