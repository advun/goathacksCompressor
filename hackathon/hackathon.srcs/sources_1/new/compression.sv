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
    output reg [7:0] onebyteout,
    output reg onebyteoutFLAG,
    output reg [DATA_WIDTH+8-1:0] largebyteout,
    output reg largebyteoutFLAG
    );
    
    import parameters::DATA_WIDTH;
    import parameters::SIGNAL_NUMBER;
    
    localparam STARTER = 0; //starter compare value for delta
    localparam RLEWIDTH = 4;  //width of RLE tracker
    localparam RAWTHRESHOLD = 3; //how big does delta have to be to go to raw? both pos and neg
    
    //packet codes
    localparam RLE = 2'b00; //Normal run length encoding 1 byte = {2'bPacket Code, 2'bSignal #, 4'bRLE_count}
    localparam DELTARLE = 2'b01; //run length encoding of deltas 1 byte = {2'bPacket Code, 2'bSignal #, 4'bRLE_count}
    localparam DELTA = 2'b10; //small delta change.  1 byte = {2'bPacket Code, 2'bSignal #, 4'bDelta}
    localparam RAW = 2'b11; //Raw data bytes: DATA_WIDTH/8 + 1 bytes {2'bPacket Code, 2'bSignal #, 4'b0000} {8'bData} {8'bData} etc
    
    reg [$clog2(SIGNAL_NUMBER)-1:0] signal; //which signal is being looked at
    
    localparam IDLE = 0, CHECK_SIGNAL = 1; //states
    reg [2:0] state;
    
    reg signed [DATA_WIDTH-1:0] storageold [SIGNAL_NUMBER-1:0]; //store full values for delta encoding. old value. signed
    reg signed [DATA_WIDTH-1:0] storagenew [SIGNAL_NUMBER-1:0]; //store full values for delta encoding. new value. signed
    reg [RLEWIDTH-1:0] RLE_count [SIGNAL_NUMBER-1:0]; //how many values same in a row.  if too big, space wasted.  if too small, splits RLE up into multiple
    reg [RLEWIDTH-1:0] deltaRLE_count [SIGNAL_NUMBER-1:0]; //how many deltas same in a row
    reg signed [DATA_WIDTH-1:0] largeDeltaold [SIGNAL_NUMBER-1:0]; //last delta.  just change out for third storage??
    reg signed [DATA_WIDTH-1:0] largeDeltanew [SIGNAL_NUMBER-1:0]; //current delta
    
    //transmission buffer
    reg [DATA_WIDTH+8-1:0] packetbuffer; //regs for packet info to be transfered. 1 byte sent per cycle, leading info byte + data bytes
    
    always @ (posedge clk) begin
        if (!reset_n) begin
        state <= IDLE;
        foreach (storageold[i]) begin //initialize starting value at 0
            storageold[i] <= STARTER;
        end
        //storage news to 0
        end
        
        else begin
            case (state) 
            
                IDLE: begin
            
                    if (start) begin
                        foreach (in[i]) begin //read in values
                            storagenew[i] <= in[i];
                        end
                        state <= CHECK_SIGNAL;
                    
                    end
            
                end
                
                CHECK_SIGNAL: begin
                
                    //this is going to cause issues with assignments!!!! (i think)
                    //storagenew[signal] <= in; //bring in new value
                    //storageold[signal] <= storagenew[signal]; //shift old value
                    
                    if (storagenew[signal] == storageold[signal]) begin //check if same
                        RLE_count[signal] <= RLE_count[signal] + 1; //RLE mode!
                        
                        if (RLE_count[signal] >= ((1 << RLEWIDTH) - 1)) begin //hit max value (avoid overflow)
                            packetbuffer[7:0] <= {RLE, signal, RLE_count[signal]};
                            RLE_count[signal] <= 0;
                        end
                        
                        signal <= signal + 1; //move to next signal
                    end
                    
                    else begin //if different
                        //RLE fail
                        if (RLE_count[signal] > 0) begin //if there is an RLE run, end it
                            packetbuffer[7:0] <= {RLE, signal, RLE_count[signal]};
                            RLE_count[signal] <= 0;
                            //failed, re run through process with same signal
                        end
                        
                        else begin
                            largeDeltanew[signal] <= storagenew[signal] - storageold[signal];  //find delta
                            
                            if (largeDeltanew[signal] == largeDeltaold[signal]) begin //Delta RLE Mode
                                deltaRLE_count[signal] <= deltaRLE_count[signal] + 1; //increment counter by 1
                        
                                if (deltaRLE_count[signal] >= ((1 << RLEWIDTH) - 1)) begin //hit max value (avoid overflow)
                                    packetbuffer[7:0] <= {DELTARLE, signal, deltaRLE_count[signal]};
                                    deltaRLE_count[signal] <= 0;
                                end
                        
                                signal <= signal + 1; //move to next signal
                            end
                            
                            else if (deltaRLE_count[signal] > 0) begin //if there is a  deltaRLE run, end it
                                packetbuffer[7:0] <= {DELTARLE, signal, deltaRLE_count[signal]};
                                deltaRLE_count[signal] <= 0;
                                //failed, re run through process with same signal
                            end
                            
                            else if ((largeDelta < RAWTHRESHOLD) && (largeDelta > -RAWTHRESHOLD)) begin // if small delta: DELTA mode!
                                packetbuffer[7:0] <= {DELTA, signal, largeDelta[DATA_WIDTH], largeDelta[2:0]};  //grab sign bit and last 3 bits of delta
                                signal <= signal + 1; //move to next signal
                            end
                            
                            else begin //large delta: RAW mode!
                            packetbuffer[7:0] <= 
                            
                            end
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
