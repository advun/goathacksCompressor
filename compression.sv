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


module compression(
    input in
    );
    import parameters::DATA_WIDTH;
    
    reg [DATA_WIDTH-1:0] datum;
    //delta encoding
    always @ (posedge clk) begin
    
    end
    
endmodule
