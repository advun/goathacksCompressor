TO RUN: Download decompress.py, connect FPGA by USB, and run python3 decompress.py --port /dev/tty.usbserial..... --baud 115200 --debug, putting in the USB it is connected to

Only Sort of Working at Moment

What is this?

This is an FPGA trace compressor.  It locally compresses signal data from the board to allow for far more data to be gathered in the small RAM, to later be transmitted off chip and be analyzed.  

Why is this useful?

Traces generate truly tremendous amounts of data.  Just one 16 bit bus at 100Mhz is 16*100M = 1.6 billion bits per second = 200MB per second. That's just one bus!  
There is no transmission protocal fast enough for a full system, and FPGA BRAM is usuualy sub 1 GB.  So, working around our limitations, if we locally compress the data, we can fit signifigantly more 
in the same limited BRAM, for later reading.  Luckily, FPGA data is fairly predictable, and thus easily compressed.  Currently, it appears to be compressing about 7.4x (though this could be improved by increasing the RLE lengths allowed).  It uses about 0.89% of the LUTs and 0.59% of the flipflops on the Basys3.  I used 4 different data compression modes:

Compression Strategies:

RAW: if data changes too much to properly compress: don’t compress it!
Delta magnitudes are large
Run lengths are short
Entropy is high

RAW: 2.5 bytes: 
2 bits for code, 2 bits for signal
8 bits for first half of value
8 bits for second half of value


Normal RLE (Run-Length Encoding Mode)
Long runs of the same number.  Replace 9,9,9,9 with {9,4} (4 9s in a row)

RLE: 1 byte: 
2 bits for code, 2 bits for signal, 4 bits for run length

Delta RLE Mode
Long runs of the same delta (like a counter).  Replace 1,2,3,4 with {1,4} (a run of 4 numbers that are each 1 higher then the last)

Delta RLE: 1 byte: 
2 bits for code, 2 bits for signal, 4 bits for run length

Small Delta
Some signals change frequently and unpredictably but only by a small amount. This can be saved in a much smaller space then RAW just by saving a small delta instead of the full value

Small Delta: 1 byte
 2 bits for code, 2 bits for signal, 4 bits for delta



This project is made for the Basys3 board, and saves 4 compressed traces that it generates in compressor_top to BRAM.  It is EXTREMELY buggy, and has readback issues that I believe
are caused by how I save to BRAM.  compression.sv is the compression algorithim (which I am like 95% is not the issue). It was made solo for the GOATHACKS hackathon.  It will be developed further.
