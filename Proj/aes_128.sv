`default_nettype none

module aes128_iterative #(
  parameter logic [127:0] AES_KEY = 128'hA5A5A5A5_A5A5A5A5_A5A5A5A5_A5A5A5A5
)(
  input  logic         clk,       // system clock
  input  logic         rst_n,     // active-low reset
  input  logic         start,     // pulse to begin encrypt/decrypt
  input  logic         mode,      // 0 = encrypt, 1 = decrypt
  input  logic [127:0] data_in,   // 128-bit plaintext or ciphertext
  output logic [127:0] data_out,  // result when done
  output logic         done       // one-cycle pulse when data_out is valid
);

  // -------------------------------------------------------
  // S-Box, InvS-Box, GF multipliers 
  // -------------------------------------------------------
  // AES S-Box
	localparam logic [7:0] SBOX [0:255] = '{
	  8'h63,8'h7c,8'h77,8'h7b,8'hf2,8'h6b,8'h6f,8'hc5,8'h30,8'h01,8'h67,8'h2b,8'hfe,8'hd7,8'hab,8'h76,
	  8'hca,8'h82,8'hc9,8'h7d,8'hfa,8'h59,8'h47,8'hf0,8'had,8'hd4,8'ha2,8'haf,8'h9c,8'ha4,8'h72,8'hc0,
	  8'hb7,8'hfd,8'h93,8'h26,8'h36,8'h3f,8'hf7,8'hcc,8'h34,8'ha5,8'he5,8'hf1,8'h71,8'hd8,8'h31,8'h15,
	  8'h04,8'hc7,8'h23,8'hc3,8'h18,8'h96,8'h05,8'h9a,8'h07,8'h12,8'h80,8'he2,8'heb,8'h27,8'hb2,8'h75,
	  8'h09,8'h83,8'h2c,8'h1a,8'h1b,8'h6e,8'h5a,8'ha0,8'h52,8'h3b,8'hd6,8'hb3,8'h29,8'he3,8'h2f,8'h84,
	  8'h53,8'hd1,8'h00,8'hed,8'h20,8'hfc,8'hb1,8'h5b,8'h6a,8'hcb,8'hbe,8'h39,8'h4a,8'h4c,8'h58,8'hcf,
	  8'hd0,8'hef,8'haa,8'hfb,8'h43,8'h4d,8'h33,8'h85,8'h45,8'hf9,8'h02,8'h7f,8'h50,8'h3c,8'h9f,8'ha8,
	  8'h51,8'ha3,8'h40,8'h8f,8'h92,8'h9d,8'h38,8'hf5,8'hbc,8'hb6,8'hda,8'h21,8'h10,8'hff,8'hf3,8'hd2,
	  8'hcd,8'h0c,8'h13,8'hec,8'h5f,8'h97,8'h44,8'h17,8'hc4,8'ha7,8'h7e,8'h3d,8'h64,8'h5d,8'h19,8'h73,
	  8'h60,8'h81,8'h4f,8'hdc,8'h22,8'h2a,8'h90,8'h88,8'h46,8'hee,8'hb8,8'h14,8'hde,8'h5e,8'h0b,8'hdb,
	  8'he0,8'h32,8'h3a,8'h0a,8'h49,8'h06,8'h24,8'h5c,8'hc2,8'hd3,8'hac,8'h62,8'h91,8'h95,8'he4,8'h79,
	  8'he7,8'hc8,8'h37,8'h6d,8'h8d,8'hd5,8'h4e,8'ha9,8'h6c,8'h56,8'hf4,8'hea,8'h65,8'h7a,8'hae,8'h08,
	  8'hba,8'h78,8'h25,8'h2e,8'h1c,8'ha6,8'hb4,8'hc6,8'he8,8'hdd,8'h74,8'h1f,8'h4b,8'hbd,8'h8b,8'h8a,
	  8'h70,8'h3e,8'hb5,8'h66,8'h48,8'h03,8'hf6,8'h0e,8'h61,8'h35,8'h57,8'hb9,8'h86,8'hc1,8'h1d,8'h9e,
	  8'he1,8'hf8,8'h98,8'h11,8'h69,8'hd9,8'h8e,8'h94,8'h9b,8'h1e,8'h87,8'he9,8'hce,8'h55,8'h28,8'hdf,
	  8'h8c,8'ha1,8'h89,8'h0d,8'hbf,8'he6,8'h42,8'h68,8'h41,8'h99,8'h2d,8'h0f,8'hb0,8'h54,8'hbb,8'h16
	};

	// AES inverse S-Box
	localparam logic [7:0] INV_SBOX [0:255] = '{
	  8'h52,8'h09,8'h6a,8'hd5,8'h30,8'h36,8'ha5,8'h38,8'hbf,8'h40,8'ha3,8'h9e,8'h81,8'hf3,8'hd7,8'hfb,
	  8'h7c,8'he3,8'h39,8'h82,8'h9b,8'h2f,8'hff,8'h87,8'h34,8'h8e,8'h43,8'h44,8'hc4,8'hde,8'he9,8'hcb,
	  8'h54,8'h7b,8'h94,8'h32,8'ha6,8'hc2,8'h23,8'h3d,8'hee,8'h4c,8'h95,8'h0b,8'h42,8'hfa,8'hc3,8'h4e,
	  8'h08,8'h2e,8'ha1,8'h66,8'h28,8'hd9,8'h24,8'hb2,8'h76,8'h5b,8'ha2,8'h49,8'h6d,8'h8b,8'hd1,8'h25,
	  8'h72,8'hf8,8'hf6,8'h64,8'h86,8'h68,8'h98,8'h16,8'hd4,8'ha4,8'h5c,8'hcc,8'h5d,8'h65,8'hb6,8'h92,
	  8'h6c,8'h70,8'h48,8'h50,8'hfd,8'hed,8'hb9,8'hda,8'h5e,8'h15,8'h46,8'h57,8'ha7,8'h8d,8'h9d,8'h84,
	  8'h90,8'hd8,8'hab,8'h00,8'h8c,8'hbc,8'hd3,8'h0a,8'hf7,8'he4,8'h58,8'h05,8'hb8,8'hb3,8'h45,8'h06,
	  8'hd0,8'h2c,8'h1e,8'h8f,8'hca,8'h3f,8'h0f,8'h02,8'hc1,8'haf,8'hbd,8'h03,8'h01,8'h13,8'h8a,8'h6b,
	  8'h3a,8'h91,8'h11,8'h41,8'h4f,8'h67,8'hdc,8'hea,8'h97,8'hf2,8'hcf,8'hce,8'hf0,8'hb4,8'he6,8'h73,
	  8'h96,8'hac,8'h74,8'h22,8'he7,8'had,8'h35,8'h85,8'he2,8'hf9,8'h37,8'he8,8'h1c,8'h75,8'hdf,8'h6e,
	  8'h47,8'hf1,8'h1a,8'h71,8'h1d,8'h29,8'hc5,8'h89,8'h6f,8'hb7,8'h62,8'h0e,8'haa,8'h18,8'hbe,8'h1b,
	  8'hfc,8'h56,8'h3e,8'h4b,8'hc6,8'hd2,8'h79,8'h20,8'h9a,8'hdb,8'hc0,8'hfe,8'h78,8'hcd,8'h5a,8'hf4,
	  8'h1f,8'hdd,8'ha8,8'h33,8'h88,8'h07,8'hc7,8'h31,8'hb1,8'h12,8'h10,8'h59,8'h27,8'h80,8'hec,8'h5f,
	  8'h60,8'h51,8'h7f,8'ha9,8'h19,8'hb5,8'h4a,8'h0d,8'h2d,8'he5,8'h7a,8'h9f,8'h93,8'hc9,8'h9c,8'hef,
	  8'ha0,8'he0,8'h3b,8'h4d,8'hae,8'h2a,8'hf5,8'hb0,8'hc8,8'heb,8'hbb,8'h3c,8'h83,8'h53,8'h99,8'h61,
	  8'h17,8'h2b,8'h04,8'h7e,8'hba,8'h77,8'hd6,8'h26,8'he1,8'h69,8'h14,8'h63,8'h55,8'h21,8'h0c,8'h7d
	};
	/*
	put into column major form  for 4x4 matrix b->byte:
	b0    b4		b8		b12
	b1		b5		b9		b13
	b2		b6		b10	b14
	b3		b7		b11	b15
	*/
	function automatic logic [127:0] to_column_major(input logic [127:0] flat);
		logic [127:0] cm;
		// Row‑major indices: flat[7:0] = b0, flat[15:8] = b1, …
		for (int col = 0; col < 4; col++)
			for (int row = 0; row < 4; row++)
				cm[((col*4)+row)*8 +: 8] = flat[((row*4)+col)*8 +: 8];
		return cm;
	endfunction


	
	
	// -------------------------------------------------------
	// Round Keys
	// -------------------------------------------------------
	// Hardcoded round keys for example
	localparam logic [127:0] round_keys [0:10] = '{
		AES_KEY,                                        // Round key 0 (original key)
		128'hA2A3A3A3_07060606_A2A3A3A3_07060606,       // Round key 1
		128'hCFCCCC66_C8CACA60_6A6969C3_6D6F6FC5,       // Round key 2
		128'h63646A5A_ABAEA03A_C1C7C9F9_ACA8A63C,       // Round key 3
		128'hA94081CB_02EE21F1_C329E808_6F814E34,       // Round key 4
		128'hB56F9963_B781B892_74A8509A_1B291EAE,       // Round key 5
		128'h301D7DCC_879CC55E_F33495C4_E81D8B6A,       // Round key 6
		128'hD4207F57_53BCBA09_A0882FCD_4895A4A7,       // Round key 7
		128'h7E692305_2DD5990C_8D5DB6C1_C5C81266,       // Round key 8
		128'h8DA010A3_A07589AF_2D283F6E_E8E02D08,       // Round key 9
		128'h5A782038_FA0DA997_D72596F9_3FC5BBF1        // Round key 10
	};

	// -------------------------------------------------------
	// AES step functions
	// -------------------------------------------------------
	
	//Encryption 1) Substitute Bytes from SBOX lookup table
	function automatic logic [127:0] sub_bytes(input logic [127:0] state);
	  for (int i = 0; i < 16; i++)
		 sub_bytes[i*8 +: 8] = SBOX[state[i*8 +: 8]];
	endfunction
	
	//Decryption 1) Inverse Substitute Bytes from INV_SBOX lookup table
	function automatic logic [127:0] inv_sub_bytes(input logic [127:0] state);
	  for (int i = 0; i < 16; i++)
		 inv_sub_bytes[i*8 +: 8] = INV_SBOX[state[i*8 +: 8]];	
	endfunction
	
	/*
	Encryption 2) Shift Rows
	shift the rows to the left
	[b0 ][b4 ][b8 ][b12]			[b0 ][b4 ][b8 ][b12], no shifts for row 0
	[b1 ][b5 ][b9 ][b13] => 	[b5 ][b9 ][b13][b1 ], shift left once row 1
	[b2 ][b6 ][b10][b14] 		[b10][b14][b2 ][b6 ], shift left twice row 2
	[b3 ][b7 ][b11][b15]			[b15][b3 ][b7 ][b11], shift left thrice row 3
	*/
	function automatic logic [127:0] shift_rows(input logic [127:0] state);
		logic [7:0] b [0:15];
	   // Unpack for clarity
		for (int i = 0; i < 16; i++) 
			b[i] = state[i*8 +: 8];

	   // Row 0: no shift
	   // Row 1: left 1
	   b[1]  = b[5];  b[5]  = b[9];  b[9]  = b[13]; b[13] = b[1];
	   // Row 2: left 2
	   {b[2],  b[6],  b[10], b[14]} = {b[10], b[14], b[2],  b[6]};
	   // Row 3: left 3  
	   {b[3],  b[7],  b[11], b[15]} = {b[7],  b[11], b[15], b[3]};

	   // Re‑pack
	   for (int i = 0; i < 16; i++) 
			shift_rows[i*8 +: 8] = b[i];
	endfunction
	
	// Decryption 2) InvShiftRows (Inverse ShiftRows for decryption)
	function automatic logic [127:0] inv_shift_rows(input logic [127:0] state);
		logic [7:0] b [0:15];
		for (int i = 0; i < 16; i++) 
			b[i] = state[i*8 +: 8];

		// Row 1: right 1
		b[1]  = b[13]; b[5]  = b[1];  b[9]  = b[5];  b[13] = b[9];
		// Row 2: right 2
		{b[2], b[6], b[10], b[14]} = {b[6], b[10], b[14], b[2]};
		// Row 3: right 3
		{b[3], b[7], b[11], b[15]} = {b[15], b[3], b[7], b[11]};

		for (int i = 0; i < 16; i++) 
			inv_shift_rows[i*8 +: 8] = b[i];
	endfunction
	

	// Encryption 3) Mix Columns
	/*
	In GF(2^8) multiplication, elements are 8-bit numbers (0-255)
	
	Columns are polynomials over GF(2^8) with a fixed polynomial
	Column‑major byte order: {b0,b4,b8,b12}, {b1,b5,b9,b13}, {b2,b6,b10,b14}, {b3,b7,b11,b15}
	Apply the fixed 4×4 matrix multiplicatoin
	02 03 01 01
	01 02 03 01
	01 01 02 03
	03 01 01 02ID
	
	*/
	
	function automatic logic [127:0] mix_columns(input logic [127:0] state);
		logic [7:0] col0 [3:0];  
		logic [7:0] col1 [3:0];  
		logic [7:0] col2 [3:0];  
		logic [7:0] col3 [3:0];  

		logic [7:0] new_col0 [3:0];
		logic [7:0] new_col1 [3:0];
		logic [7:0] new_col2 [3:0];
		logic [7:0] new_col3 [3:0];

		// Extract the columns from the state in column-major order
		{col0[0], col0[1], col0[2], col0[3]} = {state[7:0], state[39:32], state[71:64], state[103:96]};
		{col1[0], col1[1], col1[2], col1[3]} = {state[15:8], state[47:40], state[79:72], state[111:104]};
		{col2[0], col2[1], col2[2], col2[3]} = {state[23:16], state[55:48], state[87:80], state[119:112]};
		{col3[0], col3[1], col3[2], col3[3]} = {state[31:24], state[63:56], state[95:88], state[127:120]};

		// Mix Columns Transformation (GF(2^8) multiplication) for all columns	
		for (int i = 0; i < 4; i++) begin
			new_col0[i] = mul2(col0[i]) ^ mul3(col1[i]) ^ col2[i] ^ col3[i];
			new_col1[i] = col0[i] ^ mul2(col1[i]) ^ mul3(col2[i]) ^ col3[i];
			new_col2[i] = col0[i] ^ col1[i] ^ mul2(col2[i]) ^ mul3(col3[i]);
			new_col3[i] = mul3(col0[i]) ^ col1[i] ^ col2[i] ^ mul2(col3[i]);
		end

		// Reassemble the columns back into the state
		mix_columns = {new_col3[3], new_col2[3], new_col1[3], new_col0[3],
                   new_col3[2], new_col2[2], new_col1[2], new_col0[2],
                   new_col3[1], new_col2[1], new_col1[1], new_col0[1],
                   new_col3[0], new_col2[0], new_col1[0], new_col0[0]};
	endfunction

	// Function to multiply by 2 (in GF(2^8))
	function automatic logic [7:0] mul2(input logic [7:0] b);
		mul2 = {b[6:0], 1'b0} ^ (b[7] ? 8'h1B : 8'h00);	//0x1B representing x^8 + x^4 + x^3 + x + 1 in binary
	endfunction

	// Function to multiply by 3 (in GF(2^8))
	function automatic logic [7:0] mul3(input logic [7:0] b);
		mul3 = mul2(b) ^ b;	//b*2 + b*1 == multiplication of 3 in GF(2^8)
	endfunction
	
	//////////////////////////////////INVERSE MIX COLUMNS: START//////////////////////////////////////////
	//Decryption 3) Inverse Mix Columns
	function automatic logic [127:0] inv_mix_columns(input logic [127:0] state);
		logic [7:0] col0 [3:0];  
		logic [7:0] col1 [3:0];  
		logic [7:0] col2 [3:0];  
		logic [7:0] col3 [3:0];  

		logic [7:0] new_col0 [3:0];
		logic [7:0] new_col1 [3:0];
		logic [7:0] new_col2 [3:0];
		logic [7:0] new_col3 [3:0];

		// Extract the columns from the state in column-major order
		{col0[0], col0[1], col0[2], col0[3]} = {state[7:0], state[39:32], state[71:64], state[103:96]};
		{col1[0], col1[1], col1[2], col1[3]} = {state[15:8], state[47:40], state[79:72], state[111:104]};
		{col2[0], col2[1], col2[2], col2[3]} = {state[23:16], state[55:48], state[87:80], state[119:112]};
		{col3[0], col3[1], col3[2], col3[3]} = {state[31:24], state[63:56], state[95:88], state[127:120]};

		// Inverse MixColumns Transformation (using inverse matrix coefficients)
		for (int i = 0; i < 4; i++) begin
			// Apply inverse matrix multiplication for each column
			new_col0[i] = mul0e(col0[i]) ^ mul0b(col1[i]) ^ mul0d(col2[i]) ^ mul09(col3[i]);
			new_col1[i] = mul09(col0[i]) ^ mul0e(col1[i]) ^ mul0b(col2[i]) ^ mul0d(col3[i]);
			new_col2[i] = mul0d(col0[i]) ^ mul09(col1[i]) ^ mul0e(col2[i]) ^ mul0b(col3[i]);
			new_col3[i] = mul0b(col0[i]) ^ mul0d(col1[i]) ^ mul09(col2[i]) ^ mul0e(col3[i]);
		end

		// Reassemble the columns back into the state
		inv_mix_columns = {new_col3[3], new_col2[3], new_col1[3], new_col0[3],
                       new_col3[2], new_col2[2], new_col1[2], new_col0[2],
                       new_col3[1], new_col2[1], new_col1[1], new_col0[1],
                       new_col3[0], new_col2[0], new_col1[0], new_col0[0]};
	endfunction

	// Helper functions for inverse multiplication by constants (in GF(2^8))
	function automatic logic [7:0] mul0e(input logic [7:0] b);
		mul0e = mul2(mul2(mul2(b))) ^ mul3(b);  // Multiply by 0x0e
	endfunction

	function automatic logic [7:0] mul0b(input logic [7:0] b);
		mul0b = mul2(mul2(mul2(b))) ^ b;  // Multiply by 0x0b
	endfunction

	function automatic logic [7:0] mul0d(input logic [7:0] b);
		mul0d = mul2(mul2(mul2(b))) ^ mul2(b) ^ b;  // Multiply by 0x0d
	endfunction

	function automatic logic [7:0] mul09(input logic [7:0] b);
		mul09 = mul2(mul2(mul2(b))) ^ b;  // Multiply by 0x09
	endfunction
	//////////////////////////////////INVERSE MIX COLUMNS: END//////////////////////////////////////////
	
	//Encryption 4) XOR Round Key
	function automatic logic [127:0] add_round_key(input logic [127:0] state, input logic [127:0] round_key);
		add_round_key = state ^ round_key; // XOR the state with the round key
	endfunction

	
	//////////////////////////////////////////////////////////////
	//		FSM
	//////////////////////////////////////////////////////////////
	
	// FSM states
	typedef enum logic [1:0] {
		S_IDLE,
		S_ROUND,
		S_FINAL
	} state_t;

	state_t       cs, ns;		//current state, next state
	logic [127:0] state_reg;
	logic [3:0]   round_cnt;
	logic         busy;

	// output assignment
	assign data_out = state_reg; //test 128'h31323334353637383930303030303030; does not return this result to Pico. There are errors in the SPI

	// next‐state logic
	always_comb begin
		ns    = cs;
		case (cs)
			S_IDLE: if (start)    ns = S_ROUND;
			S_ROUND:
				if (mode==0 && round_cnt==10)    ns = S_FINAL;
				else if (mode==1 && round_cnt==0) ns = S_FINAL;
			S_FINAL:                       ns = S_IDLE;
		endcase
	end

	// state & data transitions
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			cs         <= S_IDLE;
			state_reg  <= '0;
			round_cnt  <= '0;
			done       <= 1'b0;
			busy       <= 1'b0;
		end else begin
      cs    <= ns;
      done  <= 1'b0;  // default

		case (cs)
        //--------------------------------------------------
			S_IDLE: begin
				busy <= 1'b0;
				if (start) begin
					busy      <= 1'b1;
					// initialize for encrypt or decrypt
					if (mode == 1'b0) begin
						// encryption
						state_reg <= data_in ^ round_keys[0];		//round_keys[0] being the AES key
						round_cnt <= 4'd1;
					end else begin
						// decryption
						state_reg <= data_in ^ round_keys[10];
						round_cnt <= 4'd9;
					end
				end
			end

			//--------------------------------------------------
			S_ROUND: begin
				// encryption middle rounds
				if (mode == 1'b0) begin
					// rounds 1–9
					//apply the 4 round transformations in order on the state matrix
					state_reg <= add_round_key(mix_columns(shift_rows(sub_bytes(state_reg))),round_keys[round_cnt]);            
					round_cnt <= round_cnt + 4'd1;

				end else begin
					// decryption middle rounds (rounds 9 to 1)
					state_reg <= inv_mix_columns(add_round_key(inv_sub_bytes(inv_shift_rows(state_reg)),round_keys[round_cnt]));
					round_cnt <= round_cnt - 4'd1;
				end
			end

			//--------------------------------------------------
			S_FINAL: begin
				// final round (no MixColumns)
				if (mode == 1'b0) begin
					// encryption final
					state_reg <= add_round_key(shift_rows(sub_bytes(state_reg)),round_keys[10]);
				end else begin
					// decryption final
					state_reg <= add_round_key(inv_sub_bytes(inv_shift_rows(state_reg)),round_keys[0]);
				end

			done <= 1'b1;
         busy <= 1'b0;
         busy <= 1'b0;
			end
		endcase
		end
	end
endmodule

`default_nettype wire
