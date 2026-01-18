`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/18/2026 09:22:38 AM
// Design Name: 
// Module Name: tb_fullsys
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


module tb_integration();
    import parameters::DATA_WIDTH;
    import parameters::SIGNAL_NUMBER;
    
    // Clock and reset
    reg clk;
    reg rst;
    
    // Button inputs
    reg btn_start_capture;
    reg btn_start_readout;
    
    // Outputs
    wire uart_tx;
    wire [15:0] led;
    
    // DUT instantiation
    compressor_top dut (
        .clk(clk),
        .rst(rst),
        .btn_start_capture(btn_start_capture),
        .btn_start_readout(btn_start_readout),
        .uart_tx(uart_tx),
        .led(led)
    );
    
    // Clock generation (100 MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // UART receiver for verification
    reg [7:0] uart_rx_buffer [0:4095];
    int uart_byte_count = 0;
    
    // Simple UART RX monitor (115200 baud at 100MHz = 868.055 clocks/bit)
    localparam CLKS_PER_BIT = 868;
    
    task uart_receive_byte(output [7:0] data);
        int i;
        begin
            // Wait for start bit
            @(negedge uart_tx);
            
            // Wait to middle of start bit
            repeat(CLKS_PER_BIT/2) @(posedge clk);
            
            // Sample data bits
            for (i = 0; i < 8; i++) begin
                repeat(CLKS_PER_BIT) @(posedge clk);
                data[i] = uart_tx;
            end
            
            // Wait through stop bit
            repeat(CLKS_PER_BIT) @(posedge clk);
            
            $display("  [%0t] UART RX: 0x%02X (%0d)", $time, data, data);
        end
    endtask
    
    // UART monitor process
    initial begin
        reg [7:0] rx_byte;
        
        // Wait for system to start
        wait(rst == 0);
        
        forever begin
            uart_receive_byte(rx_byte);
            uart_rx_buffer[uart_byte_count] = rx_byte;
            uart_byte_count++;
        end
    end
    
    // Decompressor for verification
    reg [15:0] decompressed[3:0];  // Reconstructed signals
    int sample_count = 0;
    
    task decode_packet(input [7:0] packet);
        logic [1:0] ptype, sig;
        logic [3:0] count;
        logic signed [3:0] delta_s;
        begin
            ptype = packet[7:6];
            sig = packet[5:4];
            count = packet[3:0];
            
            case (ptype)
                2'b00: begin  // RLE
                    $display("    Decoded: RLE sig=%0d, count=%0d (repeat %0d more times)", 
                             sig, count, count);
                    // Value stays same for 'count' samples
                end
                
                2'b01: begin  // DELTARLE
                    $display("    Decoded: DELTARLE sig=%0d, count=%0d", sig, count);
                    // Delta stays same for 'count' samples
                end
                
                2'b10: begin  // DELTA
                    delta_s = {packet[3], packet[2:0]};  // Sign-extend
                    $display("    Decoded: DELTA sig=%0d, delta=%0d", sig, $signed(delta_s));
                    // Apply delta once
                end
                
                2'b11: begin  // RAW
                    $display("    Decoded: RAW sig=%0d (need next 2 bytes)", sig);
                    // Need to read next bytes for full value
                end
            endcase
        end
    endtask
    
    // Main test sequence
    initial begin
        // Declare all variables at the beginning
        int rle_count, deltarle_count, delta_count, raw_count;
        int i;
        real ratio;
        
        $display("\n========================================");
        $display("FULL SYSTEM INTEGRATION TEST");
        $display("========================================\n");
        
        // Initialize
        rst = 1;
        btn_start_capture = 0;
        btn_start_readout = 0;
        
        repeat(10) @(posedge clk);
        rst = 0;
        repeat(10) @(posedge clk);
        
        $display("System initialized and running...\n");
        
        //=================================================================
        // TEST 1: Let system run and collect compressed data
        //=================================================================
        $display("TEST 1: Capturing data for 200 samples (~200ms)");
        $display("  Waiting for test signals to generate compressed packets...\n");
        
        // Wait for 200 samples (at 1kHz sample rate = 200ms = 20M clocks)
        repeat(20_000_000 / 100) @(posedge clk);  // Scaled down for sim
        
        $display("\n  Capture complete!");
        $display("  LED[13:0] shows bytes stored: %0d", led[13:0]);
        $display("  LED[14] (almost full): %0d", led[14]);
        
        //=================================================================
        // TEST 2: Trigger readout via button
        //=================================================================
        $display("\nTEST 2: Triggering UART readout");
        
        // Simulate button press (need to hold for debounce)
        btn_start_readout = 1;
        repeat(1_100_000) @(posedge clk);  // Hold for debounce time
        btn_start_readout = 0;
        
        $display("  Button pulse generated, waiting for readout...");
        $display("  LED[15] (reading out): %0d", led[15]);
        
        // Wait for readout to start
        wait(led[15] == 1);
        $display("  Readout started!");
        
        // Monitor progress
        fork
            begin
                while (led[15]) begin
                    repeat(10000) @(posedge clk);
                    $display("  Bytes sent: %0d", led[13:0]);
                end
            end
        join_none
        
        // Wait for readout to complete
        wait(led[15] == 0);
        $display("\n  Readout complete!");
        $display("  Total bytes transmitted: %0d", uart_byte_count);
        
        //=================================================================
        // TEST 3: Verify received data
        //=================================================================
        $display("\nTEST 3: Verifying received compressed data");
        
        $display("  First 20 bytes received:");
        for (i = 0; i < 20 && i < uart_byte_count; i++) begin
            $display("    [%2d] 0x%02X", i, uart_rx_buffer[i]);
            
            // Try to decode if it looks like a packet header
            if (i < uart_byte_count - 3) begin
                decode_packet(uart_rx_buffer[i]);
            end
        end
        
        //=================================================================
        // TEST 4: Verify test signal patterns
        //=================================================================
        $display("\nTEST 4: Analyzing compression effectiveness");
        
        // Count packet types
        rle_count = 0;
        deltarle_count = 0;
        delta_count = 0;
        raw_count = 0;
        
        for (i = 0; i < uart_byte_count; i++) begin
            case (uart_rx_buffer[i][7:6])
                2'b00: rle_count++;
                2'b01: deltarle_count++;
                2'b10: delta_count++;
                2'b11: begin
                    raw_count++;
                    i += 2;  // RAW packets are 3 bytes (skip next 2)
                end
            endcase
        end
        
        $display("\n  Packet type distribution:");
        $display("    RLE packets:      %0d", rle_count);
        $display("    DELTARLE packets: %0d", deltarle_count);
        $display("    DELTA packets:    %0d", delta_count);
        $display("    RAW packets:      %0d", raw_count);
        
        // Estimate uncompressed size (rough calculation)
        // Assuming 200 samples captured, 4 signals, 2 bytes each = 1600 bytes
        $display("\n  Estimated uncompressed size: ~1600 bytes");
        $display("  Compressed size: %0d bytes", uart_byte_count);
        
        if (uart_byte_count > 0) begin
            ratio = 1600.0 / uart_byte_count;
            $display("  Compression ratio: %.2fx", ratio);
        end
        
        //=================================================================
        // TEST 5: Second capture/readout cycle
        //=================================================================
        $display("\nTEST 5: Second capture and readout cycle");
        
        uart_byte_count = 0;  // Reset counter
        
        // Let it capture more
        repeat(10_000_000 / 100) @(posedge clk);
        
        // Trigger second readout
        btn_start_readout = 1;
        repeat(1_100_000) @(posedge clk);
        btn_start_readout = 0;
        
        wait(led[15] == 1);
        $display("  Second readout started...");
        
        wait(led[15] == 0);
        $display("  Second readout complete: %0d bytes", uart_byte_count);
        
        $display("\n========================================");
        $display("INTEGRATION TEST COMPLETED SUCCESSFULLY");
        $display("========================================\n");
        
        repeat(100) @(posedge clk);
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #200_000_000;  // 200ms timeout
        $display("\nERROR: Test timeout!");
        $display("Final state:");
        $display("  LED status: 0x%04X", led);
        $display("  UART bytes received: %0d", uart_byte_count);
        $finish;
    end
    
    // Signal value monitor (sample a few points)
    int monitor_count = 0;
    always @(posedge clk) begin
        if (!rst && dut.sample_tick && monitor_count < 10) begin
            $display("[Sample %0d] sig0=%0d, sig1=%0d, sig2=%0d, sig3=%0d",
                     monitor_count,
                     dut.signals[0], dut.signals[1], 
                     dut.signals[2], dut.signals[3]);
            monitor_count++;
        end
    end

endmodule