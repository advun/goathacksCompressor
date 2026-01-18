`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/18/2026 09:23:53 AM
// Design Name: 
// Module Name: tb_uart
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


module tb_uart_readout();
    
    localparam MEMSIZE = 128;  // Smaller for faster testing
    localparam CLK_FREQ = 100_000_000;
    localparam BAUD_RATE = 115200;
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    
    // Clock and reset
    reg clk;
    reg rst;
    
    // Readout control
    reg start_readout;
    reg [$clog2(MEMSIZE)-1:0] bytes_stored;
    
    // BRAM interface
    wire [$clog2(MEMSIZE)-1:0] rd_addr;
    reg [7:0] rd_data;
    
    // UART interface
    wire [7:0] tx_data;
    wire tx_valid;
    wire tx_ready;
    wire uart_tx;
    
    // Status
    wire reading_out;
    wire [$clog2(MEMSIZE)-1:0] bytes_sent;
    
    // Test BRAM (simulated)
    reg [7:0] test_bram [0:MEMSIZE-1];
    
    // Readout controller
    bram_readout #(
        .MEMSIZE(MEMSIZE)
    ) readout (
        .clk(clk),
        .rst(rst),
        .start_readout(start_readout),
        .bytes_stored(bytes_stored),
        .rd_addr(rd_addr),
        .rd_data(rd_data),
        .tx_data(tx_data),
        .tx_valid(tx_valid),
        .tx_ready(tx_ready),
        .reading_out(reading_out),
        .bytes_sent(bytes_sent)
    );
    
    // UART transmitter
    uart_tx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) uart (
        .clk(clk),
        .rst(rst),
        .data(tx_data),
        .valid(tx_valid),
        .ready(tx_ready),
        .tx(uart_tx)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // BRAM read simulation (registered output)
    always @(posedge clk) begin
        if (rst)
            rd_data <= 0;
        else
            rd_data <= test_bram[rd_addr];
    end
    
    // UART receiver for verification
    reg [7:0] received_bytes [0:MEMSIZE-1];
    int rx_count = 0;
    
    task uart_receive();
        reg [7:0] data;
        int i;
        begin
            // Wait for start bit
            @(negedge uart_tx);
            
            // Wait to middle of start bit
            repeat(CLKS_PER_BIT/2) @(posedge clk);
            
            // Sample 8 data bits
            for (i = 0; i < 8; i++) begin
                repeat(CLKS_PER_BIT) @(posedge clk);
                data[i] = uart_tx;
            end
            
            // Wait through stop bit
            repeat(CLKS_PER_BIT) @(posedge clk);
            
            received_bytes[rx_count] = data;
            $display("  [%0t] UART RX: byte %0d = 0x%02X", $time, rx_count, data);
            rx_count++;
        end
    endtask
    
    // UART receiver process
    initial begin
        wait(rst == 0);
        forever uart_receive();
    end
    
    // Main test
    initial begin
        // Declare all variables at the beginning
        int errors;
        int first_rx;
        longint start_time, end_time, duration;
        real bits_per_byte;
        real expected_time_ns;
        
        $display("\n========================================");
        $display("UART READOUT TESTBENCH");
        $display("========================================\n");
        
        // Initialize
        rst = 1;
        start_readout = 0;
        bytes_stored = 0;
        
        // Fill test BRAM with pattern
        for (int i = 0; i < MEMSIZE; i++) begin
            test_bram[i] = 8'hA0 + (i % 32);
        end
        
        repeat(10) @(posedge clk);
        rst = 0;
        repeat(10) @(posedge clk);
        
        //=================================================================
        // TEST 1: Basic readout
        //=================================================================
        $display("TEST 1: Reading 10 bytes from BRAM");
        
        bytes_stored = 10;
        rx_count = 0;
        
        @(posedge clk);
        start_readout = 1;
        @(posedge clk);
        start_readout = 0;
        
        // Wait for readout to start
        wait(reading_out == 1);
        $display("  Readout started");
        
        // Wait for completion
        wait(reading_out == 0);
        $display("  Readout completed");
        $display("  Bytes sent: %0d", bytes_sent);
        
        // Verify
        repeat(100) @(posedge clk);
        $display("\n  Verification:");
        for (int i = 0; i < 10; i++) begin
            if (received_bytes[i] !== test_bram[i]) begin
                $display("    ERROR at byte %0d: expected 0x%02X, got 0x%02X",
                         i, test_bram[i], received_bytes[i]);
            end else begin
                $display("    PASS byte %0d: 0x%02X", i, received_bytes[i]);
            end
        end
        
        //=================================================================
        // TEST 2: Full BRAM readout
        //=================================================================
        $display("\nTEST 2: Reading all %0d bytes", MEMSIZE);
        
        bytes_stored = MEMSIZE;
        rx_count = 0;
        
        @(posedge clk);
        start_readout = 1;
        @(posedge clk);
        start_readout = 0;
        
        wait(reading_out == 1);
        $display("  Readout started");
        
        // Monitor progress
        fork
            begin
                while (reading_out) begin
                    repeat(5000) @(posedge clk);
                    $display("    Progress: %0d/%0d bytes", bytes_sent, MEMSIZE);
                end
            end
        join_none
        
        wait(reading_out == 0);
        $display("  Readout completed: %0d bytes", bytes_sent);
        
        // Wait for all UART transmissions
        repeat(10000) @(posedge clk);
        
        // Verify all bytes
        errors = 0;
        for (int i = 0; i < MEMSIZE; i++) begin
            if (received_bytes[i] !== test_bram[i]) begin
                if (errors < 10) begin  // Only print first 10 errors
                    $display("    ERROR at byte %0d: expected 0x%02X, got 0x%02X",
                             i, test_bram[i], received_bytes[i]);
                end
                errors++;
            end
        end
        
        if (errors == 0) begin
            $display("  PASS: All %0d bytes verified correctly!", MEMSIZE);
        end else begin
            $display("  FAIL: %0d errors found", errors);
        end
        
        //=================================================================
        // TEST 3: Zero-length readout
        //=================================================================
        $display("\nTEST 3: Zero-length readout (edge case)");
        
        bytes_stored = 0;
        rx_count = 0;
        
        @(posedge clk);
        start_readout = 1;
        @(posedge clk);
        start_readout = 0;
        
        repeat(100) @(posedge clk);
        
        if (reading_out) begin
            $display("  ERROR: Should not start readout with 0 bytes");
        end else begin
            $display("  PASS: Correctly ignored zero-length readout");
        end
        
        //=================================================================
        // TEST 4: UART timing verification
        //=================================================================
        $display("\nTEST 4: UART timing verification");
        
        bytes_stored = 3;
        rx_count = 0;
        
        bits_per_byte = 10;  // 1 start + 8 data + 1 stop
        expected_time_ns = (3 * bits_per_byte * CLKS_PER_BIT * 10);  // 10ns per clock
        
        start_time = $time;
        
        @(posedge clk);
        start_readout = 1;
        @(posedge clk);
        start_readout = 0;
        
        wait(reading_out == 0);
        end_time = $time;
        
        repeat(2000) @(posedge clk);
        
        duration = end_time - start_time;
        $display("  Transmission duration: %0d ns", duration);
        $display("  Expected duration: ~%0d ns", int'(expected_time_ns));
        
        if (rx_count == 3) begin
            $display("  PASS: Received all 3 bytes");
        end else begin
            $display("  ERROR: Received %0d bytes instead of 3", rx_count);
        end
        
        //=================================================================
        // TEST 5: Back-to-back readouts
        //=================================================================
        $display("\nTEST 5: Back-to-back readouts");
        
        // First readout
        bytes_stored = 5;
        rx_count = 0;
        
        @(posedge clk);
        start_readout = 1;
        @(posedge clk);
        start_readout = 0;
        
        wait(reading_out == 0);
        first_rx = rx_count;
        $display("  First readout: %0d bytes", first_rx);
        
        // Immediate second readout
        rx_count = 0;
        @(posedge clk);
        start_readout = 1;
        @(posedge clk);
        start_readout = 0;
        
        wait(reading_out == 0);
        $display("  Second readout: %0d bytes", rx_count);
        
        repeat(1000) @(posedge clk);
        
        if (first_rx == 5 && rx_count == 5) begin
            $display("  PASS: Both readouts successful");
        end else begin
            $display("  ERROR: Readout counts incorrect");
        end
        
        $display("\n========================================");
        $display("UART READOUT TESTS COMPLETED");
        $display("========================================\n");
        
        $finish;
    end
    
    // Timeout
    initial begin
        #50_000_000;  // 50ms timeout
        $display("\nERROR: Test timeout!");
        $finish;
    end

endmodule
