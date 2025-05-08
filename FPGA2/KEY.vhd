--副程式:KEY
-- 1. Library Declaration and Packages Usage
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
--*****************************************************************************
-- 2. Entity Declarations
entity KEY is
	generic(fmax : integer := 5E7);
port(
	--input pins
	clk			: in  std_logic; -- Pin = 149 , 50MHz
	rst			: in  std_logic; -- active Low (internal Reset)
	f_1kp		: in  std_logic; -- 1KHz Pulsed Wave
	kb_col		: in  std_logic_vector(3 downto 0); -- active Low 
	--output pins
	kb_row	    : out std_logic_vector(3 downto 0); -- active Low
	kb_data		: buffer integer range 0 to 16;
	kb_done_p	: out std_logic                     -- Pulse(Tw = 20nS)
);
end KEY;
--*****************************************************************************
-- 3. Architectures (Body)
architecture beh of KEY is
	signal kb_col_in	     : std_logic;
	signal kb_valid		     : std_logic;
	signal kb_cnt		     : std_logic_vector(1 downto 0);
	signal diff_pp		     : std_logic;
	signal diff_np		     : std_logic;
	signal key_press	     : std_logic;
	shared variable temp_col : std_logic_vector(3 downto 0);
-------------------------------------------------------------------------------	
begin
	kb_col_in <= kb_col(3) and kb_col(2) and kb_col(1) and kb_col(0); -- active Low
--	kb_col_in <= kb_col(3)  or kb_col(2)  or kb_col(1)  or kb_col(0); -- active High
--*****************************************************************************	
-- 4x4 Keyboard Sampling and Differential Circuits
X1 : block
    signal q1,q0 : std_logic; -- Length = SW numbers
begin
    -----------------------------------------------------------------------
    -- (1). Flat Sampling Circuit
    process(clk,rst) -- Sensitivity List
    begin
        if(rst = '0')then -- Asynchronous Clear (Initializations)
            q1 <= '0';
            q0 <= '0';
        elsif(clk'event and clk = '1')then -- Positive-Edge Trigger (20nS)
            q1 <= q0;
            q0 <= kb_col_in; -- Sampling input signals write here!!
        end if;
    end process;
    -----------------------------------------------------------------------
    -- (2). Differential Circuits Pulse's Tw = 20nS
    diff_pp <= (not q1)and(    q0); -- Catch Positive Edge Pulse 
    diff_np <= (    q1)and(not q0); -- Catch Negative Edge Pulse 
end block X1;
--*****************************************************************************
-- Generating key_press signal and col_in Value Latch
X2:block
begin
    process(clk,rst) -- Sensitivity List
    begin
        if(rst = '0')then -- Asynchronous Clear (Initializations)
            key_press <= '1';
            temp_col  := (others => '0');
        elsif(clk'event and clk = '1')then -- Positive-Edge Trigger (20nS)
            if(diff_np = '1')then -- First : Pressed Key (active Low)
                key_press <= '1';
                temp_col  := kb_col; -- Latch Column Data
            elsif(diff_pp = '1')then -- Second : Released Key (active Low)
                key_press <= '0';
                temp_col  := (others => '0');
            end if;
        end if;
    end process;
end block X2;
--*****************************************************************************
-- FSM : Keyboard's Row Scanning and Key's Value Decision
X3:block
    type states is(s0,s1,s2,s3,s4,s5,s6);
    signal ps,ns,nns : states;
begin
    ---------------------------------------------------------------------------
    -- Two Processes Finite States Machine (FSM)
    ---------------------------------------------------------------------------
    -- 1. State Changing 
    process(clk,rst) -- Sensitivity List
    begin
        if(rst = '0')then -- Asynchronous Clear (Initializations)
            ps <= s0;
        elsif(clk'event and clk = '1')then -- Positive-Edge Trigger (20nS)
            ps <= ns;
        end if;
    end process;
    ---------------------------------------------------------------------------
    -- 2. Individual State Execution Sequences
    process(clk,rst) -- Sensitivity List
    begin
        if(rst = '0')then -- Asynchronous Clear (Initializations)
            kb_valid <= '0';
            kb_row   <= "1110";
            kb_cnt   <= "00";
            ns       <= s0;
        elsif(clk'event and clk = '0')then -- Negative-Edge Trigger (20nS)
            if(f_1kp = '1')then -- Sampling Rate = 1mS
                case ps is
                    when s0 => -- Horizontal 0
                        kb_row <= "1110"; -- 16,12,8,4
                        kb_cnt <= "00";
                        ns     <= s4; -- Judge Keys Pressed or not
                        nns    <= s1;
                    when s1 => -- Horizontal 1
                        kb_row <= "1101"; -- 15,11,7,3
                        kb_cnt <= "01";
                        ns     <= s4; -- Judge Keys Pressed or not
                        nns    <= s2;
                    when s2 => -- Horizontal 2
                        kb_row <= "1011"; -- 14,10,6,2
                        kb_cnt <= "10";
                        ns     <= s4; -- Judge Keys Pressed or not
                        nns    <= s3;
                    when s3=> -- Horizontal 3
                        kb_row <= "0111"; -- 13,9,5,1 
                        kb_cnt <= "11";
                        ns     <= s4; -- Judge Keys Pressed or not
                        nns    <= s0;
                    -----------------------------------------------------------
                    -- Judge Keys Pressed or not ??  
                    when s4=>
                        if(key_press = '1')then
                            if(temp_col(0) = '0')then -- Vertical 0
                                case kb_cnt is
                                    when "00" =>   kb_data <= 16; -- S16 
                                    when "01" =>   kb_data <= 11; -- S15
                                    when "10" =>   kb_data <= 15; -- S14
                                    when others => kb_data <= 13; -- S13
                                end case;
                            elsif(temp_col(1) = '0')then -- Vertical 1
                                case kb_cnt is
                                    when "00" =>   kb_data <= 16; -- S12
                                    when "01" =>   kb_data <= 3; -- S11
                                    when "10" =>   kb_data <= 2; -- S10
                                    when others => kb_data <= 1; -- S9
                                end case;
                            elsif(temp_col(2) = '0')then -- Vertical 2
                                case kb_cnt is
                                    when "00" =>   kb_data <= 10; -- S8
                                    when "01" =>   kb_data <= 6; -- S7
                                    when "10" =>   kb_data <= 5; -- S6
                                    when others => kb_data <= 4; -- S5
                                end case;
                            elsif(temp_col(3) = '0')then -- Vertical 3
                                case kb_cnt is
                                    when "00" =>   kb_data <= 0; -- S4
                                    when "01" =>   kb_data <= 9; -- S3
                                    when "10" =>   kb_data <= 8; -- S2
                                    when others => kb_data <= 7; -- S1
                                end case;
                            end if;
                            ns <= s5;
                        else -- key_press = '0' (all Keys : unpressed)
                            ns <= nns;
                        end if;
                    -----------------------------------------------------------
                    when s5=> -- Generate done_pulse
                        kb_valid <= '1';
                        ns       <= s6;
                    when s6=>
                        kb_valid <= '0';
                        if(key_press = '1')then -- Judge Keys Pressed or not
                            ns <= s6;
                        else
                            ns <= nns;
                        end if;
                end case;
            end if;
        end if;
    end process;
end block X3;
--*****************************************************************************
-- Differential Circuits (kb_done_p's Tw = 20ns)
X4:block
    signal q0,q1 : std_logic; -- Length = the numbers of SWs
begin
    -- 1. Sampling and Shift Register Circuits
    process(clk,rst) -- Sensitivity List
    begin
        if(rst = '0')then -- Asynchronous Clear (Initializations)
            q0 <= '0';
            q1 <= '0';
        elsif(clk'event and clk = '1')then -- Positive-Edge Trigger (20nS)
            q1 <= q0;
            q0 <= kb_valid; -- input signals write here!!
        end if;
    end process;
    -- 2. Differential Circuit(Tw = 20nS)
    kb_done_p <= (not q1)and(q0); -- Catch Positive-Edge Pulse
end block X4;
--*****************************************************************************	
end beh;