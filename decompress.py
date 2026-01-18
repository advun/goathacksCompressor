#!/usr/bin/env python3
"""
FPGA Trace Decompressor and Viewer
Handles bit-packed compression with RLE, Delta RLE, Delta, and Raw packet types
FIXED: Properly handles 20-bit RAW packets in bit-packed stream
"""

import serial
import matplotlib.pyplot as plt
import argparse
import time

class BitStreamReader:
    """Reads variable-width values from a bit-packed byte stream"""
    
    def __init__(self, byte_data):
        self.data = byte_data
        self.bit_buffer = 0
        self.bits_in_buffer = 0
        self.byte_pos = 0
        
    def read_bits(self, num_bits):
        """Read num_bits from the stream"""
        # Fill buffer if needed
        while self.bits_in_buffer < num_bits and self.byte_pos < len(self.data):
            # Add byte to buffer (LSB first, matching Verilog)
            self.bit_buffer |= (self.data[self.byte_pos] << self.bits_in_buffer)
            self.bits_in_buffer += 8
            self.byte_pos += 1
        
        if self.bits_in_buffer < num_bits:
            return None  # Not enough data
        
        # Extract the bits we need
        mask = (1 << num_bits) - 1
        value = self.bit_buffer & mask
        
        # Remove used bits
        self.bit_buffer >>= num_bits
        self.bits_in_buffer -= num_bits
        
        return value
    
    def has_data(self):
        """Check if more data is available"""
        return self.bits_in_buffer > 0 or self.byte_pos < len(self.data)


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
        # Store (timestamp, value) pairs for each signal
        self.signals = [[] for _ in range(self.num_signals)]
        
        # Current values for reconstruction
        self.current_values = [0] * self.num_signals
        self.current_deltas = [0] * self.num_signals
        
        # Global sample counter (increments with every packet)
        self.sample_count = 0
        
        # Packet log for visualization
        self.packet_log = []
        
        # Statistics
        self.total_bytes = 0
        self.packet_counts = {
            self.RLE: 0,
            self.DELTARLE: 0,
            self.DELTA: 0,
            self.RAW: 0
        }
        
    def process_byte_stream(self, byte_stream):
        """Process a bit-packed stream of bytes from FPGA"""
        reader = BitStreamReader(byte_stream)
        packet_num = 0
        
        while reader.has_data():
            # Read 8-bit header
            header = reader.read_bits(8)
            if header is None:
                break
            
            packet_type = (header >> 6) & 0x03
            signal_id = (header >> 4) & 0x03
            payload = header & 0x0F
            
            if packet_type == self.RLE:
                # RLE: 8-bit packet
                run_count = payload if payload > 0 else 16
                self._add_rle_samples(signal_id, run_count)
                self.packet_counts[packet_type] += 1
                self.packet_log.append({
                    'type': packet_type,
                    'signal': signal_id,
                    'payload': run_count,
                    'samples': run_count
                })
                
            elif packet_type == self.DELTARLE:
                # Delta RLE: 8-bit packet
                run_count = payload if payload > 0 else 16
                self._add_delta_rle_samples(signal_id, run_count)
                self.packet_counts[packet_type] += 1
                self.packet_log.append({
                    'type': packet_type,
                    'signal': signal_id,
                    'payload': run_count,
                    'samples': run_count
                })
                
            elif packet_type == self.DELTA:
                # Small delta: 8-bit packet (sign-magnitude encoding)
                sign_bit = (payload >> 3) & 0x01
                magnitude = payload & 0x07
                
                delta = -magnitude if sign_bit else magnitude
                
                self._add_delta_sample(signal_id, delta)
                self.packet_counts[packet_type] += 1
                self.packet_log.append({
                    'type': packet_type,
                    'signal': signal_id,
                    'payload': delta,
                    'samples': 1
                })
                
            elif packet_type == self.RAW:
                # Raw: 20-bit packet (4-bit header already read + 16-bit data)
                # Read the 16-bit data value
                data_value = reader.read_bits(16)
                if data_value is None:
                    print(f"Warning: Incomplete RAW packet at packet {packet_num}")
                    break
                
                # Convert to signed 16-bit
                if data_value & 0x8000:
                    data_value = data_value - 0x10000
                
                self._add_raw_sample(signal_id, data_value)
                self.packet_counts[packet_type] += 1
                self.packet_log.append({
                    'type': packet_type,
                    'signal': signal_id,
                    'payload': data_value,
                    'samples': 1
                })
            
            packet_num += 1
        
        self.total_bytes = len(byte_stream)
    
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
        # Each packet increments the global sample counter
        self.sample_count += 1
        
        # Store (timestamp, value) tuple
        self.signals[signal_id].append((self.sample_count, value))
    
    def get_compression_ratio(self):
        """Calculate compression ratio"""
        if self.total_bytes == 0:
            return 1.0
        # Total samples across all signals
        total_samples = sum(len(sig) for sig in self.signals)
        uncompressed = total_samples * (self.data_width // 8)
        return uncompressed / self.total_bytes
    
    def get_stats(self):
        """Return statistics dictionary"""
        ratio = self.get_compression_ratio()
        total_samples = sum(len(sig) for sig in self.signals)
        uncomp_kb = (total_samples * (self.data_width // 8)) / 1024.0
        comp_kb = self.total_bytes / 1024.0
        
        return {
            'total_samples': total_samples,
            'sample_count': self.sample_count,
            'signal_lengths': [len(sig) for sig in self.signals],
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
        print("(Press readout button on Basys3 to start transfer)")
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


def plot_compression_view(decomp):
    """Show compressed packet stream"""
    if not hasattr(decomp, 'packet_log') or len(decomp.packet_log) == 0:
        print("✗ No packet log available")
        return
    
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(16, 8))
    
    # Top: Packet type timeline
    packets = decomp.packet_log
    
    type_colors = {
        0: '#2ecc71',  # RLE - Green
        1: '#3498db',  # DeltaRLE - Blue
        2: '#f39c12',  # Delta - Orange
        3: '#e74c3c'   # Raw - Red
    }
    
    type_names = {0: 'RLE', 1: 'DeltaRLE', 2: 'Delta', 3: 'Raw'}
    
    # Plot packets
    for ptype in [0, 1, 2, 3]:
        type_packets = [i for i, p in enumerate(packets) if p['type'] == ptype]
        if type_packets:
            ax1.scatter(type_packets, [ptype] * len(type_packets), 
                       c=type_colors[ptype], s=50, alpha=0.7, 
                       label=f"{type_names[ptype]} ({len(type_packets)})")
    
    ax1.set_ylabel('Packet Type', fontsize=11, fontweight='bold')
    ax1.set_yticks([0, 1, 2, 3])
    ax1.set_yticklabels(['RLE\n(8 bits)', 'DeltaRLE\n(8 bits)', 'Delta\n(8 bits)', 'Raw\n(20 bits)'])
    ax1.grid(True, alpha=0.3, axis='x')
    ax1.legend(loc='upper right', fontsize=9)
    ax1.set_title('Compressed Packet Stream (Bit-Packed)', fontsize=12, fontweight='bold')
    
    # Bottom: Signal assignment over time
    signal_colors = ['#1f77b4', '#ff7f0e', '#2ca02c', '#d62728']
    
    for sig in range(4):
        sig_packets = [i for i, p in enumerate(packets) if p['signal'] == sig]
        if sig_packets:
            ax2.scatter(sig_packets, [sig] * len(sig_packets),
                       c=signal_colors[sig], s=30, alpha=0.7,
                       label=f"Signal {sig} ({len(sig_packets)} pkts)")
    
    ax2.set_ylabel('Signal ID', fontsize=11, fontweight='bold')
    ax2.set_xlabel('Packet Number', fontsize=11, fontweight='bold')
    ax2.set_yticks([0, 1, 2, 3])
    ax2.grid(True, alpha=0.3)
    ax2.legend(loc='upper right', fontsize=9)
    ax2.set_title('Which Signal Each Packet Updates', fontsize=12, fontweight='bold')
    
    plt.tight_layout()
    plt.show()


def plot_traces(decomp):
    """Create visualization of decompressed traces"""
    stats = decomp.get_stats()
    
    if stats['total_samples'] == 0:
        print("✗ No samples to plot")
        return
    
    # Create figure
    fig, axes = plt.subplots(4, 1, figsize=(14, 10))
    
    signal_names = [
        'Signal 0: Counter (increments every sample)',
        'Signal 1: FSM State (changes every 256 samples)',
        'Signal 2: Random LFSR (low compression)',
        'Signal 3: Slow Counter (changes every 4096 samples)'
    ]
    colors = ['#1f77b4', '#ff7f0e', '#2ca02c', '#d62728']
    
    for i, (ax, name, color) in enumerate(zip(axes, signal_names, colors)):
        if len(decomp.signals[i]) > 0:
            # Extract timestamps and values
            timestamps = [t for t, v in decomp.signals[i]]
            values = [v for t, v in decomp.signals[i]]
            
            ax.plot(timestamps, values, color=color, linewidth=1.5, label=name, marker='o', markersize=2)
            ax.set_ylabel(f'Signal {i}', fontsize=11, fontweight='bold')
            ax.legend(loc='upper right', fontsize=9)
            ax.grid(True, alpha=0.3)
            
            # Auto-scale y
            if len(values) > 0:
                y_min, y_max = min(values), max(values)
                margin = (y_max - y_min) * 0.1 if y_max != y_min else 1
                ax.set_ylim(y_min - margin, y_max + margin)
            
            # Show sample count for this signal
            ax.text(0.02, 0.95, f'{len(values)} samples', 
                   transform=ax.transAxes, fontsize=9,
                   verticalalignment='top',
                   bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5))
    
    axes[-1].set_xlabel('Packet Number (Time)', fontsize=11, fontweight='bold')
    
    # Title with compression info
    title = f'FPGA Adaptive Compression - {stats["sample_count"]:,} packets → {stats["total_samples"]:,} samples @ {stats["ratio"]:.1f}x compression'
    fig.suptitle(title, fontsize=14, fontweight='bold')
    
    # Statistics box at bottom
    stats_text = (
        f"Compressed: {stats['compressed_kb']:.2f} KB | "
        f"Uncompressed: {stats['uncompressed_kb']:.2f} KB | "
        f"Ratio: {stats['ratio']:.1f}x | "
        f"Signal lengths: {stats['signal_lengths']} | "
        f"Packets [RLE:{stats['packets'][0]} DeltaRLE:{stats['packets'][1]} "
        f"Delta:{stats['packets'][2]} RAW:{stats['packets'][3]}]"
    )
    
    fig.text(0.5, 0.02, stats_text, ha='center', fontsize=9,
             family='monospace',
             bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5))
    
    plt.tight_layout(rect=[0, 0.05, 1, 0.97])
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
    print(" Compression modes (bit-packed):")
    print("   RLE       - Run Length Encoding (8 bits)")
    print("   DeltaRLE  - Run Length of Deltas (8 bits)")
    print("   Delta     - Small delta (8 bits, -7 to +7)")
    print("   Raw       - Large changes (20 bits = 4-bit header + 16-bit value)")
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
                # Show first 30 packets with bit stream decoding
                print("\nFirst 30 packets (bit-packed stream):")
                debug_reader = BitStreamReader(buffer_data)
                for pkt_num in range(min(30, 100)):  # Try up to 30 packets
                    header = debug_reader.read_bits(8)
                    if header is None:
                        break
                    
                    ptype = (header >> 6) & 0x03
                    sig = (header >> 4) & 0x03
                    payload = header & 0x0F
                    type_names = ['RLE', 'DTRLE', 'DELTA', 'RAW']
                    
                    if ptype == 3:  # RAW
                        data = debug_reader.read_bits(16)
                        if data is not None:
                            # Convert to signed
                            value = data if data < 32768 else data - 65536
                            print(f"  Pkt {pkt_num:3d}: {type_names[ptype]:6s} sig={sig} value={value:6d} (header=0x{header:02X}, data=0x{data:04X})")
                        else:
                            print(f"  Pkt {pkt_num:3d}: {type_names[ptype]:6s} sig={sig} INCOMPLETE")
                            break
                    else:
                        count = payload if payload > 0 else 16
                        print(f"  Pkt {pkt_num:3d}: {type_names[ptype]:6s} sig={sig} payload={payload:2d} (count/delta={count:2d}, header=0x{header:02X})")
                print()
            
            decomp.process_byte_stream(buffer_data)
            
            # Display statistics
            stats = decomp.get_stats()
            print(f"\n{'='*70}")
            print(f"✓ Decompression complete!")
            print(f"{'='*70}")
            print(f"  Total packets:        {stats['sample_count']:,}")
            print(f"  Total samples:        {stats['total_samples']:,}")
            print(f"  Samples per signal:   {stats['signal_lengths']}")
            print(f"  Compressed size:      {stats['compressed_kb']:.2f} KB")
            print(f"  Uncompressed size:    {stats['uncompressed_kb']:.2f} KB")
            print(f"  Compression ratio:    {stats['ratio']:.1f}x")
            print(f"  Packet breakdown:")
            print(f"    RLE (same value):        {stats['packets'][0]}")
            print(f"    Delta RLE (incrementing): {stats['packets'][1]}")
            print(f"    Delta (small change):     {stats['packets'][2]}")
            print(f"    Raw (large change):       {stats['packets'][3]}")
            print(f"{'='*70}\n")
            
            # Plot
            plot_traces(decomp)
            
            # Show compression visualization
            print("\nGenerating compression visualization...")
            plot_compression_view(decomp)
            
            if not args.continuous:
                break
            
            print("\nReady for next capture...")
            
    except KeyboardInterrupt:
        print("\n\nExiting...")
    finally:
        receiver.close()


if __name__ == '__main__':
    main()
