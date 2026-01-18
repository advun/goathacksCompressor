`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/18/2026 09:21:28 AM
// Design Name: 
// Module Name: tb_bram
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

module tb_bramstorage();
    import parameters::DATA_WIDTH;
    import parameters::SIGNAL_NUMBER;
    
    localparam MEMSIZE = 2048;
    
    // Clock and reset
    reg clk;
    reg reset_n;
    
    // Write port inputs
    reg onebyteoutFLAG;
    reg [DATA_WIDTH+4-1:0] compressedin;
    reg largebyteoutFLAG;
    reg uncompressedflag;
    reg [DATA_WIDTH*SIGNAL_NUMBER-1:0] uncompressedin;
    
    // Read port inputs
    reg [$clog2(MEMSIZE)-1:0] rd_addr;
    
    // DUT outputs
    wire compressedready;
    wire uncompressedfull;
    wire [$clog2(MEMSIZE)-1:0] compmem_counter;
    wire [7:0] rd_data;
    
    // DUT instantiation
    bramstorage dut (
        .onebyteoutFLAG(onebyteoutFLAG),
        .compressedin(compressedin),
        .largebyteoutFLAG(largebyteoutFLAG),
        .clk(clk),
        .reset_n(reset_n),
        .uncompressedflag(uncompressedflag),
        .uncompressedin(uncompressedin),
        .compressedready(compressedready),
        .uncompressedfull(uncompressedfull),
        .compmem_counter(compmem_counter),
        .rd_addr(rd_addr),
        .rd_data(rd_data)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Storage verification array
    logic [7:0] expected_mem [0:MEMSIZE-1];
    int expected_counter = 0;
    
    // Task to write 1-byte packet
    task write_1byte(input [7:0] data);
        begin
            @(posedge clk);
            compressedin[7:0] = data;
            onebyteoutFLAG = 1;
            largebyteoutFLAG = 0;
            @(posedge clk);
            onebyteoutFLAG = 0;
            
            // Track expected data
            expected_mem[expected_counter] = data;
            expected_counter++;
        end
    endtask
    
    // Task to write 20-bit (RAW) packet
    task write_20bit(input [19:0] data);
        begin
            @(posedge clk);
            compressedin[19:0] = data;
            onebyteoutFLAG = 0;
            largebyteoutFLAG = 1;
            @(posedge clk);
            largebyteoutFLAG = 0;
            
            // 20-bit data stored as 3 bytes (bit-packed)
            // Note: This is simplified - actual storage depends on buffer state
        end
    endtask
    
    // Task to verify read data
    task verify_read(input [$clog2(MEMSIZE)-1:0] addr, input [7:0] expected);
        begin
            rd_addr = addr;
            @(posedge clk);  // Address setup
            @(posedge clk);  // Wait for registered read
            
            if (rd_data !== expected) begin
                $display("ERROR at addr %0d: expected 0x%02X, got 0x%02X", 
                         addr, expected, rd_data);
            end else begin
                $display("  PASS: addr %0d = 0x%02X", addr, rd_data);
            end
        end
    endtask
    
    // Main test
    initial begin
        $display("Starting BRAM storage testbench...\n");
        
        // Initialize
        reset_n = 0;
        onebyteoutFLAG = 0;
        largebyteoutFLAG = 0;
        uncompressedflag = 0;
        compressedin = 0;
        uncompressedin = 0;
        rd_addr = 0;
        expected_counter = 0;
        
        repeat(5) @(posedge clk);
        reset_n = 1;
        repeat(2) @(posedge clk);
        
        //=================================================================
        // TEST 1: Basic 1-byte writes
        //=================================================================
        $display("TEST 1: Writing 1-byte packets");
        
        for (int i = 0; i < 10; i++) begin
            write_1byte(8'hA0 + i);
        end
        
        repeat(5) @(posedge clk);
        
        $display("  Bytes stored: %0d (expected ~10)", compmem_counter);
        $display("  Ready status: %0d", compressedready);
        
        //=================================================================
        // TEST 2: Verify stored data via read port
        //=================================================================
        $display("\nTEST 2: Reading back data");
        
        for (int i = 0; i < 10; i++) begin
            verify_read(i, 8'hA0 + i);
        end
        
        //=================================================================
        // TEST 3: Bit packing test (buffer behavior)
        //=================================================================
        $display("\nTEST 3: Bit packing and buffer behavior");
        
        // Reset for clean test
        @(posedge clk);
        reset_n = 0;
        @(posedge clk);
        reset_n = 1;
        expected_counter = 0;
        repeat(2) @(posedge clk);
        
        // Write bytes that should pack into buffer
        $display("  Writing sequence of 1-byte packets...");
        for (int i = 0; i < 5; i++) begin
            write_1byte(8'h00 + i);
            $display("    After byte %0d: counter=%0d, buffer has data", 
                     i, compmem_counter);
        end
        
        repeat(10) @(posedge clk);
        $display("  Final count after settling: %0d", compmem_counter);
        
        //=================================================================
        // TEST 4: Near-full condition
        //=================================================================
        $display("\nTEST 4: Filling storage near capacity");
        
        @(posedge clk);
        reset_n = 0;
        @(posedge clk);
        reset_n = 1;
        repeat(2) @(posedge clk);
        
        // Fill most of the BRAM
        for (int i = 0; i < MEMSIZE - 10; i++) begin
            write_1byte(8'hFF - (i % 256));
            if (i % 100 == 0) begin
                $display("  Written %0d bytes, ready=%0d", compmem_counter, compressedready);
            end
        end
        
        repeat(10) @(posedge clk);
        $display("  Near full: counter=%0d, ready=%0d", compmem_counter, compressedready);
        
        // Try to overfill
        for (int i = 0; i < 20; i++) begin
            write_1byte(8'hEE);
        end
        
        repeat(10) @(posedge clk);
        $display("  After overfill attempt: counter=%0d, ready=%0d", 
                 compmem_counter, compressedready);
        
        //=================================================================
        // TEST 5: Uncompressed storage
        //=================================================================
        $display("\nTEST 5: Uncompressed data storage");
        
        @(posedge clk);
        reset_n = 0;
        @(posedge clk);
        reset_n = 1;
        repeat(2) @(posedge clk);
        
        for (int i = 0; i < 10; i++) begin
            uncompressedin = {16'h4444, 16'h3333, 16'h2222, 16'h1111} + i;
            uncompressedflag = 1;
            @(posedge clk);
            uncompressedflag = 0;
            @(posedge clk);
        end
        
        repeat(5) @(posedge clk);
        $display("  Uncompressed full status: %0d", uncompressedfull);
        
        //=================================================================
        // TEST 6: Simultaneous compressed + uncompressed writes
        //=================================================================
        $display("\nTEST 6: Simultaneous writes");
        
        @(posedge clk);
        reset_n = 0;
        @(posedge clk);
        reset_n = 1;
        repeat(2) @(posedge clk);
        
        for (int i = 0; i < 5; i++) begin
            // Write both compressed and uncompressed in same cycle
            @(posedge clk);
            compressedin[7:0] = 8'hCC + i;
            onebyteoutFLAG = 1;
            uncompressedin = {16'hDDDD, 16'hCCCC, 16'hBBBB, 16'hAAAA} + i;
            uncompressedflag = 1;
            @(posedge clk);
            onebyteoutFLAG = 0;
            uncompressedflag = 0;
        end
        
        repeat(5) @(posedge clk);
        $display("  Compressed counter: %0d", compmem_counter);
        
        $display("\n========================================");
        $display("BRAM storage tests completed!");
        $display("========================================\n");
        
        $finish;
    end
    
    // Timeout
    initial begin
        #50000;
        $display("ERROR: Testbench timeout!");
        $finish;
    end

endmodulemodule tb_bram(

    );
endmodule
