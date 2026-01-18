`timescale 1ns / 1ps

module tb_compression();
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
    
    // Packet decoding
    wire [1:0] packet_type;
    wire [1:0] signal_num;
    wire [3:0] rle_count;
    wire signed [3:0] delta_small;
    wire [15:0] raw_data;
    
    assign packet_type = bytesout[19:18];
    assign signal_num = bytesout[17:16];
    assign rle_count = bytesout[3:0];
    assign delta_small = {bytesout[3], bytesout[2:0]};
    assign raw_data = bytesout[15:0];
    
    // Packet type names for display
    localparam RLE = 2'b00;
    localparam DELTARLE = 2'b01;
    localparam DELTA = 2'b10;
    localparam RAW = 2'b11;
    
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
    
    // Test statistics
    int total_packets = 0;
    int rle_packets = 0;
    int deltarle_packets = 0;
    int delta_packets = 0;
    int raw_packets = 0;
    int total_input_bytes = 0;
    int total_output_bytes = 0;
    
    // Packet monitoring
    always @(posedge clk) begin
        if (onebyteoutFLAG) begin
            total_packets++;
            total_output_bytes += 1;
            
            case (packet_type)
                RLE: begin
                    rle_packets++;
                    $display("  [%0t] RLE packet: sig=%0d, count=%0d", 
                             $time, signal_num, rle_count);
                end
                DELTARLE: begin
                    deltarle_packets++;
                    $display("  [%0t] DELTARLE packet: sig=%0d, count=%0d", 
                             $time, signal_num, rle_count);
                end
                DELTA: begin
                    delta_packets++;
                    $display("  [%0t] DELTA packet: sig=%0d, delta=%0d", 
                             $time, signal_num, $signed(delta_small));
                end
            endcase
        end
        
        if (largebyteoutFLAG) begin
            total_packets++;
            total_output_bytes += 3; // 20 bits = 2.5 bytes
            raw_packets++;
            $display("  [%0t] RAW packet: sig=%0d, data=0x%04X (%0d)", 
                     $time, signal_num, raw_data, raw_data);
        end
    end
    
    // Task to send one sample
    task send_sample(input [15:0] sig0, sig1, sig2, sig3);
        begin
            in[0] = sig0;
            in[1] = sig1;
            in[2] = sig2;
            in[3] = sig3;
            start = 1;
            @(posedge clk);
            start = 0;
            @(posedge clk);
            total_input_bytes += 8; // 4 signals × 2 bytes
        end
    endtask
    
    // Task to print compression statistics
    task print_stats();
        real compression_ratio;
        begin
            compression_ratio = real'(total_input_bytes) / real'(total_output_bytes);
            $display("\n========== COMPRESSION STATISTICS ==========");
            $display("Total packets sent: %0d", total_packets);
            $display("  RLE packets:      %0d (%.1f%%)", rle_packets, 
                     100.0 * rle_packets / total_packets);
            $display("  DELTARLE packets: %0d (%.1f%%)", deltarle_packets,
                     100.0 * deltarle_packets / total_packets);
            $display("  DELTA packets:    %0d (%.1f%%)", delta_packets,
                     100.0 * delta_packets / total_packets);
            $display("  RAW packets:      %0d (%.1f%%)", raw_packets,
                     100.0 * raw_packets / total_packets);
            $display("Input bytes:  %0d", total_input_bytes);
            $display("Output bytes: %0d", total_output_bytes);
            $display("Compression ratio: %.2fx", compression_ratio);
            $display("============================================\n");
        end
    endtask
    
    // Main test sequence
    initial begin
        $display("Starting compression testbench...\n");
        
        // Initialize
        reset_n = 0;
        start = 0;
        compressedready = 1;  // Always ready for this test
        uncompressedfull = 0;
        
        foreach(in[i]) in[i] = 0;
        
        repeat(5) @(posedge clk);
        reset_n = 1;
        repeat(2) @(posedge clk);
        
        //=================================================================
        // TEST 1: RLE Mode - Constant values
        //=================================================================
        $display("TEST 1: RLE Mode - Sending 20 identical samples");
        $display("Expected: Should emit RLE packets for all signals");
        $display("Signal pattern: [100, 200, 300, 400] repeated\n");
        
        for (int i = 0; i < 20; i++) begin
            send_sample(100, 200, 300, 400);
        end
        repeat(10) @(posedge clk);
        print_stats();
        
        // Reset stats
        total_packets = 0;
        rle_packets = 0;
        deltarle_packets = 0;
        delta_packets = 0;
        raw_packets = 0;
        total_input_bytes = 0;
        total_output_bytes = 0;
        
        //=================================================================
        // TEST 2: DELTARLE Mode - Linear ramp
        //=================================================================
        $display("TEST 2: DELTARLE Mode - Linear ramp (constant delta)");
        $display("Expected: Should emit DELTARLE packets");
        $display("Signal pattern: sig0 increments by 1 each sample\n");
        
        for (int i = 0; i < 30; i++) begin
            send_sample(i, 500, 600, 700);
        end
        repeat(10) @(posedge clk);
        print_stats();
        
        // Reset stats
        total_packets = 0;
        rle_packets = 0;
        deltarle_packets = 0;
        delta_packets = 0;
        raw_packets = 0;
        total_input_bytes = 0;
        total_output_bytes = 0;
        
        //=================================================================
        // TEST 3: DELTA Mode - Small changes
        //=================================================================
        $display("TEST 3: DELTA Mode - Small random changes");
        $display("Expected: Should emit DELTA packets for small deltas\n");
        
        for (int i = 0; i < 20; i++) begin
            send_sample(1000 + (i % 4), 800, 900, 1000);
        end
        repeat(10) @(posedge clk);
        print_stats();
        
        // Reset stats
        total_packets = 0;
        rle_packets = 0;
        deltarle_packets = 0;
        delta_packets = 0;
        raw_packets = 0;
        total_input_bytes = 0;
        total_output_bytes = 0;
        
        //=================================================================
        // TEST 4: RAW Mode - Large jumps
        //=================================================================
        $display("TEST 4: RAW Mode - Large value changes");
        $display("Expected: Should emit RAW packets\n");
        
        for (int i = 0; i < 10; i++) begin
            send_sample(i * 1000, 2000, 3000, 4000);
        end
        repeat(10) @(posedge clk);
        print_stats();
        
        // Reset stats
        total_packets = 0;
        rle_packets = 0;
        deltarle_packets = 0;
        delta_packets = 0;
        raw_packets = 0;
        total_input_bytes = 0;
        total_output_bytes = 0;
        
        //=================================================================
        // TEST 5: Mixed modes
        //=================================================================
        $display("TEST 5: Mixed compression modes");
        $display("Expected: Mix of all packet types\n");
        
        // Phase 1: RLE
        for (int i = 0; i < 10; i++) 
            send_sample(100, 100, 100, 100);
        
        // Phase 2: DELTARLE
        for (int i = 0; i < 15; i++) 
            send_sample(100 + i, 100, 100, 100);
        
        // Phase 3: Small deltas
        for (int i = 0; i < 10; i++)
            send_sample(115 + (i % 3), 100, 100, 100);
        
        // Phase 4: Large jump (RAW)
        send_sample(5000, 100, 100, 100);
        
        // Phase 5: More RLE
        for (int i = 0; i < 10; i++)
            send_sample(5000, 100, 100, 100);
        
        repeat(10) @(posedge clk);
        print_stats();
        
        //=================================================================
        // TEST 6: RLE/DELTARLE counter overflow (max count = 15)
        //=================================================================
        $display("TEST 6: RLE counter overflow test");
        $display("Expected: Should emit multiple RLE packets when count > 15\n");
        
        // Reset stats
        total_packets = 0;
        rle_packets = 0;
        deltarle_packets = 0;
        delta_packets = 0;
        raw_packets = 0;
        total_input_bytes = 0;
        total_output_bytes = 0;
        
        for (int i = 0; i < 50; i++) begin
            send_sample(7777, 7777, 7777, 7777);
        end
        repeat(10) @(posedge clk);
        print_stats();
        
        //=================================================================
        // TEST 7: Backpressure test
        //=================================================================
        $display("TEST 7: Backpressure (compressedready = 0)");
        $display("Expected: Compressor should stall when not ready\n");
        
        compressedready = 0;
        send_sample(111, 222, 333, 444);
        $display("  Sent sample while not ready - should not emit packets");
        repeat(5) @(posedge clk);
        
        compressedready = 1;
        $display("  Now ready - processing should resume");
        repeat(10) @(posedge clk);
        
        $display("\n========================================");
        $display("All tests completed!");
        $display("========================================\n");
        
        $finish;
    end
    
    // Timeout
    initial begin
        #100000;
        $display("ERROR: Testbench timeout!");
        $finish;
    end

endmodule
