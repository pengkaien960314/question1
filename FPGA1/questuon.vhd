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
	-- SEG 輸出信號
	seg_scan	: out std_logic_vector(7 downto 0); -- 8 Bits , 低電位有效
	seg_out		: out std_logic_vector(7 downto 0); -- 8 Bits , 高電位有效
	-- SW 輸入信號 
	dip_sw	: in  std_logic_vector(7 downto 0); -- 8 Bits , 高電位有效
	-- KEY 4x4 I/O 信號
	kb_col	: in  std_logic_vector(3 downto 0); -- 4 Bits
	kb_row	: out std_logic_vector(3 downto 0); -- 4 Bits
	-- LED 輸出信號
	led_r		: out std_logic; -- 高電位有效
	led_g		: out std_logic; -- 高電位有效
	led_y		: out std_logic; -- 高電位有效
	-- BUZZER 輸出信號
	BUZZER_out	: out std_logic; -- 高電位有效
	-- SD178B I/O 信號
	rst_sd_n: out   std_logic; -- 低電位有效
	scl			: out   std_logic; -- I2C : 串行時鐘 (雙向)
	sda		: inout std_logic; -- I2C : 串行數據  (雙向)
	-- OLED I/O 信號
	BL_tft	: out std_logic; -- 高電位有效
	rst_tft	: out std_logic; -- 低電位有效
	cs_spi	: out std_logic; -- SPI : 低電位有效 , NET , PET
	dc_spi	: out std_logic; -- SPI : 0 : 命令 ; 1 : 數據
	scl_spi	: out std_logic; -- SPI : 時鐘
	sda_spi	: out std_logic;  -- SPI : 數據線
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
	component SEGMENT is
	port(-- 輸入信號
		clk		 		: in  std_logic; -- Pin = 149 , 50MHz
		rst		 		: in  std_logic; -- 低電位有效 (內部重置)
		scan_p	   : in  std_logic; -- 1KHz 脈衝波 , Tw = 20ns
		clk_flash  	: in  std_logic; -- 1Hz  方波        
		bin_in	     	: in  std_logic_vector(47 downto 0); -- 8 位數字 (6 Bits/數字)
		digit_blink 	: in  std_logic_vector( 7 downto 0); -- 1 : 閃爍 , 0 : 正常
		dot_on	   : in  std_logic_vector( 7 downto 0); -- 1 : 開 , 0 : 關
		dot_blink	: in  std_logic_vector( 7 downto 0); -- 1 : 閃爍 , 0 : 正常
		-- 輸出信號
		SEG_scan  : out std_logic_vector( 7 downto 0); -- 低電位有效
		seg_out	 	: out std_logic_vector( 7 downto 0)  -- 高電位有效
		);
	end component;
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
	component sd178b is
	port(-- 輸入信號
		clk	   		: in  std_logic; -- Pin = 149 , 50MHz
		rst	   		: in  std_logic; -- 低電位有效 (內部重置)
		sd178b_p : in  std_logic; -- 50KHz~60KHz 脈衝波
		start_p   	: in  std_logic; -- 啟動信號 , Tw = 20ns
		address   	: in  std_logic_vector( 6 downto 0); -- 7 Bits
		rw		   	: in  std_logic; -- 1 : 讀    , 0 : 寫
		cmd_da	   : in  std_logic; -- 0 : 命令 , 1 : Data
		cmd_char : in  std_logic_vector( 7 downto 0); -- 0 : 命令 Code , 1 : Char_cnt
		data_in   	: in  std_logic_vector((char * 16) - 1 downto 0); -- FPGA -> I2C 設備
		-- 輸出信號
		rst_sd_n 	: out std_logic;
		data_out 	: out std_logic_vector( 7 downto 0); -- I2C 設備 -> FPGA
		read_out 	: out std_logic_vector(63 downto 0); -- I2C 設備 -> FPGA
		bf_out		: out std_logic; -- 1 : 組件忙. ; 0 : 就緒
		rd_done_p: out std_logic; 
		-- I2C I/O 信號
		scl	  	: out   std_logic; -- I2C : 串行時鐘 (雙向)
		sda	: inout std_logic  -- I2C : 串行數據  (雙向)
		);
	end component;
	--------------------------------------------------------------------------------
	component OLED is
	port(-- 輸入信號
		clk				: in  std_logic; -- Pin = 149 , 50MHz
		rst				: in  std_logic; -- 低電位有效 (內部重置)
		tft_lcd_p  	: in  std_logic; -- 10MHz 脈衝波
		start_p    	: in  std_logic; -- 啟動信號 , Tw = 20ns
		rgb_code  : in  integer range 0 to 10;
		word_code: in  integer range 0 to 10;
		rgb_color 	: in  std_logic_vector(15 downto 0); -- RGB : 5-6-5 -> 16 Bits
		word_color: in  std_logic_vector(15 downto 0);
		data_in    	: in  integer range 0 to  84; -- 位數字 (BCD碼)
		row_addr	: in  integer range 0 to 159; -- 0 ~ 160
		row_range: in  integer range 1 to 160;
		col_addr   : in  integer range 0 to 127; -- 0 ~ 127
		col_range 	: in  integer range 1 to 128;
		font_sel   	: in  integer range 0 to  10; -- 0 : 160x128,3 : 16x12,8 : 形狀
		-- 輸出信號
		bf_out     : out  std_logic; -- 1 : 組件忙. ; 0 : 就緒
		-- OLED I/O 信號
		BL_tft   : out std_logic; -- 高電位有效
		rst_tft   : out std_logic; -- 低電位有效
		cs        : out std_logic; -- SPI : 低電位有效 , NET , PET
		dc        : out std_logic; -- SPI : 0 : 命令 ; 1 : 數據
		scl        : out std_logic; -- SPI : 時鐘
		sda 		: out std_logic  -- SPI : 數據線
		);
	end component;
	--------------------------------------------------------------------------------
	component BIN2BCD_8 is
	port( -- 輸入信號
		clk		 		: in  std_logic; -- Pin = 149 , 50MHz
		rst		 		: in  std_logic; -- 低電位有效 (內部重置)
		start_pulse: in  std_logic; -- 啟動信號 , Tw = 20ns
		bin_in		 	: in  std_logic_vector(7 downto 0);
		-- 輸出信號
		bcd_out	 		: out std_logic_vector(11 downto 0);
		done_pulse	: out std_logic -- 脈衝 (Tw = 20ns)
		);
	end component;
	--------------------------------------------------------------------------------
	component BUZZER is 
	port(-- 輸入信號 
		clk					: in  std_logic; -- Pin = 149 , 50MHz 
		rst					: in  std_logic; -- 低電位有效 (內部重置)
		clk_1ks			: in  std_logic; -- 1KHz 方波
		BUZZER_en	: in  std_logic; -- 開關使能信號由SW控制
		BUZZER_in  	: in  std_logic; -- 觸發輸入信號（0.2秒） 
		-- 輸出信號
		BUZZER_out	: out std_logic  -- 連接到BJT的基極端
		);
	end component;
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
	-- SEG 信號，用於SEG 控制
	signal SEG_data			: std_logic_vector(47 downto 0); -- 8 位數字
	signal SEG_dot			  	: std_logic_vector( 7 downto 0);
	signal SEG_flash		 	: std_logic_vector( 7 downto 0);
	-- KEY 信號用於KEY控制
	signal kb_data			  	: integer range 0 to 16;
	signal kb_done_p		  	: std_logic;
	-- SD178B 信號
	signal sd_start_p		: std_logic;
	signal sd_rw			  	: std_logic; -- 1 : 讀    , 0 : 寫
	signal sd_cmd_da		: std_logic; -- 0 : 命令 , 1 : 數據
	signal sd_cmd_char	: std_logic_vector( 7 downto 0); -- 0 : 命令碼 , 1 : 字符計數
	signal sd_data_in		: std_logic_vector((char * 16) - 1 downto 0); -- FPGA -> I2C 設備
	signal sd_data_out	: std_logic_vector( 7 downto 0); -- I2C 設備 -> FPGA
	signal sd_read_out	: std_logic_vector(63 downto 0); -- I2C 設備 -> FPGA
	signal sd_bf_out		: std_logic;
	signal sd_rd_done_p	: std_logic;	
	-- OLED 信號
	signal tft_start_p		: std_logic;
	signal tft_rgb_code	: integer range 0 to 10;
	signal tft_word_code: integer range 0 to 15;
	signal tft_rgb_color	: std_logic_vector(15 downto 0); -- RGB : 5-6-5 -> 16 Bits
	signal tft_word_color	: std_logic_vector(15 downto 0);
	signal tft_data_in		: integer range 0 to 84;         -- 位數字 (BCD 碼)
	signal tft_row_addr	: integer range 0 to 159;        -- 0 ~ 160
	signal tft_row_range	: integer range 1 to 160;
	signal tft_col_addr		: integer range 0 to 127;        -- 0 ~ 127
	signal tft_col_range	: integer range 1 to 128;
	signal tft_font_sel		: integer range 0 to 10;         -- 0 : 32x32 , 1 : 16x16 , 2 : 圖片
	signal tft_bf_out		: std_logic;
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
	-- X3 : 主控制邏輯電路信號
	signal mode				: std_logic_vector(1 downto 0); -- 系統模式: 0 ~ 3
	signal flag_sys 	 		: integer range 0 to 20;         		-- 系統標誌
	signal shape_sel		: std_logic; 									-- 0: 倒三角形, 1: 正方形
	signal shape	     		: std_logic; 										-- 0: 倒三角形, 1: 正方形
	signal moving_step	: integer range 0 to 16;
	signal mov_step   	: integer range 0 to 16;
	signal X3_X5_startup: std_logic; -- 用於X3 Block , X3 發送to X5
	-- X4 : SEG顯示信號
	signal x					: std_logic_vector( 7 downto 0); -- 設置數據
	signal y			 		: std_logic_vector( 7 downto 0); -- 設置數據
	signal x_pos			: std_logic_vector( 7 downto 0); -- 設置數據
	signal y_pos			: std_logic_vector( 7 downto 0); -- 設置數據
	signal x_bcd			: std_logic_vector(11 downto 0);
	signal y_bcd			: std_logic_vector(11 downto 0);
	signal bkgnd_set	: std_logic_vector( 1 downto 0); -- 設置數據
	signal bkgnd			: std_logic_vector( 1 downto 0); -- 設置數據
	-- X5 : OLED顯示信號
	shared variable i	: integer range 0 to 160; -- X
	shared variable j	: integer range 0 to 128; -- Y
	shared variable n	: integer range 0 to 32; 
	shared variable m: integer range 0 to 32; 
	signal flag_start		: integer range 0 to 1;        	-- 旋轉標誌
	signal flag_check	: integer range 0 to 2;        	-- 旋轉標誌
--**********************************************************************************
begin
	-- 系統連接 :
	--------------------------------------------------------------------------------
	-- 1. 組件實例化
	U1 : SEGMENT		  port map(clk,rst,f_1kp,f_1s,SEG_data,SEG_flash,SEG_dot,
							   x"00",seg_scan,seg_out);

	U2 : KEY port map(clk,rst,f_1kp,kb_col,kb_row,kb_data,kb_done_p);

	U3 : sd178b 	  port map(clk,rst,f_50kp,sd_start_p,"0100000",sd_rw,
							   sd_cmd_da,sd_cmd_char,sd_data_in,rst_sd_n,
							   sd_data_out,sd_read_out,sd_bf_out,sd_rd_done_p,
							   scl,sda);
 
	U4 : OLED		  port map(clk,rst,f_10Mp,tft_start_p,tft_rgb_code, 
							   tft_word_code,tft_rgb_color,tft_word_color,
							   tft_data_in,tft_row_addr,tft_row_range, 
							   tft_col_addr,tft_col_range,tft_font_sel,tft_bf_out,
							   BL_tft,rst_tft,cs_spi,dc_spi,scl_spi,sda_spi);
	--2024.03.30
UARTTx: RS232_T4 Port Map(clk,S_RESET_T,DL,ParityN,StopN,F_Set,Status_Ts,TX_W,TXData,TX);			--RS232喲芋蝯
UARTRx: RS232_R4 Port Map(clk,S_RESET_R,DL,ParityN,StopN,F_Set,Status_Rs,Rdatalength,Rx_R,RD,RxDs);--RS232交璅∠

UARTTx2: RS232_T4 Port Map(clk,S_RESET_T2,DL2,ParityN2,StopN2,F_Set2,Status_Ts2,TX_W2,TXData2,TX2);			--RS232喲芋蝯
UARTRx2: RS232_R4 Port Map(clk,S_RESET_R2,DL2,ParityN2,StopN2,F_Set2,Status_Rs2,Rdatalength2,Rx_R2,RD2,RxDs2);--RS232交璅∠	
--2024.03.30
--FPGA銝RS232
	TXData<=FPGA_ESP8266(CMDnS-CMDn);--銝鞈1byte
	--x2
	TXData2<=FPGA_ESP82662(CMDnS2-CMDn2);--銝鞈1byte
--	--------------------------------------------------------------------------------
	-- 2. SW霈閫貊
	sw_trig <= diff_pp(1) or diff_np(1) or diff_pp(0) or diff_np(0); -- Tw = 20ns
--**********************************************************************************
-- X1 : 頻率分頻器
x1 : block
	signal cnt0           : std_logic_vector(25 downto 0); -- 26 Bits
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
-- X2 : SW去抖動
x2 : block
	signal q0,q1	: std_logic_vector(7 downto 0); -- 長度 = SW數量
	signal q2,q3	: std_logic_vector(7 downto 0); -- 長度 = SW數量
	signal flat		: std_logic_vector(7 downto 0); -- 長度 = SW數量
------------------------------------------------------------------------------------
begin
	-- 1. 平滑取樣電路 ---------------------------------------------------
	process(clk,rst) -- 初始化 (異步重置)
	begin
		if(rst = '0')then -- (唳郊蔭)
			q0   <= (others => '0');
			q1   <= (others => '0');
			flat <= (others => '0');
		elsif(clk'event and clk = '1')then -- 正緣觸發 (20ns)
			if(f_1kp = '1')then -- 取樣速率 = 1ms
				q1   <= q0;
				q0   <= dip_sw; --在此處取樣輸入信號!!
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
		elsif(clk'event and clk = '1')then --  正緣觸發 (20ns)
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
	signal flag_rotate		: std_logic;        	-- 旋轉標誌
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
		if(rst = '0')then -- (SW霈) (唳郊蔭)
		mode <= dip_sw(1 downto 0);
		k := 16;						--無效鍵值
		S_RESET_T<='0';			--關閉RS232傳送
		S_RESET_R<='0';			--關閉RS232接收
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
		
		ESP8266RESETtime<= 400;--400		
		ESP8266_POWER<='0';	--經由L293D提供可控電源給ESP8266:off:L293D_1A=0=>1Y=0V
		sys_uartFs<='0';	--select sys f
		
		flag_sys <= 0;
		flag_rotate	<= '0';
		flag_start <= 0;
		x           <= X"01"; -- x =001
		x_pos       <= X"01"; -- x =001
		y           <= X"01"; -- y =001           
		y_pos       <= X"01"; -- y =001
		moving_step <= 8;    -- 移動步數
		mov_step    <= 8;    -- 移動步數
		shape_sel   <= '0';  -- 倒三角形物體
		shape       <= '0';  -- 倒三角形物體
		bkgnd_set   <= "00"; -- OLED的背景色 = 白色
		bkgnd       <= "00"; -- OLED的背景色 = 白色
		ns          <= s0;
		led_r <= '0';
		led_g <= '0';
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
			mode       <= dip_sw(1 downto 0);
			flag_sys   <= 0; -- 模式初始化
			ns         <= s0;
		-- 2. 檢查KEY是否按下
		elsif(kb_done_p = '1')then
			k := kb_data;
		end if;
		--UART x1 x2===============================================
		if ESP8266RESETtime=0 then
			S_RESET_T<='0';			--RS232傳送 OFF
			S_RESET_R<='0';			--RS232接收 OFF
			S_RESET_T2<='0';		--RS232傳送 OFF
			S_RESET_R2<='0';		--RS232接收 OFF
		else
			ESP8266RESETtime<=ESP8266RESETtime-1;
			if ESP8266RESETtime=500 then
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
			--UART-----------------------------------------
			CMDn_R<=0;	--接收數量(1 byte)
			CMDn_RS<=0;	--接收緩衝區偏移量
			CMDn_R2<=0;	--接收數量(1 byte)
			CMDn_RS2<=0;--接收緩衝區偏移量
				S_RESET_R<='1';	--RS232接收 ON
				if(k = 1)then    --  檢查 S1 : 開始
					flag_sys   <= 1; -- 進入
				elsif(flag_start  =  0 and k = 2)then --  檢查 S1 : 開始
					flag_sys <= 2;
					flag_start <= 1;
				elsif(flag_rotate = '0' and k = 5)then	--  檢查 S5 : 旋轉
					flag_rotate <= '1'; -- 長方形
					flag_sys <= 3;
				elsif(flag_rotate = '1' and k = 5)then	--   檢查 S5 : 旋轉
					flag_rotate <= '0'; -- 寬方形
					flag_sys <= 4;
				elsif(k = 6)then --  檢查 S6 : 
					flag_sys <= 5;
				else
					flag_sys <= 0;
					if CMDn_R=0 then--接收完成
						CMDn_R<=1;	--接收數量(1 byte)
						CMDn_RS<=1;	--接收緩衝區偏移量
						if ESP8266_FPGA_int(0) = 10 then --檢查 S11 : 上
							flag_sys <= 10;
							led_r <= '1';
						elsif ESP8266_FPGA_int(0) = 11 then --檢查 S12 : 下
							flag_sys <= 11;
							led_r <= '0';
						elsif ESP8266_FPGA_int(0) = 14 then --檢查 S15 : 左
							flag_sys <= 14;
							led_g <= '1';
						elsif ESP8266_FPGA_int(0) = 15 then --檢查 S16 : 右
							flag_sys <= 15;
							led_g <= '0';
						end if;
					end if;
				end if;
			------------------------------------------------------------------------
			-- 4. X3啟動X5觸發信號 (20ns)
			------------------------------------------------------------------------
			if(flag_sys /= 0)then 
			--====== 模式00: OLED演示 ==============================--
				if(mode = "00" and flag_sys = 1)then -- 20ns
					case ps is
						when s0 =>
							X3_X5_startup<= '0';
							ns            <= S1;
						when s1 =>
							X3_X5_startup<= '1';
							ns            <= S2;
						when s2 =>
							X3_X5_startup<= '0';
							ns            <= S3;
						when others =>
					end case;
				--====== 模式01 : SEG ===========================================--
				elsif(mode = "01" and flag_sys = 1)then -- 20ns
					case ps is
						when s0 =>
							X3_X5_startup<= '0';
							ns            <= S1;
						when s1 =>
							X3_X5_startup<= '1';
							ns            <= S2;
						when s2 =>
							X3_X5_startup<= '0';
							ns            <= S3;
						when others =>
					end case;
				--====== 模式10 : OLED + SEG =============================--
				elsif(mode = "10" and flag_sys = 1)then -- 20ns
					case ps is
						when s0 =>
							X3_X5_startup<= '0';
							ns            <= S1;
						when s1 =>
							X3_X5_startup<= '1';
							ns            <= S2;
						when s2 =>
							X3_X5_startup<= '0';
							ns            <= S3;
						when others =>
					end case;
				 --====== 模式11 : OLED + SEG + SD178B ==================--
				elsif(mode = "11" and flag_sys = 1)then
					case ps is
						when s0 =>
							X3_X5_startup<= '0';
							ns            <= S1;
						when s1 =>
							X3_X5_startup<= '1';
							ns            <= S2;
						when s2 =>
							X3_X5_startup<= '0';
							ns            <= S3;
						when others =>
					end case;
				end if;
				--================================================================--
			end if;
		end if;
	end if;
	end process;
end block x3;
--**********************************************************************************
-- X4 : SEG驅動頂層實體控制電路
x4 : block
begin
	process(clk,rst) -- 敏感度列表 
	begin
		if(rst = '0')then -- 初始化 (異步重置)
			SEG_data  <= (others => '1');   -- 所有段關閉
			SEG_dot   <= "00000000";        -- 所有點關閉
			SEG_flash <= "00000000";        -- 正常顯示
		elsif(clk'event and clk = '1')then  -- 正緣觸發 (20ns)
			--====== 模式00 =====================================================--
			if(mode = "00")then
				SEG_data <= (others => '1'); -- 所有段關閉
				SEG_dot	 <= "00000000";      -- 所有點關閉
			--====== 模式01 , 模式10 , 模式11 =================================--
			elsif(mode = "01" or mode = "10" or mode = "11")then
				if(flag_sys = 1)then       
					SEG_data <= "011100" & "011101" & "001010" & "011011"
											& "011101" & "101100" & "111111" & "111111";
					SEG_dot  <= "00000100";
				elsif(flag_sys = 10)then
					SEG_data <= "001100" & "010110" & "001101" & "000001"
											& "011110" & "011001" & "101100" & "111111";
					SEG_dot  <= "00000010";
				elsif(flag_sys = 11)then
					SEG_data <= "001100" & "010110" & "001101" & "000001"
											& "001101" & "100000" & "101100" & "111111";
					SEG_dot  <= "00000010";
				elsif(flag_sys = 14)then
					SEG_data <= "001100" & "010110" & "001101" & "000001"
											& "010101" & "011101" & "101100" & "111111";
					SEG_dot  <= "00000010";
				elsif(flag_sys = 15)then
					SEG_data <= "001100" & "010110" & "001101" & "000001"
											& "011011" & "011101" & "101100" & "111111";
					SEG_dot  <= "00000010";
				end if;
			end if;
			--===================================================================--
		end if;
	end process; 
end block x4;
--**********************************************************************************
-- X5 : OLED驅動頂層實體FSM
x5 : block
	type   states is (s0,s1,s2,s3,s4,s5,s6,s7,s8,s9,s10,s11,s12,s13,s14,s15,s16,s17,
					  s18,s19,s20,s21,s22,s23,s24,s25,s26,s27,s28,s29,s30,s31,s32,s33,
					  s34,s35,s36,s37,s38,s39,s40,s41,s42,s43,s44,s45,s46,s47,s48,s49,
					  s50,s51,s52,s53,s54,s55,s56,s57,s58,s59,s60,s61,s62,s63,s64,s65);
	signal ps,ns	     : states;    -- 用於OLED主流程的FSM
	signal flag_tft_init : std_logic;
	signal flag_tft_sub  : std_logic; -- 用於OLED子程序的標誌
	signal X5_startup   : std_logic;
	signal char_cnt	     : integer range 0 to 15; -- 用於字符計數
	signal cnt		     : std_logic_vector(25 downto 0); -- 26 Bits
------------------------------------------------------------------------------------
begin
	--------------------------------------------------------------------------------
	-- FSM (兩過程有限狀態機)
	--------------------------------------------------------------------------------
	-- (1) 狀態改變
	process(clk,rst) -- 敏感度列表
	begin
		if(rst = '0')then --初始化 (異步重置)
			ps <= s0;
		elsif(clk'event and clk= '1')then --  正緣觸發 (20ns)
			ps <= ns;
		end if;
	end process;
	--------------------------------------------------------------------------------
	--(2) 個別狀態執行序列
	process(clk,rst) -- 敏感度列表
		begin
		if(rst = '0')then -- 初始化 (異步重置)
			flag_check <= 0;
			flag_tft_init <= '1';
			flag_tft_sub  <= '0'; -- 子程序執行標誌
			X5_startup   <= '0';
			tft_start_p   <= '0';
			tft_font_sel  <=   0; -- 字體大小 = 160x128
			tft_row_addr  <=   0; -- 左上角行地址
			tft_col_addr  <=   0; -- 左上角列地址
			tft_row_range <= 160;
			tft_col_range <= 128;
			tft_word_code <=   7; -- 字顏色 = 白色
			tft_rgb_code  <=   7; -- 背景色設置= 白色
			char_cnt      <=   0;
			cnt <= (others => '0');
			led_y <= '0';
			i	:= 74;
			j	:= 48;
			n	:= 19;
			ns <= s0;
		elsif(clk'event and clk = '0')then -- 負緣觸發 (20ns)
			--===== OLED 初始化 ===================================--
			if(flag_tft_init = '1' or sw_trig = '1')then
				flag_tft_init <= '0';
				flag_tft_sub  <= '1'; -- 子程序執行標誌
				cnt           <= (others => '0'); -- 用於延遲計數
			--====================================================================--
			-- from X3 Block 啟動信號(Main Control Logic)
			elsif(X3_X5_startup= '1' and flag_tft_init = '0')then
				flag_tft_sub  <= '1'; -- 子程序執行標誌
				X5_startup   <= '1';
				cnt           <= (others => '0'); -- 用於延遲計數
				char_cnt      <= 0;   -- 用於字符計數
				ns            <= s0;
			--====================================================================--
			--===== OLED Subroutine : 清屏為白色===============--
			--====================================================================--
			elsif(flag_tft_sub = '1')then -- 20ns
				case ps is
					when s0 =>
						if(tft_bf_out = '1')then -- 等待忙標誌?
							ns  <= s0;
						else
							ns  <= s1;
						end if;
					when s1 => -- 設置行範圍和列範圍
						tft_font_sel  <=   0;  -- 字體大小 = 160x128
						tft_row_addr  <=   0;  -- 左上角行地址
						tft_col_addr  <=   0;  -- 左上角列地址
						tft_row_range <= 160;
						tft_col_range <= 128;
						tft_word_code <=  7; -- 字顏色 = 白色
						tft_rgb_code  <=   7; -- 背景色設置= 白色 
						cnt           <= (others => '0');
						ns            <= s2;
					when s2 =>
						tft_start_p <= '1'; -- 啟動OLED驅動程序
						if(cnt < 5)then     -- 等待用於100ns
							cnt <= cnt + 1;
							ns  <= s2;
						else
							cnt <= (others => '0');
							ns  <= s3; 
						end if;
					when s3 =>
						tft_start_p <= '0';
						if(tft_bf_out = '1')then -- 等待忙標誌?
							ns  <= s3;
						else
							cnt <= (others => '0');
							ns  <= s4;
						end if;   
					when others =>
						flag_tft_sub <= '0'; -- Clear 子程序執行標誌.
						cnt          <= (others => '0'); -- 用於延遲計數
						ns           <= s0;  -- OLED的FSM初始化
				end case;
			--====================================================================--
			--====== X5主控制邏輯電路 ========================--
			--====================================================================--

			elsif(X5_startup= '1')then -- 20ns
				--====== mode 00 =================================================--
				if(mode = "00" and flag_sys /= 0)then
					case ps is
						when s0 => -- 循環初始化
							i  := 64;
							j  := 48;
							ns <= s1;
						when s1 => -- 外循環
							n		:= 19;
							ns <= s2;
						when s2 => -- 內循環 (清屏為白色)
							tft_font_sel  <=   0;   -- 字體大小 = 160x128
							tft_row_addr  <=   0;   -- 左上角行地址
							tft_col_addr  <=   0;   -- 左上角列地址
							tft_row_range <= 160; 
							tft_col_range <= 128;
							tft_word_code <=   4; -- 字顏色 = 白色
							tft_rgb_code  <=   8; -- 背景色設置= 白色
							tft_start_p   <= '1'; -- 啟動OLED驅動程序
							ns            <= s3;
						when s3 =>
							tft_start_p <= '0';
							if(tft_bf_out = '1')then -- 等待忙標誌?
								ns  <= s3;
							else
								cnt <= (others => '0');
								ns  <= s4;
							end if;
						when s4 =>
							if(cnt < 4E6)then -- 等待用於80ms ?
								cnt <= cnt + 1;
								ns  <= s4;
							else
								ns  <= s5;
							end if;
						------------------------------------------------------------
						when s5 =>
							tft_font_sel  <=  8; -- 字體大小 = 32x32
							tft_row_addr  <=  10; -- 左上角行地址
							tft_row_range <= 32; 
							tft_col_range <= 32;
							ns            <= s6;
						when s6 =>
							case char_cnt is -- 左上角列地址
								when 0 => tft_col_addr <=   5; tft_data_in <= 6; tft_word_code <= 1;				--三角形橙色
								when 1 => tft_col_addr <=  48; tft_data_in <= 0; tft_word_code <= 6;			--圓形紫色
								when others =>tft_col_addr <= 91; tft_data_in <= 4; tft_word_code <= 15;	--正方形暗黃色
							end case;
							cnt <= (others => '0');
							ns  <= s7;
						when s7 =>
							tft_start_p <= '1'; -- 啟動OLED驅動程序
							if(cnt < 5)then     -- 等待用於100ns
								cnt <= cnt +1;
								ns  <= s7;
							else
								cnt <= (others => '0');
								ns  <= s8; 
							end if;
						when s8 =>
							tft_start_p <= '0';
							if(tft_bf_out = '1')then -- 等待忙標誌?
								ns  <= s8;
							else
								ns  <= s9;
							end if;
						when s9 =>  
							if(char_cnt < 8)then
								char_cnt <= char_cnt + 1;
								ns       <= s6; -- 第1行
							else
								char_cnt <= 0;
								ns       <= s10; -- 第2行預設
							end if;
						when s10 =>
							if(flag_start = 0)then
								if(cnt < 5E7)then -- 等待1秒
									cnt <= cnt + 1;
									ns  <= s10;
								else
									cnt <= (others => '0');
									ns  <= s11;
								end if;
							elsif(flag_start = 1)then
								if(cnt < 3E5)then -- 等待1秒
									cnt <= cnt + 1;
									ns  <= s10;
								else
									cnt <= (others => '0');
									ns  <= s11;
								end if;
							end if;
						------------------------------------------------------------
						when s11 =>
							tft_font_sel  <=  8; -- 字體大小 = 32x32
							tft_row_addr  <=  64; -- 左上角行地址
							ns            <= s12;
						when s12 =>
							case char_cnt is -- 左上角列地址
								when 0 => tft_col_addr <=   5; tft_data_in <= 3; tft_word_code <= 11;--三角形亮藍色
								when others =>tft_col_addr <= 91; tft_data_in <= 2; tft_word_code <= 3;--菱形暗綠色
							end case;
							cnt <= (others => '0');
							ns  <= s13;
						when s13 =>
							tft_start_p <= '1'; -- 啟動OLED驅動程序
							if(cnt < 5)then     -- 等待用於100ns
								cnt <= cnt +1;
								ns  <= s13;
							else
								cnt <= (others => '0');
								ns  <= s14; 
							end if;
						when s14 =>
							tft_start_p <= '0';
							if(tft_bf_out = '1')then -- 等待忙標誌?
								ns  <= s14;
							else
								ns  <= s15;
							end if;
						when s15 =>  
							if(char_cnt < 8)then
								char_cnt <= char_cnt + 1;
								ns       <= s12; -- 第2行
							else
								char_cnt <= 0;
								ns       <= s16; -- 第3行預設
							end if;
						when s16 =>
							if(flag_start = 0)then
								if(cnt < 5E7)then -- 等待1秒
									cnt <= cnt + 1;
									ns  <= s16;
								else
									cnt <= (others => '0');
									ns  <= s17;
								end if;
							elsif(flag_start = 1)then
								if(cnt < 3E5)then -- 等待1秒
									cnt <= cnt + 1;
									ns  <= s16;
								else
									cnt <= (others => '0');
									ns  <= s17;
								end if;
							end if;
						------------------------------------------------------------
						when s17 =>
							tft_font_sel  <=  8; -- 字體大小 = 32x32
							tft_row_addr  <=  118; -- 第3行行地址
							ns            <= s18;
						when s18 =>
							case char_cnt is -- 左上角列地址
								when 0 => tft_col_addr <= 5; tft_data_in <= 9; tft_word_code <= 12;--寬方形亮暗藍色
								when 1 => tft_col_addr <= 48; tft_data_in <= 7; tft_word_code <= 13;--倒三角形棕色
								when others =>tft_col_addr <= 91; tft_data_in <= 8; tft_word_code <= 10;--八角形亮綠色
							end case;
							cnt <= (others => '0');
							ns  <= s19;
						when s19 =>
							tft_start_p <= '1'; -- 啟動OLED驅動程序
							if(cnt < 5)then     -- 等待用於100ns
								cnt <= cnt +1;
								ns  <= s19;
							else
								cnt <= (others => '0');
								ns  <= s20; 
							end if;
						when s20 =>
							tft_start_p <= '0';
							if(tft_bf_out = '1')then -- 等待忙標誌?
								ns  <= s20;
							else
								ns  <= s21;
							end if;
						when s21 =>  
							if(char_cnt < 8)then
								char_cnt <= char_cnt + 1;
								ns       <= s18; -- 第2行
							else
								char_cnt <= 0;
								ns       <= s22; -- 第3行預設
							end if;
						when s22 =>
							if(flag_start = 0)then
								if(cnt < 5E7)then -- 等待1秒
									cnt <= cnt + 1;
									ns  <= s22;
								else
									cnt <= (others => '0');
									ns  <= s23;
								end if;
							elsif(flag_start = 1)then
								if(cnt < 3E5)then -- 等待1秒
									cnt <= cnt + 1;
									ns  <= s22;
								else
									cnt <= (others => '0');
									ns  <= s24;
								end if;
							end if;
						------------------------------------------------------------
						--9. 檢查S2的標誌
						when s23 =>
							if(flag_sys = 0 or flag_sys = 1)then -- /= : 不等於
								ns  <= s23; -- 不啟動
							else
								ns  <= s24; -- 啟動
								cnt <= (others => '0');
							end if;
						-- 11. 顯示第五格
						when s24 =>
							tft_font_sel  <=  8; -- 字體大小 = 32x32
							tft_row_addr  <=  i; -- 左上角行地址
							tft_col_addr  <=  j; -- 左上角列地址
							tft_row_range <= 32;
							tft_col_range <= 32;
							tft_word_code <=  2; -- 字顏色 = 亮黃色
							tft_data_in   <=  n; -- 19 : 正方形物體
							ns            <= s25;
						when s25 =>
							tft_start_p <= '1'; -- 啟動OLED驅動程序
							ns          <= s26;
						when s26 =>
							tft_start_p <= '0';
							if(tft_bf_out = '1')then -- 等待忙標誌?
								ns  <= s26;
							else
								cnt <= (others => '0');
								ns  <= s27;
							end if;
						when s27 =>-- 在此等待，直到kb_done_p觸發
							if(cnt < 5E5)then -- 等待1秒
								cnt <= cnt + 1;
								ns  <= s27;
							else
								if(sys_uartFs ='1')then
									cnt <= (others => '0');
									ns  <= s28;
								elsif(kb_done_p = '1')then
									cnt <= (others => '0');
									ns  <= s28;
								else
									ns  <= s27;
								end if;
							end if;
						------------------------------------------------------------
						when s28 =>
							tft_font_sel  <= 8; -- 字體大小 = 32x32
							tft_row_addr  <= i; -- 左上角行地址
							tft_col_addr  <= j; -- 左上角列地址
							tft_row_range <= 32;
							tft_col_range <= 32;
							tft_word_code <= 8; -- 字顏色 = 白色
							tft_data_in   <= 4; -- 4 : 正方形物體
							ns			<= s29;
							tft_rgb_code  <= 8; -- 背景色設置= 白色
						when s29 =>
							tft_start_p <= '1'; -- 啟動OLED驅動程序
							ns			<= s30;
						when s30 =>
							tft_start_p <= '0';
							if(tft_bf_out = '1')then -- 等待忙標誌?
								ns  <= s30;
							else
								ns <= s31;
							end if;
						when s31 =>
							if(cnt < 5E5)then -- 等待1秒
								cnt <= cnt + 1;
								ns  <= s31;
							else
								cnt <= (others => '0');
								ns  <= s32;
							end if;
						when s32 =>
							if(flag_sys = 3)then
								n := 22;
								ns  <= s5;
							elsif(flag_sys = 4)then
								n := 19;
								ns  <= s5;
							elsif(flag_sys = 10)then -- UP
								if(i > 31 )then
									i := i - 54;
									j := j;
									ns  <= s5;
								else
									ns  <= s24;
								end if;
							elsif(flag_sys = 11)then -- DW
								if(i < 107)then
									i  := i + 54;
									j := j;
									ns  <= s5;
								else
									ns  <= s24;
								end if;
							elsif(flag_sys = 14)then -- LT
								if(j > 42)then
									i := i;
									j  := j - 43;
									ns  <= s5;
								else
									ns  <= s24;
								end if;
							elsif(flag_sys = 15)then -- RT
								if(j < 118)then
									i := i;
									j := j + 43;
									ns <= s5;
								else
									ns <= s24;
								end if;
							else	
								ns <= s24;
							end if;
						
						when others =>
							ns <= s5; -- 無限循環
					end case;
				--====== 模式01 =================================================--
				elsif(mode = "01")then -- 20ns
					case ps is
						when s0 => -- 設置行範圍和列範圍
							tft_font_sel  <=   0;  -- 字體大小 = 160x128
							tft_row_addr  <=   0;  -- 左上角行地址
							tft_col_addr  <=   0;  -- 左上角列地址
							tft_row_range <= 160;
							tft_col_range <= 128;
							tft_word_code <=   7; -- 字顏色 = 黑色
							tft_rgb_code  <=   7; -- 背景色設置= 黑色 
							ns            <= s1;
						when s1 =>
							tft_start_p <= '1'; -- 啟動OLED驅動程序
							ns          <= s2;
						when s2 =>
							tft_start_p <= '0';
							if(tft_bf_out = '1')then -- 等待忙標誌?
								ns  <= s2;
							else
								ns  <= s3;
							end if;
						when others =>
							null;
					end case;
				--====== 模式10和模式11 =====================================--
				-- 模式10: 設置OLED的參數
				-- 模式11: OLED的集成測試
				elsif((mode = "10" and flag_sys /= 0) or (mode = "11" and flag_sys /= 0))then
					case ps is
						when s0 => -- 循環初始化
							i  := 64;
							j  := 48;
							ns <= s1;
						when s1 => -- 外循環
							ns <= s2;
						when s2 => -- 內循環 (清屏為白色)
							tft_font_sel  <=   0;   -- 字體大小 = 160x128
							tft_row_addr  <=   0;   -- 左上角行地址
							tft_col_addr  <=   0;   -- 左上角列地址
							tft_row_range <= 160; 
							tft_col_range <= 128;
							tft_word_code <=   4; -- 字顏色 = 白色
							tft_rgb_code  <=   8; -- 背景色設置= 白色
							tft_start_p   <= '1'; -- 啟動OLED驅動程序
							ns            <= s3;
						when s3 =>
							tft_start_p <= '0';
							if(tft_bf_out = '1')then -- 等待忙標誌?
								ns  <= s3;
							else
								cnt <= (others => '0');
								ns  <= s4;
							end if;
						when s4 =>
							if(cnt < 4E6)then -- 等待用於80ms ?
								cnt <= cnt + 1;
								ns  <= s4;
							else
								ns  <= s5;
							end if;
						------------------------------------------------------------
						when s5 =>
							tft_font_sel  <=  8; -- 字體大小 = 32x32
							tft_row_addr  <=  10; -- 左上角行地址
							tft_row_range <= 32; 
							tft_col_range <= 32;
							ns            <= s6;
						when s6 =>
							case char_cnt is -- 左上角列地址
								when 0 => tft_col_addr <=   5; tft_data_in <= 6; tft_word_code <= 1;				--三角形橙色
								when 1 => tft_col_addr <=  48; tft_data_in <= 0; tft_word_code <= 6;			--圓形紫色
								when others =>tft_col_addr <= 91; tft_data_in <= 4; tft_word_code <= 15;	--正方形暗黃色
							end case;
							cnt <= (others => '0');
							ns  <= s7;
						when s7 =>
							tft_start_p <= '1'; -- 啟動OLED驅動程序
							if(cnt < 5)then     -- 等待用於100ns
								cnt <= cnt +1;
								ns  <= s7;
							else
								cnt <= (others => '0');
								ns  <= s8; 
							end if;
						when s8 =>
							tft_start_p <= '0';
							if(tft_bf_out = '1')then -- 等待忙標誌?
								ns  <= s8;
							else
								ns  <= s9;
							end if;
						when s9 =>  
							if(char_cnt < 8)then
								char_cnt <= char_cnt + 1;
								ns       <= s6; -- 第1行
							else
								char_cnt <= 0;
								ns       <= s10; -- 第2行預設
							end if;
						when s10 =>
							if(cnt < 3E5)then -- 等待1秒
								cnt <= cnt + 1;
								ns  <= s10;
							else
								cnt <= (others => '0');
								ns  <= s11;
							end if;
						------------------------------------------------------------
						when s11 =>
							tft_font_sel  <=  8; -- 字體大小 = 32x32
							tft_row_addr  <=  64; -- 左上角行地址
							ns            <= s12;
						when s12 =>
							if(flag_start = 0)then
								case char_cnt is -- 左上角列地址
									when 0 => tft_col_addr <=   5; tft_data_in <= 3; tft_word_code <= 11;--三角形亮藍色
									when 1 =>tft_col_addr <= 48; tft_data_in <= 21; tft_word_code <= 7;--菱形暗綠色
									when others =>tft_col_addr <= 91; tft_data_in <= 2; tft_word_code <= 3;--菱形暗綠色
								end case;
							elsif(flag_start = 1)then
								case char_cnt is -- 左上角列地址
									when 0 => tft_col_addr <=   5; tft_data_in <= 3; tft_word_code <= 11;--三角形亮藍色
									when others =>tft_col_addr <= 91; tft_data_in <= 2; tft_word_code <= 3;--菱形暗綠色
								end case;
							end if;
							cnt <= (others => '0');
							ns  <= s13;
						when s13 =>
							tft_start_p <= '1'; -- 啟動OLED驅動程序
							if(cnt < 5)then     -- 等待用於100ns
								cnt <= cnt +1;
								ns  <= s13;
							else
								cnt <= (others => '0');
								ns  <= s14; 
							end if;
						when s14 =>
							tft_start_p <= '0';
							if(tft_bf_out = '1')then -- 等待忙標誌?
								ns  <= s14;
							else
								ns  <= s15;
							end if;
						when s15 =>  
							if(char_cnt < 8)then
								char_cnt <= char_cnt + 1;
								ns       <= s12; -- 第2行
							else
								char_cnt <= 0;
								ns       <= s16; -- 第3行預設
							end if;
						when s16 =>
							if(cnt < 3E5)then -- 等待1秒
								cnt <= cnt + 1;
								ns  <= s16;
							else
								cnt <= (others => '0');
								ns  <= s17;
							end if;
						------------------------------------------------------------
						when s17 =>
							tft_font_sel  <=  8; -- 字體大小 = 32x32
							tft_row_addr  <=  118; -- 第3行行地址
							ns            <= s18;
						when s18 =>
							case char_cnt is -- 左上角列地址
								when 0 => tft_col_addr <= 5; tft_data_in <= 9; tft_word_code <= 12;--寬方形亮暗藍色
								when 1 => tft_col_addr <= 48; tft_data_in <= 7; tft_word_code <= 13;--倒三角形棕色
								when others =>tft_col_addr <= 91; tft_data_in <= 8; tft_word_code <= 10;--八角形亮綠色
							end case;
							cnt <= (others => '0');
							ns  <= s19;
						when s19 =>
							tft_start_p <= '1'; -- 啟動OLED驅動程序
							if(cnt < 5)then     -- 等待用於100ns
								cnt <= cnt +1;
								ns  <= s19;
							else
								cnt <= (others => '0');
								ns  <= s20; 
							end if;
						when s20 =>
							tft_start_p <= '0';
							if(tft_bf_out = '1')then -- 等待忙標誌?
								ns  <= s20;
							else
								ns  <= s21;
							end if;
						when s21 =>  
							if(char_cnt < 8)then
								char_cnt <= char_cnt + 1;
								ns       <= s18; -- 第2行
							else
								char_cnt <= 0;
								ns       <= s22; -- 第3行預設
							end if;
						when s22 =>
							if(flag_check = 0)then
								if(cnt < 3E5)then -- 等待1秒
									cnt <= cnt + 1;
									ns  <= s22;
								else
									cnt <= (others => '0');
									ns  <= s23;
								end if;
							elsif(flag_check = 1)then
								if(cnt < 3E5)then -- 等待1秒
									cnt <= cnt + 1;
									ns  <= s22;
								else
									cnt <= (others => '0');
									ns  <= s24;
								end if;
							end if;
						------------------------------------------------------------
						--9. 檢查S2的標誌
						when s23 =>
							if(flag_sys = 0 or flag_sys = 1)then -- /= : 不等於
								ns  <= s23; -- 不啟動
							else
								ns  <= s24; -- 啟動
								cnt <= (others => '0');
							end if;
						-- 11. 顯示第五格
						when s24 =>
							tft_font_sel  <=  8; -- 字體大小 = 32x32
							tft_row_addr  <=  i; -- 左上角行地址
							tft_col_addr  <=  j; -- 左上角列地址
							tft_row_range <= 32;
							tft_col_range <= 32;
							tft_word_code <=  2; -- 字顏色 = 亮黃色
							tft_data_in   <=  13; -- 19 : 正方形物體
							ns            <= s25;
						when s25 =>
							tft_start_p <= '1'; -- 啟動OLED驅動程序
							ns          <= s26;
						when s26 =>
							if(flag_check = 0)then
								tft_start_p <= '0';
								if(tft_bf_out = '1')then -- 等待忙標誌?
									ns  <= s26;
								else
									cnt <= (others => '0');
									ns  <= s27;
								end if;
							else
								ns <= s34;
							end if;
						when s27 =>-- 在此等待，直到kb_done_p觸發
							if(cnt < 5E5)then -- 等待1秒
								cnt <= cnt + 1;
								ns  <= s27;
							else
								if(sys_uartFs ='1')then
									cnt <= (others => '0');
									ns  <= s28;
								elsif(kb_done_p = '1')then
									cnt <= (others => '0');
									ns  <= s28;
								else
									ns  <= s27;
								end if;
							end if;
						------------------------------------------------------------
						when s28 =>
							tft_font_sel  <= 8; -- 字體大小 = 32x32
							tft_row_addr  <= i; -- 左上角行地址
							tft_col_addr  <= j; -- 左上角列地址
							tft_row_range <= 32;
							tft_col_range <= 32;
							tft_word_code <= 8; -- 字顏色 = 白色
							tft_data_in   <= 4; -- 4 : 正方形物體
							ns			<= s29;
							tft_rgb_code  <= 8; -- 背景色設置= 白色
						when s29 =>
							tft_start_p <= '1'; -- 啟動OLED驅動程序
							ns			<= s30;
						when s30 =>
							tft_start_p <= '0';
							if(tft_bf_out = '1')then -- 等待忙標誌?
								ns  <= s30;
							else
								ns <= s31;
							end if;
						when s31 =>
							if(cnt < 5E5)then -- 等待1秒
								cnt <= cnt + 1;
								ns  <= s31;
							else
								cnt <= (others => '0');
								ns  <= s32;
							end if;
						when s32 =>
							if(flag_sys = 10)then -- UP
								if(i > 32 )then
									i := i - 54;
									j := j;
									ns  <= s33;
								else
									ns  <= s24;
								end if;
							elsif(flag_sys = 11)then -- DW
								if(i < 96)then
									i  := i + 54;
									j := j;
									ns  <= s33;
								else
									ns  <= s24;
								end if;
							elsif(flag_sys = 14)then -- LT
								if(j > 32)then
									i := i;
									j  := j - 43;
									ns  <= s33;
								else
									ns  <= s24;
								end if;
							elsif(flag_sys = 15)then -- RT
								if(j < 128)then
									i := i;
									j := j + 43;
									ns <= s33;
								else
									ns <= s24;
								end if;
							else	
								ns <= s24;
							end if;
						when s33 =>
							if(i = 64 and j = 5)then
								ns <= s5;
								led_y <= '1';
								flag_check <= 1;
							else
								ns <= s5;
							end if;
						when s34 =>
							if(cnt < 5E5)then -- 等待1秒
								cnt <= cnt + 1;
								ns  <= s34;
							else
								if(sys_uartFs ='1')then
									cnt <= (others => '0');
									ns  <= s5;
								elsif(kb_done_p = '1')then
									ns <= s35;
								else
									ns  <= s34;
								end if;
							end if;
						when s35 =>
							if(flag_sys = 5)then
								flag_check <= 2;
								ns  <= s36;
							else
								ns  <= s5;
							end if;
						when s36 =>
							tft_font_sel  <= 8; -- 字體大小 = 32x32
							tft_row_addr  <= 64; -- 左上角行地址
							tft_col_addr  <= 5; -- 左上角列地址
							tft_row_range <= 32;
							tft_col_range <= 32;
							tft_word_code <= 8; -- 字顏色 = 白色
							tft_rgb_code  <= 8; -- 背景色設置= 白色
							tft_data_in   <= 4; -- 4 : 正方形物體
							ns			<= s37;
						when s37 =>
							tft_start_p <= '1'; -- 啟動OLED驅動程序
							ns			<= s38;
						when s38 =>
							tft_start_p <= '0';
							if(tft_bf_out = '1')then -- 等待忙標誌?
								ns  <= s38;
							else
								ns <= s39;
							end if;
						when s39 =>
							if(cnt < 5E5)then -- 等待1秒
								cnt <= cnt + 1;
								ns  <= s39;
							else
								cnt <= (others => '0');
								ns  <= s40;
							end if;
						when others =>
					end case;
				end if;
			end if;
		end if;
	end process;
end block x5;
--**********************************************************************************
-- X6 : SD178B驅動程序頂層實體的FSM
x6 : block
	type  states is (s0,s1,s2,s3,s4,s5,s6,s7,s8,s9,s10,s11,s12,s13,s14,s15,s16,s17,
					 s18,s19,s20,s21,s22,s23,s24,s25,s26,s27,s28,s29,s30,s31,s32,
					 s33,s34,s35,s36,s37,s38,s39,s40,s41,s42,s43,s44,s45,s46,s47,s48,
					 s49,s50,s51,s52,s53,s54,s55,s56,s57,s58,s59,s60,s61,s62,s63);
	signal ps,ns,nns : states;
	signal cnt 		 : std_logic_vector(25 downto 0); -- 26 Bits
	signal cnt_sd	 : std_logic_vector(29 downto 0); -- 30 Bits
	signal p_cnt 	 : std_logic_vector( 1 downto 0);
-------------------------------------------------------------------------------
begin
	---------------------------------------------------------------------------
	-- FSM (兩過程有限狀態機)
	---------------------------------------------------------------------------
	-- (1) 狀態改變
	process(clk,rst) -- 敏感度列表 
	begin
		if(rst = '0')then -- 初始化 (異步重置)
			ps    <= s0;
		elsif(clk'event and clk = '1')then -- 正緣觸發 (20ns)
			ps    <= ns;
		end if;
	end process;
	---------------------------------------------------------------------------
	--(2) 個別狀態執行序列
	process(clk,rst) -- 敏感度列表 
	begin
		if(rst = '0')then -- 初始化 (異步重置)
			cnt    <= (others => '0');
			cnt_sd <= (others => '0');
			ns     <= s0;
		elsif(clk'event and clk = '0')then -- 負緣觸發 (20ns)
			--******************************************************************--
			-- FSM (有限狀態機)
			--******************************************************************--
			if(mode = "11")then
				case ps is -- 20ns
					when s0 => -- 延遲10us(僅為防止Bug)
						if(cnt < 500)then -- 500 x 20ns = 10000ns
							cnt <= cnt + 1;
							ns  <= s0;
						else
							cnt <= (others => '0');
							ns  <= s1;
						end if;
					when s1 => -- 等待忙標誌(芯片啟動)
						if(sd_bf_out = '1')then
							ns <= s1;
						else
							ns <= s2;
						end if;
					-- 設置音頻通道 (設置為兩個通道啟用
					when s2 =>
						sd_start_p  <= '0';   -- 啟動SD178B驅動信號
						sd_rw       <= '0';   -- 寫
						sd_cmd_da   <= '0';   -- 命令
						sd_cmd_char <= X"8B"; -- 音頻通道設置
						sd_data_in  <= (others => '0');  -- 清除未使用位
						sd_data_in(7 downto 0) <= X"07"; -- 耳機+揚聲器（左-右）
						cnt         <= (others => '0');
						ns			<= s3;
					when s3 =>
						sd_start_p <= '1'; -- 啟動SD178B驅動程序
						ns         <= s4; 
					when s4 =>
						sd_start_p <= '0';
						if(sd_bf_out = '1')then -- 等待忙標誌?
							ns <= s4;
						else
							ns <= s5;
						end if;
					-- 設置播放速度（設置為+0%速度）
					when s5 =>
						sd_rw       <= '0'; -- 寫
						sd_cmd_da   <= '0'; -- 命令
						sd_cmd_char <= X"83"; -- 播放速度設置
						sd_data_in  <= (others => '0');  -- 清除未使用位
						sd_data_in(7 downto 0) <= X"28"; -- 設置值 (按百分比)
						ns                     <= s6;
					when s6 =>
						sd_start_p <= '1'; -- 啟動SD178B驅動程序
						ns         <= s7; 
					when s7 =>
						sd_start_p <= '0';
						if(sd_bf_out = '1')then -- 等待忙標誌?
							ns <= s7;
						else
							ns <= s8;
						end if;
					-- 設置播放音量
					when s8 =>
						sd_rw       <= '0';   -- 寫
						sd_cmd_da   <= '0';   -- 命令
						sd_cmd_char <= X"86"; -- 設置音量
						sd_data_in <= (others => '0');   -- 清除未使用位
						sd_data_in(7 downto 0) <= X"FA"; --  -2.5dB
						ns                     <= s9;
					when s9 =>
						sd_start_p <= '1'; -- 啟動SD178B驅動程序
						ns         <= s10; 
					when s10 =>
						sd_start_p <= '0';
						if(sd_bf_out = '1')then -- 等待忙標誌?
							ns <= s10;
						else
							ns <= s11;
						end if;
					when s11 =>
						sd_data_in  <= (others => '0'); -- 清除所有位
						sd_cmd_char <= "00000000";      -- 長度 = 0
						cnt_sd      <= (others => '0');
						ns          <= s12;
					----------------------------------------------------------------
					-- 1. 播放句子並響應KEY操作
					----------------------------------------------------------------
					when s12 => -- 在此等待，直到kb_done_p觸發
						if(cnt_sd < 5E7)then -- 等待1秒
							cnt_sd <= cnt_sd + 1;
							ns     <= s12;
						else -- 在此等待，直到按下S1鍵以播放句子
							if(flag_sys = 1)then -- S1
								cnt_sd <= (others => '0'); 
								ns     <= s13;
							end if;
						end if;
					----------------------------------------------------------------
					-- 播放句子1
					when s13 => 
						sd_rw       <= '0'; -- 寫
						sd_cmd_da   <= '1'; -- 數據
						sd_cmd_char <= "00000110"; -- 長度  = 6
						--                            無線連結成功
						sd_data_in(95 downto 0) <= X"B54C_BD75_B373_B5B2_A6A8_A55C";
						ns <= s14;
					when s14 => -- 發送觸發信號
						sd_start_p <= '1'; -- 啟動SD178B驅動程序
						ns         <= s15; 
					when s15 =>
						sd_start_p <= '0';
						if(sd_bf_out = '1')then -- 等待忙標誌?
							ns <= s15;
						else
							ns <= s16;
						end if;
					----------------------------------------------------------------
					-- 1. 播放句子並響應KEY操作
					----------------------------------------------------------------
					when s16 => -- 在此等待，直到kb_done_p觸發
						if(cnt_sd < 5E7)then -- 等待1秒
							cnt_sd <= cnt_sd + 1;
							ns     <= s16;
						else -- 在此等待，直到按下S1鍵以播放句子
							if(flag_sys = 2)then -- S1
								cnt_sd <= (others => '0'); 
								ns     <= s17;
							end if;
						end if;
					----------------------------------------------------------------
					-- 播放句子2
					when s17 => 
						sd_rw       <= '0'; -- 寫
						sd_cmd_da   <= '1'; -- 數據
						sd_cmd_char <= "00001000"; -- 長度  = 8
						--                            實心幾何圖形產生
						sd_data_in(127 downto 0) <= X"B9EA_A4DF_B458_A6F3_B9CF_A7CE_B2A3_A5CD";
						ns <= s18;
					when s18 => -- 發送觸發信號
						sd_start_p <= '1'; -- 啟動SD178B驅動程序
						ns         <= s19; 
					when s19 =>
						sd_start_p <= '0';
						if(sd_bf_out = '1')then -- 等待忙標誌?
							ns <= s19;
						else
							ns <= s20;
						end if;
					----------------------------------------------------------------
					-- 1. 播放句子並響應KEY操作
					----------------------------------------------------------------
					when s20 => -- 在此等待，直到kb_done_p觸發
						if(cnt_sd < 5E7)then -- 等待1秒
							cnt_sd <= cnt_sd + 1;
							ns     <= s20;
						else -- 在此等待，直到按下S1鍵以播放句子
							if(sys_uartFs ='1')then -- S1
								cnt_sd <= (others => '0'); 
								ns     <= s21;
							end if;
						end if;
					----------------------------------------------------------------
					-- 播放句子3
					when s21 => 
						sd_rw       <= '0'; -- 寫
						sd_cmd_da   <= '1'; -- 數據
						sd_cmd_char <= "00000111"; -- 長度  = 6
						if(flag_sys = 10)then
							--                           圖形往上方移動
							sd_data_in(111 downto 0) <= X"B9CF_A7C1_A9B9_A457_A4E8_B2BE_B0CA";
						elsif(flag_sys = 11)then
							--                            圖形往下方移動
							sd_data_in(111 downto 0) <= X"B9CF_A7C1_A9B9_A455_A4E8_B2BE_B0CA";
						elsif(flag_sys = 14)then
							--                            圖形往左方移動
							sd_data_in(111 downto 0) <= X"B9CF_A7C1_A9B9_A5AA_A4E8_B2BE_B0CA";
						elsif(flag_sys = 15)then
							--                            圖形往右方移動
							sd_data_in(111 downto 0) <= X"B9CF_A7C1_A9B9_A56B_A4E8_B2BE_B0CA";
						end if;
						ns <= s22;
					when s22 => -- 發送觸發信號
						sd_start_p <= '1'; -- 啟動SD178B驅動程序
						ns         <= s23; 
					when s23 =>
						sd_start_p <= '0';
						if(sd_bf_out = '1')then -- 等待忙標誌?
							ns <= s23;
						else
							ns <= s24;
						end if;
					----------------------------------------------------------------
					-- 1. 播放句子並響應KEY操作
					----------------------------------------------------------------
					when s24 => -- 在此等待，直到kb_done_p觸發
						if(cnt_sd < 5E7)then -- 等待1秒
							cnt_sd <= cnt_sd + 1;
							ns     <= s24;
						else -- 在此等待，直到按下S1鍵以播放句子
							if(flag_check = 0)then -- S1
								cnt_sd <= (others => '0'); 
								ns     <= s20;
							else
								cnt_sd <= (others => '0'); 
								ns     <= s25;
							end if;
						end if;
					----------------------------------------------------------------
					when s25 => -- 在此等待，直到kb_done_p觸發
						if(cnt_sd < 5E7)then -- 等待1秒
							cnt_sd <= cnt_sd + 1;
							ns     <= s25;
						else -- 在此等待，直到按下S1鍵以播放句子
							if(flag_check = 2)then -- S1
								cnt_sd <= (others => '0'); 
								ns     <= s26;
							else
								cnt_sd <= (others => '0'); 
								ns     <= s25;
							end if;
						end if;
					----------------------------------------------------------------
					-- 播放句子1
					when s26 => 
						sd_rw       <= '0'; -- 寫
						sd_cmd_da   <= '1'; -- 數據
						sd_cmd_char <= "00000110"; -- 長度  = 6
						--                            幾何圖形相同
						sd_data_in(95 downto 0) <= X"B458_A6F3_B9CF_A7CE_ACDB_A650";
						ns <= s27;
					when s27 => -- 發送觸發信號
						sd_start_p <= '1'; -- 啟動SD178B驅動程序
						ns         <= s28; 
					when s28 =>
						sd_start_p <= '0';
						if(sd_bf_out = '1')then -- 等待忙標誌?
							ns <= s28;
						else
							ns <= s29;
						end if;
					when others => 
						null;
					----------------------------------------------------------------
				end case;
			end if;	    
		end if;
	end process;
end block x6;
--**********************************************************************************
end PKE;