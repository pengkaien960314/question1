--副程式:SD178B
--1. Libraries Declarations and Packages usage
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
--*****************************************************************************
--2. Entity Declarations
entity SD178B is
generic (char : integer := 20 -- Max Word.
		);
port(-- input signals
	 clk      : in	  std_logic; -- 50MHz , Pin = 149
	 rst	  : in	  std_logic; -- active Low (internal Reset)
	 SD178B_p : in	  std_logic; -- 50KHz~60KHz Pulse
	 start_p  : in	  std_logic;
	 address  : in	  std_logic_vector( 6 downto 0); -- 7 Bits
	 rw		  : in    std_logic; -- 1 : read    , 0 : write
	 cmd_da   : in	  std_logic; -- 0 : Command , 1 : Data
	 cmd_char : in	  std_logic_vector( 7 downto 0); -- 0 : Command Code , 1 : Char_cnt
	 data_in  : in	  std_logic_vector((char * 16) - 1 downto 0); -- FPGA -> I2C Device
	 -- output signals
	 rst_sd_n : out	  std_logic; -- active Low
	 data_out : out	  std_logic_vector( 7 downto 0); -- I2C Device -> FPGA
	 read_out : out	  std_logic_vector(63 downto 0); -- I2C Device -> FPGA
	 bf_out   : out	  std_logic;
	 rd_done_p: out	  std_logic;
--	 led      : out std_logic_vector(3 downto 0);
	 -- I2C I/O signals
	 scl	  : out   std_logic; -- I2C : serial clock (bi-directions)
	 sda	  : inout std_logic  -- I2C : serial data  (bi-directions)
	 );
end SD178B;
--*****************************************************************************
--3. Architectures (Body)
architecture beh of SD178B is
	-- Global Signals
	-- 1.SD178MB I2C Signals
	signal sda_temp   : std_logic_vector(7 downto 0);
	
	type   data_array is array (0 to char*2-1) of std_logic_vector(7 downto 0); -- 40 Bytes
	signal data_temp  : data_array;
	
	type   read_array is array (0 to 7) of std_logic_vector(7 downto 0); -- 8 Bytes
	signal read_temp  : read_array;
	
	-- 2.SD178BMI FSM's Flags
	signal flag_init  : std_logic;
	signal flag_start : std_logic;
	signal flag_level : integer range 0 to 3;	
	-- Level 0 : address + rw
	-- Level 1 : command bytes or data bytes
	-- Level 2 : read SD178Bmi's data
--*****************************************************************************
begin
-- System Connections

--*****************************************************************************
-- SD178BMI I2C FSM
x1 : block
	-- SD178MB I2C FSM's Signals
	type   states is ( s0, s1, s2, s3, s4, s5, s6, s7, s8, s9,s10,s11,s12,s13,
					  s14,s15,s16,s17,s18,s19,s20,s21,s22,s23,s24,s25);
	signal ps,ns   : states;
	signal cnt_x   : std_logic_vector(25 downto 0); -- For Reset Delay
-------------------------------------------------------------------------------
begin
	---------------------------------------------------------------------------
	-- Two Processes FSM (Finite State Machine)
	---------------------------------------------------------------------------
	-- (1) State Changing
	process(clk) -- Sensitivity List
	begin
		if(rst = '0')then -- Initializations
			ps <= s0;
		elsif(clk'event and clk = '1')then -- Positive-Edge Trigger (20nS)
			ps <= ns;
		end if;
	end process;
	---------------------------------------------------------------------------
	-- (2) Individual State Execution Sequences
	process(rst,clk) -- Sensitivity List
		variable cnt      : integer range 0 to 31; -- 5 bits
		variable cnt_bit  : integer range 0 to 31; -- 5 bits
		variable cnt_byte : integer range 0 to 31; -- 5 bits
		variable cnt_da   : integer range 0 to char*2-1;
	begin
		if(rst = '0')then      -- Initializations
			scl 	   <= '1'; -- Idled State
			sda 	   <= '1';
			ns  	   <= s0;
			bf_out     <= '1'; -- 1 : Busy
			rd_done_p  <= '0';
			read_out   <= (others => '0');		
			flag_init  <= '1'; -- Entry SD178BMI Initializations
			flag_start <= '0';
			flag_level <=  0;
			rst_sd_n   <= '1';  -- NPN's Base (ON) : active Low (Reset)
			data_out   <= (others => '0');			
			cnt_x      <= (others => '0');
			for x in 4 downto 0 loop
				read_temp(x) <= (others => '0');
			end loop;
--			led        <= "1111";
        -----------------------------------------------------------------------
		elsif(clk'event and clk = '0')then -- Negative-Edge Trigger (20nS)
            -------------------------------------------------------------------
			-- 1. SD178BMI Initializations
			if(flag_init = '1')then
				if(cnt_x < 1E6 - 1)then -- Wait 20mS
					cnt_x     <= cnt_x + 1;
					bf_out    <= '1';
					flag_init <= '1';
				else
					rst_sd_n  <= '0';  -- NPN's Base (OFF) : Reset Ending
					cnt_x     <= (others => '0');
					bf_out    <= '0';
					flag_init <= '0';
				end if;
			-------------------------------------------------------------------
			-- 2. Check Start Pulse (SD178BMI normal Operations)
			elsif(flag_init = '0' and start_p = '1')then -- 20nS
				flag_start <= '1';
				bf_out     <= '1'; -- 1 : busy
				data_out   <= (others => '0');
				cnt_x      <= (others => '0');
				cnt        := 0; 
				ns         <= s0;
				if(rw = '0')then -- Write : FPGA --> SD178BMI
					flag_level <=  0;  -- address + rw
					if(cmd_da = '1')then -- cmd = 1 : Data
						if(conv_integer(cmd_char) = 0)then
							cnt_da := 0;
							for x in 19 downto 0 loop
								data_temp(x) <= (others => '0');
							end loop;
						else
							cnt_da := (conv_integer(cmd_char) * 2) - 1;
							for y in (char * 2) - 1 downto 0 loop
								data_temp(y) <= data_in(((y*8)+7) downto (y*8));
							end loop;
						end if;
					else                 -- cmd = 0 : Command 
						case cmd_char is
							when X"87" => -- Delay : U32 (ms) : 32 Bits
								data_temp(6) <= X"00"; -- Waiting 20mS
								data_temp(5) <= X"00";
								data_temp(4) <= X"87";
								data_temp(3) <= data_in(31 downto 24);
								data_temp(2) <= data_in(23 downto 16);
								data_temp(1) <= data_in(15 downto  8);
								data_temp(0) <= data_in( 7 downto  0);
								cnt_da       := 6;
							when X"88" => -- Play U16A U16B : U16A.wav, U16B : times
								data_temp(6) <= X"00";
								data_temp(5) <= X"00";
								data_temp(4) <= X"88";
								data_temp(3) <= data_in(31 downto 24); -- U16A-H
								data_temp(2) <= data_in(23 downto 16); -- U16A-L
								data_temp(1) <= data_in(15 downto  8); -- U16B-H
								data_temp(0) <= data_in( 7 downto  0); -- U16B-L
								cnt_da       := 6;
							when X"89" => -- Sleep Mode
								data_temp(2) <= X"00";
								data_temp(1) <= X"00";
								data_temp(0) <= X"89";
								cnt_da       := 2;
							when X"80" => -- Clear Buffer & Stop TTS (Text to Speech)
								data_temp(2) <= X"00";
								data_temp(1) <= X"00";
								data_temp(0) <= X"80";
								cnt_da       := 2;
							when X"81" => -- Volume : +0.5dB
								data_temp(2) <= X"00";
								data_temp(1) <= X"00";
								data_temp(0) <= X"81";
								cnt_da       := 2;
							when X"82" => -- Volume : -0.5dB
								data_temp(2) <= X"00";
								data_temp(1) <= X"00";
								data_temp(0) <= X"82";
								cnt_da       := 2;
							when others => -- X"83"  X"86"  X"8A" X"8B" X"8F"
										   -- Speed  Volume MO    Audio Extras
								data_temp(3) <= X"00";
								data_temp(2) <= X"00";
								data_temp(1) <= cmd_char;
								data_temp(0) <= data_in(7 downto 0);
								cnt_da       := 3;
						end case;
					end if;
				else -- Read : FPGA <-- SD178BMI
					flag_level <= 2;
				end if;
			-------------------------------------------------------------------
			-- 3. Startup SD178BMI's I2C FSM
			elsif(flag_start = '1' and SD178B_p = '1')then -- 50KHz~60KHz
				case ps is -- 20uS
					-----------------------------------------------------------
					-- 1. SD178BM I2C's Start Sequence
					when s0 =>
						scl <= '1'; -- Idled State
						sda <= '1';
						if(cnt_x < 1E3 - 1)then -- Waiting 20ms
							cnt_x <= cnt_x + 1;
							ns    <= s0;
						else
							cnt_x <= (others => '0');
							ns    <= s1;
						end if;
					when s1 =>	
						scl <= '1';
						sda <= '0'; -- Start Sequence(H -> L)
						ns  <= s2;
					when s2 =>	
						scl <= '0'; -- Data be Changed
						sda <= '0';
						cnt := 8;
						case flag_level is
							---------------------------------------------------
							-- SD178BM Normal Operations
							when 0 => -- Send  + R/W and Data Bits
--								sda_temp <= address & rw; -- X"40"
								sda_temp <= X"40";
							when 1 => -- Send Data Byte Sequence
								sda_temp <= data_temp(cnt_da);
							when 2 =>
--								sda_temp <= address & rw; -- X"41"
								sda_temp <= X"41";
							when others =>
								null;
						end case;
						ns <= s3;
					-----------------------------------------------------------
					-- 2. Send I2C Device's Slave Address + R/W and Data Bit 
					when s3 =>
						cnt := cnt - 1;
						sda <= sda_temp(cnt);
						ns  <= s4;
					when s4 =>
						scl <= '1'; -- Positive-Edge Trigger 
						ns  <= s5;
					when s5 =>
						scl <= '0'; -- Data be Changed
						ns  <= s6;
					when s6 =>
						if(cnt = 0)then
							ns  <= s7;
						else
							ns  <= s3;
						end if;
					-----------------------------------------------------------
					-- 3. Waiting for Ackowledge Signal	(FPGA <- SD178BMI)
					when s7 => 
						scl <= '0';
						sda <= 'Z'; -- Floating : Hi-Z
						ns  <= s8;
					when s8 =>     
						scl <= '1'; -- Positive-Edge Trigger 
						ns  <= s9;
					when s9 => -- Check I2C Device's ACK
						if(sda = '0')then -- ACK : OK
							scl <= '0';
							sda <= '0'; -- Output
							case flag_level is
								------------------------------
								-- Level
								when 0 =>              
									flag_level <= 1;   
									ns         <= s2; 
								when 1 =>
									if(cnt_da = 0)then
										flag_level <= 0;
										ns         <= s19; -- I2C End
									else
										flag_level <= 1; 
										cnt_da     := cnt_da - 1;
										ns         <= s2; 
									end if;
								when 2 =>                   
									cnt_bit  := 8;
									cnt_byte := 0;
									ns       <= s11;       -- Read Mode
								when others =>
									null;
							end case;
						else -- ACK : Fail
							scl <= '0';
							sda <= '0';
							ns  <= s10; -- ACK : Error
						end if;
					-----------------------------------------------------------
					-- 4. Send Error Code Sequence
					when s10 =>
						data_out <= conv_std_logic_vector(flag_level,4) &
						            conv_std_logic_vector(cnt,4);
						ns       <= s19;
					-----------------------------------------------------------
					-- 5. Read Data Mode
					when s11 =>
						scl <= '0';
						ns  <= s12;
					when s12 =>
						sda <= 'Z'; -- Floating : Hi-Z (Immediately)
						scl <= '0';
						ns  <= s13;
					when s13 =>
						scl <= '1'; -- Positive-Edge Trigger (SD178BMI Output Data)
						ns  <= s14;
					when s14 =>
						scl                          <= '0';
						cnt_bit                      := cnt_bit - 1;
						read_temp(cnt_byte)(cnt_bit) <= sda;
						ns                           <= s15;
					when s15 =>
						if(cnt_bit = 0)then
							-- FPGA Send ACK to SD178BMI
							cnt_byte := cnt_byte + 1;
							cnt_bit  := 8;
							ns       <= s16;
							if(cnt_byte > 7)then -- internal data 8 bytes
								-- Send NACK to the Last Byte
								sda <= '1'; -- FPGA Send NACK 1 to SD178BMI
							else
								sda <= '0'; -- FPGA Send  ACK 0 to SD178BMI
							end if;
						else
							ns  <= s13;
						end if;
					when s16 =>
						scl <= '1'; -- FPGA Send ACK to SD178BMI
						ns  <= s17;
					when s17 =>
						if(cnt_byte > 7)then -- internal data 8 bytes
							ns  <= s18;
						else
							ns  <= s11;
						end if;
					when s18 =>
						read_out <= read_temp(0) & read_temp(1) & read_temp(2) & read_temp(3) &
						            read_temp(4) & read_temp(5) & read_temp(6) & read_temp(7);  -- concat array (8 bytes)
--						led      <= "0101";
						ns  <= s19;
					-----------------------------------------------------------
					-- 6. Generate I2C's Stop Sequence
					when s19 =>
						scl <= '0';
						sda <= '0';
						ns  <= s20;
					when s20 =>
						scl <= '1';
						sda <= '0';
						ns  <= s21;
					when s21 =>
						scl       <= '1';
						sda       <= '1'; -- Stop Sequence(L -> H)
						rd_done_p <= '1';
						ns        <= s22;
					-----------------------------------------------------------
					-- 7. End I2C
					when others =>
						scl        <= '1'; -- Idled State
						sda        <= '1';
						bf_out     <= '0';
						flag_init  <= '0';
						flag_start <= '0';
						flag_level <= 0;
						cnt        := 0;
						rd_done_p  <= '0';
						ns         <= s0;
				end case;
			end if;
		end if;
	end process;
end block x1;
--*****************************************************************************
end beh;