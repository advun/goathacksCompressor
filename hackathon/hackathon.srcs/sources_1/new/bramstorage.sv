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
    input [DATA_WIDTH+4-1:0] bytesout, //data output to memory
    input largebyteoutFLAG, //flag for memory to say how many bytes are being output
    input clk,
    input reset_n
    );
    
    import parameters::DATA_WIDTH;
    import parameters::SIGNAL_NUMBER;
    
    logic [7:0] compressedstorage [0:2047];
    logic [7:0] uncompressedstorage [0:2047];
    
    reg [10:0] mem_counter; //11 bits to keep track of where in memory we are
    
    always @ (posedge clk) begin //storage
        if (reset_n) begin
            
        
        end
        
        else begin
            if (onebyteoutFLAG) begin
                compressedstorage[mem_counter] = bytesout[7:0];
                mem_counter = mem_counter + 1; //blocking on purpose (unfortunatly)
            end
            
            else if (largebyteoutFLAG) begin
                compressedstorage[mem_counter] = bytesout[7:0];
                compressedstorage[mem_counter+1] = bytesout[15:8];
                compressedstorage[mem_counter+2] = bytesout[7:0];
                mem_counter = mem_counter + 3; //blocking on purpose (unfortunatly)
            end
        
        end
    
    end
    
    
endmodule

logic [31:0] bit_buf;
reg  [5:0]  bit_count; // up to 32 bits

always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        bit_buf   <= 0;
        bit_count <= 0;
        mem_counter <= 0;
    end else begin
        // Append new bits to buffer
        if (onebyteoutFLAG) begin
            bit_buf   <= bit_buf | (bytesout[7:0] << bit_count);
            bit_count <= bit_count + 8;
        end
        else if (largebyteoutFLAG) begin
            bit_buf   <= bit_buf | (bytesout[19:0] << bit_count); // 2.5 bytes
            bit_count <= bit_count + 20;
        end

        // While there are full bytes, write to memory
        while (bit_count >= 8) begin
            compressedstorage[mem_counter] <= bit_buf[7:0];
            mem_counter <= mem_counter + 1;
            bit_buf <= bit_buf >> 8;
            bit_count <= bit_count - 8;
        end
    end
end
