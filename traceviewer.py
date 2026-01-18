#!/usr/bin/env python3
"""
FPGA Trace Decompressor and Viewer
Handles RLE, Delta RLE, Delta, and Raw packet types
"""

import serial
import matplotlib.pyplot as plt
import struct
import argparse
import time

class FPGATraceDecompressor:
    """Decompresses FPGA signal traces with 4 compression modes"""
    
    # Packet types (match Verilog)
    RLE = 0       # 2'b00
    DELTARLE = 1  # 2'b01
    DELTA = 2     # 2'b10
    RAW = 3       # 2'b11
    
    def __init__(self, num_signals=4, data_width=16):
        self.num_signals = num_signals
        self.data_width = data_width
        self.reset()
        
    def reset(self):
        """Reset for new capture"""
        self.signals = [[] for _ in range(self.num_signals)]
        self.timestamps = []
        
        # Current values for reconstruction
        self.current_values = [0] * self.num_signals
        self.current_deltas = [0] * self.num_signals
        
        # Statistics
        self.total_samples = 0
        self.total_bytes = 0
        self.packet_counts = {
            self.RLE: 0,
            self.DELTARLE: 0,
            self.DELTA: 0,
            self.RAW: 0
        }
        
    def process_byte_stream(self, byte_stream):
        """Process a stream of bytes from FPGA"""
        i = 0
        while i < len(byte_stream):
            # Read header byte
            header = byte_stream[i]
            packet_type = (header >> 6) & 0x03
            signal_id = (header >> 4) & 0x03
            payload = header & 0x0F
            
            i += 1
            
            if packet_type == self.RLE:
                # RLE: {type, signal, count}
                run_count = payload
                self._add_rle_samples(signal_id, run_count)
                self.total_bytes += 1
                
            elif packet_type == self.DELTARLE:
                # Delta RLE: {type, signal, count}
                run_count = payload
                self._add_delta_rle_samples(signal_id, run_count)
                self.total_bytes += 1
                
            elif packet_type == self.DELTA:
                # Small delta: {type, signal, sign_bit, 3_bits}
                sign_bit = (payload >> 3) & 0x01
                delta_val = payload & 0x07
                
                # Reconstruct signed 4-bit value
                if sign_bit:
                    delta = delta_val - 8  # Negative
                else:
                    delta = delta_val      # Positive
                
                self._add_delta_sample(signal_id, delta)
                self.total_bytes += 1
                
            elif packet_type == self.RAW:
                # Raw: {type, signal, data[15:8], data[7:0]}
                if i + 1 < len(byte_stream):
                    data_high = byte_stream[i]
                    data_low = byte_stream[i + 1]
                    value = (data_high << 8) | data_low
                    
                    # Convert to signed if needed
                    if value & 0x8000:
                        value = value - 0x10000
                    
                    self._add_raw_sample(signal_id, value)
                    i += 2
                    self.total_bytes += 3
                else:
                    print(f"Warning: Incomplete RAW packet at byte {i}")
                    break
            
            self.packet_counts[packet_type] += 1
    
    def _add_rle_samples(self, signal_id, count):
        """Add RLE samples - repeat current value"""
        for _ in range(count):
            self._add_sample(signal_id, self.current_values[signal_id])
    
    def _add_delta_rle_samples(self, signal_id, count):
        """Add Delta RLE samples - apply same delta repeatedly"""
        delta = self.current_deltas[signal_id]
        for _ in range(count):
            self.current_values[signal_id] += delta
            self._add_sample(signal_id, self.current_values[signal_id])
    
    def _add_delta_sample(self, signal_id, delta):
        """Add one delta-encoded sample"""
        self.current_deltas[signal_id] = delta
        self.current_values[signal_id] += delta
        self._add_sample(signal_id, self.current_values[signal_id])
    
    def _add_raw_sample(self, signal_id, value):
        """Add one raw sample"""
        self.current_values[signal_id] = value
        self.current_deltas[signal_id] = 0  # Reset delta tracking
        self._add_sample(signal_id, value)
    
    def _add_sample(self, signal_id, value):
        """Add a decompressed sample to the trace"""
        # Update timestamp when signal 0 is updated (assumes round-robin)
        if signal_id == 0:
            self.total_samples += 1
            self.timestamps.append(self.total_samples)
        
        self.signals[signal_id].append(value)
    
    def get_compression_ratio(self):
        """Calculate compression ratio"""
        if self.total_bytes == 0:
            return 1.0
        uncompressed = self.total_samples * self.num_signals * (self.data_width // 8)
        return uncompressed / self.total_bytes
    
    def get_stats(self):
        """Return statistics dictionary"""
        ratio = self.get_compression_ratio()
        uncomp_kb = (self.total_samples * self.num_signals * (self.data_width // 8)) / 1024.0
        comp_kb = self.total_bytes / 1024.0
        
        return {
            'samples': self.total_samples,
            'compressed_kb': comp_kb,
            'uncompressed_kb': uncomp_kb,
            'ratio': ratio,
            'packets': self.packet_counts.copy()
        }


class BufferReceiver:
    """Receives BRAM dumps from FPGA via UART"""
    
    def __init__(self, port, baudrate=115200):
        try:
            self.ser = serial.Serial(port, baudrate, timeout=1.0)
            print(f"✓ Connected to {port} at {baudrate} baud")
        except Exception as e:
            print(f"✗ Error opening serial port: {e}")
            print(f"   Common ports: Linux=/dev/ttyUSB0, Windows=COM3, Mac=/dev/tty.usbserial-*")
            exit(1)
    
    def receive_buffer(self):
        """
        Receive a complete buffer dump from FPGA
        Returns bytes, or None if timeout
        """
        print("\n" + "="*70)
        print("Waiting for FPGA buffer dump...")
        print("(Press DOWN button on Basys3 to start transfer)")
        print("="*70)
        
        buffer = bytearray()
        timeout = 30.0
        start_time = time.time()
        last_byte_time = time.time()
        receiving = False
        
        while True:
            # Overall timeout
            if time.time() - start_time > timeout:
                if len(buffer) == 0:
                    print("✗ Timeout waiting for data")
                    return None
                else:
                    break
            
            # Data stopped arriving
            if receiving and (time.time() - last_byte_time > 2.0):
                print(f"\n✓ Transfer complete ({len(buffer)} bytes)")
                break
            
            # Read available data
            if self.ser.in_waiting > 0:
                chunk = self.ser.read(self.ser.in_waiting)
                buffer.extend(chunk)
                last_byte_time = time.time()
                
                if not receiving:
                    receiving = True
                    print(f"✓ Receiving data...")
                
                # Progress indicator
                if len(buffer) % 100 == 0:
                    print(f"  Received {len(buffer)} bytes...", end='\r')
        
        return bytes(buffer) if len(buffer) > 0 else None
    
    def close(self):
        self.ser.close()


def plot_traces(decomp):
    """Create visualization of decompressed traces"""
    stats = decomp.get_stats()
    
    if stats['samples'] == 0:
        print("✗ No samples to plot")
        return
    
    # Create figure
    fig, axes = plt.subplots(4, 1, figsize=(14, 10))
    fig.suptitle(f'FPGA Adaptive Compression - {stats["samples"]:,} samples @ {stats["ratio"]:.1f}x compression',
                 fontsize=16, fontweight='bold')
    
    signal_names = [
        'Signal 0: Counter (Delta/DeltaRLE)',
        'Signal 1: FSM State (RLE)',
        'Signal 2: Random (Low Compression)',
        'Signal 3: Slow Counter (Extreme RLE)'
    ]
    colors = ['#1f77b4', '#ff7f0e', '#2ca02c', '#d62728']
    
    x_data = decomp.timestamps
    
    for i, (ax, name, color) in enumerate(zip(axes, signal_names, colors)):
        y_data = decomp.signals[i]
        
        if len(y_data) > 0:
            ax.plot(x_data[:len(y_data)], y_data, color=color, linewidth=1.5, label=name)
            ax.set_ylabel(f'Signal {i}', fontsize=11, fontweight='bold')
            ax.legend(loc='upper right', fontsize=9)
            ax.grid(True, alpha=0.3)
            
            # Auto-scale y
            y_min, y_max = min(y_data), max(y_data)
            margin = (y_max - y_min) * 0.1 if y_max != y_min else 1
            ax.set_ylim(y_min - margin, y_max + margin)
    
    axes[-1].set_xlabel('Sample Number', fontsize=11, fontweight='bold')
    
    # Statistics box
    stats_text = (
        f"Compressed: {stats['compressed_kb']:.2f} KB | "
        f"Uncompressed: {stats['uncompressed_kb']:.2f} KB | "
        f"Ratio: {stats['ratio']:.1f}x | "
        f"Packets [RLE:{stats['packets'][0]} DeltaRLE:{stats['packets'][1]} "
        f"Delta:{stats['packets'][2]} RAW:{stats['packets'][3]}]"
    )
    
    fig.text(0.5, 0.02, stats_text, ha='center', fontsize=10,
             family='monospace',
             bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5))
    
    # Comparison box
    bram_kb = 2  # 2KB BRAM
    uncomp_max = int((bram_kb * 1024) / (decomp.num_signals * 2))
    comp_max = int(uncomp_max * stats['ratio'])
    
    compare_text = (
        f"With {bram_kb}KB BRAM: "
        f"Uncompressed = {uncomp_max:,} samples | "
        f"Compressed = {comp_max:,} samples ({stats['ratio']:.1f}x MORE!)"
    )
    
    fig.text(0.5, 0.96, compare_text, ha='center', fontsize=12,
             family='monospace', fontweight='bold', color='green')
    
    plt.tight_layout(rect=[0, 0.04, 1, 0.94])
    plt.show()


def main():
    parser = argparse.ArgumentParser(description='FPGA Adaptive Compression Trace Viewer')
    parser.add_argument('--port', default='/dev/ttyUSB0',
                       help='Serial port')
    parser.add_argument('--baud', type=int, default=115200,
                       help='Baud rate (default: 115200)')
    parser.add_argument('--continuous', action='store_true',
                       help='Continuously receive new captures')
    parser.add_argument('--debug', action='store_true',
                       help='Print packet-by-packet debug info')
    
    args = parser.parse_args()
    
    print("=" * 70)
    print(" FPGA ADAPTIVE COMPRESSION TRACE VIEWER")
    print("=" * 70)
    print(" Compression modes:")
    print("   RLE       - Run Length Encoding (same value)")
    print("   DeltaRLE  - Run Length of Deltas (incrementing counter)")
    print("   Delta     - Small delta (-8 to +7)")
    print("   Raw       - Large changes (16-bit value)")
    print("=" * 70)
    print()
    
    receiver = BufferReceiver(args.port, args.baud)
    decomp = FPGATraceDecompressor()
    
    try:
        while True:
            # Receive buffer dump
            buffer_data = receiver.receive_buffer()
            
            if buffer_data is None:
                if not args.continuous:
                    break
                continue
            
            # Reset decompressor
            decomp.reset()
            
            # Decompress
            print(f"\nDecompressing {len(buffer_data)} bytes...")
            if args.debug:
                print("\nPacket details:")
                for i, byte in enumerate(buffer_data[:20]):  # Show first 20 bytes
                    print(f"  Byte {i}: 0x{byte:02X} ({byte:08b})")
            
            decomp.process_byte_stream(buffer_data)
            
            # Display statistics
            stats = decomp.get_stats()
            print(f"\n{'='*70}")
            print(f"✓ Decompression complete!")
            print(f"{'='*70}")
            print(f"  Samples captured:     {stats['samples']:,}")
            print(f"  Compressed size:      {stats['compressed_kb']:.2f} KB")
            print(f"  Uncompressed would be: {stats['uncompressed_kb']:.2f} KB")
            print(f"  Compression ratio:    {stats['ratio']:.1f}x")
            print(f"  Packet breakdown:")
            print(f"    RLE (same value):        {stats['packets'][0]}")
            print(f"    Delta RLE (incrementing): {stats['packets'][1]}")
            print(f"    Delta (small change):     {stats['packets'][2]}")
            print(f"    Raw (large change):       {stats['packets'][3]}")
            print(f"{'='*70}\n")
            
            # Verify all signals have same length
            signal_lengths = [len(sig) for sig in decomp.signals]
            if len(set(signal_lengths)) > 1:
                print(f"⚠ Warning: Signals have different lengths: {signal_lengths}")
            
            # Plot
            plot_traces(decomp)
            
            if not args.continuous:
                break
            
            print("\nReady for next capture...")
            
    except KeyboardInterrupt:
        print("\n\nExiting...")
    finally:
        receiver.close()


if __name__ == '__main__':
    main()
