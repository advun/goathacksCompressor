`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/16/2026 09:34:57 PM
// Design Name: 
// Module Name: compression
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


module compression #(parameter STARTER = 0)( //starting value
    input in, //single bit input stream
    input clk,
    input reset_n
    );
    import parameters::DATA_WIDTH;
    
    reg [DATA_WIDTH-1:0] storage0; //store full values for delta encoding. old value
    reg [DATA_WIDTH-1:0] storage1; //store full values for delta encoding. new value
    reg [DATA_WIDTH-1:0] i; //counting variable
    
    //accumulator (accumulates single bit input stream into storage registers)
    always @ (posedge clk) begin
        if (!reset_n) begin
            storage0 <= STARTER;
            storage1 <= 0;
        end
        
        else begin
            storage1[i] = in;
            
        end
    
    end
    
    
    //delta encoding
    always @ (posedge clk) begin
    
    end
    
endmodule
