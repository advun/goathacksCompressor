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


module compression ( //starting value
    input [DATA_WIDTH-1:0] in [SIGNAL_NUMBER-1:0],
    input start,
    input clk,
    input reset_n,
    input [$clog2(SIGNAL_NUMBER)-1:0] signal
    );
    import parameters::DATA_WIDTH;
    import parameters::SIGNAL_NUMBER;
    
    localparam STARTER = 0; //starter compare value for delta
    localparam RLEWIDTH = 4;  //width of RLE tracker
    localparam RAWTHRESHOLD = 3; //how big does delta have to be to go to raw?
    
    localparam RLE = 2'b00;
    localparam DELTA = 2'b01;
    localparam RAW = 2'b10;
    
    localparam IDLE = 0, CHECK_SIGNAL = 1; //states
    reg [2:0] state;
    
    reg signed [DATA_WIDTH-1:0] storageold [SIGNAL_NUMBER-1:0]; //store full values for delta encoding. old value. signed
    reg signed [DATA_WIDTH-1:0] storagenew [SIGNAL_NUMBER-1:0]; //store full values for delta encoding. new value. signed
    reg [RLEWIDTH-1:0] RLE_count [SIGNAL_NUMBER-1:0]; //how many values same in a row.  if too big, space wasted.  if too small, splits RLE up into multiple
    reg signed [DATA_WIDTH:0] largeDelta; //has to be one larger, as signed
    
    //transmission buffer
    reg [7:0] packetinfo; //regs for packet info to be transfered
    reg [7:0] packetdata [((DATA_WIDTH + 8 - 1) / 8)-1:0]; //regs for data packets
    
    always @ (posedge clk) begin
        if (!reset_n) begin
        //storage olds to starter
        //storage news to 0
        end
        
        else begin
            case (state) 
            
                IDLE: begin
            
                    if (start)
            
                end
                
                CHECK_SIGNAL: begin
                
                    storagenew[signal] <= in; //bring in new value
                    storageold[signal] <= storagenew[signal]; //shift old value
                    
                    if (storagenew[signal] == storageold[signal]) begin //check if same
                        RLE_count[signal] <= RLE_count[signal] + 1; //RLE mode!
                        
                        if (RLE_count[signal] >= ((1 << RLEWIDTH) - 1)) begin //hit max value
                            //RLE fail
                            RLE_count[signal] <= 0;
                            packetinfo <= {1,1,RLE, signal}; //transmission starts with 2 1s
                            //Send RLE flag, length, value (delta?)
                        end
                    end
                    
                    else begin //if different
                        //RLE fail
                        RLE_count[signal] <= 0;
                        //Send RLE flag, length, value (delta?)
                    
                        largeDelta <= storagenew[signal] - storageold[signal];
                    
                        if ((largeDelta < RAWTHRESHOLD) && (largeDelta > -RAWTHRESHOLD)) begin //small delta: DELTA mode!
                        
                    
                        end
                        
                        else begin //large delta: RAW mode!
                        
                        end
                   
                    end
                end
                
                TODO: begin
            
            
            
                end
            
            endcase
            
        end
    
    end
    
    
    
    always @ (posedge clk) begin
    
    end
    
endmodule
