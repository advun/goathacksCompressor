`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/18/2026 09:49:34 AM
// Design Name: 
// Module Name: tb_compression_simple
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


module tb_compression_simple();
    import parameters::DATA_WIDTH;
    import parameters::SIGNAL_NUMBER;
    
    // Clock and reset
    reg clk;
    reg reset_n;
    
    // DUT inputs
    reg [DATA_WIDTH-1:0] in [SIGNAL_NUMBER-1:0];
    reg start;
    reg compressedready;
    reg uncompressedfull;
    
    // DUT outputs
    wire onebyteoutFLAG;
    wire [DATA_WIDTH+4-1:0] bytesout;
    wire largebyteoutFLAG;
    wire uncompressedFLAG;
    wire [DATA_WIDTH*SIGNAL_NUMBER-1:0] uncompressed;
    
    // DUT instantiation
    compression dut (
        .in(in),
        .start(start),
        .clk(clk),
        .reset_n(reset_n),
        .compressedready(compressedready),
        .uncompressedfull(uncompressedfull),
        .onebyteoutFLAG(onebyteoutFLAG),
        .bytesout(bytesout),
        .largebyteoutFLAG(largebyteoutFLAG),
        .uncompressedFLAG(uncompressedFLAG),
        .uncompressed(uncompressed)
    );
    
    // Clock generation (100 MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Packet monitoring
    always @(posedge clk) begin
        if (onebyteoutFLAG) begin
            $display("  [%0t] 1-byte packet: 0x%02X", $time, bytesout[7:0]);
        end
        
        if (largebyteoutFLAG) begin
            $display("  [%0t] RAW packet: 0x%05X", $time, bytesout[19:0]);
        end
    end
    
    // Simple test
    integer i;
    initial begin
        $display("=== SIMPLE COMPRESSION TEST ===\n");
        
        // Initialize
        reset_n = 0;
        start = 0;
        compressedready = 1;
        uncompressedfull = 0;
        in[0] = 0;
        in[1] = 0;
        in[2] = 0;
        in[3] = 0;
        
        #50;
        reset_n = 1;
        #20;
        
        $display("TEST: Send 10 samples of value 100");
        for (i = 0; i < 10; i = i + 1) begin
            $display("Sample %0d:", i);
            in[0] = 100;
            in[1] = 100;
            in[2] = 100;
            in[3] = 100;
            start = 1;
            #10;
            start = 0;
            #50;  // Wait between samples
        end
        
        $display("\nTEST: Wait for any pending packets");
        #200;
        
        $display("\n=== TEST COMPLETE ===\n");
        #100;
        $finish;
    end
    
    // Safety timeout
    initial begin
        #10000;
        $display("ERROR: Timeout at %0t", $time);
        $finish;
    end

endmodule
