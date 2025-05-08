--副程式:SEGMENT
-- 1. Library Declaration and Packages Usage
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
--*****************************************************************************
-- 2. Entity Declarations
entity SEGMENT is
	generic(fmax : integer := 5E7);
port(-- input Signals
	 clk		 : in  std_logic; -- Pin = 149 , 50MHz
	 rst		 : in  std_logic; -- active Low (internal Reset)
	 scan_p	     : in  std_logic; -- 1KHz Pulsed Wave (Tw = 20nS)
	 clk_flash   : in  std_logic; -- 1Hz  Square Wave
	 bin_in	     : in  std_logic_vector(47 downto 0); -- 8 Digits-6 Bits : 44 Fonts
	 digit_blink : in  std_logic_vector( 7 downto 0); -- 1 : Blink , 0 : Normal
	 dot_on	     : in  std_logic_vector( 7 downto 0); -- 1 : On    , 0 : Off
	 dot_blink	 : in  std_logic_vector( 7 downto 0); -- 1 : Blink , 0 : Normal
	 -- output Signals
	 SEG_scan    : out std_logic_vector( 7 downto 0); -- active Low
	 seg_out	 : out std_logic_vector( 7 downto 0)  -- active High	
    );
end SEGMENT;
--*****************************************************************************
-- 3. Architectures (Body)
architecture beh of SEGMENT is
	-- SEG Signals
    signal segs 	   : std_logic_vector(7 downto 0);
	signal scan_cnt	   : integer range 0 to 7;         -- 3 Bits
	-- Binary Data MUX. Signal
	signal bin		   : std_logic_vector(5 downto 0); -- 6 Bits
	-- Blinking Signals
	signal clk_flash_7 : std_logic_vector(6 downto 0);
-------------------------------------------------------------------------------	
begin
	---------------------------------------------------------------------------
	-- 1. SEG Row Scan Counter circuit
	process(clk,rst) -- Sensitivity List
	begin
		if(rst = '0')then -- Asynchronous Clear (Initializations)
			scan_cnt <= 0;
		elsif(clk'event and clk='1')then -- Positive-Edge Trigger (20nS)
			if(scan_p = '1')then -- 1Khz Pulse
				if(scan_cnt < 7)then
					scan_cnt <= scan_cnt + 1;
				else
					scan_cnt <= 0;
				end if;
			end if;
		end if;
	end process;
	---------------------------------------------------------------------------
	-- 2. 3 to 8 Decoder (active Low) : connect to PNP BJT (Common Cathode SEG)
	SEG_scan <= "11111110" when (scan_cnt = 0)else
				"11111101" when (scan_cnt = 1)else
				"11111011" when (scan_cnt = 2)else
				"11110111" when (scan_cnt = 3)else
				"11101111" when (scan_cnt = 4)else
				"11011111" when (scan_cnt = 5)else
				"10111111" when (scan_cnt = 6)else
				"01111111" ;
    ---------------------------------------------------------------------------
	-- 3. Data Selector : 6 Bits 8 Group to 1 MUX
	bin     <=	bin_in( 5 downto  0) when (scan_cnt = 0)else 
                bin_in(11 downto  6) when (scan_cnt = 1)else
                bin_in(17 downto 12) when (scan_cnt = 2)else
                bin_in(23 downto 18) when (scan_cnt = 3)else
                bin_in(29 downto 24) when (scan_cnt = 4)else
                bin_in(35 downto 30) when (scan_cnt = 5)else
                bin_in(41 downto 36) when (scan_cnt = 6)else
                bin_in(47 downto 42) ;
    ---------------------------------------------------------------------------
	-- 4. Dot Selector  : 1 Bits 8 to 1 MUX
	segs(7) <= dot_on(0) when (scan_cnt = 0)else
               dot_on(1) when (scan_cnt = 1)else
			   dot_on(2) when (scan_cnt = 2)else
			   dot_on(3) when (scan_cnt = 3)else
			   dot_on(4) when (scan_cnt = 4)else
			   dot_on(5) when (scan_cnt = 5)else
			   dot_on(6) when (scan_cnt = 6)else
			   dot_on(7) ;
    ---------------------------------------------------------------------------
	-- 5. Bin to 7-SEGMENT Display : connect to PNP BJT (Common Cathode SEG)
	--                   gfedcba    (active High)
	segs(6 downto 0) <= "0111111" when (bin = "000000")else -- 0
						"0000110" when (bin = "000001")else -- 1
						"1011011" when (bin = "000010")else -- 2
						"1001111" when (bin = "000011")else -- 3
						"1100110" when (bin = "000100")else -- 4
						"1101101" when (bin = "000101")else -- 5
						"1111101" when (bin = "000110")else -- 6
						"0000111" when (bin = "000111")else -- 7
						"1111111" when (bin = "001000")else -- 8
						"1101111" when (bin = "001001")else -- 9
						"1110111" when (bin = "001010")else -- A
						"1111100" when (bin = "001011")else -- b
						"0111001" when (bin = "001100")else -- C
						"1011110" when (bin = "001101")else -- d
						"1111001" when (bin = "001110")else -- E
						"1110001" when (bin = "001111")else -- F
						"0111101" when (bin = "010000")else -- G
						"1110110" when (bin = "010001")else -- H
						"0110000" when (bin = "010010")else -- I
						"0001110" when (bin = "010011")else -- J
						"1110101" when (bin = "010100")else -- K
						"0111000" when (bin = "010101")else -- L
						"1010101" when (bin = "010110")else -- M
						"1010100" when (bin = "010111")else -- n
						"1011100" when (bin = "011000")else -- o
						"1110011" when (bin = "011001")else -- P
						"1100111" when (bin = "011010")else -- Q
						"1010000" when (bin = "011011")else -- R
						"1101101" when (bin = "011100")else -- S
						"1111000" when (bin = "011101")else -- T
						"0111110" when (bin = "011110")else -- U
						"0001100" when (bin = "011111")else -- V
						"0101010" when (bin = "100000")else -- W
						"1001001" when (bin = "100001")else -- X
						"1101110" when (bin = "100010")else -- Y
						"1011011" when (bin = "100011")else -- Z
						"1000000" when (bin = "100100")else -- -
						"1010010" when (bin = "100101")else -- /
						"1000001" when (bin = "100110")else -- = (upper)
						"1001000" when (bin = "100111")else -- = (lower)
						"1100100" when (bin = "101000")else -- \
						"0011100" when (bin = "101001")else -- v
						"0100011" when (bin = "101010")else -- ^
						"1100011" when (bin = "101011")else -- upper o
						"0000010" when (bin = "101100")else -- |
						"0000000" ;                         -- Empty (7 SEGMENTs Off)
	---------------------------------------------------------------------------
	-- 6. SEG Blink Control Circuits	
	clk_flash_7         <= clk_flash & clk_flash & clk_flash & clk_flash &
                           clk_flash & clk_flash & clk_flash;
	seg_out(7)          <= (segs(7) and clk_flash) when(dot_blink(scan_cnt) = '1') else
                            segs(7);
	seg_out(6 downto 0) <= (segs(6 downto 0) and clk_flash_7)when(digit_blink(scan_cnt) 
                            = '1')else segs(6 downto 0);
--*****************************************************************************
end beh;