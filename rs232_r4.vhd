--RS232RX  接收緩衝器加大版 2018.01.18 16byte
--RS232RX  接收緩衝器加大版 2024.03.29 256byte
Library IEEE;
	Use IEEE.std_logic_1164.all;
	Use IEEE.std_logic_unsigned.all;
-- ----------------------------------------------------
Entity RS232_R4 is
	generic
	(
		TXRD_buff : natural--定義buffer 大小
	);
	Port(Clk,Reset:in std_logic;--clk:50MHz
		 DL:in std_logic_vector(1 downto 0);	 --00:5,01:6,10:7,11:8 Bit
		 ParityN:in std_logic_vector(2 downto 0);--0xx:None,100:Even,101:Odd,110:Space,111:Mark
		 StopN:in std_logic_vector(1 downto 0);	 --0x:1Bit,10:2Bit,11:1.5Bit
		 F_Set:in std_logic_vector(3 downto 0);
		 Status_s:out std_logic_vector(2 downto 0);
		 RX_BBN:buffer integer range 0 to TXRD_buff+1;	--buffer 現有資料量--2024.03.30
		 Rx_R:in std_logic;
		 RD:in std_logic;
		 RxDs:out std_logic_vector(7 downto 0));
End RS232_R4;
-- -----------------------------------------------------
Architecture RS232_R4_Arch of RS232_R4 is
Signal StopNn:std_logic_vector(2 downto 0);
Signal Rx_B_Empty,Rx_P_Error,Rx_OW:std_logic;
-------------
Signal RDf,Rx_f,Rx_PEOSM,R_Half_f:std_logic;
Signal RxD,RxDB, RX_buffer:std_logic_vector(7 downto 0);
Signal Rsend_RDLNs,RDLN:std_logic_vector(3 downto 0);
Signal Rc:std_logic_vector(2 downto 0);
Signal Rx_s,Rff,BaudRate1234:std_logic_vector(1 downto 0);
Signal RX_BaudRate:integer range 0 to 41667;
--2018.01.18--16byte---2024.03.29--256byte---2024.05.13--512byte----------------------
Signal BaudRateset:std_logic_vector(5 downto 0);--BaudRate
type buffer_data_T is array(0 to TXRD_buff) of std_logic_vector(7 downto 0);--接收緩衝器加大版512byte
signal RX_B_data:buffer_data_T;	--接收緩衝器
signal RX_B_P_Error,RX_B_OW:std_logic_vector(TXRD_buff downto 0);	--緩衝器資料同位元錯誤、覆寫旗標
Signal RX_B_P0,RX_B_P1:integer range 0 to TXRD_buff;				--緩衝器資料取出、加入指標
Signal Rx_B_OWs,upload0,upload1:std_logic;	--覆寫狀態旗標
-- --------------------------
Begin
Status_s<=Rx_B_Empty & Rx_P_Error & Rx_OW;
RDf<=Clk When (Rx_s(0) = Rx_s(1)) Else Rx_f;
-------------------------------------------
RxLP:Process(clk,Reset)
Begin
--	--upload_1--可能隱藏風險---------
--	if Reset='0' Then
--		RX_B_P0<=0;
--		Rx_B_Empty<='0';
--		Rx_OW<='0';
--		Rx_P_Error<='0';
--		upload0<='0';
--		RX_B_P1<=0;
--		RX_BBN<=0;
--	Elsif clk'event and clk='0' Then
--		upload0<=upload1;
--		if upload0='1' then
--			RX_B_data(RX_B_P1)<=RxDB;--xxx;	--緩衝器資料加入--2018.01.12
--			RX_B_P1<=RX_B_P1+1;			--緩衝器資料加入指標+1
--			RX_BBN<=RX_BBN+1;
--		else
--			if RX_BBN/=0 and Rx_B_Empty='0' then
--				RxDs<=RX_B_data(RX_B_P0);			--緩衝器資料取出
--				Rx_OW<=RX_B_OW(RX_B_P0); 			--Rx Buffer Over Write
--				Rx_P_Error<=RX_B_P_Error(RX_B_P0);	--Parity Error
--				Rx_B_Empty<='1';
--				RX_B_P0<=RX_B_P0+1;
--				RX_BBN<=RX_BBN-1;
--			elsIf Rx_R='1' Then
--				Rx_B_Empty<='0';
--			end if;
--		end if;
--	end if;

--  --upload_2--可能隱藏風險---------
--	if Reset='0' Then
--		RX_B_P0<=0;
--		Rx_B_Empty<='0';
--		Rx_OW<='0';
--		Rx_P_Error<='0';
--		upload0<='0';
--		RX_B_P1<=0;
--		RX_BBN<=0;
--	Elsif clk'event and clk='0' Then
--		upload0<=upload1;
--		if upload0='1' then
--			RX_B_data(RX_B_P1)<=RxDB;--xxx;	--緩衝器資料加入--2018.01.12
--			RX_B_P1<=RX_B_P1+1;			--緩衝器資料加入指標+1
--			RX_BBN<=RX_BBN+1;
--		elsif RX_BBN/=0 and Rx_B_Empty='0' then
--			RxDs<=RX_B_data(RX_B_P0);			--緩衝器資料取出
--			Rx_OW<=RX_B_OW(RX_B_P0); 			--Rx Buffer Over Write
--			Rx_P_Error<=RX_B_P_Error(RX_B_P0);	--Parity Error
--			Rx_B_Empty<='1';
--			RX_B_P0<=RX_B_P0+1;
--			RX_BBN<=RX_BBN-1;
--		elsIf Rx_R='1' Then
--			Rx_B_Empty<='0';
--		end if;
--	end if;

--	--upload_3--very good----------
	if Reset='0' Then
		RX_B_P0<=0;
		Rx_B_Empty<='0';
		Rx_OW<='0';
		Rx_P_Error<='0';
		upload0<='0';
		RX_B_P1<=0;
		RX_BBN<=0;
	Elsif clk'event and clk='0' Then
		upload0<=upload1;
		if upload1='1' then
			RX_B_data(RX_B_P1)<=RxDB;	--緩衝器資料加入--2018.01.12
			RX_B_P1<=RX_B_P1+1;			--緩衝器資料加入指標+1
			RX_BBN<=RX_BBN+1;
		else
			if RX_BBN/=0 and Rx_B_Empty='0' then
				RxDs<=RX_B_data(RX_B_P0);			--緩衝器資料取出
				Rx_OW<=RX_B_OW(RX_B_P0); 			--Rx Buffer Over Write
				Rx_P_Error<=RX_B_P_Error(RX_B_P0);	--Parity Error
				Rx_B_Empty<='1';
				RX_B_P0<=RX_B_P0+1;
				RX_BBN<=RX_BBN-1;
			elsIf Rx_R='1' Then
				Rx_B_Empty<='0';
			end if;
		end if;
	end if;
		
----  --upload_4--very good----------
--	if Reset='0' Then
--		RX_B_P0<=0;
--		Rx_B_Empty<='0';
--		Rx_OW<='0';
--		Rx_P_Error<='0';
--		upload0<='0';
--		RX_B_P1<=0;
--		RX_BBN<=0;
--	Elsif clk'event and clk='0' Then
--		upload0<=upload1;
--		if upload1='1' then
--			RX_B_data(RX_B_P1)<=RxDB;	--緩衝器資料加入--2018.01.12
--			RX_B_P1<=RX_B_P1+1;			--緩衝器資料加入指標+1
--			RX_BBN<=RX_BBN+1;
--		elsif RX_BBN/=0 and Rx_B_Empty='0' then
--			RxDs<=RX_B_data(RX_B_P0);			--緩衝器資料取出
--			Rx_OW<=RX_B_OW(RX_B_P0); 			--Rx Buffer Over Write
--			Rx_P_Error<=RX_B_P_Error(RX_B_P0);	--Parity Error
--			Rx_B_Empty<='1';
--			RX_B_P0<=RX_B_P0+1;
--			RX_BBN<=RX_BBN-1;
--		elsIf Rx_R='1' Then
--			Rx_B_Empty<='0';
--		end if;
--	end if;
End Process RxLP;

------------------------
RxP:Process(RDf,Reset)
Begin
	If Reset='0' Then
		Rx_s<="00";
		RX_B_P_Error<=(others=>'0');
		RX_B_OW<=(others=>'0');
		Rx_B_OWs<='0';
		upload1<='0';
	elsif upload0='1' then
		upload1<='0';
	Elsif RDf'event and RDf='0' Then
	--2018.01.18---------------------------------------------------
		If Rx_s=0 Then
			If RD='0' Then	--Start Bit
				Rx_s<="01";
				R_Half_f<='1';
				Rx_PEOSM<=ParityN(0);
			End If;
			Rsend_RDLNs<="0000";
		Elsif Rx_s="11" Then--Stop Bit
			Rx_s<=Not (RD & RD);
		Else				
			R_Half_f<=Not R_Half_f;
			If R_Half_f='1' Then
				If Rsend_RDLNs=RDLN Then
					--------------------------------------------------------
					upload1<='1';
					if RX_BBN>TXRD_buff+1 then
						RX_B_OW(RX_B_P1)<='1';	--覆寫狀態
					else
						RX_B_OW(RX_B_P1)<='0';	--覆寫狀態
					end if;
					----------------------------------------------------------
					If ParityN(2)='1' Then		--Now is Parity Bit
						If RD/=Rx_PEOSM Then
							RX_B_P_Error(RX_B_P1)<='1';	--RX_buffer Parity Error 2018.01.12
						End If;					
						Rx_s<="11";
					Else						--Now is Stop Bit
						Rx_s<="00";
					End If;
				Else							--Now is Start or Data Bit
					RxD<=RD & RxD(7 Downto 1);
					Rx_PEOSM<=Rx_PEOSM Xor RD;
					Rsend_RDLNs<=Rsend_RDLNs+1;	--含Start Bit
				End If;
			End If;
		End If;
	End If;
End Process RxP;

------------------------------------------
RxBaudP:process(Clk,Rx_s)
VARIABLE F_Div:integer range 0 to 41667;
Begin
	If Rx_s(0)=Rx_s(1) Then
		F_Div:=0;Rx_f<='1';BaudRate1234<="00";
	Elsif Clk'event and Clk='1' Then
		If F_Div=RX_BaudRate Then
			F_Div:=0;
			Rx_f<=Not Rx_f;
			BaudRate1234<=BaudRate1234+1;
		Else
			F_Div:=F_Div+1;
		End If;
	End If;
End Process RxBaudP;

------------------------------------------
--BaudRate:
BaudRateset<=F_Set & BaudRate1234;
With BaudRateset Select
  RX_BaudRate<=	--Baud Rate Set 依Clk=50MHz設定:50000000/(41666*4)=300
  		41667 When "000000",--300
		41667 When "000001",--300
		41667 When "000010",--300
		41666 When "000011",--300
        20833 When "000100",--600
        20834 When "000101",--600
        20833 When "000110",--600
        20833 When "000111",--600
		10416 When "001000",--1200
        10417 When "001001",--1200
        10417 When "001010",--1200
        10417 When "001011",--1200
        5208  When "001100",--2400
        5209  When "001101",--2400
        5208  When "001110",--2400
        5208  When "001111",--2400
        2604  When "010000",--4800
        2605  When "010001",--4800
        2604  When "010010",--4800
        2604  When "010011",--4800
        1302  When "010100",--9600
        1302  When "010101",--9600
        1302  When "010110",--9600
        1302  When "010111",--9600
        651   When "011000",--19200
        651   When "011001",--19200
        651   When "011010",--19200
        651   When "011011",--19200
        434   When "011100",--28800
        434   When "011101",--28800
        434   When "011110",--28800
        434   When "011111",--28800
        325   When "100000",--38400
        326   When "100001",--38400
        326   When "100010",--38400
        325   When "100011",--38400
        217   When "100100",--57600
        217   When "100101",--57600
        217   When "100110",--57600
        217   When "100111",--57600
        162   When "101000",--76800
        163   When "101001",--76800
        163   When "101010",--76800
        163   When "101011",--76800
        108   When "101100",--115200
        109   When "101101",--115200
        108   When "101110",--115200
        108   When "101111",--115200
        54    When "110000",--230400
        55    When "110001",--230400
        54    When "110010",--230400
        54    When "110011",--230400
        27    When "110100",--460800
        27    When "110101",--460800
        28    When "110110",--460800
        27    When "110111",--460800
        21    When "111000",--576000
        22    When "111001",--576000
        22    When "111010",--576000
        22    When "111011",--576000
        13    When "111100",--921600
        14    When "111101",--921600
        14    When "111110",--921600
        13    When "111111",--921600
        0 	  When oThers;
-------------------------------
--		50000000 50000000		0.00000002	0.000000005			
--0000--300	     0.003333333	166666.6667	41666.66667	41666.7	166667	41667+41667+41667+41666
--0001--600	     0.001666667	83333.33333	20833.33333	20833.3	83333	20833+20834+20833+20833
--0010--1200	 0.000833333	41666.66667	10416.66667	10416.7	41667	10416+10417+10417+10417
--0011--2400	 0.000416667	20833.33333	5208.333333	5208.3	20833	5208+5209+5208+5208
--0100--4800	 0.000208333	10416.66667	2604.166667	2604.2	10417	2604+2605+2604+2604
--0101--9600	 0.000104167	5208.333333	1302.083333	1302.1	5208	1302+1302+1302+1302
--0110--19200	 5.20833E-05	2604.166667	651.0416667	651		2604	651+651+651+651
--0111--28800	 3.47222E-05	1736.111111	434.0277778	434		1736	434+434+434+434
--1000--38400	 2.60417E-05	1302.083333	325.5208333	325.5	1302	325+326+326+325
--1001--57600	 1.73611E-05	868.0555556	217.0138889	217		868		217+217+217+217
--1010--76800	 1.30208E-05	651.0416667	162.7604167	162.8	651		162+163+163+163
--1011--115200   8.68056E-06	434.0277778	108.5069444	108.5	433		108+109+108+108
--1100--230400   4.34028E-06	217.0138889	54.25347222	54.3	217		54+55+54+54
--1101--460800   2.17014E-06	108.5069444	27.12673611	27.1	109		27+27+28+27
--1110--576000   1.73611E-06	86.80555556	21.70138889	21.7	87		21+22+22+22
--1111--921600   1.08507E-06	54.25347222	13.56336806	13.6	54		13+14+14+13
-------------------------------
With DL Select	--Data Length 含Start Bit
  RDLN<="0110" When "00",   --5bit 
        "0111" When "01",	--6bit
        "1000" When "10",	--7bit
        "1001" When "11",	--8bit
        "0000" When oThers;
-------------------------------
With DL Select	--Data Length 
  RxDB<="000" & RxD(7 Downto 3) When "00",	--5bit 
        "00" & RxD(7 Downto 2) When "01",	--6bit
        "0" & RxD(7 Downto 1) When "10",	--7bit
        RxD 				 When "11",		--8bit
        "11111111" 			When oThers;
-------------------------------
With StopN Select
  StopNn<="101" When "10",--2bit
          "110" When "11",--1.5bit
          "111" When oThers; --1bit
----------------------------------------------------
End RS232_R4_Arch;
