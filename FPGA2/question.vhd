-- 1. 庫聲明和包使用
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
--**********************************************************************************
-- 2. 實體聲明
entity question is
generic(fmax    : integer := 5E7;  -- 50MHz
		TXRD_buff_N:natural:=511;
		char    : integer := 20 ); -- 最大字符數量
port(-- 輸入信號
	clk			: in  std_logic; -- Pin = 149 , 50MHz
	rst_n		: in  std_logic; -- Pin = 145 , 低電位有效 (FPGA的全局重置)
	-- KEY 4x4 I/O 信號
	kb_col	: in  std_logic_vector(3 downto 0); -- 4 Bits
	kb_row	: out std_logic_vector(3 downto 0); -- 4 Bits
	--uart
	S_RESET_T,S_RESET_T2:buffer std_logic;
	RD,RD2:in std_logic;
	TX,TX2:out std_logic
	);
end question;
--**********************************************************************************
-- 3. 結構體（主體）
architecture PKE of question is
	-- (1) 主體內的組件聲明
	--------------------------------------------------------------------------------
	component KEY is
	port(-- 輸入信號
		clk	  		: in  std_logic; -- Pin = 149 , 50MHz
		rst	   	: in  std_logic; -- 低電位有效 (內部重置)
		f_1kp	   : in  std_logic; -- 1KHz 脈衝波
		kb_col	: in  std_logic_vector(3 downto 0); -- col_in   (低電位有效)
		-- 輸出信號
		kb_row 		: out std_logic_vector(3 downto 0); -- row scan (低電位有效)
		kb_data		: buffer integer range 0 to 16;
		kb_done_p	: out std_logic                   			  -- 脈衝 (Tw = 20ns)
		);
	end component;
	--------------------------------------------------------------------------------
	--RS232_T1
	component RS232_T4 is
	generic(TXRD_buff : natural:= TXRD_buff_N);
	port(clk,Reset:in std_logic;--clk:25MHz
		 DL:in std_logic_vector(1 downto 0);	 --00:5,01:6,10:7,11:8 Bit
		 ParityN:in std_logic_vector(2 downto 0);--000:None,100:Even,101:Odd,110:Space,111:Mark
		 StopN:in std_logic_vector(1 downto 0);	 --0x:1Bit,10:2Bit,11:1.5Bit
		 F_Set:in std_logic_vector(3 downto 0);	--BaudRate:000:1200,001:2400,010:4800,011:9600,100:19200,101:38400,110:57600,111:115200
		 Status_s:out std_logic_vector(1 downto 0);
		 TX_W:in std_logic;
		 TXData:in std_logic_vector(7 downto 0);
		 TX:out std_logic);
	end component;
	--RS232_R3
	component RS232_R4 is
	generic(TXRD_buff : natural:= TXRD_buff_N);
	port(Clk,Reset:in std_logic;--clk:25MHz
		 DL:in std_logic_vector(1 downto 0);	 --00:5,01:6,10:7,11:8 Bit
		 ParityN:in std_logic_vector(2 downto 0);--0xx:None,100:Even,101:Odd,110:Space,111:Mark
		 StopN:in std_logic_vector(1 downto 0);	 --0x:1Bit,10:2Bit,11:1.5Bit
		 F_Set:in std_logic_vector(3 downto 0);	--BaudRate:000:1200,001:2400,010:4800,011:9600,100:19200,101:38400,110:57600,111:115200
		 Status_s:out std_logic_vector(2 downto 0);
		 RX_BBN:buffer integer range 0 to TXRD_buff_N+1;--511;	--buffer 現有資料量--2024.03.30
		 Rx_R:in std_logic;
		 RD:in std_logic;
		 RxDs:out std_logic_vector(7 downto 0));
	end component;
	---1
	constant DL:std_logic_vector(1 downto 0):="11";	 	 --00:5,01:6,10:7,11:8 Bit
	constant ParityN:std_logic_vector(2 downto 0):="000";--0xx:None,100:Even,101:Odd,110:Space,111:Mark
	constant StopN:std_logic_vector(1 downto 0):="00";	 --0x>1Bit,10>2Bit,11>1.5Bit
	constant F_Set:std_logic_vector(3 downto 0):="1011";
	--BaudRate:0000:300,0001:600,0010:1200,0011:2400,0100:4800,0101:9600,0101:19200,0111:28800,
	--		   1000:38400,1001:57600,1010:76800,1011:115200,1100:230400,1101:460800,1110:576000,1111:921600

	
	--signal S_RESET_T:std_logic;						--Rs232 reset傳送
	signal TX_W:std_logic;							--寫入緩衝區
	signal Status_Ts:std_logic_vector(1 downto 0);	--傳送狀態
	signal TXData:std_logic_vector(7 downto 0);		--傳送資料
	
	signal S_RESET_R:std_logic;						--Rs232 reset接收
	signal Rx_R:std_logic;							--讀出緩衝區
	signal Status_Rs:std_logic_vector(2 downto 0);	--接收狀態
	signal RxDs:std_logic_vector(7 downto 0);		--接收資料
	---2
	constant DL2:std_logic_vector(1 downto 0):="11";	 	 --00:5,01:6,10:7,11:8 Bit
	constant ParityN2:std_logic_vector(2 downto 0):="000";--0xx:None,100:Even,101:Odd,110:Space,111:Mark
	constant StopN2:std_logic_vector(1 downto 0):="00";	 --0x>1Bit,10>2Bit,11>1.5Bit
	constant F_Set2:std_logic_vector(3 downto 0):="1011";
	--BaudRate:0000:300,0001:600,0010:1200,0011:2400,0100:4800,0101:9600,0101:19200,0111:28800,
	--		   1000:38400,1001:57600,1010:76800,1011:115200,1100:230400,1101:460800,1110:576000,1111:921600
	
	--signal S_RESET_T2:std_logic;						--Rs232 reset傳送
	signal TX_W2:std_logic;							--寫入緩衝區
	signal Status_Ts2:std_logic_vector(1 downto 0);	--傳送狀態
	signal TXData2:std_logic_vector(7 downto 0);		--傳送資料
	
	signal S_RESET_R2:std_logic;						--Rs232 reset接收
	signal Rx_R2:std_logic;							--讀出緩衝區
	signal Status_Rs2:std_logic_vector(2 downto 0);	--接收狀態
	signal RxDs2:std_logic_vector(7 downto 0);		--接收資料	
		
	--2024.03.30
	signal Rdatalength,Rdatalength2:integer range 0 to TXRD_buff_N+1;--511;	--buffer 現有資料量--2024.03.30
	type ESP8266com_T is array (0 to TXRD_buff_N) of std_logic_vector(7 Downto 0);
	signal FPGA_ESP8266,ESP8266_FPGA,FPGA_ESP82662,ESP8266_FPGA2:ESP8266com_T;
	type ESP8266com_T2 is array (0 to TXRD_buff_N) of integer range 0 to 255;
	signal ESP8266_FPGA_int,ESP8266_FPGA_int2:ESP8266com_T2;
	signal pre_item,pre_item2:std_logic_vector(7 downto 0);
	
	--指令
	signal instruction,instruction2:std_logic_vector(7 downto 0);
	signal CMDn,CMDn_R,CMDnS,CMDn_RS:integer range 0 to TXRD_buff_N;	--Rs232傳出數,接收數
	signal CMDn2,CMDn_R2,CMDnS2,CMDn_RS2:integer range 0 to TXRD_buff_N;	--Rs232傳出數,接收數
	signal ESP8266RESETtime:integer range 0 to 1000;
	signal ESP8266_POWER:std_logic:='0';	--經由L293D提供可控電源
	
	signal sys_uartFs:std_logic:='0';	--系統操作頻率選擇

	---------------------------------------------------
	--******************************************************************************
	-- (2) 全局信號：包括(a)和(b)
	-- (a) 控制組件信號
	-- KEY 信號用於KEY控制
	signal kb_data			  	: integer range 0 to 16;
	signal kb_done_p		  	: std_logic;
	--計時計數
	signal times:integer range 0 to 4095;
	signal times1,times2,times3,times4,sound_Times:integer range 0 to 511;
	signal S0on,Soundonoff:std_logic;
	--------------------------------------------------------------------------------
	-- (b) 區塊信號 
	-- 系統信號
	signal sw_trig					: std_logic; -- 高電位有效
	-- X1 : 頻率分頻器信號
	signal rst		     				: std_logic; -- 低電位有效 (內部)
	signal f_1s,f_1p	 			: std_logic; -- 用於SEG和LED閃爍
	signal f_2s,f_2p	 			: std_logic; 								-- 用於SEG和LED閃爍
	signal f_10s,f_10p	 	: std_logic; 								-- 用於DHT11自動啟動信號
	signal f_1ks,f_1kp	 		: std_logic; 								-- 用於KEY和SW去抖動
	signal f_50ks,f_50kp		: std_logic; 								--用於SD178B驅動CLK
	signal f_10ms,f_10Mp	: std_logic; 								-- 用於OLED驅動CLK
	-- X2 : SW去抖動信號
	signal diff_pp		 : std_logic_vector(7 downto 0); 	-- 長度 = SW數量
	signal diff_np		 : std_logic_vector(7 downto 0); 	-- 長度 = SW數量
--**********************************************************************************
begin
	-- 系統連接 :
	--------------------------------------------------------------------------------
	-- 1. 組件實例化
	U1 : KEY port map(clk,rst,f_1kp,kb_col,kb_row,kb_data,kb_done_p);
	--2024.03.30
UARTTx: RS232_T4 Port Map(clk,S_RESET_T,DL,ParityN,StopN,F_Set,Status_Ts,TX_W,TXData,TX);			--RS232傳送模組
UARTRx: RS232_R4 Port Map(clk,S_RESET_R,DL,ParityN,StopN,F_Set,Status_Rs,Rdatalength,Rx_R,RD,RxDs);--RS232接收模組

UARTTx2: RS232_T4 Port Map(clk,S_RESET_T2,DL2,ParityN2,StopN2,F_Set2,Status_Ts2,TX_W2,TXData2,TX2);			--RS232傳送模組
UARTRx2: RS232_R4 Port Map(clk,S_RESET_R2,DL2,ParityN2,StopN2,F_Set2,Status_Rs2,Rdatalength2,Rx_R2,RD2,RxDs2);--RS232接收模組	
--2024.03.30
--FPGA上傳RS232
	TXData<=FPGA_ESP8266(CMDnS-CMDn);--上傳資料1byte
	--x2
	TXData2<=FPGA_ESP82662(CMDnS2-CMDn2);--上傳資料1byte

--	--------------------------------------------------------------------------------
	-- 2. SW變更觸發
	sw_trig <= diff_pp(1) or diff_np(1) or diff_pp(0) or diff_np(0); -- Tw = 20ns
--**********************************************************************************
-- X1 : 頻率分頻器
x1 : block
	signal cnt0         			  : std_logic_vector(25 downto 0); -- 26 Bits
	signal cnt1,cnt2,cnt3 : std_logic_vector(25 downto 0); -- 26 Bits
	signal cnt4,cnt5,cnt6 : std_logic_vector(25 downto 0); -- 26 Bits
------------------------------------------------------------------------------------	
begin
	process(clk, rst_n) -- 敏感度列表
	begin
		if(rst_n = '0')then -- 異步重置 (初始化)
			cnt0 <= (others => '0');
			cnt1 <= (others => '0');
			cnt2 <= (others => '0');
			cnt3 <= (others => '0');
			cnt4 <= (others => '0');
			cnt5 <= (others => '0');
			cnt6 <= (others => '0');
			rst  <= '0'; -- 內部重置 (軟件)
		elsif(clk'event and clk = '1')then -- 正緣觸發 (20ns)
		----------------------------------------------------------------------------
		-- 1. 上電：自動重置信號 (100ms)
			if(cnt0 < fmax / 10 - 1)then -- 分母=輸出頻率
				cnt0 <= cnt0 + 1;
				rst  <= '0';     -- 內部軟重置信號(低電位有效)
			else
				rst <= '1';
			end if;
		-- 2. 1Hz脈衝，用於LED閃爍-----------------------------------------
			if(cnt1 < fmax / 2 - 1)then    -- 用於半周期 : 輸出低態
				f_1s <= '0';
				f_1p <= '0';
				cnt1 <= cnt1 + 1;
			elsif(cnt1 < fmax / 1 - 1)then -- 分母 : 輸出頻率
				f_1s <= '1';               -- 用於半周期 : 輸出高態
				f_1p <= '0';
				cnt1 <= cnt1 + 1;
			else
				f_1s <= '0';
				f_1p <= '1';
				cnt1 <= (others => '0');
			end if;
		-- 3. 2Hz脈衝，用於LED閃爍 -----------------------------------------
			if(cnt2 < fmax / 4 - 1)then    -- 用於半周期 : 輸出低態
				f_2s <= '0';
				f_2p <= '0';
				cnt2 <= cnt2 + 1;
			elsif(cnt2 < fmax / 2 - 1)then -- 分母 : 輸出頻率
				f_2s <= '1';               -- 用於半周期 : 輸出高態
				f_2p <= '0';
				cnt2 <= cnt2 + 1;
			else
				f_2s <= '0';
				f_2p <= '1';
				cnt2 <= (others => '0');
			end if;
		-- 4. 10Hz脈衝，用於DHT11啟動 ----------------------------------------
			if(cnt3 < fmax / 20 - 1)then    -- 用於半周期 : 輸出低態
				f_10s <= '0';
				f_10p <= '0';
				cnt3  <= cnt3 + 1;
			elsif(cnt3 < fmax / 10 - 1)then -- 分母 : 輸出頻率
				f_10s <= '1';               -- 用於半周期 : 輸出高態
				f_10p <= '0';
				cnt3  <= cnt3 + 1;
			else
				f_10s <= '0';
				f_10p <= '1';
				cnt3  <= (others => '0');
			end if;
		-- 5. 1KHz脈衝，用於KEY和SW去抖動 ----------------------------
			if(cnt4 < fmax / 2E3 - 1)then    -- 用於半周期 : 輸出低態
				f_1ks <= '0';
				f_1kp <= '0';
				cnt4  <= cnt4 + 1;
			elsif(cnt4 < fmax / 1E3 - 1)then -- 分母 : 輸出頻率
				f_1ks <= '1';                -- 用於半周期 : 輸出高態
				f_1kp <= '0';
				cnt4  <= cnt4 + 1;
			else
				f_1ks <= '0';
				f_1kp <= '1';
				cnt4  <= (others => '0');
			end if;
		-- 6. 50kHz脈衝用於SD178B設備CLK ---------------------------------
			if(cnt5 < fmax / 10E4 - 1)then   -- 用於半周期 : 輸出低態
				f_50ks <= '0';
				f_50kp <= '0';
				cnt5   <= cnt5 + 1;
			elsif(cnt5 < fmax / 5E4 - 1)then -- 分母 : 輸出頻率
				f_50ks <= '1';               -- 用於半周期 : 輸出高態
				f_50kp <= '0';
				cnt5   <= cnt5 + 1;
			else
				f_50ks <= '0';
				f_50kp <= '1';
				cnt5   <= (others => '0');
			end if;
		-- 7. 10MHz脈衝用於OLED設備CLK----------------------------------
			if(cnt6 < fmax / 20E6 - 1)then    -- 用於半周期 : 輸出低態
				f_10ms <= '0';
				f_10Mp <= '0';
				cnt6   <= cnt6 + 1;
			elsif(cnt6 < fmax / 10E6 - 1)then -- 分母 : 輸出頻率
				f_10ms <= '1';                -- 用於半周期 : 輸出高態
				f_10Mp <= '0';
				cnt6   <= cnt6 + 1;
			else
				f_10ms <= '0';
				f_10Mp <= '1';
				cnt6   <= (others => '0');
			end if;
		----------------------------------------------------------------------------
		end if;
	end process;
end block x1;

--**********************************************************************************
--- X2 : SW去抖動
x2 : block
	signal q0,q1	: std_logic_vector(7 downto 0); -- 長度 = SW數量
	signal q2,q3	: std_logic_vector(7 downto 0); -- 長度 = SW數量
	signal flat		: std_logic_vector(7 downto 0); -- 長度 = SW數量
------------------------------------------------------------------------------------
begin
	-- 1. 平滑取樣電路 ---------------------------------------------------
	process(clk,rst) -- 敏感度列表 
	begin
		if(rst = '0')then -- 初始化 (異步重置)
			q0   <= (others => '0');
			q1   <= (others => '0');
			flat <= (others => '0');
		elsif(clk'event and clk = '1')then -- 正緣觸發 (20ns)
			if(f_1kp = '1')then -- 取樣速率 = 1ms
				q1   <= q0;
				flat <= ((q0 or q1) and flat) or (q0 and q1); -- SR-FF
			end if;
		end if;
	end process;
	-- 2. 移位寄存器電路 --------------------------------------------------
	process(clk,rst) -- 敏感度列表 
	begin
		if(rst = '0')then -- 初始化 (異步重置)
			q3 <= (others => '0');
			q2 <= (others => '0');
		elsif(clk'event and clk = '1')then -- 正緣觸發 (20ns)
			q3 <= q2;
			q2 <= flat; -- 在此處寫入差分輸入信號!!
		end if;
	end process;
	-- 3. 差分電路 (脈衝的Tw = 20ns) --------------------------------
	diff_pp <= (not q3)and(    q2); -- 捕獲正邊脈衝 
	diff_np <= (    q3)and(not q2); -- 捕獲負邊脈衝
end block x2;
--**********************************************************************************
-- X3 : 主控制邏輯電路 (KEY和SW)
x3 : block
	type   states  is (s0,s1,s2,s3,s4,s5,s6,s7,s8,s9,s10);
	signal ps,ns    : states;
	signal cnt      : std_logic_vector(7 downto 0);
	signal cnt1     : std_logic_vector(1 downto 0);
------------------------------------------------------------------------------------
begin
	--------------------------------------------------------------------------------
	-- FSM (兩過程有限狀態機)
	--------------------------------------------------------------------------------
	-- (1) 狀態改變
	process(clk,rst) -- 敏感度列表
	begin
		if(rst = '0')then -- 初始化 (異步重置)
			ps <= s0;
		elsif(clk'event and clk= '1')then -- 正緣觸發 (20ns)
			ps <= ns;
		end if;
	end process;
	--------------------------------------------------------------------------------
	--(2) 個別狀態執行序列
	process(clk,rst) -- 敏感度列表 
	variable k:integer range 0 to 31;
	begin
		if(rst = '0')then -- 初始化 (SW變更) (異步重置)
		k:=16;						--無效鍵值
		S_RESET_T<='0';			--關閉RS232傳送
		S_RESET_R<='0';			--關閉RS232接
		Rx_R<='0';				--取消讀取信號
		TX_W<='0';				--取消資料載入信號
		CMDn_R<=0;				--接收數量(2 byte)
		CMDn_RS<=0;				--接收緩衝區偏移量
		CMDn<=0;				--上傳數量(0 byte)
		CMDnS<=0;				--上傳緩衝區偏移量
		--x2
		S_RESET_T2<='0';		--關閉RS232傳送
		S_RESET_R2<='0';		--關閉RS232接收
		Rx_R2<='0';				--取消讀取信號
		TX_W2<='0';				--取消資料載入信號
		CMDn_R2<=0;				--接收數量(2 byte)
		CMDn_RS2<=0;			--接收緩衝區偏移量
		CMDn2<=0;				--上傳數量(0 byte)
		CMDnS2<=0;				--上傳緩衝區偏移量

		ESP8266RESETtime<=600;--800		
		ESP8266_POWER<='0';	--經由L293D提供可控電源給ESP8266:off:L293D_1A=0=>1Y=0V
		sys_uartFs<='0';	--select sys f
	elsif (Rx_R='1' and Status_Rs(2)='0') then	--rs232接收即時處理
		Rx_R<='0';
	elsif (Rx_R2='1' and Status_Rs2(2)='0') then--rs232接收即時處理
		Rx_R2<='0';
	elsif(clk'event and clk = '0')then -- 負緣觸發 (20ns)
		------------------------------------------------------------------------
		-- 優先檢查 (每20ns一次)
		------------------------------------------------------------------------
		-- 1. 模式鎖存
		if(sw_trig = '1')then
			ns         <= s0;
		elsif k/=16 then
			k:=16;
		-- 2. 檢查KEY是否按下
		elsif(kb_done_p = '1')then
			k:=kb_data;
		end if;
		--UART x1 x2===============================================
		if ESP8266RESETtime=0 then
			S_RESET_T<='1';			--RS232傳送 ON
			S_RESET_R<='1';			--RS232接收 ON
			S_RESET_T2<='1';		--RS232傳送 OFF
			S_RESET_R2<='1';		--RS232接收 OFF
		else
			ESP8266RESETtime<=ESP8266RESETtime-1;
			if ESP8266RESETtime=300 then
				ESP8266_POWER<='1';		--經由L293D提供可控電源給ESP8266:on:L293D_1A=1=>1Y=?V
			end if;
		end if;
		--UART: x1 x2 全雙工
		if (S_RESET_T='1'and CMDn>0)or(S_RESET_T2='1'and CMDn2>0)
		or(S_RESET_R='1'and Status_Rs(2)='1'and CMDn_R>0)or(S_RESET_R2='1'and Status_Rs2(2)='1'and CMDn_R2>0) then
			sys_uartFs<='1';	--select uart f
			--x1
			if S_RESET_T='1'and CMDn>0 and TX_W='0'then--上傳剩餘數量
				if Status_Ts(1)='0' then--傳送緩衝區已空
					TX_W<='1';	--傳送資料載入
				end if;
			elsif TX_W='1'and Status_Ts(1)='1' then
				TX_W<='0';			--取消傳送資料載入時脈
				CMDn<=CMDn-1;		--指標指向下一筆資料
			end if;
			--x2
			if S_RESET_T2='1'and CMDn2>0 and TX_W2='0'then--上傳剩餘數量
				if Status_Ts2(1)='0'then--傳送緩衝區已空
					TX_W2<='1';	--傳送資料載入
				end if;
			elsif TX_W2='1'and Status_Ts2(1)='1' then
				TX_W2<='0';			--取消傳送資料載入時脈
				CMDn2<=CMDn2-1;		--指標指向下一筆資料
			end if;
			-----------------------
				--x1
			if S_RESET_R='1'and Status_Rs(2)='1'and Rx_R='0'and CMDn_R>0 then
				Rx_R<='1';					--讀取信號
				if CMDn_RS=511 then	--第一筆為實際數量
					CMDn_R<=conv_integer(RxDs);
					CMDn_RS<=conv_integer(RxDs);
				else
					CMDn_R<=CMDn_R-1;			--筆數減1
					ESP8266_FPGA(CMDn_RS-CMDn_R)<=RxDs;	--存入接收緩衝區
					ESP8266_FPGA_int(CMDn_RS-CMDn_R)<=conv_integer(RxDs);	--存入接收緩衝區
					--如傳輸資料中有未使用的碼時，此時可當作結束碼，如"X"FF"
					if CMDn_RS=510 and RxDs=X"FF" then
						CMDn_R<=0;--結束接收
						CMDn_RS<=CMDn_RS-CMDn_R;--本次接收數
					end if;
					--如傳輸資料中有未使用的2碼時，此時可當作結束碼，如 X"FE" & X"FF"
					pre_item<=RxDs;--前一項
					if CMDn_RS=509 and CMDn_RS/=CMDn_R then
						if pre_item=X"FE" and RxDs=X"FF" then
							CMDn_R<=0;--結束接收
							CMDn_RS<=CMDn_RS-CMDn_R-1;--本次接收數
						end if;
					end if;
				end if;
			end if;
			--x2
			if S_RESET_R2='1'and Status_Rs2(2)='1'and Rx_R2='0'and CMDn_R2>0 then
				Rx_R2<='1';					--讀取信號
				if CMDn_RS2=511 then	--第一筆為實際數量
					CMDn_R2<=conv_integer(RxDs2);
					CMDn_RS2<=conv_integer(RxDs2);
				else
					CMDn_R2<=CMDn_R2-1;			--筆數減1
					ESP8266_FPGA2(CMDn_RS2-CMDn_R2)<=RxDs2;	--存入接收緩衝區
					ESP8266_FPGA_int2(CMDn_RS2-CMDn_R2)<=conv_integer(RxDs2);	--存入接收緩衝區
					--如傳輸資料中有未使用的碼時，此時可當作結束碼，如X"FF"
					if CMDn_RS2=510 and RxDs2=X"FF" then
						CMDn_R2<=0;--結束接收
						CMDn_RS2<=CMDn_RS2-CMDn_R2;--本次接收數
					end if;
					--如傳輸資料中有未使用的2碼時，此時可當作結束碼，如X"FE" & "X"FF"
					pre_item2<=RxDs2;--前一項
					if CMDn_RS2=509 and CMDn_RS2/=CMDn_R2 then
						if pre_item2=X"FE" and RxDs2=X"FF" then
							CMDn_R2<=0;--結束接收
							CMDn_RS2<=CMDn_RS2-CMDn_R2-1;--本次接收數
						end if;
					end if;
				end if;
			end if;
--------------------------------------------------------
		else
			sys_uartFs<='0';	--select sys f
			CMDnS<=1;	--蹌西肅喳
			FPGA_ESP8266(0)<=conv_std_logic_vector(k,8);--key
			S_RESET_R<='1';			--RS232接收 OFF
			case k is
				--====================================================
				when 0 =>--s1
					CMDn<=1;	--上傳數量(1 byte)

				when 1 =>--s2
					CMDn<=1;	--上傳數量(1 byte)

				when 2 =>--s3
					CMDn<=1;	--上傳數量(1 byte)

				when 3 =>--s4
					CMDn<=1;	--上傳數量(1 byte)
				
				when 4 =>--s5
					CMDn<=1;	--上傳數量(1 byte)

				when 5 =>--s6
					CMDn<=1;	--上傳數量(1 byte)

				when 6 =>--s7
					CMDn<=1;	--上傳數量(1 byte)

				when 7 =>--s8
					CMDn<=1;	--上傳數量(1 byte)
					
				when 8 =>--s9
					CMDn<=1;	--上傳數量(1 byte)

				when 9 =>--s10
					CMDn<=1;	--上傳數量(1 byte)

				when 10 =>--s11
					CMDn<=1;	--上傳數量(1 byte)

				when 11 =>--s12
					CMDn<=1;	--上傳數量(1 byte)
					
				when 12 =>--s13
					CMDn<=1;	--上傳數量(1 byte)

				when 13 =>--s14
					CMDn<=1;	--上傳數量(1 byte)

				when 14 =>--s15
					CMDn<=1;	--上傳數量(1 byte)

				when 15 =>--s16
					CMDn<=1;	--上傳數量(1 byte)

				when others =>
					null;
			end case;
		end if;
	end if;
	end process;
end block x3;
end PKE;