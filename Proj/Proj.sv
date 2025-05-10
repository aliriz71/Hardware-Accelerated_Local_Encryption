// ============================================================================
// Project: Proj - DE10-Lite SPI Enc/Dec Test (128-bit, Continuous, Final Sync Fix)
// Module:  Proj (Top Level)
//
// Description:
// - Includes synchronizers for SPI input signals.
// - Implements a 128-bit SPI Slave interface (Mode 0).
// - Continuously receives 16 bytes (128 bits) from the master.
// - Processes received data using simple XOR based on SW[0].
// - Continuously prepares the processed result (if SW[1]=1) or zeros (if SW[1]=0)
//   for the next SPI transmission.
// - Transmits the prepared data back on MISO when requested by master.
// - Uses GPIO[0..3] for SPI communication.
// - Displays first 2 bytes received on HEX3-0.
// - Displays last byte of prepared-to-send data on HEX5-4.
// - Uses LEDs for status. KEY[0] is active-low reset.
// ============================================================================
`default_nettype none

//-----------------------------------------------------------------------------
// 7-Segment Decoder Module (Common Cathode, Active HIGH segments)
//-----------------------------------------------------------------------------
module seven_segment_decoder_cc (
    input wire [3:0]  bcd_in,
    output reg [6:0] segments_out // abcdefg (active HIGH)
);
    // Common Cathode mapping: 1 = segment ON, 0 = segment OFF
    always_comb begin
        case (bcd_in)
          // gfedcba
          4'h0: segments_out = 7'b0111111; 4'h1: segments_out = 7'b0000110;
          4'h2: segments_out = 7'b1011011; 4'h3: segments_out = 7'b1001111;
          4'h4: segments_out = 7'b1100110; 4'h5: segments_out = 7'b1101101;
          4'h6: segments_out = 7'b1111101; 4'h7: segments_out = 7'b0000111;
          4'h8: segments_out = 7'b1111111; 4'h9: segments_out = 7'b1101111;
          4'hA: segments_out = 7'b1110111; 4'hB: segments_out = 7'b1111100; // b
          4'hC: segments_out = 7'b0111001; 4'hD: segments_out = 7'b1011110; // d
          4'hE: segments_out = 7'b1111001; 4'hF: segments_out = 7'b1110001;
          default: segments_out = 7'b0000000; // OFF
        endcase
    end
endmodule : seven_segment_decoder_cc

//-----------------------------------------------------------------------------
// SPI Slave Module (128-bit, Mode 0) - WITH SYNCHRONIZERS
//-----------------------------------------------------------------------------
module spi_slave_128bit (
    input wire clk,         // System clock (CLOCK_50)
    input wire rst_n,       // Active low reset

    // SPI Interface Pins (Asynchronous to clk)
    input wire spi_sclk,
    input wire spi_mosi,
    input wire spi_cs_n,
    output reg spi_miso,    // Output driven by clk domain

    // Data Interface (Synchronous to clk)
    input wire [127:0] data_to_transmit,
    output reg [127:0] data_received,
    output reg         data_valid
    // Removed spi_cs_n_sync output, use internal one only
);

    reg [127:0] rx_shift_reg;
    reg [127:0] tx_shift_reg; // Internal transmit buffer, loaded when CS goes high
    reg [7:0]   bit_count;

    // --- Synchronizers for Inputs ---
    reg spi_sclk_sync1, spi_sclk_sync2;
    reg spi_mosi_sync1, spi_mosi_sync2;
    reg spi_cs_n_sync1, spi_cs_n_sync2;

    wire spi_sclk_sync = spi_sclk_sync2;
    wire spi_mosi_sync = spi_mosi_sync2;
    wire spi_cs_n_sync = spi_cs_n_sync2; // Internal synchronized CS

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            spi_sclk_sync1 <= 1'b0; spi_sclk_sync2 <= 1'b0;
            spi_mosi_sync1 <= 1'b0; spi_mosi_sync2 <= 1'b0;
            spi_cs_n_sync1 <= 1'b1; spi_cs_n_sync2 <= 1'b1;
        end else begin
            spi_sclk_sync1 <= spi_sclk; spi_sclk_sync2 <= spi_sclk_sync1;
            spi_mosi_sync1 <= spi_mosi; spi_mosi_sync2 <= spi_mosi_sync1;
            spi_cs_n_sync1 <= spi_cs_n; spi_cs_n_sync2 <= spi_cs_n_sync1;
        end
    end

    // --- Edge Detection (using synchronized clock) ---
    reg spi_sclk_sync_d1;
    wire spi_sclk_rising_edge_sync;
    wire spi_sclk_falling_edge_sync;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin spi_sclk_sync_d1 <= 1'b0; end
        else begin spi_sclk_sync_d1 <= spi_sclk_sync; end
    end
    assign spi_sclk_rising_edge_sync  = (spi_sclk_sync == 1'b1) && (spi_sclk_sync_d1 == 1'b0);
    assign spi_sclk_falling_edge_sync = (spi_sclk_sync == 1'b0) && (spi_sclk_sync_d1 == 1'b1);

    // --- SPI Logic (using synchronized inputs) ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_shift_reg <= 128'b0; tx_shift_reg <= 128'b0; spi_miso <= 1'b1;
            bit_count <= 8'b0; data_received <= 128'b0; data_valid <= 1'b0;
        end else begin
            data_valid <= 1'b0; // Default

            if (spi_cs_n_sync == 1'b1) begin // CS inactive
                 spi_miso <= 1'b1; bit_count <= 8'b0;
                 tx_shift_reg <= data_to_transmit; // Latch data for next send cycle
            end else begin // CS active
                 // Transmit (Mode 0: Change on falling edge)
                if (spi_sclk_falling_edge_sync) begin
                   spi_miso <= tx_shift_reg[127];
                   tx_shift_reg <= {tx_shift_reg[126:0], 1'b0};
                end
                 // Receive (Mode 0: Sample on rising edge)
                 if (spi_sclk_rising_edge_sync) begin
                    rx_shift_reg <= {rx_shift_reg[126:0], spi_mosi_sync}; // Use sync MOSI
                    bit_count <= bit_count + 1;
                    if (bit_count == 8'd127) begin
                        data_received <= {rx_shift_reg[126:0], spi_mosi_sync}; // Use sync MOSI
                        data_valid <= 1'b1;
                    end
                 end
            end
        end
    end
endmodule : spi_slave_128bit

//-----------------------------------------------------------------------------
// Top Level Module: Proj
//-----------------------------------------------------------------------------
module Proj (
    input wire        CLOCK_50,
    input wire [1:0]  KEY,
    input wire [9:0]  SW,
    output wire [9:0] LEDR,
    output wire [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, // Common Cathode

    inout wire [35:0] GPIO
);

    localparam [127:0] DUMMY_KEY_128 = 128'hA5A5A5A5_A5A5A5A5_A5A5A5A5_A5A5A5A5;

    wire rst_n = KEY[0];
    wire reset = ~rst_n;

    // SPI Connections to GPIO
    wire spi_sclk_in = GPIO[0];
    wire spi_mosi_in = GPIO[1];
    wire spi_miso_out; // Output from slave module
    wire spi_cs_n_in = GPIO[3];

    // Internal signals from SPI slave
    wire spi_data_valid;
    wire [127:0] received_data_from_spi;

    // Control signals
    wire decrypt_mode = SW[0];	//controlled through first switch and is input for the AES core
    wire send_enable = SW[1]; // Controls what data gets prepared

    // Data registers
    reg [127:0] spi_received_data_reg; // Stores the last fully received data
    reg [127:0] processed_data_reg;    // Stores the XOR result
    wire [127:0] data_for_spi_slave;   // Data to feed into SPI slave's transmit input

	 //AES module wires
	 logic [127:0]    aes_out;
    logic            aes_done;
	 
	 
	assign GPIO[2] = spi_miso_out; // Connect MISO output driver

   // --- Instantiate SPI Slave with Synchronizers ---
   spi_slave_128bit u_spi_slave (
        .clk             (CLOCK_50),
        .rst_n           (rst_n),
        .spi_sclk        (spi_sclk_in),
        .spi_mosi        (spi_mosi_in),
        .spi_miso        (spi_miso_out),
        .spi_cs_n        (spi_cs_n_in),
        .data_to_transmit(data_for_spi_slave), // Data selected below
        .data_received   (received_data_from_spi),
        .data_valid      (spi_data_valid)
       // .spi_cs_n_sync() // Not directly needed here
    );
	 
	 /*
	  * Get the encryption/decryption from aes_128
	  *
	 */
	aes128_iterative #(
	  .AES_KEY(DUMMY_KEY_128)
	) u_aes (
	  .clk      (CLOCK_50),
	  .rst_n    (rst_n),
	  .start    (spi_data_valid ),  
	  .mode     (decrypt_mode),
	  .data_in  (received_data_from_spi),
	  .data_out (aes_out),
	  .done     (aes_done)
	);

	 
	 

    // --- Latch received data & Process it ---
   //----------------------------------------------------------------------
	//  Capture SPI word & then grab AES result
	//----------------------------------------------------------------------

	always_ff @(posedge CLOCK_50 or posedge reset) begin
	  if (reset) begin
		 spi_received_data_reg <= 128'b0;
		 processed_data_reg    <= 128'b0;
	  end else begin
		 // Step 1: whenever a new 128-bit arrives, grab it
		 if (spi_data_valid) begin
			spi_received_data_reg <= received_data_from_spi;
		 end

		 // Step 2: when AES core finishes, grab the encrypted/decrypted block
		 if (aes_done) begin
			processed_data_reg <= aes_out;
		 end
	  end
	end

    // --- Combinational logic: Select data to prepare for sending ---
    // This selected data will be latched by the SPI slave when CS goes high.
    assign data_for_spi_slave = send_enable ? processed_data_reg : 128'b0;

    // --- LED Outputs ---
    assign LEDR[0] = ~spi_cs_n_in;     // Direct CS status (Active LOW)
    assign LEDR[1] = spi_data_valid;   // Data valid pulse
    assign LEDR[8] = send_enable;      // SW[1] status should be SW[1] == 1 for enabling a send
    assign LEDR[9] = decrypt_mode;     // SW[0] status SW[0]==0 encrypt, SW[0]==1 decrypt
    assign LEDR[7:2] = 6'b0;

	 
    // --- HEX Display Assignment ---
    logic [3:0] rx_nibble0, rx_nibble1, rx_nibble2, rx_nibble3;
    logic [3:0] tx_nibble0, tx_nibble1; // Displaying last byte PREPARED TO SEND

    // Display FIRST 16 bits (MSBs) of RECEIVED data on HEX3..HEX0
    assign rx_nibble0 = spi_received_data_reg[115:112]; // First byte received (Byte 15), Lnib
    assign rx_nibble1 = spi_received_data_reg[119:116]; // First byte received (Byte 15), Hnib
    assign rx_nibble2 = spi_received_data_reg[123:120]; // Second byte received (Byte 14), Lnib
    assign rx_nibble3 = spi_received_data_reg[127:124]; // Second byte received (Byte 14), Hnib

    // Display last 8 bits (LSBs) of data PREPARED TO SEND on HEX5..HEX4
    assign tx_nibble0 = data_for_spi_slave[3:0];
    assign tx_nibble1 = data_for_spi_slave[7:4];

    // Instantiate Common Cathode 7-Segment Decoders
    seven_segment_decoder_cc hex0_decoder (.bcd_in(rx_nibble0),   .segments_out(HEX0));
    seven_segment_decoder_cc hex1_decoder (.bcd_in(rx_nibble1),   .segments_out(HEX1));
    seven_segment_decoder_cc hex2_decoder (.bcd_in(rx_nibble2),   .segments_out(HEX2));
    seven_segment_decoder_cc hex3_decoder (.bcd_in(rx_nibble3),   .segments_out(HEX3));
    seven_segment_decoder_cc hex4_decoder (.bcd_in(tx_nibble0),   .segments_out(HEX4));
    seven_segment_decoder_cc hex5_decoder (.bcd_in(tx_nibble1),   .segments_out(HEX5));

endmodule : Proj
`default_nettype wire