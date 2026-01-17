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

module compression (
    input [DATA_WIDTH-1:0] in [SIGNAL_NUMBER-1:0],
    input start,
    input clk,
    input reset_n,
    output reg onebyteoutFLAG, //flag for memory to say how many bytes are being output
    output reg [DATA_WIDTH+4-1:0] bytesout, //data output to memory
    output reg largebyteoutFLAG //flag for memory to say how many bytes are being output 
    );
    
    import parameters::DATA_WIDTH;
    import parameters::SIGNAL_NUMBER;
    
    localparam STARTER = 0; //starter compare value for delta
    localparam RLEWIDTH = 4;  //width of RLE tracker
    localparam RAWTHRESHOLD = 7; //how big does delta have to be to go to raw? both pos and neg
    
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
    
    always @ (posedge clk) begin
        if (!reset_n) begin
            
            foreach (storagenew[i]) begin //initialize starting value at 0
                storagenew[i] <= STARTER;
            end
            
            //reset run length counts
            foreach (RLE_count[i]) begin 
                RLE_count[i] <= 0;
            end
            
            foreach (deltaRLE_count[i]) begin
                deltaRLE_count[i] <= 0;
            end
            
            foreach (largeDeltaold[i]) begin
                largeDeltaold[i] <= 0;
            end
            
            foreach (largeDeltanew[i]) begin
                largeDeltanew[i] <= 0;
            end
            
            onebyteoutFLAG <= 0;
            largebyteoutFLAG <= 0;
            signal <= 0;
            state <= IDLE;
        end
        
        else begin
            //clear flags every cycle
            onebyteoutFLAG <= 0;
            largebyteoutFLAG <= 0;
            
            case (state) 
            
                IDLE: begin
            
                    if (start) begin
                        foreach (storagenew[i]) begin //move new values to old values
                            storageold[i] <= storagenew[i];
                        end
                        
                        foreach (in[i]) begin //read in new values
                            storagenew[i] <= in[i];
                        end
                        
                        signal <= 0;
                        state <= CHECK_SIGNAL;
                    end
            
                end
                
                CHECK_SIGNAL: begin
                    
                    if (storagenew[signal] == storageold[signal]) begin //check if same
                        RLE_count[signal] <= RLE_count[signal] + 1; //RLE mode!
                        
                        if (RLE_count[signal] >= ((1 << RLEWIDTH) - 1)) begin //hit max value (avoid overflow)
                            bytesout[7:0] <= {RLE, signal, RLE_count[signal]};
                            onebyteoutFLAG <= 1;
                            RLE_count[signal] <= 0;
                        end
                        
                        if (signal == SIGNAL_NUMBER-1) begin //if done with signals, go back to IDLE
                                    state <= IDLE;
                                    signal <= 0;
                                end
                                else begin
                                    signal <= signal + 1; //move to next signal
                                end
                    end
                    
                    else begin //if different
                        //RLE fail
                        if (RLE_count[signal] > 0) begin //if there is an RLE run, end it
                            bytesout[7:0] <= {RLE, signal, RLE_count[signal]};
                            onebyteoutFLAG <= 1;
                            RLE_count[signal] <= 0;
                            //failed, re run through process with same signal
                        end
                        
                        else begin
                            //not super happy about this being blocking, but may be simplest approach.  check if timing violations
                            largeDeltaold[signal] = largeDeltanew[signal]; //update largeDeltaold
                            largeDeltanew[signal] = storagenew[signal] - storageold[signal];  //find delta
                            
                            if (largeDeltanew[signal] == largeDeltaold[signal]) begin //Delta RLE Mode
                                deltaRLE_count[signal] <= deltaRLE_count[signal] + 1; //increment counter by 1
                        
                                if (deltaRLE_count[signal] >= ((1 << RLEWIDTH) - 1)) begin //hit max value (avoid overflow)
                                    bytesout[7:0] <= {DELTARLE, signal, deltaRLE_count[signal]};
                                    onebyteoutFLAG <= 1;
                                    deltaRLE_count[signal] <= 0;
                                end
                                if (signal == SIGNAL_NUMBER-1) begin //if done with signals, go back to IDLE
                                    state <= IDLE;
                                    signal <= 0;
                                end
                                else begin
                                    signal <= signal + 1; //move to next signal
                                end
                            end
                            
                            else if (deltaRLE_count[signal] > 0) begin //if there is a deltaRLE run, end it
                                bytesout[7:0] <= {DELTARLE, signal, deltaRLE_count[signal]};
                                onebyteoutFLAG <= 1;
                                deltaRLE_count[signal] <= 0;
                                //failed, re run through process with same signal
                            end
                            
                            else if ((largeDeltanew[signal] < RAWTHRESHOLD) && (largeDeltanew[signal] > -RAWTHRESHOLD)) begin // if small delta: DELTA mode!
                                bytesout[7:0] <= {DELTA, signal, largeDeltanew[signal][DATA_WIDTH-1], largeDeltanew[signal][2:0]};  //grab sign bit and last 3 bits of delta
                                onebyteoutFLAG <= 1;
                                if (signal == SIGNAL_NUMBER-1) begin //if done with signals, go back to IDLE
                                    state <= IDLE;
                                    signal <= 0;
                                end
                                else begin
                                    signal <= signal + 1; //move to next signal
                                end
                            end
                            
                            else begin //large delta: RAW mode!
                                bytesout[DATA_WIDTH+4-1:0] <= {RAW, signal, storagenew[signal]}; 
                                largebyteoutFLAG <= 1;
                                if (signal == SIGNAL_NUMBER-1) begin //if done with signals, go back to IDLE
                                        state <= IDLE;
                                        signal <= 0;
                                    end
                                    else begin
                                        signal <= signal + 1; //move to next signal
                                    end
                            end   
                        end
                    end
                end
                
                //Extra Case: begin
            
            
            
                //end         
            endcase
            
        end
    
    end
    
endmodule
